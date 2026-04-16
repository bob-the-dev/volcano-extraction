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
	var depth: int = 0  # Depth level from 0 (walls/shallow) to 4 (deep)

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

@export_group("Depth Sources")
## Number of rooms to designate as lava sources (depth 4 centers)
@export var num_lava_sources: int = 2
## Number of rooms to designate as highground (depth 0 centers)
@export var num_highground: int = 1
## Influence radius for depth sources (in cells)
@export var depth_source_influence: float = 8.0
## Wall proximity bias strength (higher = stronger bias to 0 near walls)
@export var wall_bias_strength: float = 2.0
## Height per depth step - player can step up 1 level (0.15 = standard stair height)
@export var depth_step_height: float = 0.15

@export_subgroup("Heightmap Generation")
## Pixels per grid cell in heightmap texture (higher = smoother transitions)
@export_range(4, 16) var pixels_per_cell: int = 6
## Blur radius in pixels (higher = smoother but less defined plateaus)
@export_range(0, 20) var blur_radius: int = 5
## Grid mesh subdivisions (vertices per cell, higher = smoother terrain)
@export_range(1, 4) var mesh_subdivisions: int = 2
## Heightmap displacement multiplier (higher = more dramatic height differences)
@export_range(0.1, 10.0) var heightmap_displacement_amplitude: float = 5.0
## Export heightmap texture for debugging
@export var export_heightmap_debug: bool = false

@export_group("Rendering")
## Enable floor tile rendering (disable to show only layered base mesh)
@export var render_floor_tiles: bool = false
## Use layered depth rendering for base mesh
@export var use_layered_depth: bool = true

@export_group("Debug")
@export var show_grid_debug: bool = true
@export var grid_line_color: Color = Color(0, 1, 0, 0.5)
@export var grid_line_width: float = 0.02
## Show depth labels on floor tiles (0-4)
@export var show_depth_labels: bool = true
## Color for depth labels
@export var depth_label_color: Color = Color(1, 1, 1, 1)

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
var _lava_sources: Array[Vector2] = []
var _highground_positions: Array[Vector2] = []
var _is_regenerating: bool = false
var _heightmap_texture: ImageTexture
var _heightmap_image: Image  # Store heightmap image for collision generation

# Materials
var _base_material: StandardMaterial3D

# Generated values (set during map generation)
var map_width: int = 100
var map_height: int = 100
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
	
	# Generate random map dimensions based on seed (rounded to integers)
	map_width = int(round(_rng.randf_range(min_map_size, max_map_size)))
	map_height = int(round(_rng.randf_range(min_map_size, max_map_size)))
	
	# Calculate number of rooms based on area (12 rooms for 100x100 = 10,000 area)
	var map_area: int = map_width * map_height
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
	# Select depth sources (lava sources and highground)
	_select_depth_sources()
	
	# Calculate depths for all cells
	print("[Map] Calculating tile depths...")
	for cell in _cells:
		if cell.is_wall:
			# Walls always have depth 0
			cell.depth = 0
		else:
			# Floor and lava cells get calculated depth
			var distance: float = _distance_to_nearest_wall(cell.position)
			cell.depth = _calculate_tile_depth(cell.position, distance, cell.noise_value)
	
	# Override depth for special source cells
	for lava_pos in _lava_sources:
		var lava_cell: Cell = _get_cell_at(lava_pos)
		if lava_cell:
			lava_cell.depth = 4
			print("[Map] Lava source at grid ", lava_pos, " set to depth 4")
		else:
			push_warning("[Map] Failed to find cell for lava source at grid ", lava_pos)
	
	for high_pos in _highground_positions:
		var high_cell: Cell = _get_cell_at(high_pos)
		if high_cell:
			high_cell.depth = 0
			print("[Map] Highground at grid ", high_pos, " set to depth 0")
		else:
			push_warning("[Map] Failed to find cell for highground at grid ", high_pos)
	
	# Spawn custom base mesh that follows map outline
	_spawn_base_mesh()
	
	for cell in _cells:
		var world_pos := _cell_to_world(cell.position)
		
		if cell.is_wall:
			_spawn_wall(world_pos)
			_spawn_depth_label(world_pos, cell.depth)
		elif cell.is_floor and not cell.is_lava:
			# Always collect floor cells for pathfinding
			_floor_cells.append(cell)
			# Only spawn tile visuals if enabled
			if render_floor_tiles:
				_spawn_floor_tile(world_pos, cell.position)
			_spawn_depth_label(world_pos, cell.depth)
		elif cell.is_lava:
			_spawn_depth_label(world_pos, cell.depth)
			_lava_cells.append(cell)
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


