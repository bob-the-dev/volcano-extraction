extends Node3D

## Room-based procedural level generator ported from TypeScript.
## Generates rooms with floors, walls, and lava tiles.

# Signals
signal map_regenerated()
signal generation_stage_changed(step_index: int, step_count: int, title: String, description: String)

# Constants
const DEFAULT_TERRAIN_PERIMETER_CELLS: int = 2
const OUTER_TERRAIN_PERIMETER_DEPTH: int = 0
const HEIGHTMAP_DETAIL_NOISE_WORLD_SCALE: float = 4.0

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


class TerrainFootprint:
	var position_x: float
	var position_z: float
	var spawn_time: float
	var major_radius: float
	var direction_x: float
	var direction_z: float
	var minor_radius: float

	func _init(world_position: Vector3, spawn_time_seconds: float, move_direction: Vector3, major_radius_value: float, minor_radius_value: float) -> void:
		var horizontal_direction: Vector2 = Vector2(move_direction.x, move_direction.z)
		if horizontal_direction.length_squared() <= 0.0001:
			horizontal_direction = Vector2(0.0, 1.0)
		else:
			horizontal_direction = horizontal_direction.normalized()

		position_x = world_position.x
		position_z = world_position.z
		spawn_time = spawn_time_seconds
		major_radius = major_radius_value
		direction_x = horizontal_direction.x
		direction_z = horizontal_direction.y
		minor_radius = minor_radius_value

	func to_primary_vector() -> Vector4:
		return Vector4(position_x, position_z, spawn_time, major_radius)

	func to_shape_vector() -> Vector4:
		return Vector4(direction_x, direction_z, minor_radius, 0.0)

	func with_spawn_time(new_spawn_time: float) -> TerrainFootprint:
		return TerrainFootprint.new(
			Vector3(position_x, 0.0, position_z),
			new_spawn_time,
			Vector3(direction_x, 0.0, direction_z),
			major_radius,
			minor_radius
		)

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

@export_group("Materials")
@export var solid_ground_material: StandardMaterial3D = preload("res://materials/solid_ground.tres"):
	set(value):
		solid_ground_material = value
		_base_material = solid_ground_material
		if is_inside_tree():
			_sync_ground_surface_material_parameters(true)

@export_group("Terrain Perimeter")
## Adds a non-walkable terrain collar around the generated terrain outline.
@export_range(0, 4, 1) var terrain_perimeter_cells: int = DEFAULT_TERRAIN_PERIMETER_CELLS:
	set(value):
		terrain_perimeter_cells = value
		if not Engine.is_editor_hint() and is_inside_tree() and not _is_regenerating:
			call_deferred("_regenerate_map")

@export_group("Depth Sources")
## Number of rooms to designate as lava sources (depth 4 centers)
@export var num_lava_sources: int = 2
## Number of rooms to designate as highground (depth 0 centers)
@export var num_highground: int = 1
## Influence radius for depth sources (in cells)
@export var depth_source_influence: float = 4.0
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
@export_range(1, 128) var mesh_subdivisions: int = 48
## Heightmap displacement multiplier (higher = more dramatic height differences)
@export_range(0.1, 10.0) var heightmap_displacement_amplitude: float = 5.0
## Signed per-pixel heightmap noise added before blur. Negative values invert the extra detail.
@export_range(-0.5, 0.5, 0.001) var heightmap_noise_displacement_strength: float = 0.0
## Export heightmap texture for debugging
@export var export_heightmap_debug: bool = false

@export_group("Rendering")
## Use layered depth rendering for base mesh
@export var use_layered_depth: bool = true

@export_group("Exploration")
## Number of cells around the player that become permanently revealed on the minimap.
@export_range(0, 6, 1) var exploration_reveal_radius_cells: int = 2

@export_group("Footprints")
## Enable simple fading footprints on the terrain shader.
@export var enable_terrain_footprints: bool = true
## Maximum number of recent footprints kept visible in the terrain shader.
@export_range(4, 32, 1) var terrain_footprint_count: int = 12:
	set(value):
		terrain_footprint_count = value
		if not Engine.is_editor_hint() and is_inside_tree() and not _is_regenerating:
			call_deferred("_regenerate_map")
## Number of overflowed footprints allowed to remain while fading out.
@export_range(1, 16, 1) var terrain_footprint_overflow_fade_count: int = 6:
	set(value):
		terrain_footprint_overflow_fade_count = value
		if not Engine.is_editor_hint() and is_inside_tree() and not _is_regenerating:
			call_deferred("_regenerate_map")
## Lifetime in seconds for each footprint before it fully fades.
@export var terrain_footprint_lifetime: float = 5.0
## Fade time used when a footprint is pushed out by the visible count cap.
@export_range(0.1, 5.0, 0.1) var terrain_footprint_overflow_fade_duration: float = 1.2
## Half-length of each footprint ellipse along the movement direction.
@export var terrain_footprint_length: float = 0.26
## Half-width of each footprint ellipse across the movement direction.
@export var terrain_footprint_width: float = 0.12
## Darkness applied where the footprint mask is strongest.
@export_range(0.0, 1.0, 0.01) var terrain_footprint_strength: float = 0.32

@export_group("Scene Spawns")
## Optional scene to place at each deepest walkable source cell.
@export var deepest_point_scene: PackedScene = preload("res://fatguy.gltf")
## Fallback material override for procedurally spawned deepest-point meshes when the player material cannot be resolved.
@export var deepest_point_material_override: Material = preload("res://materials/player.tres")
## Match procedurally spawned deepest-point meshes to the live player material when available.
@export var deepest_point_match_player_material: bool = true
## Uniform scale applied to spawned deepest-point scenes.
@export var deepest_point_scene_scale: Vector3 = Vector3(8.909, 8.909, 8.909)
## Extra world-space height added after sampling the terrain surface.
@export var deepest_point_scene_height_offset: float = 0.0
## Keep deepest-point scenes afloat on the generated lava surface.
@export var deepest_point_float_on_lava: bool = true
## Disable physics collision on procedurally spawned deepest-point scenes.
@export var deepest_point_scene_disable_collision: bool = true
## Extra vertical offset from the lava surface for floating deepest-point scenes. Negative values sink them deeper.
@export var deepest_point_lava_float_offset: float = -0.08
## Vertical bob amplitude used to sell buoyancy.
@export_range(0.0, 1.0, 0.01) var deepest_point_bob_amplitude: float = 0.08
## Bob speed used for floating deepest-point scenes.
@export_range(0.0, 10.0, 0.05) var deepest_point_bob_speed: float = 1.4
## Enable gentle rocking while floating.
@export var deepest_point_rotate_while_floating: bool = true
## Maximum tilt around the X axis while floating, in degrees.
@export_range(0.0, 20.0, 0.1) var deepest_point_rock_x_amplitude_degrees: float = 3.0
## Maximum tilt around the Z axis while floating, in degrees.
@export_range(0.0, 20.0, 0.1) var deepest_point_rock_z_amplitude_degrees: float = 2.0
## Minimum rocking speed while floating, in cycles per second.
@export_range(0.0, 5.0, 0.05) var deepest_point_rock_speed_min: float = 0.25
## Maximum rocking speed while floating, in cycles per second.
@export_range(0.0, 5.0, 0.05) var deepest_point_rock_speed_max: float = 0.65

@export_group("Lava")
## Spawn a translucent lava volume over submerged terrain.
@export var render_lava: bool = true
## Lava surface height in depth levels, where 0 is highest and 4 is lowest.
@export_range(0.0, 4.0, 0.05) var lava_height_level: float = 3.0
## Automatically pushes the lava upward over time.
@export var lava_auto_rise_enabled: bool = false
## Rising speed in depth levels per second. Lower values produce a slower climb.
@export_range(0.0, 0.5, 0.001) var lava_rise_speed_levels_per_second: float = 0.02
## Immediately reset the lava back to depth level 3.0 when it reaches the surface.
@export var debug_loop_rising_lava: bool = false
## Amount to move the lava height per button press, measured in depth levels.
@export_range(0.05, 1.0, 0.05) var lava_height_step_levels: float = 0.25
## Interpolation speed used when animating the visible lava height toward the target level.
@export_range(0.5, 20.0, 0.1) var lava_height_lerp_speed: float = 6.0
## Lift the lava surface slightly to avoid z-fighting on the lava line.
@export var lava_surface_offset: float = 0.02
## Lowers the generated lava surface below its sampled depth level without changing terrain heights.
@export_range(0.0, 0.5, 0.005) var lava_surface_lowering: float = 0.03
## Extra world-space coverage added to each side of the generated surface.
@export_range(0.0, 1.0, 0.05) var lava_surface_margin_ratio: float = 0.2
## Minimum extra world-space coverage added to each side of the generated surface.
@export_range(0.0, 100.0, 0.5) var lava_surface_min_margin_world: float = 0.0
## Maximum subdivisions used for the generated lava surface plane.
@export_range(8, 256) var lava_surface_max_subdivisions: int = 96
## Optional material override for the generated lava surface.
@export var lava_material: Material
## Base color and transparency for the fallback generated lava surface material.
@export var lava_color: Color = Color(0.08, 0.33, 0.46, 0.5)
## Emission tint to keep the fallback material readable in darker areas.
@export var lava_emission_color: Color = Color(0.04, 0.18, 0.28, 1.0)

