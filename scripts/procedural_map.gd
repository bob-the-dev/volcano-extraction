extends Node3D

## Room-based procedural level generator ported from TypeScript.
## Generates rooms with floors, walls, and lava tiles.

# Inner classes
class Room:
	var position: Vector2
	var radius: float
	var type: String
	var has_exit: bool

class Cell:
	var position: Vector2
	var filled: bool
	var is_floor: bool
	var is_wall: bool
	var is_lava: bool
	var type: String
	var noise_value: float

# Export parameters
@export_group("Map Size")
@export var map_width: float = 100.0:
	set(value):
		map_width = value
		if not Engine.is_editor_hint():
			call_deferred("_regenerate_map")

@export var map_height: float = 100.0:
	set(value):
		map_height = value
		if not Engine.is_editor_hint():
			call_deferred("_regenerate_map")

@export var cell_size: float = 2.0:
	set(value):
		cell_size = value
		if not Engine.is_editor_hint():
			call_deferred("_regenerate_map")

@export_group("Room Generation")
@export var num_rooms: int = 10
@export var random_seed: int = 0:
	set(value):
		random_seed = value
		# Only trigger regeneration if not already regenerating (prevents infinite loop)
		if not Engine.is_editor_hint() and not _is_regenerating:
			call_deferred("_regenerate_map")

@export var randomize_seed: bool = true

@export_group("Visualization")
@export var floor_height: float = 0.1
@export var base_thickness: float = 1.0
@export var regenerate_on_ready: bool = true

# Private variables
var _rng: RandomNumberGenerator
var _noise: FastNoiseLite
var _wall_scene: PackedScene
var _spawned_objects: Array = []
var _rooms: Array[Room] = []
var _cells: Array[Cell] = []
var _lava_cells: Array[Cell] = []
var _floor_cells: Array[Cell] = []
var _is_regenerating: bool = false

# Materials
var _floor_material: StandardMaterial3D
var _base_material: StandardMaterial3D


func _ready() -> void:
	_wall_scene = load("res://procedural_wall.tscn")
	
	# Create floor material
	_floor_material = StandardMaterial3D.new()
	_floor_material.albedo_color = Color(0.4, 0.3, 0.2)
	
	# Create base material
	_base_material = StandardMaterial3D.new()
	_base_material.albedo_color = Color(0.25, 0.2, 0.15)
	
	if regenerate_on_ready and not Engine.is_editor_hint():
		_regenerate_map()


## Regenerates the entire map.
func _regenerate_map() -> void:
	if _is_regenerating:
		return
	
	_is_regenerating = true
	_clear_map()
	_generate_map()
	_spawn_geometry()
	_place_player_on_floor()
	_is_regenerating = false
	
	print("Map generated: ", _rooms.size(), " rooms, ", _cells.size(), " cells")
	print("  - Floors: ", _floor_cells.size())
	print("  - Lava: ", _lava_cells.size())


## Clears all spawned geometry.
func _clear_map() -> void:
	for obj in _spawned_objects:
		if is_instance_valid(obj):
			obj.queue_free()
	_spawned_objects.clear()
	_rooms.clear()
	_cells.clear()
	_lava_cells.clear()
	_floor_cells.clear()


## Main map generation algorithm (ported from TypeScript).
func _generate_map() -> void:
	# Initialize RNG and noise
	_rng = RandomNumberGenerator.new()
	if randomize_seed:
		_rng.randomize()
		random_seed = _rng.seed
	else:
		_rng.seed = random_seed
	
	_noise = FastNoiseLite.new()
	_noise.seed = _rng.seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.05
	
	# Generate rooms
	_generate_rooms()
	
	# Generate cell grid
	_generate_cells()
	
	# Mark walls (cells adjacent to floors)
	_mark_walls()
	
	# Mark lava
	_mark_lava()