## Identifies the center position of each room
func _identify_room_centers() -> Array[Vector2]:
	var room_centers: Array[Vector2] = []
	
	for room in _rooms:
		# Convert room world position to grid coordinates
		var grid_pos: Vector2 = _world_to_grid(room.position)
		
		# Verify that this grid position has a floor cell
		var cell: Cell = _get_cell_at(grid_pos)
		if cell and cell.is_floor and not cell.is_lava:
			room_centers.append(grid_pos)
			print("[Room Centers] Room at world ", room.position, " -> grid ", grid_pos, " (valid floor)")
		else:
			print("[Room Centers] Room at world ", room.position, " -> grid ", grid_pos, " (NOT a valid floor, skipping)")
	
	return room_centers


## Selects which rooms become lava sources and highground
func _select_depth_sources() -> void:
	_lava_sources.clear()
	_highground_positions.clear()
	
	var room_centers: Array[Vector2] = _identify_room_centers()
	if room_centers.size() == 0:
		push_warning("[Map] No valid room centers found for depth sources!")
		return
	
	print("[Map] Found ", room_centers.size(), " valid room centers (floors) out of ", _rooms.size(), " rooms")
	
	# Shuffle room centers for random selection
	var shuffled_centers: Array[Vector2] = room_centers.duplicate()
	shuffled_centers.shuffle()
	
	# Select lava sources
	var lava_count: int = mini(num_lava_sources, shuffled_centers.size())
	for i in range(lava_count):
		_lava_sources.append(shuffled_centers[i])
		print("[Map] Selected lava source at grid ", shuffled_centers[i])
	
	# Select highground (from remaining rooms)
	var highground_start: int = lava_count
	var highground_count: int = mini(num_highground, shuffled_centers.size() - highground_start)
	for i in range(highground_count):
		_highground_positions.append(shuffled_centers[highground_start + i])
		print("[Map] Selected highground at grid ", shuffled_centers[highground_start + i])
	
	print("[Map] Total depth sources - Lava: ", _lava_sources.size(), " | Highground: ", _highground_positions.size())


## Gets a cell at specific grid position
func _get_cell_at(grid_pos: Vector2) -> Cell:
	for cell in _cells:
		if cell.position == grid_pos:
			return cell
	return null


## Calculates the distance from a cell to the nearest wall
func _distance_to_nearest_wall(cell_pos: Vector2) -> float:
	var min_distance := INF
	
	# Check cells in expanding radius
	for radius in range(1, 30):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue
				
				var check_pos := Vector2(cell_pos.x + dx, cell_pos.y + dy)
				var check_cell := _get_cell_at(check_pos)
				
				if check_cell and check_cell.is_wall:
					var distance := cell_pos.distance_to(check_pos)
					if distance < min_distance:
						min_distance = distance
		
		# Early exit if we found a wall
		if min_distance < INF:
			return min_distance
	
	return min_distance