@export_group("Internal Walls")
## Convert some interior floor cells into actual wall cells during map generation.
@export var scatter_internal_walls: bool = true
## Noise scale used to cluster internal wall placement across the level.
@export_range(0.05, 2.0, 0.05) var internal_wall_noise_scale: float = 0.25
## Minimum normalized noise value required before a floor cell becomes an internal wall.
@export_range(0.0, 1.0, 0.01) var internal_wall_noise_threshold: float = 0.84
## Minimum number of neighboring floor cells required before converting a floor cell into a wall.
@export_range(0, 8, 1) var internal_wall_min_floor_neighbors: int = 5
## Print extra diagnostics for internal wall placement decisions.
@export var debug_internal_walls: bool = true

@export_group("Debug")
@export var show_grid_debug: bool = true
@export var grid_line_color: Color = Color(0, 1, 0, 0.5)
@export var grid_line_width: float = 0.02
## Show depth labels on terrain cells (0-4)
@export var show_depth_labels: bool = true
## Color for depth labels
@export var depth_label_color: Color = Color(1, 1, 1, 1)

# Private variables
var _rng: RandomNumberGenerator
var _noise: FastNoiseLite
var _wall_scene: PackedScene
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
var _lava_volume: MeshInstance3D
var _displayed_lava_height_level: float = 3.0
var _target_lava_height_level: float = 3.0
var _default_lava_surface_material: Material = preload("res://shaders/psOneLava.tres")
var _floating_deepest_point_nodes: Array[Node3D] = []
var _floating_motion_time: float = 0.0
var _terrain_shader_material: ShaderMaterial
var _terrain_footprints: Array[TerrainFootprint] = []
var _retiring_terrain_footprints: Array[TerrainFootprint] = []
var _terrain_grid_rect: Rect2i = Rect2i(0, 0, 0, 0)
var _terrain_world_rect: Rect2 = Rect2(Vector2.ZERO, Vector2.ZERO)
var _explored_cells: Dictionary = {}
var _exploration_player: Node3D = null
var _last_exploration_player_grid_key: String = ""

# Materials
var _base_material: StandardMaterial3D
var _last_ground_albedo: Color = Color(-1.0, -1.0, -1.0, -1.0)
var _last_ground_emission: Color = Color(-1.0, -1.0, -1.0, -1.0)
var _last_ground_emission_enabled: bool = false
var _last_ground_emission_energy: float = -1.0
var _last_ground_roughness: float = -1.0
var _last_ground_metallic: float = -1.0
var _last_ground_specular: float = -1.0

# Generated values (set during map generation)
var map_width: int = 100
var map_height: int = 100
var num_rooms: int = 12


func _ready() -> void:
	# Add to group for easy lookup
	add_to_group("procedural_map")
	_sync_lava_height_state()
	
	_wall_scene = load("res://procedural_wall.tscn")
	_base_material = solid_ground_material
	
	if regenerate_on_ready and not Engine.is_editor_hint():
		_regenerate_map()


func _process(delta: float) -> void:
	_floating_motion_time += delta
	_update_rising_lava(delta)
	_update_lava_height_animation(delta)
	_update_floating_deepest_point_scenes()
	_sync_terrain_footprint_shader_time()
	_sync_ground_surface_material_parameters()
	_update_exploration_tracking()


## Regenerates the entire map.
func _regenerate_map() -> void:
	if _is_regenerating:
		return
	
	_is_regenerating = true
	_sync_lava_height_state()
	_clear_map()
	_generate_map()
	_spawn_geometry()
	_spawn_deepest_point_scenes()
	_place_player_on_floor()
	_setup_exploration_tracking()
	_finalize_regeneration()


func generate_map_with_loading() -> void:
	if _is_regenerating:
		return

	var stage_count: int = 10
	_is_regenerating = true
	_sync_lava_height_state()
	_emit_generation_stage(1, stage_count, "Evicting Yesterday", "Sweeping out the last expedition before anyone trips over it.")
	await get_tree().process_frame
	_clear_map()

	_emit_generation_stage(2, stage_count, "Consulting The Volcano", "Reading tremors, static, and several deeply suspicious omens.")
	await get_tree().process_frame
	_initialize_generation_state()

	_emit_generation_stage(3, stage_count, "Sketching Escape Routes", "Dropping rooms where future panic will feel most cinematic.")
	await get_tree().process_frame
	_generate_rooms()

	_emit_generation_stage(4, stage_count, "Stamping The Grid", "Turning wild crater dreams into tiles the boots can understand.")
	await get_tree().process_frame
	_generate_cells()

	_emit_generation_stage(5, stage_count, "Teaching Rocks To Be Rude", "Marking walls in all the places your ankles would least appreciate.")
	await get_tree().process_frame
	_mark_walls()

	_emit_generation_stage(6, stage_count, "Pouring In The Regret", "Letting lava settle into every low spot that looked remotely comfortable.")
	await get_tree().process_frame
	_mark_lava()

	_emit_generation_stage(7, stage_count, "Extruding The Disaster", "Pulling cliffs, floors, and molten nonsense out of the ground.")
	await get_tree().process_frame
	_spawn_geometry()

	_emit_generation_stage(8, stage_count, "Launching The Mascot", "Floating our roundest survivor into the danger zone.")
	await get_tree().process_frame
	_spawn_deepest_point_scenes()

	_emit_generation_stage(9, stage_count, "Dropping You Somewhere Legal", "Finding a tile that counts as safe enough for paperwork.")
	await get_tree().process_frame
	_place_player_on_floor()

	_emit_generation_stage(10, stage_count, "Teaching The Map To Gossip", "Preparing exploration tracking for every questionable decision ahead.")
	await get_tree().process_frame
	_setup_exploration_tracking()
	_finalize_regeneration()


func _emit_generation_stage(step_index: int, step_count: int, title: String, description: String) -> void:
	generation_stage_changed.emit(step_index, step_count, title, description)


func _finalize_regeneration() -> void:
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
	_terrain_shader_material = null
	_terrain_footprints.clear()
	_retiring_terrain_footprints.clear()
	_terrain_grid_rect = Rect2i(0, 0, 0, 0)
	_terrain_world_rect = Rect2(Vector2.ZERO, Vector2.ZERO)
	_explored_cells.clear()
	_exploration_player = null
	_last_exploration_player_grid_key = ""
	_floating_deepest_point_nodes.clear()
	_floating_motion_time = 0.0
	_lava_volume = null
	_rooms.clear()
	_cells.clear()
	_lava_cells.clear()
	_floor_cells.clear()


## Main map generation algorithm (ported from TypeScript).
func _generate_map() -> void:
	_initialize_generation_state()

	# Generate rooms
	_generate_rooms()

	# Generate cell grid
	_generate_cells()

	# Mark walls (cells adjacent to floors)
	_mark_walls()

	# Mark lava
	_mark_lava()


func _initialize_generation_state() -> void:
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
		if cell.is_floor:
			cell.is_wall = false
		else:
			cell.is_wall = _has_neighbours(cell, "is_floor", 2.5)

	if not scatter_internal_walls or _noise == null:
		if debug_internal_walls:
			print("[Internal Walls] Skipped. enabled=", scatter_internal_walls, " noise=", _noise != null)
		return

	var protected_positions: Array[Vector2] = []
	for room in _rooms:
		var room_center_pos: Vector2 = _world_to_grid(room.position)
		var room_center_cell: Cell = _get_cell_at(room_center_pos)
		if room_center_cell != null and room_center_cell.is_floor:
			protected_positions.append(room_center_pos)

	var candidate_count: int = 0
	var protected_count: int = 0
	var sparse_count: int = 0
	var below_threshold_count: int = 0
	var converted_count: int = 0
	var min_noise_sample: float = INF
	var max_noise_sample: float = -INF

	for cell in _cells:
		if not cell.is_floor:
			continue

		candidate_count += 1

		if protected_positions.has(cell.position):
			protected_count += 1
			continue

		if _count_floor_neighbors(cell.position) < internal_wall_min_floor_neighbors:
			sparse_count += 1
			continue

		var noise_sample: float = _get_internal_wall_noise(cell.position)
		min_noise_sample = minf(min_noise_sample, noise_sample)
		max_noise_sample = maxf(max_noise_sample, noise_sample)
		if noise_sample < internal_wall_noise_threshold:
			below_threshold_count += 1
			continue

		cell.is_floor = false
		cell.is_wall = true
		converted_count += 1

	if min_noise_sample == INF:
		min_noise_sample = 0.0
	if max_noise_sample == -INF:
		max_noise_sample = 0.0

	if debug_internal_walls:
		print(
			"[Internal Walls] candidates=", candidate_count,
			" protected=", protected_count,
			" sparse=", sparse_count,
			" below_threshold=", below_threshold_count,
			" converted=", converted_count,
			" threshold=", internal_wall_noise_threshold,
			" noise_range=", Vector2(min_noise_sample, max_noise_sample)
		)


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
	print("[Map] Calculating terrain depths...")
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
	_spawn_lava_volume()
	
	for cell in _cells:
		var world_pos := _cell_to_world(cell.position)
		
		if cell.is_wall:
			_spawn_wall(world_pos)
			_spawn_depth_label(world_pos, cell.depth)
		elif cell.is_floor and not cell.is_lava:
			# Always collect floor cells for pathfinding
			_floor_cells.append(cell)
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
	wall.source_surface_material = _base_material
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


## Returns the normalized noise value used to decide whether a floor cell becomes an internal wall.
func _get_internal_wall_noise(grid_pos: Vector2) -> float:
	var sample_x: float = (grid_pos.x + 37.0) * internal_wall_noise_scale
	var sample_y: float = (grid_pos.y + 91.0) * internal_wall_noise_scale
	return (_noise.get_noise_2d(sample_x, sample_y) + 1.0) * 0.5


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

