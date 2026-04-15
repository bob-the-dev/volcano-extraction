extends Node3D

## Room-based procedural level generator ported from TypeScript.
## Generates rooms with floors, walls, and lava tiles.

# Signals
signal map_regenerated()

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
@export var min_map_size: float = 80.0
@export var max_map_size: float = 120.0
@export var cell_size: float = 2.0:
	set(value):
		cell_size = value
		if not Engine.is_editor_hint() and is_inside_tree() and not _is_regenerating:
			call_deferred("_regenerate_map")

@export_group("Room Generation")
@export var median_rooms: int = 12  # Number of rooms for a 100x100 map
@export var edge_margin: int = 3  # Number of cells to leave empty on each edge
@export var random_seed: int = 0:
	set(value):
		random_seed = value
		# Only trigger regeneration if not already regenerating and value actually changed
		if not Engine.is_editor_hint() and not _is_regenerating and is_inside_tree():
			call_deferred("_regenerate_map")

@export var randomize_seed: bool = true

@export_group("Visualization")
@export var floor_height: float = 0.1
@export var base_thickness: float = 1.0
@export var regenerate_on_ready: bool = true

@export_subgroup("Tile Variation")
## Maximum displacement for tile corners to create irregular shapes.
@export var tile_corner_displacement: float = 0.08
## Noise frequency for tile corner variation (higher = more variation, less smoothness).
@export var tile_variation_frequency: float = 5.0

@export_group("Debug")
@export var show_grid_debug: bool = true
@export var grid_line_color: Color = Color(0, 1, 0, 0.5)
@export var grid_line_width: float = 0.02

# Private variables
var _rng: RandomNumberGenerator
var _noise: FastNoiseLite
var _wall_scene: PackedScene
var _floor_tile_scene: PackedScene
var _spawned_objects: Array = []
var _rooms: Array[Room] = []
var _cells: Array[Cell] = []
var _lava_cells: Array[Cell] = []
var _floor_cells: Array[Cell] = []
var _is_regenerating: bool = false

# Materials
var _base_material: StandardMaterial3D

# Generated values (set during map generation)
var map_width: float = 100.0
var map_height: float = 100.0
var num_rooms: int = 12


func _ready() -> void:
	# Add to group for easy lookup
	add_to_group("procedural_map")
	
	_wall_scene = load("res://procedural_wall.tscn")
	_floor_tile_scene = load("res://procedural_floor_tile.tscn")
	
	# Load materials
	_base_material = load("res://materials/wall.tres")
	
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
	
	# Emit signal for other systems (like pathfinding) to update
	map_regenerated.emit()


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
	
	# Generate random map dimensions based on seed
	map_width = _rng.randf_range(min_map_size, max_map_size)
	map_height = _rng.randf_range(min_map_size, max_map_size)
	
	# Calculate number of rooms based on area (12 rooms for 100x100 = 10,000 area)
	var map_area := map_width * map_height
	var base_area := 10000.0  # Area that corresponds to median_rooms
	num_rooms = int(round((map_area / base_area) * median_rooms))
	num_rooms = maxi(num_rooms, 3)  # Ensure at least 3 rooms
	
	print("Generated map size: ", map_width, "x", map_height, " (area: ", map_area, ") with ", num_rooms, " rooms")
	
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
	# Calculate playable area (accounting for edge margin)
	var playable_width := map_width - (edge_margin * 2 * cell_size)
	var playable_height := map_height - (edge_margin * 2 * cell_size)
	var edge_offset := edge_margin * cell_size
	
	var base_radius := minf(playable_width, playable_height) / 8.0
	var attempts := 0
	
	while _rooms.size() < num_rooms and attempts < 1000:
		if _rooms.is_empty():
			# First room (base) - positioned within playable area
			var x := _constrain(_rng.randf_range(0, playable_width), base_radius * 3, playable_width - base_radius * 3) + edge_offset
			var y := _constrain(_rng.randf_range(0, playable_height), base_radius * 3, playable_height - base_radius * 3) + edge_offset
			
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
			
			var room_offset := Vector2(0, previous.radius + radius).rotated(rand_angle)
			var new_pos := previous.position + room_offset
			
			# Check if too close to other rooms or edges
			var too_close := false
			for i in range(_rooms.size()):
				var room := _rooms[i]
				if i != previous_idx and new_pos.distance_to(room.position) < room.radius * 2.25:
					too_close = true
					break
			
			# Check edge distance (within playable area)
			if new_pos.x > map_width - edge_offset - radius * 3 or new_pos.x < edge_offset + radius * 3 or \
			   new_pos.y > map_height - edge_offset - radius * 3 or new_pos.y < edge_offset + radius * 3:
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
	var w := int(floor(map_width / cell_size)) - (edge_margin * 2)
	var h := int(floor(map_height / cell_size)) - (edge_margin * 2)
	
	for j in range(h):
		for i in range(w):
			var pos := Vector2(i, j)
			# Convert to world position (with edge margin offset)
			var world_pos := _cell_to_world(pos)
			
			# Get noise value
			var n := _get_noise(world_pos.x, world_pos.z)
			
			# Check if in any room (pass world position for proper comparison)
			var room_info := _check_floor_world(world_pos)
			
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
	# Spawn custom base mesh that follows map outline
	_spawn_base_mesh()
	
	for cell in _cells:
		var world_pos := _cell_to_world(cell.position)
		
		if cell.is_wall:
			_spawn_wall(world_pos)
		elif cell.is_floor and not cell.is_lava:
			_spawn_floor_tile(world_pos, cell.position)
			_floor_cells.append(cell)
		elif cell.is_lava:
			_lava_cells.append(cell)
			# TODO: Spawn lava visual when available
	
	# Draw debug grid if enabled
	if show_grid_debug:
		_draw_debug_grid()