## Calculates depth for a tile based on multiple influences
## Returns depth from 0 (shallow/walls) to 4 (deep)
func _calculate_tile_depth(grid_pos: Vector2, distance_from_wall: float, noise_value: float) -> int:
	# Convert noise from [-1, 1] to [0, 1]
	var noise_factor: float = (noise_value + 1.0) * 0.5
	
	# Calculate distance to nearest lava source (pulls toward 4)
	var distance_to_lava: float = INF
	for lava_pos in _lava_sources:
		var dist: float = grid_pos.distance_to(lava_pos)
		if dist < distance_to_lava:
			distance_to_lava = dist
	
	# Calculate distance to nearest highground (pulls toward 0)
	var distance_to_highground: float = INF
	for high_pos in _highground_positions:
		var dist: float = grid_pos.distance_to(high_pos)
		if dist < distance_to_highground:
			distance_to_highground = dist
	
	# Normalize distances
	var lava_influence: float = 0.0
	if distance_to_lava < depth_source_influence:
		# Close to lava = high influence toward 4
		lava_influence = 1.0 - (distance_to_lava / depth_source_influence)
		lava_influence = lava_influence * lava_influence  # Exponential falloff
	
	var highground_influence: float = 0.0
	if distance_to_highground < depth_source_influence:
		# Close to highground = high influence toward 0
		highground_influence = 1.0 - (distance_to_highground / depth_source_influence)
		highground_influence = highground_influence * highground_influence
	
	# Wall influence (exponential, stronger bias near walls)
	var wall_influence: float = 0.0
	if distance_from_wall < 3.0:
		wall_influence = (1.0 - (distance_from_wall / 3.0)) * wall_bias_strength
		wall_influence = clamp(wall_influence, 0.0, 1.0)
	
	# Combine influences
	# Start with noise as base
	var depth_value: float = noise_factor
	
	# Lava sources pull up
	depth_value += lava_influence * 2.0
	
	# Walls and highground pull down
	var pull_down: float = maxf(wall_influence, highground_influence)
	depth_value -= pull_down * 2.0
	
	# Scale to 0-4 range
	depth_value = clamp(depth_value, 0.0, 1.0) * 4.0
	
	var depth: int = int(floor(depth_value))
	return clamp(depth, 0, 4)


## Spawns a debug label showing depth value above a tile
func _spawn_depth_label(world_pos: Vector3, depth: int) -> void:
	if not show_depth_labels:
		return
	
	var label := Label3D.new()
	label.text = str(depth)
	label.pixel_size = 0.015
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.modulate = depth_label_color
	label.outline_size = 4
	label.outline_modulate = Color.BLACK
	label.no_depth_test = true  # Render on top of geometry
	label.extra_cull_margin = 1000.0  # Prevent culling at distance
	
	# Color code by depth
	match depth:
		0: label.modulate = Color(0.5, 0.5, 0.5)  # Gray - shallow
		1: label.modulate = Color(0.7, 0.9, 1.0)  # Light blue
		2: label.modulate = Color(0.4, 0.7, 1.0)  # Blue
		3: label.modulate = Color(0.2, 0.5, 0.9)  # Dark blue
		4: label.modulate = Color(0.1, 0.3, 0.7)  # Deep blue
	
	add_child(label)
	# Position slightly above floor_height and rotate to face upward
	label.global_position = Vector3(world_pos.x, floor_height + 0.05, world_pos.z)
	label.rotation.x = -PI / 2.0  # Rotate 90 degrees to lay flat
	_spawned_objects.append(label)


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
	
	# Get surface mesh for visibility and material settings
	var surface_mesh: MeshInstance3D = floor_tile.get_node_or_null("Surface")
	if surface_mesh:
		# Prevent distance culling for all tiles
		surface_mesh.extra_cull_margin = 1000.0
		
		# Make tiles transparent when debug labels are shown
		if show_depth_labels:
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_color = Color(0.8, 0.8, 0.8, 0.3)  # Light gray, 30% opacity
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # Show both sides
			surface_mesh.material_override = mat
	
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