## Spawns a custom base mesh with layered depth (terraced platforms).
func _spawn_base_mesh() -> void:
	if not use_layered_depth:
		_spawn_base_mesh_flat()
		return
	
	# Collect all cells that should have base underneath, including the synthetic perimeter ring.
	var base_cells: Array[Cell] = _build_terrain_base_cells()
	
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
	
	# Step 3: Apply shader with displacement and solid ground material properties
	var terrain_shader := _create_terrain_displacement_material()
	_terrain_shader_material = terrain_shader
	mesh_instance.material_override = terrain_shader
	_sync_ground_surface_material_parameters(true)
	_sync_terrain_footprint_shader_parameters()
	
	# Step 4: Create collision that follows the displayed terrain surface
	var terrain_grid_rect: Rect2i = _get_terrain_grid_rect()
	var terrain_world_rect: Rect2 = _get_terrain_world_rect()
	
	var static_body := StaticBody3D.new()
	var collision_shape := CollisionShape3D.new()
	var terrain_collision_shape: Shape3D = _create_terrain_collision_shape(
		terrain_world_rect.size.x,
		terrain_world_rect.size.y,
		terrain_grid_rect.size.x,
		terrain_grid_rect.size.y
	)
	if terrain_collision_shape:
		collision_shape.shape = terrain_collision_shape
	else:
		var max_displacement: float = depth_step_height * 4.0 * heightmap_displacement_amplitude
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(terrain_world_rect.size.x, 0.2, terrain_world_rect.size.y)
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

func _get_terrain_grid_rect() -> Rect2i:
	return _terrain_grid_rect


func _get_terrain_world_rect() -> Rect2:
	return _terrain_world_rect


func _build_terrain_base_cells() -> Array[Cell]:
	var base_cells: Array[Cell] = []
	var occupied_positions: Dictionary = {}
	for cell in _cells:
		if cell.is_wall or cell.is_floor:
			base_cells.append(cell)
			var grid_pos: Vector2i = Vector2i(int(cell.position.x), int(cell.position.y))
			occupied_positions[_grid_position_key(grid_pos)] = grid_pos

	if base_cells.is_empty():
		_terrain_grid_rect = Rect2i(0, 0, 0, 0)
		_terrain_world_rect = Rect2(Vector2.ZERO, Vector2.ZERO)
		return base_cells

	var perimeter_positions: Dictionary = _build_terrain_perimeter_positions(occupied_positions)
	for perimeter_key in perimeter_positions.keys():
		var perimeter_grid_pos: Vector2i = perimeter_positions[perimeter_key]
		base_cells.append(_create_outer_terrain_perimeter_cell(perimeter_grid_pos))

	_update_terrain_bounds_from_cells(base_cells)
	return base_cells


func _build_terrain_perimeter_positions(occupied_positions: Dictionary) -> Dictionary:
	var perimeter_positions: Dictionary = {}
	var perimeter_layer_count: int = maxi(terrain_perimeter_cells, 0)
	if perimeter_layer_count <= 0 or occupied_positions.is_empty():
		return perimeter_positions

	var search_rect: Rect2i = _build_terrain_perimeter_search_rect(occupied_positions, perimeter_layer_count)
	var external_empty_positions: Dictionary = _flood_fill_external_empty_positions(search_rect, occupied_positions)
	var current_frontier: Array[Vector2i] = []
	var all_neighbor_offsets: Array[Vector2i] = _get_all_grid_neighbor_offsets()

	for occupied_key in occupied_positions.keys():
		var occupied_grid_pos: Vector2i = occupied_positions[occupied_key]
		for neighbor_offset in all_neighbor_offsets:
			var neighbor_grid_pos: Vector2i = occupied_grid_pos + neighbor_offset
			if not search_rect.has_point(neighbor_grid_pos):
				continue

			var neighbor_key: String = _grid_position_key(neighbor_grid_pos)
			if not external_empty_positions.has(neighbor_key) or perimeter_positions.has(neighbor_key):
				continue

			perimeter_positions[neighbor_key] = neighbor_grid_pos
			current_frontier.append(neighbor_grid_pos)

	for layer_index in range(1, perimeter_layer_count):
		var next_frontier: Array[Vector2i] = []
		for frontier_grid_pos in current_frontier:
			for neighbor_offset in all_neighbor_offsets:
				var neighbor_grid_pos: Vector2i = frontier_grid_pos + neighbor_offset
				if not search_rect.has_point(neighbor_grid_pos):
					continue

				var neighbor_key: String = _grid_position_key(neighbor_grid_pos)
				if not external_empty_positions.has(neighbor_key) or perimeter_positions.has(neighbor_key):
					continue

				perimeter_positions[neighbor_key] = neighbor_grid_pos
				next_frontier.append(neighbor_grid_pos)

		if next_frontier.is_empty():
			break

		current_frontier = next_frontier

	return perimeter_positions


func _build_terrain_perimeter_search_rect(occupied_positions: Dictionary, perimeter_layer_count: int) -> Rect2i:
	var terrain_rect: Rect2i = _calculate_grid_rect_from_position_lookup(occupied_positions)
	var search_padding: int = perimeter_layer_count + 1
	return Rect2i(
		terrain_rect.position.x - search_padding,
		terrain_rect.position.y - search_padding,
		terrain_rect.size.x + (search_padding * 2),
		terrain_rect.size.y + (search_padding * 2)
	)


func _flood_fill_external_empty_positions(search_rect: Rect2i, occupied_positions: Dictionary) -> Dictionary:
	var external_empty_positions: Dictionary = {}
	var queue: Array[Vector2i] = [search_rect.position]
	var queue_index: int = 0
	var cardinal_neighbor_offsets: Array[Vector2i] = _get_cardinal_grid_neighbor_offsets()

	while queue_index < queue.size():
		var current_grid_pos: Vector2i = queue[queue_index]
		queue_index += 1

		if not search_rect.has_point(current_grid_pos):
			continue

		var current_key: String = _grid_position_key(current_grid_pos)
		if occupied_positions.has(current_key) or external_empty_positions.has(current_key):
			continue

		external_empty_positions[current_key] = current_grid_pos
		for neighbor_offset in cardinal_neighbor_offsets:
			var neighbor_grid_pos: Vector2i = current_grid_pos + neighbor_offset
			if search_rect.has_point(neighbor_grid_pos):
				queue.append(neighbor_grid_pos)

	return external_empty_positions


func _calculate_grid_rect_from_position_lookup(position_lookup: Dictionary) -> Rect2i:
	if position_lookup.is_empty():
		return Rect2i(0, 0, 0, 0)

	var has_position: bool = false
	var min_x: int = 0
	var min_y: int = 0
	var max_x: int = 0
	var max_y: int = 0
	for position_key in position_lookup.keys():
		var grid_pos: Vector2i = position_lookup[position_key]
		if not has_position:
			min_x = grid_pos.x
			min_y = grid_pos.y
			max_x = grid_pos.x
			max_y = grid_pos.y
			has_position = true
			continue

		min_x = mini(min_x, grid_pos.x)
		min_y = mini(min_y, grid_pos.y)
		max_x = maxi(max_x, grid_pos.x)
		max_y = maxi(max_y, grid_pos.y)

	return Rect2i(min_x, min_y, (max_x - min_x) + 1, (max_y - min_y) + 1)


func _update_terrain_bounds_from_cells(cells: Array[Cell]) -> void:
	if cells.is_empty():
		_terrain_grid_rect = Rect2i(0, 0, 0, 0)
		_terrain_world_rect = Rect2(Vector2.ZERO, Vector2.ZERO)
		return

	var position_lookup: Dictionary = {}
	for cell in cells:
		var grid_pos: Vector2i = Vector2i(int(cell.position.x), int(cell.position.y))
		position_lookup[_grid_position_key(grid_pos)] = grid_pos

	_terrain_grid_rect = _calculate_grid_rect_from_position_lookup(position_lookup)
	var offset: float = edge_margin * cell_size
	_terrain_world_rect = Rect2(
		Vector2(
			_terrain_grid_rect.position.x * cell_size + offset,
			_terrain_grid_rect.position.y * cell_size + offset
		),
		Vector2(
			_terrain_grid_rect.size.x * cell_size,
			_terrain_grid_rect.size.y * cell_size
		)
	)


func _create_outer_terrain_perimeter_cell(grid_pos: Vector2i) -> Cell:
	var perimeter_cell: Cell = Cell.new()
	perimeter_cell.position = Vector2(float(grid_pos.x), float(grid_pos.y))
	perimeter_cell.filled = true
	perimeter_cell.is_floor = false
	perimeter_cell.is_wall = false
	perimeter_cell.is_lava = false
	perimeter_cell.type = "terrain_perimeter"
	perimeter_cell.noise_value = 0.0
	perimeter_cell.depth = OUTER_TERRAIN_PERIMETER_DEPTH
	return perimeter_cell


func _grid_position_key(grid_pos: Vector2i) -> String:
	return "%d,%d" % [grid_pos.x, grid_pos.y]