## Generates rooms using algorithm from TypeScript.
func _generate_rooms() -> void:
	var base_radius := minf(map_width, map_height) / 8.0
	var attempts := 0
	
	while _rooms.size() < num_rooms and attempts < 1000:
		if _rooms.is_empty():
			# First room (base)
			var x := _constrain(_rng.randf_range(0, map_width), base_radius * 3, map_width - base_radius * 3)
			var y := _constrain(_rng.randf_range(0, map_height), base_radius * 3, map_height - base_radius * 3)
			
			var room := Room.new()
			room.position = Vector2(x, y)
			room.radius = base_radius
			room.type = "base"
			room.has_exit = false
			_rooms.append(room)
		else:
			# Subsequent rooms
			var previous_idx := _rng.randi_range(0, _rooms.size() - 1)
			var previous := _rooms[previous_idx]
			
			var rand_angle := _rng.randf() * TAU
			var radius := _map_values(_rooms.size() - 2, 0, num_rooms, base_radius * 0.8, base_radius * 0.1) * _rng.randf_range(0.8, 1.5)
			
			var offset := Vector2(0, previous.radius + radius).rotated(rand_angle)
			var new_pos := previous.position + offset
			
			# Check if too close to other rooms or edges
			var too_close := false
			for i in range(_rooms.size()):
				var room := _rooms[i]
				if i != previous_idx and new_pos.distance_to(room.position) < room.radius * 2.25:
					too_close = true
					break
			
			# Check edge distance
			if new_pos.x > map_width - radius * 3 or new_pos.x < radius * 3 or \
			   new_pos.y > map_height - radius * 3 or new_pos.y < radius * 3:
				too_close = true
			
			if not too_close:
				var room := Room.new()
				room.position = new_pos
				room.radius = radius
				room.has_exit = _rng.randf() < 0.2
				room.type = "exit" if room.has_exit else "base"
				_rooms.append(room)
		
		attempts += 1


## Generates grid of cells.
func _generate_cells() -> void:
	var w := int(floor(map_width / cell_size)) - 4
	var h := int(floor(map_height / cell_size)) - 4
	
	for j in range(h):
		for i in range(w):
			var pos := Vector2(i, j)
			var world_pos := pos * cell_size
			
			# Get noise value
			var n := _get_noise(world_pos.x, world_pos.y)
			
			# Check if in any room
			var room_info := _check_floor(pos)
			
			var cell := Cell.new()
			cell.position = pos
			cell.filled = false
			cell.is_floor = room_info.is_floor
			cell.is_wall = false
			cell.is_lava = false
			cell.type = room_info.type
			cell.noise_value = n
			
			_cells.append(cell)


## Marks cells as walls if adjacent to floors.
func _mark_walls() -> void:
	for cell in _cells:
		if not cell.is_floor:
			cell.is_wall = _has_neighbours(cell, "is_floor", 2.5)


## Marks cells as lava based on noise and proximity.
func _mark_lava() -> void:
	for cell in _cells:
		if cell.is_floor:
			var near_wall := _has_neighbours(cell, "is_wall", 2.0 + cell.noise_value)
			var noise_check := cell.noise_value < 0.33 or cell.noise_value > 0.66
			cell.is_lava = near_wall or noise_check
		
		cell.filled = cell.is_lava or cell.is_floor or cell.is_wall


## Spawns visual geometry for cells.
func _spawn_geometry() -> void:
	# Spawn base platform first
	_spawn_base_platform()
	
	for cell in _cells:
		var world_pos := _cell_to_world(cell.position)
		
		if cell.is_wall:
			_spawn_wall(world_pos)
		elif cell.is_floor and not cell.is_lava:
			_spawn_floor_tile(world_pos)
			_floor_cells.append(cell)
		elif cell.is_lava:
			_lava_cells.append(cell)
			# TODO: Spawn lava visual when available


## Spawns a wall at given position.
func _spawn_wall(pos: Vector3) -> void:
	if not _wall_scene:
		return
	
	var wall: Node3D = _wall_scene.instantiate()
	add_child(wall)
	wall.position = pos
	
	# Randomize wall parameters
	wall.base_height = _rng.randf_range(0.5, 2.0)
	wall.corner_nw_offset = _rng.randf_range(-0.5, 1.0)
	wall.corner_ne_offset = _rng.randf_range(-0.5, 1.0)
	wall.corner_sw_offset = _rng.randf_range(-0.5, 1.0)
	wall.corner_se_offset = _rng.randf_range(-0.5, 1.0)
	
	if wall.has_method("_regenerate"):
		wall.call("_regenerate")
	
	_spawned_objects.append(wall)