## Spawns a custom base mesh with layered depth (terraced platforms).
func _spawn_base_mesh() -> void:
	if not use_layered_depth:
		_spawn_base_mesh_flat()
		return
	
	# Collect all cells that should have base underneath (walls + floors)
	var base_cells: Array[Cell] = []
	for cell in _cells:
		if cell.is_wall or cell.is_floor:
			base_cells.append(cell)
	
	if base_cells.is_empty():
		return
	
	print("[Heightmap Terrain] Generating heightmap texture...")
	
	# Step 1: Generate heightmap texture from cell depths
	_heightmap_texture = _generate_heightmap_texture(base_cells)
	
	if not _heightmap_texture:
		print("[Heightmap Terrain] ERROR: Failed to generate heightmap texture")
		return
	
	# Step 2: Create flat subdivided plane mesh
	var mesh_instance := _create_terrain_mesh()
	
	# Enable shadow casting and receiving
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	# Step 3: Apply shader with displacement AND wall.tres material properties
	var terrain_shader := _create_terrain_displacement_material()
	mesh_instance.material_override = terrain_shader
	
	# Step 4: Create collision that follows the displayed terrain surface
	var grid_width: int = int(floor(map_width / cell_size)) - (edge_margin * 2)
	var grid_height: int = int(floor(map_height / cell_size)) - (edge_margin * 2)
	var playable_width: float = grid_width * cell_size
	var playable_height: float = grid_height * cell_size
	
	var static_body := StaticBody3D.new()
	var collision_shape := CollisionShape3D.new()
	var terrain_collision_shape: Shape3D = _create_terrain_collision_shape(playable_width, playable_height, grid_width, grid_height)
	if terrain_collision_shape:
		collision_shape.shape = terrain_collision_shape
	else:
		var max_displacement: float = depth_step_height * 4.0 * heightmap_displacement_amplitude
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(playable_width, 0.2, playable_height)
		collision_shape.shape = box_shape
		collision_shape.position = Vector3(0, max_displacement, 0)
		push_warning("[Heightmap Terrain] Falling back to flat collision because terrain collision generation failed")
	
	static_body.add_child(collision_shape)
	static_body.position = mesh_instance.position
	static_body.add_to_group("base_platform")
	
	add_child(static_body)
	add_child(mesh_instance)
	_spawned_objects.append(static_body)
	_spawned_objects.append(mesh_instance)
	
	print("[Heightmap Terrain] Terrain collision anchored to mesh base Y: ", mesh_instance.position.y)
	print("[Heightmap Terrain] Terrain mesh with terrain-following collision added to scene")
	
	print("[Heightmap Terrain] Created terrain mesh with heightmap texture")


## Creates a collision-only trimesh that matches the displayed terrain surface.
func _create_terrain_collision_shape(playable_width: float, playable_height: float, grid_width: int, grid_height: int) -> Shape3D:
	if _heightmap_image == null:
		push_error("[Heightmap Terrain] Missing heightmap image for terrain collision generation")
		return null

	var width_segments: int = grid_width * mesh_subdivisions
	var depth_segments: int = grid_height * mesh_subdivisions
	if width_segments <= 0 or depth_segments <= 0:
		push_error("[Heightmap Terrain] Invalid terrain subdivision values for collision generation")
		return null

	var displacement_amplitude: float = depth_step_height * 4.0 * heightmap_displacement_amplitude
	var vertices: Array[PackedVector3Array] = []
	vertices.resize(width_segments + 1)

	for x_index in range(width_segments + 1):
		var column: PackedVector3Array = PackedVector3Array()
		column.resize(depth_segments + 1)
		var x_ratio: float = float(x_index) / float(width_segments)
		var local_x: float = lerpf(-playable_width * 0.5, playable_width * 0.5, x_ratio)

		for z_index in range(depth_segments + 1):
			var z_ratio: float = float(z_index) / float(depth_segments)
			var local_z: float = lerpf(-playable_height * 0.5, playable_height * 0.5, z_ratio)
			var uv: Vector2 = Vector2(
				(local_x / playable_width) + 0.5,
				(local_z / playable_height) + 0.5
			)
			var height_value: float = _sample_heightmap_bilinear(_heightmap_image, uv)
			column[z_index] = Vector3(local_x, height_value * displacement_amplitude, local_z)

		vertices[x_index] = column

	var faces: PackedVector3Array = PackedVector3Array()
	faces.resize(width_segments * depth_segments * 6)
	var face_index: int = 0

	for x_index in range(width_segments):
		for z_index in range(depth_segments):
			var top_left: Vector3 = vertices[x_index][z_index]
			var top_right: Vector3 = vertices[x_index + 1][z_index]
			var bottom_left: Vector3 = vertices[x_index][z_index + 1]
			var bottom_right: Vector3 = vertices[x_index + 1][z_index + 1]

			faces[face_index] = top_left
			face_index += 1
			faces[face_index] = bottom_left
			face_index += 1
			faces[face_index] = top_right
			face_index += 1

			faces[face_index] = top_right
			face_index += 1
			faces[face_index] = bottom_left
			face_index += 1
			faces[face_index] = bottom_right
			face_index += 1

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces

	var array_mesh: ArrayMesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var shape: ConcavePolygonShape3D = array_mesh.create_trimesh_shape()
	if shape == null:
		push_error("[Heightmap Terrain] Failed to convert generated terrain mesh into a collision shape")
		return null

	shape.backface_collision = true

	print("[Heightmap Terrain] Generated terrain collision with ", width_segments, "x", depth_segments, " quads")
	return shape