func _get_cardinal_grid_neighbor_offsets() -> Array[Vector2i]:
	return [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


func _get_all_grid_neighbor_offsets() -> Array[Vector2i]:
	return [
		Vector2i(-1, -1),
		Vector2i(0, -1),
		Vector2i(1, -1),
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(-1, 1),
		Vector2i(0, 1),
		Vector2i(1, 1)
	]


## Spawns the configured scene at each deepest walkable source cell.
func _spawn_deepest_point_scenes() -> void:
	if deepest_point_scene == null:
		return

	if _lava_sources.is_empty():
		return

	_floating_deepest_point_nodes.clear()
	var spawn_material_override: Material = _resolve_deepest_point_material_override()

	for source_grid_pos in _lava_sources:
		var source_cell: Cell = _get_cell_at(source_grid_pos)
		if source_cell == null:
			push_warning("[Deepest Spawn] Missing cell for source at ", source_grid_pos)
			continue

		var spawned_node: Node3D = deepest_point_scene.instantiate() as Node3D
		if spawned_node == null:
			push_warning("[Deepest Spawn] Configured scene root must inherit Node3D")
			return

		add_child(spawned_node)
		spawned_node.scale = deepest_point_scene_scale
		spawned_node.position = _get_deepest_point_spawn_position(source_cell, spawned_node)
		_disable_collision_for_deepest_point_scene(spawned_node)
		if spawn_material_override != null:
			_apply_material_override_to_meshes(spawned_node, spawn_material_override)
		spawned_node.add_to_group("deepest_point_scene")
		if _should_float_deepest_point_scene():
			var lowest_local_y: float = _get_lowest_local_y_for_node(spawned_node)
			var float_phase: float = _rng.randf_range(0.0, TAU)
			var base_yaw: float = _rng.randf_range(0.0, TAU)
			var rock_speed: float = _rng.randf_range(
				minf(deepest_point_rock_speed_min, deepest_point_rock_speed_max),
				maxf(deepest_point_rock_speed_min, deepest_point_rock_speed_max)
			)
			var rock_phase_x: float = _rng.randf_range(0.0, TAU)
			var rock_phase_z: float = _rng.randf_range(0.0, TAU)
			var rock_x_amplitude_radians: float = deg_to_rad(_rng.randf_range(0.4, 1.0) * deepest_point_rock_x_amplitude_degrees)
			var rock_z_amplitude_radians: float = deg_to_rad(_rng.randf_range(0.4, 1.0) * deepest_point_rock_z_amplitude_degrees)
			spawned_node.set_meta("deepest_point_lowest_local_y", lowest_local_y)
			spawned_node.set_meta("deepest_point_float_phase", float_phase)
			spawned_node.set_meta("deepest_point_base_yaw", base_yaw)
			spawned_node.set_meta("deepest_point_rock_speed", rock_speed)
			spawned_node.set_meta("deepest_point_rock_phase_x", rock_phase_x)
			spawned_node.set_meta("deepest_point_rock_phase_z", rock_phase_z)
			spawned_node.set_meta("deepest_point_rock_x_amplitude_radians", rock_x_amplitude_radians)
			spawned_node.set_meta("deepest_point_rock_z_amplitude_radians", rock_z_amplitude_radians)
			spawned_node.rotation.y = base_yaw
			_floating_deepest_point_nodes.append(spawned_node)
		_spawned_objects.append(spawned_node)

	print("[Deepest Spawn] Spawned ", _lava_sources.size(), " scene instances")


func _resolve_deepest_point_material_override() -> Material:
	if deepest_point_match_player_material:
		var player_node: Node = NodeUtils.find_node(self, "player", ["../Player"], "Player.gd")
		if player_node != null:
			var player_material: Material = _find_first_material_override_in_subtree(player_node)
			if player_material != null:
				return player_material

	return deepest_point_material_override


func _find_first_material_override_in_subtree(current_node: Node) -> Material:
	if current_node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = current_node as MeshInstance3D
		if mesh_instance.material_override != null:
			return mesh_instance.material_override
		if mesh_instance.mesh != null:
			var surface_count: int = mesh_instance.mesh.get_surface_count()
			for surface_index in range(surface_count):
				var surface_material: Material = mesh_instance.get_active_material(surface_index)
				if surface_material != null:
					return surface_material

	for child in current_node.get_children():
		var child_node: Node = child
		var child_material: Material = _find_first_material_override_in_subtree(child_node)
		if child_material != null:
			return child_material

	return null



func _get_deepest_point_spawn_position(source_cell: Cell, spawned_node: Node3D) -> Vector3:
	var spawn_position: Vector3 = _get_cell_surface_position(source_cell) + Vector3(0.0, deepest_point_scene_height_offset, 0.0)
	var lowest_local_y: float = _get_lowest_local_y_for_node(spawned_node)
	if not _should_float_deepest_point_scene():
		spawn_position.y -= lowest_local_y
		return spawn_position

	spawn_position.y = _get_lava_surface_world_height(_displayed_lava_height_level) + deepest_point_scene_height_offset + deepest_point_lava_float_offset - lowest_local_y
	return spawn_position

func _disable_collision_for_deepest_point_scene(root_node: Node) -> void:
	if not deepest_point_scene_disable_collision:
		return

	_disable_collision_in_subtree(root_node)

func _disable_collision_in_subtree(current_node: Node) -> void:
	if current_node is CollisionObject3D:
		var collision_object: CollisionObject3D = current_node as CollisionObject3D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0

	if current_node is CollisionShape3D:
		var collision_shape: CollisionShape3D = current_node as CollisionShape3D
		collision_shape.disabled = true

	if current_node is CollisionPolygon3D:
		var collision_polygon: CollisionPolygon3D = current_node as CollisionPolygon3D
		collision_polygon.disabled = true

	for child in current_node.get_children():
		var child_node: Node = child
		_disable_collision_in_subtree(child_node)


func _should_float_deepest_point_scene() -> bool:
	return deepest_point_float_on_lava and render_lava and use_layered_depth


func _update_floating_deepest_point_scenes() -> void:
	if _floating_deepest_point_nodes.is_empty():
		return

	if not _should_float_deepest_point_scene():
		return

	var surface_y: float = _get_lava_surface_world_height(_displayed_lava_height_level) + deepest_point_scene_height_offset + deepest_point_lava_float_offset
	for spawned_node in _floating_deepest_point_nodes:
		if not is_instance_valid(spawned_node):
			continue

		var lowest_local_y: float = 0.0
		if spawned_node.has_meta("deepest_point_lowest_local_y"):
			lowest_local_y = float(spawned_node.get_meta("deepest_point_lowest_local_y"))

		var float_phase: float = 0.0
		if spawned_node.has_meta("deepest_point_float_phase"):
			float_phase = float(spawned_node.get_meta("deepest_point_float_phase"))

		var bob_offset: float = sin((_floating_motion_time * deepest_point_bob_speed) + float_phase) * deepest_point_bob_amplitude
		var next_position: Vector3 = spawned_node.position
		next_position.y = surface_y - lowest_local_y + bob_offset
		spawned_node.position = next_position

		if deepest_point_rotate_while_floating:
			var base_yaw: float = 0.0
			if spawned_node.has_meta("deepest_point_base_yaw"):
				base_yaw = float(spawned_node.get_meta("deepest_point_base_yaw"))

			var rock_speed: float = 0.0
			if spawned_node.has_meta("deepest_point_rock_speed"):
				rock_speed = float(spawned_node.get_meta("deepest_point_rock_speed"))

			var rock_phase_x: float = 0.0
			if spawned_node.has_meta("deepest_point_rock_phase_x"):
				rock_phase_x = float(spawned_node.get_meta("deepest_point_rock_phase_x"))

			var rock_phase_z: float = 0.0
			if spawned_node.has_meta("deepest_point_rock_phase_z"):
				rock_phase_z = float(spawned_node.get_meta("deepest_point_rock_phase_z"))

			var rock_x_amplitude_radians: float = 0.0
			if spawned_node.has_meta("deepest_point_rock_x_amplitude_radians"):
				rock_x_amplitude_radians = float(spawned_node.get_meta("deepest_point_rock_x_amplitude_radians"))

			var rock_z_amplitude_radians: float = 0.0
			if spawned_node.has_meta("deepest_point_rock_z_amplitude_radians"):
				rock_z_amplitude_radians = float(spawned_node.get_meta("deepest_point_rock_z_amplitude_radians"))

			var next_rotation: Vector3 = spawned_node.rotation
			next_rotation.x = sin((_floating_motion_time * TAU * rock_speed) + rock_phase_x) * rock_x_amplitude_radians
			next_rotation.y = base_yaw
			next_rotation.z = sin((_floating_motion_time * TAU * rock_speed * 0.87) + rock_phase_z) * rock_z_amplitude_radians
			spawned_node.rotation = next_rotation


func _get_lowest_local_y_for_node(root_node: Node3D) -> float:
	var bounds_state: Dictionary = {
		"found_mesh": false,
		"min_y": 0.0,
	}
	_collect_lowest_local_y(root_node, root_node, bounds_state)
	return float(bounds_state.get("min_y", 0.0))


func _collect_lowest_local_y(root_node: Node3D, current_node: Node, bounds_state: Dictionary) -> void:
	if current_node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = current_node as MeshInstance3D
		if mesh_instance.mesh != null:
			var local_transform: Transform3D = root_node.global_transform.affine_inverse() * mesh_instance.global_transform
			var mesh_aabb: AABB = mesh_instance.mesh.get_aabb()
			var corners: Array[Vector3] = _get_aabb_corners(mesh_aabb)
			for corner in corners:
				var corner_in_root: Vector3 = local_transform * corner
				if not bool(bounds_state.get("found_mesh", false)) or corner_in_root.y < float(bounds_state.get("min_y", 0.0)):
					bounds_state["min_y"] = corner_in_root.y
					bounds_state["found_mesh"] = true

	for child in current_node.get_children():
		var child_node: Node = child
		_collect_lowest_local_y(root_node, child_node, bounds_state)


func _get_aabb_corners(bounds: AABB) -> Array[Vector3]:
	var corners: Array[Vector3] = []
	var min_corner: Vector3 = bounds.position
	var max_corner: Vector3 = bounds.position + bounds.size
	corners.append(Vector3(min_corner.x, min_corner.y, min_corner.z))
	corners.append(Vector3(min_corner.x, min_corner.y, max_corner.z))
	corners.append(Vector3(min_corner.x, max_corner.y, min_corner.z))
	corners.append(Vector3(min_corner.x, max_corner.y, max_corner.z))
	corners.append(Vector3(max_corner.x, min_corner.y, min_corner.z))
	corners.append(Vector3(max_corner.x, min_corner.y, max_corner.z))
	corners.append(Vector3(max_corner.x, max_corner.y, min_corner.z))
	corners.append(Vector3(max_corner.x, max_corner.y, max_corner.z))
	return corners


## Applies a material override to every mesh in a spawned scene subtree.
func _apply_material_override_to_meshes(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		mesh_instance.material_override = material

	for child in node.get_children():
		var child_node: Node = child
		_apply_material_override_to_meshes(child_node, material)


## Spawns a full-area lava surface plane that tracks the configured depth level.
func _spawn_lava_volume() -> void:
	_remove_lava_volume()

	if not render_lava or not use_layered_depth:
		return

	var surface_bounds: Dictionary = _get_lava_surface_bounds()
	if surface_bounds.is_empty():
		push_warning("[Lava] Could not determine generated map bounds for lava surface")
		return

	var clamped_lava_level: float = clampf(_displayed_lava_height_level, 0.0, 4.0)
	var surface_y: float = _get_lava_surface_world_height(clamped_lava_level)
	var surface_center: Vector3 = surface_bounds.get("center", Vector3.ZERO)
	var surface_size: Vector2 = surface_bounds.get("size", Vector2.ZERO)
	if surface_size.x <= 0.0 or surface_size.y <= 0.0:
		push_warning("[Lava] Lava surface bounds produced an invalid size")
		return

	var plane_mesh: PlaneMesh = PlaneMesh.new()
	plane_mesh.size = surface_size
	var subdivisions_x: int = clampi(int(ceil(surface_size.x / maxf(cell_size, 0.001))), 8, lava_surface_max_subdivisions)
	var subdivisions_z: int = clampi(int(ceil(surface_size.y / maxf(cell_size, 0.001))), 8, lava_surface_max_subdivisions)
	plane_mesh.subdivide_width = subdivisions_x
	plane_mesh.subdivide_depth = subdivisions_z

	var lava_instance: MeshInstance3D = MeshInstance3D.new()
	lava_instance.mesh = plane_mesh
	lava_instance.material_override = _create_lava_material()
	lava_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lava_instance.extra_cull_margin = 1000.0
	lava_instance.add_to_group("lava_volume")
	lava_instance.add_to_group("lava_surface")
	lava_instance.position = Vector3(surface_center.x, surface_y, surface_center.z)
	_lava_volume = lava_instance

	add_child(lava_instance)
	_spawned_objects.append(lava_instance)

	print("[Lava] Spawned lava surface plane at level ", clamped_lava_level, " with size ", surface_size)


## Creates the material used by the generated lava surface.
func _create_lava_material() -> Material:
	if lava_material != null:
		return lava_material

	if _default_lava_surface_material != null:
		return _default_lava_surface_material

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = lava_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.08
	material.metallic = 0.02
	material.emission_enabled = true
	material.emission = lava_emission_color
	material.emission_energy_multiplier = 0.35
	material.refraction_enabled = true
	material.refraction_scale = 0.02
	return material


## Raises the lava surface by one configured step.
func raise_lava_height() -> float:
	return set_lava_height_level(lava_height_level - lava_height_step_levels)


## Lowers the lava surface by one configured step.
func lower_lava_height() -> float:
	return set_lava_height_level(lava_height_level + lava_height_step_levels)


## Sets the lava surface height in depth levels and refreshes the lava mesh.
func set_lava_height_level(new_level: float) -> float:
	var clamped_level: float = clampf(new_level, 0.0, 4.0)
	if is_equal_approx(clamped_level, _target_lava_height_level):
		return _target_lava_height_level

	lava_height_level = clamped_level
	_target_lava_height_level = clamped_level
	if _cells.is_empty():
		_displayed_lava_height_level = clamped_level
	return _target_lava_height_level


## Returns the current lava height in depth levels.
func get_lava_height_level() -> float:
	return _displayed_lava_height_level


## Returns the current target lava height in depth levels.
func get_target_lava_height_level() -> float:
	return _target_lava_height_level


## Returns the visible lava height as a normalized world-height percentage.
func get_lava_height_normalized() -> float:
	return clampf(1.0 - (_displayed_lava_height_level / 4.0), 0.0, 1.0)


## Removes and rebuilds only the lava mesh for runtime height updates.
func _refresh_lava_volume() -> void:
	if _cells.is_empty():
		return

	if _lava_volume == null or not is_instance_valid(_lava_volume):
		_spawn_lava_volume()
		return

	_lava_volume.position.y = _get_lava_surface_world_height(_displayed_lava_height_level)


## Synchronizes the lava target and displayed level from the exported value.
func _sync_lava_height_state() -> void:
	var clamped_level: float = clampf(lava_height_level, 0.0, 4.0)
	lava_height_level = clamped_level
	_target_lava_height_level = clamped_level
	_displayed_lava_height_level = clamped_level


## Gradually raises the lava toward depth 0 and optionally loops back for debugging.
func _update_rising_lava(delta: float) -> void:
	if not lava_auto_rise_enabled:
		return

	if lava_rise_speed_levels_per_second <= 0.0:
		return

	if _target_lava_height_level <= 0.0:
		if debug_loop_rising_lava:
			lava_height_level = 4.0
			_target_lava_height_level = 4.0
			_displayed_lava_height_level = 4.0
			_refresh_lava_volume()
		return

	var next_target_level: float = maxf(0.0, _target_lava_height_level - (lava_rise_speed_levels_per_second * delta))
	if is_equal_approx(next_target_level, _target_lava_height_level):
		return

	lava_height_level = next_target_level
	_target_lava_height_level = next_target_level


## Animates the visible lava level toward the target and refreshes the lava mesh.
func _update_lava_height_animation(delta: float) -> void:
	if _cells.is_empty() or not render_lava or not use_layered_depth:
		return

	if is_equal_approx(_displayed_lava_height_level, _target_lava_height_level):
		return

	var lerp_weight: float = minf(1.0, lava_height_lerp_speed * delta)
	var next_lava_level: float = lerpf(_displayed_lava_height_level, _target_lava_height_level, lerp_weight)
	if absf(next_lava_level - _target_lava_height_level) <= 0.01:
		next_lava_level = _target_lava_height_level

	if is_equal_approx(next_lava_level, _displayed_lava_height_level):
		return

	_displayed_lava_height_level = next_lava_level
	_refresh_lava_volume()


## Removes the current lava volume if one is present.
func _remove_lava_volume() -> void:
	if _lava_volume == null:
		return

	if _spawned_objects.has(_lava_volume):
		_spawned_objects.erase(_lava_volume)

	if is_instance_valid(_lava_volume):
		_lava_volume.queue_free()

	_lava_volume = null


## Converts a discrete depth level into the world-space terrain height.
func _get_depth_world_height(depth: int) -> float:
	return _get_depth_level_world_height(float(depth))


## Returns the world-space height used by the generated lava surface plane.
func _get_lava_surface_world_height(depth_level: float) -> float:
	return _get_depth_level_world_height(depth_level) + lava_surface_offset - lava_surface_lowering


## Returns the generated map bounds expanded with an extra surface margin on every side.
func _get_lava_surface_bounds() -> Dictionary:
	if _cells.is_empty():
		return {}

	var half_cell: float = cell_size * 0.5
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF

	for cell in _cells:
		if not cell.filled:
			continue

		var world_pos: Vector3 = _cell_to_world(cell.position)
		min_x = minf(min_x, world_pos.x - half_cell)
		max_x = maxf(max_x, world_pos.x + half_cell)
		min_z = minf(min_z, world_pos.z - half_cell)
		max_z = maxf(max_z, world_pos.z + half_cell)

	if min_x == INF or min_z == INF:
		return {}

	var base_width: float = max_x - min_x
	var base_depth: float = max_z - min_z
	var margin_x: float = maxf(base_width * lava_surface_margin_ratio, lava_surface_min_margin_world)
	var margin_z: float = maxf(base_depth * lava_surface_margin_ratio, lava_surface_min_margin_world)
	var expanded_width: float = base_width + (margin_x * 2.0)
	var expanded_depth: float = base_depth + (margin_z * 2.0)
	var center: Vector3 = Vector3((min_x + max_x) * 0.5, 0.0, (min_z + max_z) * 0.5)

	return {
		"center": center,
		"size": Vector2(expanded_width, expanded_depth)
	}


func _setup_exploration_tracking() -> void:
	_explored_cells.clear()
	_last_exploration_player_grid_key = ""
	_exploration_player = null

	if _cells.is_empty():
		return

	_exploration_player = NodeUtils.find(self, "player", ["../Player"])
	if _exploration_player == null:
		push_warning("[Exploration] Player not found. Explored areas will not update.")
		return

	_update_exploration_tracking(true)


func _update_exploration_tracking(force_reveal: bool = false) -> void:
	if _cells.is_empty():
		return

	if _exploration_player == null or not is_instance_valid(_exploration_player):
		_exploration_player = NodeUtils.find(self, "player", ["../Player"])
		if _exploration_player == null:
			return

	var player_grid: Vector2 = _world_to_grid(Vector2(_exploration_player.global_position.x, _exploration_player.global_position.z))
	var player_grid_pos: Vector2i = Vector2i(int(player_grid.x), int(player_grid.y))
	var player_grid_key: String = _grid_position_key(player_grid_pos)
	if not force_reveal and player_grid_key == _last_exploration_player_grid_key:
		return

	_last_exploration_player_grid_key = player_grid_key
	_reveal_exploration_cells(player_grid_pos)


func _reveal_exploration_cells(center_grid_pos: Vector2i) -> void:
	for x_offset in range(-exploration_reveal_radius_cells, exploration_reveal_radius_cells + 1):
		for y_offset in range(-exploration_reveal_radius_cells, exploration_reveal_radius_cells + 1):
			var offset: Vector2 = Vector2(float(x_offset), float(y_offset))
			if offset.length() > float(exploration_reveal_radius_cells) + 0.35:
				continue

			var grid_pos: Vector2i = Vector2i(center_grid_pos.x + x_offset, center_grid_pos.y + y_offset)
			_reveal_exploration_cell(grid_pos)


func _reveal_exploration_cell(grid_pos: Vector2i) -> void:
	var cell: Cell = _get_cell_at(Vector2(float(grid_pos.x), float(grid_pos.y)))
	if cell == null or not cell.filled:
		return

	var grid_key: String = _grid_position_key(grid_pos)
	_explored_cells[grid_key] = true


## Converts a continuous depth level into the world-space terrain height.
func _get_depth_level_world_height(depth_level: float) -> float:
	var clamped_depth_level: float = clampf(depth_level, 0.0, 4.0)
	var max_displacement: float = _get_max_terrain_displacement()
	var normalized_height: float = 1.0 - (clamped_depth_level / 4.0)
	return floor_height - max_displacement + (normalized_height * max_displacement)


## Returns the maximum terrain height displacement used by the terrain mesh.
func _get_max_terrain_displacement() -> float:
	return depth_step_height * 4.0 * heightmap_displacement_amplitude


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


func _get_heightmap_detail_noise(world_x: float, world_z: float) -> float:
	if _noise == null or is_zero_approx(heightmap_noise_displacement_strength):
		return 0.0

	var sample_x: float = (world_x + 137.0) * HEIGHTMAP_DETAIL_NOISE_WORLD_SCALE
	var sample_z: float = (world_z + 281.0) * HEIGHTMAP_DETAIL_NOISE_WORLD_SCALE
	var detail_noise: float = _noise.get_noise_2d(sample_x, sample_z)
	return detail_noise * heightmap_noise_displacement_strength


## Generates a heightmap texture from cell depth data
func _generate_heightmap_texture(cells: Array[Cell]) -> ImageTexture:
	var terrain_grid_rect: Rect2i = _get_terrain_grid_rect()
	var grid_width: int = terrain_grid_rect.size.x
	var grid_height: int = terrain_grid_rect.size.y
	var tex_width: int = grid_width * pixels_per_cell
	var tex_height: int = grid_height * pixels_per_cell
	
	print("[Heightmap] Creating ", tex_width, "x", tex_height, " texture (", grid_width, "x", grid_height, " cells)")
	
	# Create image
	var image := Image.create(tex_width, tex_height, false, Image.FORMAT_RF)
	image.fill(Color(0, 0, 0, 1))  # Black = lowest depth
	
	# Fill image with depth values
	for cell in cells:
		var grid_x: int = int(cell.position.x) - terrain_grid_rect.position.x
		var grid_y: int = int(cell.position.y) - terrain_grid_rect.position.y
		
		# Calculate pixel region for this cell
		var px_start_x: int = grid_x * pixels_per_cell
		var px_start_y: int = grid_y * pixels_per_cell
		
		# Convert depth (0-4) to grayscale (1.0 = depth 0/highest, 0.0 = depth 4/lowest)
		var depth_normalized: float = 1.0 - (float(cell.depth) / 4.0)
		var pixel_color: Color = Color(depth_normalized, 0, 0, 1)
		
		# Fill the cell's pixel block
		for py in range(pixels_per_cell):
			for px in range(pixels_per_cell):
				var img_x: int = px_start_x + px
				var img_y: int = px_start_y + py
				if img_x < tex_width and img_y < tex_height:
					image.set_pixel(img_x, img_y, pixel_color)
	
	if not is_zero_approx(heightmap_noise_displacement_strength):
		image = _apply_heightmap_detail_noise(image, terrain_grid_rect)

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


func _apply_heightmap_detail_noise(source_image: Image, terrain_grid_rect: Rect2i) -> Image:
	var width: int = source_image.get_width()
	var height: int = source_image.get_height()
	if width <= 0 or height <= 0:
		return source_image

	var result_image: Image = source_image.duplicate()
	for y in range(height):
		for x in range(width):
			var grid_x: float = float(x) / float(pixels_per_cell)
			var grid_y: float = float(y) / float(pixels_per_cell)
			var world_x: float = (float(terrain_grid_rect.position.x) + grid_x + 0.5) * cell_size + (edge_margin * cell_size)
			var world_z: float = (float(terrain_grid_rect.position.y) + grid_y + 0.5) * cell_size + (edge_margin * cell_size)
			var detail_noise: float = _get_heightmap_detail_noise(world_x, world_z)
			var current_height: float = source_image.get_pixel(x, y).r
			var displaced_height: float = clampf(current_height + detail_noise, 0.0, 1.0)
			result_image.set_pixel(x, y, Color(displaced_height, 0, 0, 1))

	return result_image


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
	
	var terrain_grid_rect: Rect2i = _get_terrain_grid_rect()
	var terrain_world_rect: Rect2 = _get_terrain_world_rect()
	var terrain_width: float = terrain_world_rect.size.x
	var terrain_height: float = terrain_world_rect.size.y
	
	# Size the plane to cover the generated area plus the outer edge expansion ring.
	plane_mesh.size = Vector2(terrain_width, terrain_height)
	
	# Subdivide based on grid and mesh_subdivisions
	plane_mesh.subdivide_width = terrain_grid_rect.size.x * mesh_subdivisions
	plane_mesh.subdivide_depth = terrain_grid_rect.size.y * mesh_subdivisions
	
	mesh_instance.mesh = plane_mesh
	
	# Position mesh lower so shader displacement brings depth 0 to floor_height
	# Shader displaces upward from 0 (depth 4) to amplitude (depth 0)
	# So mesh starts at floor_height - amplitude, depth 0 reaches floor_height
	var max_displacement: float = depth_step_height * 4.0 * heightmap_displacement_amplitude
	mesh_instance.position = Vector3(
		terrain_world_rect.position.x + (terrain_width * 0.5),
		floor_height - max_displacement,
		terrain_world_rect.position.y + (terrain_height * 0.5)
	)
	mesh_instance.extra_cull_margin = 1000.0
	
	print("[Terrain Mesh] Created plane ", terrain_width, "x", terrain_height, " with ", plane_mesh.subdivide_width, "x", plane_mesh.subdivide_depth, " subdivisions")
	print("[Terrain Mesh] Max displacement: ", max_displacement, " units")
	print("[Terrain Mesh] Mesh base Y: ", floor_height - max_displacement, " (depth 4)")
	print("[Terrain Mesh] After displacement Y: ", floor_height, " (depth 0, wall level)")
	
	return mesh_instance


## Creates terrain shader with displacement and the shared solid ground material.
func _create_terrain_displacement_material() -> ShaderMaterial:
	var shader_material := ShaderMaterial.new()
	var shader := Shader.new()
	var footprint_uniforms: Array[String] = []
	var footprint_contributions: Array[String] = []
	for index in range(_get_total_terrain_footprint_shader_slots()):
		footprint_uniforms.append("uniform vec4 footprint_data_%d = vec4(0.0, 0.0, -1000.0, 0.0);" % index)
		footprint_uniforms.append("uniform vec4 footprint_shape_%d = vec4(0.0, 1.0, 0.0, 0.0);" % index)
		footprint_contributions.append("\tfootprint_mask += compute_footprint_mask(footprint_data_%d, footprint_shape_%d, world_xz);" % [index, index])
	
	var terrain_world_rect: Rect2 = _get_terrain_world_rect()
	
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
uniform float bottom_darkness = 0.45;
uniform float depth_gradient_strength = 1.0;
uniform float darkness_noise_scale = 18.0;
uniform float darkness_noise_strength = 0.16;
uniform float footprint_lifetime = 5.0;
uniform float footprint_strength = 0.32;
uniform float footprint_current_time = 0.0;
%s

varying vec2 heightmap_uv;
varying vec2 world_xz;
varying float terrain_upness;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 uv) {
	vec2 cell = floor(uv);
	vec2 local = fract(uv);
	vec2 smooth_local = local * local * (3.0 - 2.0 * local);

	float bottom_left = hash12(cell);
	float bottom_right = hash12(cell + vec2(1.0, 0.0));
	float top_left = hash12(cell + vec2(0.0, 1.0));
	float top_right = hash12(cell + vec2(1.0, 1.0));

	float bottom_mix = mix(bottom_left, bottom_right, smooth_local.x);
	float top_mix = mix(top_left, top_right, smooth_local.x);
	return mix(bottom_mix, top_mix, smooth_local.y);
}

float compute_footprint_mask(vec4 footprint_data, vec4 footprint_shape, vec2 sample_world_xz) {
	if (footprint_data.w <= 0.0 || footprint_shape.z <= 0.0) {
		return 0.0;
	}

	float age = footprint_current_time - footprint_data.z;
	if (age < 0.0 || age > footprint_lifetime) {
		return 0.0;
	}

	vec2 forward_axis = footprint_shape.xy;
	if (length(forward_axis) <= 0.0001) {
		forward_axis = vec2(0.0, 1.0);
	} else {
		forward_axis = normalize(forward_axis);
	}
	vec2 right_axis = vec2(-forward_axis.y, forward_axis.x);
	vec2 sample_offset = sample_world_xz - footprint_data.xy;
	float local_right = dot(sample_offset, right_axis);
	float local_forward = dot(sample_offset, forward_axis);
	float ellipse_distance = length(vec2(local_right / footprint_shape.z, local_forward / footprint_data.w));
	float radial_mask = 1.0 - smoothstep(0.55, 1.0, ellipse_distance);
	float fade_mask = 1.0 - clamp(age / footprint_lifetime, 0.0, 1.0);
	return radial_mask * fade_mask;
}

void vertex() {
	// VERTEX coordinates for PlaneMesh range from -plane_size/2 to +plane_size/2
	// Convert to UV space (0 to 1)
	vec2 uv = (VERTEX.xz / plane_size) + 0.5;
	heightmap_uv = uv;
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	
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
	terrain_upness = clamp(calculated_normal.y, 0.0, 1.0);
}

void fragment() {
	float height_value = texture(heightmap, heightmap_uv).r;
	float noise_a = value_noise(heightmap_uv * darkness_noise_scale);
	float noise_b = value_noise((heightmap_uv + vec2(17.3, 9.1)) * (darkness_noise_scale * 0.5));
	float combined_noise = mix(noise_a, noise_b, 0.35);
	float noise_offset = (combined_noise - 0.5) * darkness_noise_strength;
	float depth_factor = clamp((1.0 - height_value) * depth_gradient_strength + noise_offset, 0.0, 1.0);
	vec3 depth_tint = mix(vec3(bottom_darkness), vec3(1.0), 1.0 - depth_factor);
	float footprint_mask = 0.0;
%s
	float slope_mask = smoothstep(0.2, 0.7, terrain_upness);
	float final_footprint_mask = clamp(footprint_mask * slope_mask, 0.0, 1.0);
	vec3 footprint_tint = vec3(1.0 - footprint_strength * final_footprint_mask);

	// Apply shared surface material properties
	ALBEDO = albedo_color.rgb * depth_tint * footprint_tint;
	EMISSION = emission_color.rgb * emission_energy * depth_tint * footprint_tint;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	SPECULAR = specular_value;
}
""" % ["\n".join(footprint_uniforms), "\n".join(footprint_contributions)]
	
	shader_material.shader = shader
	shader_material.set_shader_parameter("heightmap", _heightmap_texture)
	shader_material.set_shader_parameter("amplitude", depth_step_height * 4.0 * heightmap_displacement_amplitude)
	shader_material.set_shader_parameter("plane_size", terrain_world_rect.size)
	_apply_ground_surface_parameters_to_terrain_shader(shader_material)
	shader_material.set_shader_parameter("footprint_lifetime", terrain_footprint_lifetime)
	shader_material.set_shader_parameter("footprint_strength", terrain_footprint_strength)
	
	print("[Terrain Shader] Material properties from solid_ground_material:")
	if _base_material != null:
		print("  Albedo: ", _base_material.albedo_color)
		if _base_material.emission_enabled:
			print("  Emission: ", _base_material.emission, " * ", _base_material.emission_energy_multiplier)
		else:
			print("  Emission: disabled")
		print("  Roughness: ", _base_material.roughness, " Metallic: ", _base_material.metallic, " Specular: ", _base_material.metallic_specular)
	print("[Terrain Shader] Heightmap texture valid: ", _heightmap_texture != null)
	if _heightmap_texture:
		print("[Terrain Shader] Heightmap size: ", _heightmap_texture.get_width(), "x", _heightmap_texture.get_height())
	print("[Terrain Shader] Displacement amplitude: ", depth_step_height * 4.0 * heightmap_displacement_amplitude)
	
	return shader_material


func _apply_ground_surface_parameters_to_terrain_shader(shader_material: ShaderMaterial) -> void:
	if shader_material == null:
		return

	var ground_albedo: Color = Color(0.46, 0.18, 0.0, 1.0)
	var ground_emission: Color = Color(0.0, 0.0, 0.0, 1.0)
	var ground_emission_energy: float = 0.0
	var ground_roughness: float = 0.0
	var ground_metallic: float = 0.0
	var ground_specular: float = 0.0

	if _base_material != null:
		ground_albedo = _base_material.albedo_color
		if _base_material.emission_enabled:
			ground_emission = _base_material.emission
			ground_emission_energy = _base_material.emission_energy_multiplier
		ground_roughness = _base_material.roughness
		ground_metallic = _base_material.metallic
		ground_specular = _base_material.metallic_specular

	shader_material.set_shader_parameter("albedo_color", ground_albedo)
	shader_material.set_shader_parameter("emission_color", ground_emission)
	shader_material.set_shader_parameter("emission_energy", ground_emission_energy)
	shader_material.set_shader_parameter("roughness_value", ground_roughness)
	shader_material.set_shader_parameter("metallic_value", ground_metallic)
	shader_material.set_shader_parameter("specular_value", ground_specular)


func _sync_ground_surface_material_parameters(force_sync: bool = false) -> void:
	var ground_albedo: Color = Color(0.46, 0.18, 0.0, 1.0)
	var ground_emission: Color = Color(0.0, 0.0, 0.0, 1.0)
	var ground_emission_energy: float = 0.0
	var ground_roughness: float = 0.0
	var ground_metallic: float = 0.0
	var ground_specular: float = 0.0
	var emission_enabled: bool = false

	if _base_material != null:
		ground_albedo = _base_material.albedo_color
		emission_enabled = _base_material.emission_enabled
		if emission_enabled:
			ground_emission = _base_material.emission
			ground_emission_energy = _base_material.emission_energy_multiplier
		ground_roughness = _base_material.roughness
		ground_metallic = _base_material.metallic
		ground_specular = _base_material.metallic_specular

	if not force_sync \
	and _last_ground_albedo == ground_albedo \
	and _last_ground_emission == ground_emission \
	and _last_ground_emission_enabled == emission_enabled \
	and is_equal_approx(_last_ground_emission_energy, ground_emission_energy) \
	and is_equal_approx(_last_ground_roughness, ground_roughness) \
	and is_equal_approx(_last_ground_metallic, ground_metallic) \
	and is_equal_approx(_last_ground_specular, ground_specular):
		return

	if _terrain_shader_material != null:
		_apply_ground_surface_parameters_to_terrain_shader(_terrain_shader_material)

	_sync_spawned_wall_surface_materials()
	_sync_spawned_base_platform_materials()

	_last_ground_albedo = ground_albedo
	_last_ground_emission = ground_emission
	_last_ground_emission_enabled = emission_enabled
	_last_ground_emission_energy = ground_emission_energy
	_last_ground_roughness = ground_roughness
	_last_ground_metallic = ground_metallic
	_last_ground_specular = ground_specular


func _sync_spawned_wall_surface_materials() -> void:
	for wall_node in get_tree().get_nodes_in_group("wall"):
		wall_node.source_surface_material = _base_material
		if wall_node.has_method("sync_surface_material"):
			wall_node.call("sync_surface_material")


func _sync_spawned_base_platform_materials() -> void:
	for base_node in get_tree().get_nodes_in_group("base_platform"):
		for child_node in base_node.get_children():
			var mesh_instance: MeshInstance3D = child_node as MeshInstance3D
			if mesh_instance != null:
				mesh_instance.material_override = _base_material


func register_terrain_footprint(world_position: Vector3, move_direction: Vector3, major_radius: float = -1.0, minor_radius: float = -1.0) -> void:
	if not enable_terrain_footprints:
		return

	var footprint_major_radius: float = major_radius
	if footprint_major_radius <= 0.0:
		footprint_major_radius = terrain_footprint_length

	var footprint_minor_radius: float = minor_radius
	if footprint_minor_radius <= 0.0:
		footprint_minor_radius = terrain_footprint_width

	var footprint_time: float = _get_terrain_footprint_time()
	_prune_expired_terrain_footprints(footprint_time)
	var footprint_data: TerrainFootprint = TerrainFootprint.new(
		world_position,
		footprint_time,
		move_direction,
		footprint_major_radius,
		footprint_minor_radius
	)
	if _terrain_footprints.size() >= terrain_footprint_count:
		var retiring_footprint: TerrainFootprint = _terrain_footprints[0]
		_terrain_footprints.remove_at(0)
		_queue_retiring_terrain_footprint(retiring_footprint, footprint_time)
	_terrain_footprints.append(footprint_data)
	_sync_terrain_footprint_shader_parameters()


func _get_terrain_footprint_time() -> float:
	return Time.get_ticks_usec() / 1000000.0


func _sync_terrain_footprint_shader_time() -> void:
	if _terrain_shader_material == null:
		return

	_terrain_shader_material.set_shader_parameter("footprint_current_time", _get_terrain_footprint_time())


func _sync_terrain_footprint_shader_parameters() -> void:
	if _terrain_shader_material == null:
		return

	_terrain_shader_material.set_shader_parameter("footprint_lifetime", terrain_footprint_lifetime)
	_terrain_shader_material.set_shader_parameter("footprint_strength", terrain_footprint_strength)
	_sync_terrain_footprint_shader_time()
	var combined_footprints: Array[TerrainFootprint] = []
	combined_footprints.append_array(_terrain_footprints)
	combined_footprints.append_array(_retiring_terrain_footprints)
	for index in range(_get_total_terrain_footprint_shader_slots()):
		var uniform_name: String = "footprint_data_%d" % index
		var shape_uniform_name: String = "footprint_shape_%d" % index
		var footprint_value: Vector4 = Vector4(0.0, 0.0, -1000.0, 0.0)
		var footprint_shape_value: Vector4 = Vector4(0.0, 1.0, 0.0, 0.0)
		if index < combined_footprints.size():
			footprint_value = combined_footprints[index].to_primary_vector()
			footprint_shape_value = combined_footprints[index].to_shape_vector()
		_terrain_shader_material.set_shader_parameter(uniform_name, footprint_value)
		_terrain_shader_material.set_shader_parameter(shape_uniform_name, footprint_shape_value)


func _queue_retiring_terrain_footprint(footprint_data: TerrainFootprint, current_time: float) -> void:
	var overflow_fade_duration: float = min(terrain_footprint_overflow_fade_duration, terrain_footprint_lifetime)
	if overflow_fade_duration <= 0.0:
		return

	var fade_timestamp: float = current_time - max(terrain_footprint_lifetime - overflow_fade_duration, 0.0)
	var retiring_footprint: TerrainFootprint = footprint_data.with_spawn_time(fade_timestamp)
	if _retiring_terrain_footprints.size() >= terrain_footprint_overflow_fade_count:
		_retiring_terrain_footprints.remove_at(0)
	_retiring_terrain_footprints.append(retiring_footprint)


func _prune_expired_terrain_footprints(current_time: float) -> void:
	var active_footprints: Array[TerrainFootprint] = []
	for footprint_data in _terrain_footprints:
		if current_time - footprint_data.spawn_time <= terrain_footprint_lifetime:
			active_footprints.append(footprint_data)
	_terrain_footprints = active_footprints

	var retiring_footprints: Array[TerrainFootprint] = []
	for footprint_data in _retiring_terrain_footprints:
		if current_time - footprint_data.spawn_time <= terrain_footprint_lifetime:
			retiring_footprints.append(footprint_data)
	_retiring_terrain_footprints = retiring_footprints


func _get_total_terrain_footprint_shader_slots() -> int:
	return terrain_footprint_count + terrain_footprint_overflow_fade_count


## Spawns a flat base mesh (legacy/fallback).
func _spawn_base_mesh_flat() -> void:
	# Collect all cells that should have base underneath, including the synthetic perimeter ring.
	var base_cells: Array[Cell] = _build_terrain_base_cells()
	
	if base_cells.is_empty():
		return

	var base_cell_lookup: Dictionary = _build_cell_position_lookup(base_cells)
	
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
		if not _has_position_lookup_neighbor(base_cell_lookup, cell.position, Vector2i(-1, 0)):  # Left
			inset_left = inset
		if not _has_position_lookup_neighbor(base_cell_lookup, cell.position, Vector2i(1, 0)):   # Right
			inset_right = inset
		if not _has_position_lookup_neighbor(base_cell_lookup, cell.position, Vector2i(0, -1)):  # Top
			inset_top = inset
		if not _has_position_lookup_neighbor(base_cell_lookup, cell.position, Vector2i(0, 1)):   # Bottom
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
		push_warning("No walkable floor cells available to place player!")
		return
	
	# Find player node using multiple fallback methods
	var player: Node3D = NodeUtils.find(self, "player", ["../Player"])
	
	if not player:
		push_warning("Player node not found!")
		return

	var player_ground_offset: float = _get_player_ground_offset(player)
	
	# Try to place on highground first
	var spawn_pos: Vector3
	if _highground_positions.size() > 0:
		# Place on a random highground position
		var highground_index: int = _rng.randi_range(0, _highground_positions.size() - 1)
		var highground_cell: Cell = _get_cell_at(_highground_positions[highground_index])
		if highground_cell == null:
			push_warning("[Player Spawn] Highground cell missing; falling back to random floor")
			var fallback_cell: Cell = _floor_cells[_rng.randi_range(0, _floor_cells.size() - 1)]
			spawn_pos = _get_cell_surface_position(fallback_cell)
		else:
			spawn_pos = _get_cell_surface_position(highground_cell)
		spawn_pos.y += player_ground_offset
		print("[Player Spawn] Placed on highground at: ", spawn_pos)
	else:
		# Fallback to random floor tile if no highground
		var random_cell: Cell = _floor_cells[_rng.randi_range(0, _floor_cells.size() - 1)]
		spawn_pos = _get_cell_surface_position(random_cell)
		spawn_pos.y += player_ground_offset
		print("[Player Spawn] Placed at random floor: ", spawn_pos)
	
	player.global_position = spawn_pos

	var player_body: CharacterBody3D = player as CharacterBody3D
	if player_body != null:
		player_body.velocity = Vector3.ZERO


func _get_player_ground_offset(player: Node3D) -> float:
	var lowest_local_y: float = INF

	for child: Node in player.get_children():
		var collision_shape: CollisionShape3D = child as CollisionShape3D
		if collision_shape == null or collision_shape.shape == null:
			continue

		var shape_lowest_y: float = _get_collision_shape_lowest_local_y(collision_shape)
		lowest_local_y = minf(lowest_local_y, shape_lowest_y)

	if lowest_local_y == INF:
		return 0.05

	return maxf(-lowest_local_y + 0.02, 0.02)


func _get_collision_shape_lowest_local_y(collision_shape: CollisionShape3D) -> float:
	var shape: Shape3D = collision_shape.shape
	var transform_origin_y: float = collision_shape.transform.origin.y

	if shape is ConvexPolygonShape3D:
		var convex_shape: ConvexPolygonShape3D = shape as ConvexPolygonShape3D
		var lowest_y: float = INF
		for point: Vector3 in convex_shape.points:
			lowest_y = minf(lowest_y, point.y + transform_origin_y)
		if lowest_y != INF:
			return lowest_y

	if shape is CapsuleShape3D:
		var capsule_shape: CapsuleShape3D = shape as CapsuleShape3D
		return transform_origin_y - capsule_shape.radius - (capsule_shape.height * 0.5)

	if shape is SphereShape3D:
		var sphere_shape: SphereShape3D = shape as SphereShape3D
		return transform_origin_y - sphere_shape.radius

	if shape is CylinderShape3D:
		var cylinder_shape: CylinderShape3D = shape as CylinderShape3D
		return transform_origin_y - (cylinder_shape.height * 0.5)

	if shape is BoxShape3D:
		var box_shape: BoxShape3D = shape as BoxShape3D
		return transform_origin_y - (box_shape.size.y * 0.5)

	return transform_origin_y


## Returns the sampled terrain surface position at the center of a cell.
func _get_cell_surface_position(cell: Cell) -> Vector3:
	var world_pos: Vector3 = _cell_to_world(cell.position)
	world_pos.y = _get_world_surface_height(Vector2(world_pos.x, world_pos.z))
	return world_pos


## Samples the generated terrain height at a world-space XZ position.
func _get_world_surface_height(world_xz: Vector2) -> float:
	if not use_layered_depth or _heightmap_image == null:
		return floor_height

	var terrain_world_rect: Rect2 = _get_terrain_world_rect()
	if terrain_world_rect.size.x <= 0.0 or terrain_world_rect.size.y <= 0.0:
		return floor_height

	var uv: Vector2 = Vector2(
		(world_xz.x - terrain_world_rect.position.x) / terrain_world_rect.size.x,
		(world_xz.y - terrain_world_rect.position.y) / terrain_world_rect.size.y
	)
	var height_value: float = _sample_heightmap_bilinear(_heightmap_image, uv)
	return (floor_height - _get_max_terrain_displacement()) + (height_value * _get_max_terrain_displacement())


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


func _build_cell_position_lookup(cells: Array[Cell]) -> Dictionary:
	var position_lookup: Dictionary = {}
	for cell in cells:
		var grid_pos: Vector2i = Vector2i(int(cell.position.x), int(cell.position.y))
		position_lookup[_grid_position_key(grid_pos)] = true
	return position_lookup


## Helper: Check if a cell lookup contains a neighbor in a specific direction.
func _has_position_lookup_neighbor(position_lookup: Dictionary, grid_pos: Vector2, direction: Vector2i) -> bool:
	var neighbor_pos: Vector2i = Vector2i(int(grid_pos.x) + direction.x, int(grid_pos.y) + direction.y)
	return position_lookup.has(_grid_position_key(neighbor_pos))


## Counts neighboring floor cells in the 8-cell neighborhood around a grid position.
func _count_floor_neighbors(grid_pos: Vector2) -> int:
	var count: int = 0

	for x_offset in range(-1, 2):
		for y_offset in range(-1, 2):
			if x_offset == 0 and y_offset == 0:
				continue

			var neighbor_pos: Vector2 = Vector2(grid_pos.x + x_offset, grid_pos.y + y_offset)
			var neighbor_cell: Cell = _get_cell_at(neighbor_pos)
			if neighbor_cell != null and neighbor_cell.is_floor:
				count += 1

	return count


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


## Public getter for explored cells (used by minimap).
func get_explored_cells() -> Dictionary:
	return _explored_cells


## Returns whether a specific grid cell has been permanently explored.
func is_cell_explored(grid_pos: Vector2i) -> bool:
	return _explored_cells.has(_grid_position_key(grid_pos))


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