## Spawns a wall at given position.
func _spawn_wall(pos: Vector3) -> void:
	if not _wall_scene:
		return
	
	var wall: Node3D = _wall_scene.instantiate()
	add_child(wall)
	wall.add_to_group("wall")
	wall.position = pos
	
	# Randomize wall parameters
	wall.base_height = _rng.randf_range(0.5, 1.0)
	wall.corner_nw_offset = _rng.randf_range(-0.2, 0.4)
	wall.corner_ne_offset = _rng.randf_range(-0.2, 0.4)
	wall.corner_sw_offset = _rng.randf_range(-0.2, 0.4)
	wall.corner_se_offset = _rng.randf_range(-0.2, 0.4)
	
	# Randomize pillar base radii (0.5 to 1.0)
	wall.corner_nw_base_radius = _rng.randf_range(0.5, 1.0)
	wall.corner_ne_base_radius = _rng.randf_range(0.5, 1.0)
	wall.corner_sw_base_radius = _rng.randf_range(0.5, 1.0)
	wall.corner_se_base_radius = _rng.randf_range(0.5, 1.0)
	
	# Randomize pillar top radii (0.2 to 0.8, always smaller than base)
	wall.corner_nw_top_radius = minf(_rng.randf_range(0.2, 0.8), wall.corner_nw_base_radius)
	wall.corner_ne_top_radius = minf(_rng.randf_range(0.2, 0.8), wall.corner_ne_base_radius)
	wall.corner_sw_top_radius = minf(_rng.randf_range(0.2, 0.8), wall.corner_sw_base_radius)
	wall.corner_se_top_radius = minf(_rng.randf_range(0.2, 0.8), wall.corner_se_base_radius)
	
	# Randomize pillar top insets for slant (-0.3 to 0.3)
	wall.corner_nw_top_inset = _rng.randf_range(-0.3, 0.3)
	wall.corner_ne_top_inset = _rng.randf_range(-0.3, 0.3)
	wall.corner_sw_top_inset = _rng.randf_range(-0.3, 0.3)
	wall.corner_se_top_inset = _rng.randf_range(-0.3, 0.3)
	
	if wall.has_method("_regenerate"):
		wall.call("_regenerate")
	
	_spawned_objects.append(wall)


## Spawns a floor tile at given position.
func _spawn_floor_tile(pos: Vector3, grid_pos: Vector2) -> void:
	if not _floor_tile_scene:
		return
	
	var floor_tile: StaticBody3D = _floor_tile_scene.instantiate()
	add_child(floor_tile)
	floor_tile.add_to_group("floor_tile")
	floor_tile.position = pos + Vector3(0, floor_height * 1.5, 0)
	
	# Set tile size to match cell size
	floor_tile.tile_size = cell_size * 0.9
	floor_tile.tile_height = floor_height
	
	# Apply corner displacement based on grid position
	if tile_corner_displacement > 0.0:
		var corner_offsets := _calculate_tile_corner_offsets(grid_pos)
		floor_tile.corner_offset_tl = corner_offsets[0]
		floor_tile.corner_offset_tr = corner_offsets[1]
		floor_tile.corner_offset_br = corner_offsets[2]
		floor_tile.corner_offset_bl = corner_offsets[3]
	
	# Regenerate mesh with new parameters
	if floor_tile.has_method("_regenerate"):
		floor_tile.call("_regenerate")
	
	# Store tile center for click-to-move (pos is already the center of the cell)
	floor_tile.set_meta("tile_center", pos + Vector3(0, floor_height, 0))
	
	_spawned_objects.append(floor_tile)