## Samples the heightmap image using bilinear filtering to match rendered terrain.
func _sample_heightmap_bilinear(image: Image, uv: Vector2) -> float:
	var clamped_uv: Vector2 = Vector2(
		clampf(uv.x, 0.0, 1.0),
		clampf(uv.y, 0.0, 1.0)
	)
	var width: int = image.get_width()
	var height: int = image.get_height()
	if width <= 0 or height <= 0:
		return 0.0

	var pixel_x: float = clamped_uv.x * float(width - 1)
	var pixel_y: float = clamped_uv.y * float(height - 1)
	var x0: int = int(floor(pixel_x))
	var y0: int = int(floor(pixel_y))
	var x1: int = mini(x0 + 1, width - 1)
	var y1: int = mini(y0 + 1, height - 1)
	var x_lerp: float = pixel_x - float(x0)
	var y_lerp: float = pixel_y - float(y0)

	var top_left: float = image.get_pixel(x0, y0).r
	var top_right: float = image.get_pixel(x1, y0).r
	var bottom_left: float = image.get_pixel(x0, y1).r
	var bottom_right: float = image.get_pixel(x1, y1).r
	var top: float = lerpf(top_left, top_right, x_lerp)
	var bottom: float = lerpf(bottom_left, bottom_right, x_lerp)

	return lerpf(top, bottom, y_lerp)


## Generates a heightmap texture from cell depth data
func _generate_heightmap_texture(cells: Array[Cell]) -> ImageTexture:
	# Calculate actual grid dimensions (matching cell generation)
	var grid_width: int = int(floor(map_width / cell_size)) - (edge_margin * 2)
	var grid_height: int = int(floor(map_height / cell_size)) - (edge_margin * 2)
	var tex_width: int = grid_width * pixels_per_cell
	var tex_height: int = grid_height * pixels_per_cell
	
	print("[Heightmap] Creating ", tex_width, "x", tex_height, " texture (", grid_width, "x", grid_height, " cells)")
	
	# Create image
	var image := Image.create(tex_width, tex_height, false, Image.FORMAT_RF)
	image.fill(Color(0, 0, 0, 1))  # Black = lowest depth
	
	# Fill image with depth values
	for cell in cells:
		var grid_x: int = int(cell.position.x)
		var grid_y: int = int(cell.position.y)
		
		# Calculate pixel region for this cell
		var px_start_x: int = grid_x * pixels_per_cell
		var px_start_y: int = grid_y * pixels_per_cell
		
		# Convert depth (0-4) to grayscale (1.0 = depth 0/highest, 0.0 = depth 4/lowest)
		var depth_normalized: float = 1.0 - (float(cell.depth) / 4.0)
		var pixel_color := Color(depth_normalized, 0, 0, 1)
		
		# Fill the cell's pixel block
		for py in range(pixels_per_cell):
			for px in range(pixels_per_cell):
				var img_x: int = px_start_x + px
				var img_y: int = px_start_y + py
				if img_x < tex_width and img_y < tex_height:
					image.set_pixel(img_x, img_y, pixel_color)
	
	# Apply Gaussian blur for smooth transitions
	if blur_radius > 0:
		print("[Heightmap] Applying Gaussian blur with radius ", blur_radius)
		image = _apply_gaussian_blur(image, blur_radius)
	
	# Debug: Save heightmap texture to file
	if export_heightmap_debug:
		var save_path: String = "res://debug_heightmap.png"
		image.save_png(save_path)
		print("[Heightmap] Saved debug texture to ", save_path)
	
	# Debug: Print depth distribution
	var depth_counts: Array[int] = [0, 0, 0, 0, 0]
	for cell in cells:
		if cell.depth >= 0 and cell.depth <= 4:
			depth_counts[cell.depth] += 1
	print("[Heightmap] Depth distribution: D0=", depth_counts[0], " D1=", depth_counts[1], " D2=", depth_counts[2], " D3=", depth_counts[3], " D4=", depth_counts[4])
	
	# Store image for collision generation
	_heightmap_image = image
	
	# Create texture from image
	var texture := ImageTexture.create_from_image(image)
	print("[Heightmap] Texture generated successfully")
	return texture