## Spawns a floor tile at given position.
func _spawn_floor_tile(pos: Vector3) -> void:
	var floor_tile := CSGBox3D.new()
	floor_tile.size = Vector3(cell_size * 0.95, floor_height, cell_size * 0.95)
	floor_tile.material = _floor_material
	floor_tile.use_collision = true
	
	add_child(floor_tile)
	floor_tile.position = pos + Vector3(0, floor_height * 0.5, 0)
	
	_spawned_objects.append(floor_tile)


## Spawns a large base platform underneath all tiles.
func _spawn_base_platform() -> void:
	# Calculate map bounds based on cell grid
	var w := int(floor(map_width / cell_size)) - 4
	var h := int(floor(map_height / cell_size)) - 4
	
	# Base covers entire map area plus margin
	var base_width := w * cell_size + cell_size * 2
	var base_depth := h * cell_size + cell_size * 2
	
	var base := CSGBox3D.new()
	base.size = Vector3(base_width, base_thickness, base_depth)
	base.material = _base_material
	base.use_collision = true
	
	add_child(base)
	# Position base below floor tiles
	base.position = Vector3(
		(w * cell_size) / 2.0,
		-base_thickness / 2.0,
		(h * cell_size) / 2.0
	)
	
	_spawned_objects.append(base)


## Places the player on a random walkable floor tile.
func _place_player_on_floor() -> void:
	if _floor_cells.is_empty():
		push_warning("No floor tiles available to place player!")
		return
	
	# Find player node
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if not player:
		# Try to find by name
		player = get_node_or_null("../Player")
		if not player:
			player = get_node_or_null("../fatman")
	
	if not player:
		push_warning("Player node not found!")
		return
	
	# Place on random floor tile
	var random_cell := _floor_cells[_rng.randi_range(0, _floor_cells.size() - 1)]
	var spawn_pos := _cell_to_world(random_cell.position)
	spawn_pos.y = floor_height + 1.0  # Place slightly above floor
	
	player.position = spawn_pos
	print("Player placed at: ", spawn_pos)


## Helper: Check if cell is in a room (floor).
func _check_floor(grid_pos: Vector2) -> Dictionary:
	var world_pos := grid_pos * cell_size
	
	for room in _rooms:
		var dist := world_pos.distance_to(room.position)
		var distortion := 80.0
		
		var noise_x := _map_values(grid_pos.x, 0, map_width, 0, distortion)
		var noise_y := _map_values(grid_pos.y, 0, map_height, 0, distortion)
		var noise_val := _get_noise(noise_x, noise_y)
		var rad_noise := _map_values(noise_val, 0, 1, -0.1, 0.2)
		
		if dist <= room.radius * 1.25 + rad_noise * room.radius:
			return {"is_floor": true, "type": room.type}
	
	return {"is_floor": false, "type": "base"}


## Helper: Check if cell has neighbours matching a condition.
func _has_neighbours(cell: Cell, property: String, max_distance: float) -> bool:
	for other in _cells:
		if other.get(property) and cell.position.distance_to(other.position) <= max_distance:
			return true
	return false


## Helper: Convert cell grid position to world position.
func _cell_to_world(grid_pos: Vector2) -> Vector3:
	return Vector3(grid_pos.x * cell_size, 0, grid_pos.y * cell_size)


## Helper: Get noise value.
func _get_noise(x: float, y: float) -> float:
	return (_noise.get_noise_2d(x, y) + 1.0) / 2.0


## Helper: Map value from one range to another.
func _map_values(value: float, from_min: float, from_max: float, to_min: float, to_max: float) -> float:
	var d := (to_max - to_min) / (from_max - from_min)
	return (value - from_min) * d + to_min


## Helper: Constrain value between min and max.
func _constrain(value: float, min_val: float, max_val: float) -> float:
	return clamp(value, min_val, max_val)


## Public getter for cells array (used by minimap).
func get_cells() -> Array:
	return _cells