## Calculates corner offsets for a tile based on grid position using noise.
## Returns an array of 4 Vector2 offsets: [top-left, top-right, bottom-right, bottom-left]
func _calculate_tile_corner_offsets(grid_pos: Vector2) -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	
	if not _noise:
		# Return zero offsets if no noise is available
		return [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	
	# Sample noise at different offsets for each corner to get unique values
	# Using prime number offsets to avoid patterns
	var corner_seeds: Array[Vector2] = [
		Vector2(0.0, 0.0),      # Top-left
		Vector2(13.7, 0.0),     # Top-right
		Vector2(13.7, 23.1),    # Bottom-right
		Vector2(0.0, 23.1)      # Bottom-left
	]
	
	for i in range(4):
		var sample_pos: Vector2 = (grid_pos + corner_seeds[i]) * tile_variation_frequency
		
		# Sample noise twice (for x and y displacement)
		var noise_x := _noise.get_noise_2d(sample_pos.x, sample_pos.y)
		var noise_y := _noise.get_noise_2d(sample_pos.x + 100.0, sample_pos.y + 100.0)
		
		# Convert from [-1, 1] range to displacement range
		var offset := Vector2(
			noise_x * tile_corner_displacement,
			noise_y * tile_corner_displacement
		)
		
		offsets.append(offset)
	
	return offsets


## Spawns a custom base mesh that follows the map outline (walls + floors).
func _spawn_base_mesh() -> void:
	# Collect all cells that should have base underneath (walls + floors, not empty space)
	var base_cells: Array[Cell] = []
	for cell in _cells:
		if cell.is_wall or cell.is_floor:
			base_cells.append(cell)
	
	if base_cells.is_empty():
		return
	
	# Create a mesh instance to hold our base
	var mesh_instance := MeshInstance3D.new()
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# For each base cell, create a quad (2 triangles) at the base level
	# Apply small inset to create gap at perimeter
	var inset := cell_size * 0.25  # Half-cell inset on perimeter
	for cell in base_cells:
		var world_pos := _cell_to_world(cell.position)
		
		# Check which sides are on the perimeter and apply inset only there
		var inset_left := 0.0
		var inset_right := 0.0
		var inset_top := 0.0
		var inset_bottom := 0.0
		
		# Check each direction for perimeter
		if not _has_filled_neighbor(cell, Vector2(-1, 0)):  # Left
			inset_left = inset
		if not _has_filled_neighbor(cell, Vector2(1, 0)):   # Right
			inset_right = inset
		if not _has_filled_neighbor(cell, Vector2(0, -1)):  # Top
			inset_top = inset
		if not _has_filled_neighbor(cell, Vector2(0, 1)):   # Bottom
			inset_bottom = inset
		
		var half_size := cell_size * 0.5
		var y_pos := 0.0  # At ground level, same as floor tiles
		
		# Define the 4 corners of this cell's base quad (with directional inset)
		var nw := Vector3(world_pos.x - half_size + inset_left, y_pos, world_pos.z - half_size + inset_top)
		var ne := Vector3(world_pos.x + half_size - inset_right, y_pos, world_pos.z - half_size + inset_top)
		var sw := Vector3(world_pos.x - half_size + inset_left, y_pos, world_pos.z + half_size - inset_bottom)
		var se := Vector3(world_pos.x + half_size - inset_right, y_pos, world_pos.z + half_size - inset_bottom)
		
		# Top face (2 triangles)
		surface_tool.set_normal(Vector3.UP)
		surface_tool.add_vertex(nw)
		surface_tool.add_vertex(ne)
		surface_tool.add_vertex(sw)
		
		surface_tool.add_vertex(sw)
		surface_tool.add_vertex(ne)
		surface_tool.add_vertex(se)
	
	# Generate normals and commit to mesh
	var array_mesh := surface_tool.commit()
	mesh_instance.mesh = array_mesh
	mesh_instance.material_override = _base_material
	
	# Create collision shape
	var static_body := StaticBody3D.new()
	var collision_shape := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(array_mesh.get_faces())
	collision_shape.shape = shape
	
	static_body.add_child(collision_shape)
	static_body.add_to_group("base_platform")
	
	add_child(static_body)
	static_body.add_child(mesh_instance)
	
	_spawned_objects.append(static_body)
	
	print("[Base Mesh] Created base with ", base_cells.size(), " cells")


## Places the player on a random walkable floor tile.
func _place_player_on_floor() -> void:
	if _floor_cells.is_empty():
		push_warning("No floor tiles available to place player!")
		return
	
	# Find player node using multiple fallback methods
	var player: Node3D = NodeUtils.find(self, "player", ["../Player"])
	
	if not player:
		push_warning("Player node not found!")
		return
	
	# Place on random floor tile
	var random_cell := _floor_cells[_rng.randi_range(0, _floor_cells.size() - 1)]
	var spawn_pos := _cell_to_world(random_cell.position)
	spawn_pos.y = floor_height + 1.0  # Place slightly above floor
	
	player.position = spawn_pos
	print("Player placed at: ", spawn_pos)


## Helper: Check if world position is in a room (floor).
func _check_floor_world(world_pos: Vector3) -> Dictionary:
	var pos_2d := Vector2(world_pos.x, world_pos.z)
	
	for room in _rooms:
		var dist := pos_2d.distance_to(room.position)
		var distortion := 80.0
		
		var noise_x := _map_values(pos_2d.x, 0, map_width, 0, distortion)
		var noise_y := _map_values(pos_2d.y, 0, map_height, 0, distortion)
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


## Helper: Check if cell has a filled neighbor in a specific direction.
func _has_filled_neighbor(cell: Cell, direction: Vector2) -> bool:
	var neighbor_pos: Vector2 = cell.position + direction
	
	for other in _cells:
		if other.position == neighbor_pos and (other.is_wall or other.is_floor):
			return true
	
	return false


## Helper: Convert cell grid position to world position (center of cell).
func _cell_to_world(grid_pos: Vector2) -> Vector3:
	# Add edge_margin offset to push cells away from map edges
	# Return the CENTER of the cell, not the corner
	var offset := edge_margin * cell_size
	return Vector3(
		grid_pos.x * cell_size + cell_size * 0.5 + offset,
		0,
		grid_pos.y * cell_size + cell_size * 0.5 + offset
	)


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


## Draw debug grid lines to visualize cell boundaries
func _draw_debug_grid() -> void:
	var w := int(floor(map_width / cell_size)) - (edge_margin * 2)
	var h := int(floor(map_height / cell_size)) - (edge_margin * 2)
	
	# Create material for grid lines
	var line_material := StandardMaterial3D.new()
	line_material.albedo_color = grid_line_color
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_material.no_depth_test = true
	
	# Draw vertical lines
	for i in range(w + 1):
		var x := i * cell_size + edge_margin * cell_size
		var z_start := edge_margin * cell_size
		var z_end := h * cell_size + edge_margin * cell_size
		
		var line := _create_line_mesh(
			Vector3(x, floor_height + 0.01, z_start),
			Vector3(x, floor_height + 0.01, z_end),
			line_material
		)
		add_child(line)
		_spawned_objects.append(line)
	
	# Draw horizontal lines
	for j in range(h + 1):
		var z := j * cell_size + edge_margin * cell_size
		var x_start := edge_margin * cell_size
		var x_end := w * cell_size + edge_margin * cell_size
		
		var line := _create_line_mesh(
			Vector3(x_start, floor_height + 0.01, z),
			Vector3(x_end, floor_height + 0.01, z),
			line_material
		)
		add_child(line)
		_spawned_objects.append(line)
	
	# Draw cell center markers for floor and lava cells (for debugging)
	for cell in _floor_cells + _lava_cells:
		var center := _cell_to_world(cell.position)
		center.y = floor_height + 0.02
		
		var marker := CSGBox3D.new()
		marker.size = Vector3(0.1, 0.01, 0.1)
		marker.material = StandardMaterial3D.new()
		if cell.is_lava:
			marker.material.albedo_color = Color(1, 0, 0, 0.8)
		else:
			marker.material.albedo_color = Color(0, 1, 0, 0.8)
		marker.position = center
		add_child(marker)
		_spawned_objects.append(marker)
	
	print("[Debug] Grid lines drawn: ", w + 1, " vertical, ", h + 1, " horizontal")


## Helper to create a line mesh between two points
func _create_line_mesh(from: Vector3, to: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var immediate_mesh := ImmediateMesh.new()
	
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_add_vertex(from)
	immediate_mesh.surface_add_vertex(to)
	immediate_mesh.surface_end()
	
	mesh_instance.mesh = immediate_mesh
	mesh_instance.material_override = material
	
	return mesh_instance