## Applies Gaussian blur to an image
func _apply_gaussian_blur(source_image: Image, radius: int) -> Image:
	var width: int = source_image.get_width()
	var height: int = source_image.get_height()
	
	# Create temporary image for horizontal pass
	var temp_image := Image.create(width, height, false, source_image.get_format())
	
	# Generate Gaussian kernel
	var kernel: Array[float] = []
	var kernel_sum: float = 0.0
	var sigma: float = radius / 2.0
	
	for i in range(-radius, radius + 1):
		var value: float = exp(-(i * i) / (2.0 * sigma * sigma))
		kernel.append(value)
		kernel_sum += value
	
	# Normalize kernel
	for i in range(kernel.size()):
		kernel[i] /= kernel_sum
	
	# Horizontal pass
	for y in range(height):
		for x in range(width):
			var sum: float = 0.0
			for i in range(-radius, radius + 1):
				var sample_x: int = clampi(x + i, 0, width - 1)
				var pixel: Color = source_image.get_pixel(sample_x, y)
				sum += pixel.r * kernel[i + radius]
			temp_image.set_pixel(x, y, Color(sum, 0, 0, 1))
	
	# Vertical pass
	var result_image := Image.create(width, height, false, source_image.get_format())
	for y in range(height):
		for x in range(width):
			var sum: float = 0.0
			for i in range(-radius, radius + 1):
				var sample_y: int = clampi(y + i, 0, height - 1)
				var pixel: Color = temp_image.get_pixel(x, sample_y)
				sum += pixel.r * kernel[i + radius]
			result_image.set_pixel(x, y, Color(sum, 0, 0, 1))
	
	return result_image


## Creates a subdivided plane mesh for terrain
func _create_terrain_mesh() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var plane_mesh := PlaneMesh.new()
	
	# Calculate actual playable area dimensions (without edge margins)
	var grid_width: int = int(floor(map_width / cell_size)) - (edge_margin * 2)
	var grid_height: int = int(floor(map_height / cell_size)) - (edge_margin * 2)
	var playable_width: float = grid_width * cell_size
	var playable_height: float = grid_height * cell_size
	
	# Size the plane to cover only the playable area
	plane_mesh.size = Vector2(playable_width, playable_height)
	
	# Subdivide based on grid and mesh_subdivisions
	plane_mesh.subdivide_width = grid_width * mesh_subdivisions
	plane_mesh.subdivide_depth = grid_height * mesh_subdivisions
	
	mesh_instance.mesh = plane_mesh
	
	# Position mesh lower so shader displacement brings depth 0 to floor_height
	# Shader displaces upward from 0 (depth 4) to amplitude (depth 0)
	# So mesh starts at floor_height - amplitude, depth 0 reaches floor_height
	var max_displacement: float = depth_step_height * 4.0 * heightmap_displacement_amplitude
	var offset: float = edge_margin * cell_size
	mesh_instance.position = Vector3(
		playable_width * 0.5 + offset,
		floor_height - max_displacement,
		playable_height * 0.5 + offset
	)
	mesh_instance.extra_cull_margin = 1000.0
	
	print("[Terrain Mesh] Created plane ", playable_width, "x", playable_height, " with ", plane_mesh.subdivide_width, "x", plane_mesh.subdivide_depth, " subdivisions")
	print("[Terrain Mesh] Max displacement: ", max_displacement, " units")
	print("[Terrain Mesh] Mesh base Y: ", floor_height - max_displacement, " (depth 4)")
	print("[Terrain Mesh] After displacement Y: ", floor_height, " (depth 0, wall level)")
	
	return mesh_instance


## Creates terrain shader with displacement and wall.tres material
func _create_terrain_displacement_material() -> ShaderMaterial:
	var shader_material := ShaderMaterial.new()
	var shader := Shader.new()
	
	# Calculate playable area size for shader
	var grid_width: int = int(floor(map_width / cell_size)) - (edge_margin * 2)
	var grid_height: int = int(floor(map_height / cell_size)) - (edge_margin * 2)
	var playable_width: float = grid_width * cell_size
	var playable_height: float = grid_height * cell_size
	
	# Get wall.tres material properties
	var wall_albedo: Color = Color(0.46, 0.18, 0.0, 1.0)
	var wall_emission: Color = Color(0.68, 0.0, 0.08, 1.0)
	var wall_emission_energy: float = 0.27
	var wall_roughness: float = 0.0
	var wall_metallic: float = 0.0
	var wall_metallic_specular: float = 0.0
	var wall_refraction_enabled: bool = false
	var wall_refraction_scale: float = 0.0
	
	if _base_material:
		wall_albedo = _base_material.albedo_color
		if _base_material.emission_enabled:
			wall_emission = _base_material.emission
			wall_emission_energy = _base_material.emission_energy_multiplier
		wall_roughness = _base_material.roughness
		wall_metallic = _base_material.metallic
		wall_metallic_specular = _base_material.metallic_specular
		if _base_material.refraction_enabled:
			wall_refraction_enabled = true
			wall_refraction_scale = _base_material.refraction_scale
	
	# Complete shader with displacement AND material
	shader.code = """
shader_type spatial;
render_mode depth_draw_opaque;

uniform sampler2D heightmap : repeat_disable;
uniform float amplitude = 1.0;
uniform vec2 plane_size = vec2(100.0, 100.0);
uniform vec4 albedo_color : source_color = vec4(0.46, 0.18, 0.0, 1.0);
uniform vec4 emission_color : source_color = vec4(0.68, 0.0, 0.08, 1.0);
uniform float emission_energy = 0.27;
uniform float roughness_value = 0.0;
uniform float metallic_value = 0.0;
uniform float specular_value = 0.0;

void vertex() {
	// VERTEX coordinates for PlaneMesh range from -plane_size/2 to +plane_size/2
	// Convert to UV space (0 to 1)
	vec2 uv = (VERTEX.xz / plane_size) + 0.5;
	
	// Sample heightmap and displace vertex upward
	float height_value = texture(heightmap, uv).r;
	VERTEX.y += height_value * amplitude;
	
	// Calculate normals from heightmap for proper lighting
	float texel_size_x = 1.0 / plane_size.x;
	float texel_size_z = 1.0 / plane_size.y;
	
	// Sample neighboring heights
	float height_right = texture(heightmap, uv + vec2(texel_size_x, 0.0)).r;
	float height_left = texture(heightmap, uv - vec2(texel_size_x, 0.0)).r;
	float height_up = texture(heightmap, uv + vec2(0.0, texel_size_z)).r;
	float height_down = texture(heightmap, uv - vec2(0.0, texel_size_z)).r;
	
	// Calculate tangent vectors
	vec3 tangent_x = vec3(2.0 * texel_size_x * plane_size.x, (height_right - height_left) * amplitude, 0.0);
	vec3 tangent_z = vec3(0.0, (height_up - height_down) * amplitude, 2.0 * texel_size_z * plane_size.y);
	
	// Cross product gives normal
	vec3 calculated_normal = normalize(cross(tangent_z, tangent_x));
	NORMAL = calculated_normal;
}

void fragment() {
	// Apply wall.tres material properties
	ALBEDO = albedo_color.rgb;
	EMISSION = emission_color.rgb * emission_energy;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	SPECULAR = specular_value;
}
"""
	
	shader_material.shader = shader
	shader_material.set_shader_parameter("heightmap", _heightmap_texture)
	shader_material.set_shader_parameter("amplitude", depth_step_height * 4.0 * heightmap_displacement_amplitude)
	shader_material.set_shader_parameter("plane_size", Vector2(playable_width, playable_height))
	shader_material.set_shader_parameter("albedo_color", wall_albedo)
	shader_material.set_shader_parameter("emission_color", wall_emission)
	shader_material.set_shader_parameter("emission_energy", wall_emission_energy)
	shader_material.set_shader_parameter("roughness_value", wall_roughness)
	shader_material.set_shader_parameter("metallic_value", wall_metallic)
	shader_material.set_shader_parameter("specular_value", wall_metallic_specular)
	
	print("[Terrain Shader] Material properties from wall.tres:")
	print("  Albedo: ", wall_albedo)
	print("  Emission: ", wall_emission, " * ", wall_emission_energy)
	print("  Roughness: ", wall_roughness, " Metallic: ", wall_metallic, " Specular: ", wall_metallic_specular)
	print("[Terrain Shader] Heightmap texture valid: ", _heightmap_texture != null)
	if _heightmap_texture:
		print("[Terrain Shader] Heightmap size: ", _heightmap_texture.get_width(), "x", _heightmap_texture.get_height())
	print("[Terrain Shader] Displacement amplitude: ", depth_step_height * 4.0 * heightmap_displacement_amplitude)
	
	return shader_material


## Spawns a flat base mesh (legacy/fallback).
func _spawn_base_mesh_flat() -> void:
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
	
	# Prevent culling at distance
	mesh_instance.extra_cull_margin = 1000.0
	var large_aabb := AABB(Vector3(-map_width, -10.0, -map_height), Vector3(map_width * 2, 20.0, map_height * 2))
	mesh_instance.set_custom_aabb(large_aabb)
	
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
	
	# Try to place on highground first
	var spawn_pos: Vector3
	if _highground_positions.size() > 0:
		# Place on a random highground position
		var highground_index: int = _rng.randi_range(0, _highground_positions.size() - 1)
		spawn_pos = _cell_to_world(_highground_positions[highground_index])
		spawn_pos.y = floor_height + 1.0
		print("[Player Spawn] Placed on highground at: ", spawn_pos)
	else:
		# Fallback to random floor tile if no highground
		var random_cell := _floor_cells[_rng.randi_range(0, _floor_cells.size() - 1)]
		spawn_pos = _cell_to_world(random_cell.position)
		spawn_pos.y = floor_height + 1.0
		print("[Player Spawn] Placed at random floor: ", spawn_pos)
	
	player.position = spawn_pos


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


## Converts world position (XZ) to grid coordinates.
func _world_to_grid(world_pos: Vector2) -> Vector2:
	var offset: float = edge_margin * cell_size
	var grid_x: float = (world_pos.x - offset - cell_size * 0.5) / cell_size
	var grid_y: float = (world_pos.y - offset - cell_size * 0.5) / cell_size
	return Vector2(round(grid_x), round(grid_y))


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


## Public getter for lava source positions (used by minimap).
func get_lava_sources() -> Array[Vector2]:
	return _lava_sources


## Public getter for highground positions (used by minimap).
func get_highground_positions() -> Array[Vector2]:
	return _highground_positions


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
