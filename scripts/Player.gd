extends CharacterBody3D

@onready var camera: Camera3D = get_viewport().get_camera_3d()
@onready var visual_root: Node3D = $VisualRoot
@onready var visual_motion_root: Node3D = $VisualRoot/FatmanMotionRoot
@onready var face_sprite: Sprite3D = $VisualRoot/FatmanMotionRoot/FaceSprite

@export var can_move : bool = true
@export var has_gravity : bool = true

## Enable click-to-move functionality
@export var click_to_move : bool = true
## Show debug visualization
@export var debug_movement : bool = true

## Reference to the procedural map for pathfinding
@export var procedural_map: Node3D = null

@export_group("Movement Physics")
## How long to snap to floor when going down slopes
@export var floor_snap : float = 0.1
## How quickly the visible model aligns to the ground normal.
@export var ground_alignment_speed : float = 10.0

@export_group("Visual Motion")
## Vertical float amount while standing still.
@export var idle_float_height: float = 0.03
## Idle float cycles per second.
@export var idle_float_speed: float = 0.8
## Vertical bob amount while walking.
@export var walk_bob_height: float = 0.05
## Walk wobble cycles per second.
@export var walk_wobble_speed: float = 2.6
## Side-to-side roll while walking.
@export var walk_roll_degrees: float = 8.0
## Gentle yaw sway while walking.
@export var walk_yaw_degrees: float = 5.0
## Local position of the simple face sprite on the fatman model.
@export var face_local_position: Vector3 = Vector3(0.0, 0.56, 0.16)
## Size multiplier for the simple face sprite.
@export var face_scale: float = 0.18

@export_group("Camera Orbit")
## Scene path to the PhantomCamera3D node that orbits around the player.
@export var camera_orbit_rig_path: NodePath = NodePath("../PhantomCamera3D")
## Degrees to rotate the camera each time Tab is pressed.
@export var camera_orbit_step_degrees: float = 90.0
## Duration of the camera orbit tween in seconds.
@export var camera_orbit_rotate_duration: float = 0.18

@export_group("Footprints")
## Enable terrain footprint emission while grounded and moving.
@export var emit_terrain_footprints : bool = true
## Time in seconds between footprint stamps while grounded and moving.
@export var footstep_interval : float = 0.18
## Random variation applied to the base footstep interval.
@export var footstep_interval_randomness : float = 0.05
## Minimum horizontal distance required between consecutive footprint stamps.
@export var footstep_min_distance : float = 0.22
## Minimum horizontal speed required before footprints are emitted.
@export var footstep_min_speed : float = 1.0
## Side offset used to alternate left and right footsteps.
@export var footstep_lateral_offset : float = 0.18
## Forward offset used to place footprints closer to the character's feet.
@export var footstep_forward_offset : float = 0.0
## Half-length of the emitted footprint ellipse along its forward direction.
@export var footstep_length : float = 0.26
## Half-width of the emitted footprint ellipse across its forward direction.
@export var footstep_width : float = 0.12
## Base outward angle applied to each footprint away from the body center.
@export var footstep_outward_angle_degrees : float = 7.0
## Random angle variation applied on top of the outward footprint rotation.
@export var footstep_angle_randomness_degrees : float = 4.0
## How far above the player origin the terrain contact probe starts.
@export var footstep_ground_probe_start_height : float = 1.0
## How far downward the terrain contact probe checks for nearby ground.
@export var footstep_ground_probe_distance : float = 1.4

@export_group("Input Actions")
## Name of Input Action to move Left.
@export var input_left : String = "move_left"
## Name of Input Action to move Right.
@export var input_right : String = "move_right"
## Name of Input Action to move Forward.
@export var input_forward : String = "move_up"
## Name of Input Action to move Backward.
@export var input_back : String = "move_down"

@export_group("Speeds")
## Move speed.
@export var move_speed : float = 4.0
## How fast the character rotates to face movement direction.
@export var rotation_speed : float = 10.0
## How close to target before stopping
@export var arrival_distance : float = 0.3

@export_group("Tile Highlighting")
## Color for hovering over a tile
@export var hover_color : Color = Color(1.0, 0.97, 0.8, 1.0)
## Color for selected target tile
@export var target_color : Color = Color(1.0, 0.92, 0.6, 1.0)
## Emission energy for highlights
@export var highlight_emission : float = 0.1
## Show floating target indicator above clicked tile
@export var show_target_indicator : bool = false
## Height offset for target indicator above tile
@export var target_indicator_height : float = 0.3
## Size of target indicator ring
@export var target_indicator_size : float = 0.8

@export_group("Click Indicator")
## Show particle effect when clicking
@export var show_click_effect : bool = true:
	set(value):
		show_click_effect = value
		_refresh_click_indicator_scene()
## Color of click indicator particles when no custom material is assigned.
@export var click_effect_color : Color = Color(1.0, 0.95, 0.7, 0.8):
	set(value):
		click_effect_color = value
		_refresh_click_indicator_scene()
## Optional material override used by the click indicator particle quads.
@export var click_effect_material: Material:
	set(value):
		click_effect_material = value
		_refresh_click_indicator_scene()
## Number of particles in puff
@export var click_particle_count : int = 15:
	set(value):
		click_particle_count = value
		_refresh_click_indicator_scene()
## Height offset for particles above clicked position
@export var click_particle_height : float = 0.25

@export_group("Pathfinding Costs")
## Cost multiplier per depth level (higher depth = deeper = more cost)
@export var depth_cost_multiplier: float = 1.1
## Base cost for depth 0 (highest) tiles
@export var floor_base_cost: float = 1.0
## Extra cost applied once a traversed cell is currently below the visible lava surface.
@export var submerged_lava_penalty_base_cost: float = 8.0
## Additional cost applied per depth level a traversed cell sits below the visible lava surface.
@export var submerged_lava_penalty_per_level: float = 18.0

# Click-to-move variables
var _target_position: Vector3
var _has_target: bool = false
var _hovered_tile: Node3D = null
var _target_tile: Node3D = null
var _stored_materials: Dictionary = {}  # Store original materials
var _click_indicator_scene: PackedScene = null
var _target_indicator: Node3D = null  # Floating indicator mesh above target

# Pathfinding variables
var _astar: AStar2D = AStar2D.new()
var _pathfinding_initialized: bool = false
var _cell_depth_by_id: Dictionary = {}
var _current_path: Array[Vector3] = []
var _current_path_index: int = 0
var _grid_cell_size: float = 2.0  # Default, will be updated from map
var _footstep_interval_timer: float = 0.0
var _next_footstep_interval: float = 0.18
var _was_emitting_terrain_footprints: bool = false
var _use_left_footstep: bool = true
var _footstep_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_terrain_footprint_position: Vector3 = Vector3.ZERO
var _has_last_terrain_footprint_position: bool = false
var _camera_orbit_rig: Node3D = null
var _camera_orbit_tween: Tween = null
var _camera_orbit_base_horizontal_rotation: float = 0.0
var _has_camera_orbit_base_horizontal_rotation: bool = false
var _visual_motion_time: float = 0.0
var _visual_motion_base_position: Vector3 = Vector3.ZERO


func _toggle_fullscreen_mode() -> void:
	var current_window_mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	if current_window_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		return

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _restart_current_scene() -> void:
	var reload_error: Error = get_tree().reload_current_scene()
	if reload_error != OK:
		push_error("Failed to reload the current scene.")


func _log_camera_orbit(message: String) -> void:
	if debug_movement:
		print("[CameraOrbit] ", message)

func _ready() -> void:
	# Add to player group for easy lookup
	add_to_group("player")
	_footstep_rng.randomize()
	_camera_orbit_rig = _resolve_camera_orbit_rig()
	_capture_camera_orbit_base_rotation()
	if _camera_orbit_rig:
		_log_camera_orbit("Ready with rig '" + _camera_orbit_rig.name + "' at path " + str(_camera_orbit_rig.get_path()))
	else:
		_log_camera_orbit("Ready without a resolved orbit rig. Configured path: " + str(camera_orbit_rig_path))
	
	# Enable step-up for small ledges
	floor_stop_on_slope = false
	floor_snap_length = floor_snap
	
	# Setup click indicator particle system
	_setup_click_indicator()
	
	# Find procedural map if not set - uses multiple fallback methods
	print("[Player] Looking for procedural map...")
	if not procedural_map:
		procedural_map = NodeUtils.find_node(
			self,
			"procedural_map",  # Try group first (fastest)
			["../Procedural Map"],  # Then try as sibling
			"procedural_map",  # Finally search by script
			true  # Enable debug output
		)
		if not procedural_map:
			print("[Player] WARNING: Could not find procedural map!")
	else:
		print("[Player] Procedural map already assigned: ", procedural_map.name)
	
	# Connect to map regeneration signal and initialize when map is ready
	if procedural_map:
		# Connect to map regeneration signal
		if procedural_map.has_signal("map_regenerated"):
			procedural_map.map_regenerated.connect(_on_map_regenerated)
			print("[Player] Connected to map_regenerated signal")
		
		# Check if map already has cells (already generated)
		if "_floor_cells" in procedural_map:
			var floor_cells: Array = procedural_map._floor_cells
			if not floor_cells.is_empty():
				print("[Player] Map already generated, initializing pathfinding immediately")
				call_deferred("_initialize_pathfinding")
			else:
				print("[Player] Map not yet generated, waiting for map_regenerated signal")
		else:
			print("[Player] Map not yet generated, waiting for map_regenerated signal")
	else:
		print("[Player] ERROR: No procedural map found - pathfinding will not work!")

	if visual_motion_root:
		_visual_motion_base_position = visual_motion_root.position

	if face_sprite:
		face_sprite.position = face_local_position
		face_sprite.scale = Vector3.ONE * face_scale
		_ensure_face_texture()


## Called when the map regenerates
func _on_map_regenerated() -> void:
	if debug_movement:
		print("Map regenerated - rebuilding pathfinding")
	_initialize_pathfinding()


## Initialize pathfinding grid from procedural map
func _initialize_pathfinding() -> void:
	print("[Pathfinding] Starting initialization...")
	
	if not procedural_map:
		print("[Pathfinding] ERROR: procedural_map not found")
		return
	
	print("[Pathfinding] Found procedural map: ", procedural_map.name)
	
	# Clear existing AStar nodes
	_astar.clear()
	_cell_depth_by_id.clear()
	
	# Get cell size from map
	if "cell_size" in procedural_map:
		_grid_cell_size = procedural_map.cell_size
		print("[Pathfinding] Cell size: ", _grid_cell_size)
	else:
		print("[Pathfinding] WARNING: No cell_size property found, using default: ", _grid_cell_size)
	
	# Get cells from map
	var cells: Array = procedural_map._cells if "_cells" in procedural_map else []
	var floor_cells: Array = procedural_map._floor_cells if "_floor_cells" in procedural_map else []
	
	print("[Pathfinding] Total cells: ", cells.size(), " | Floor cells: ", floor_cells.size())
	
	if cells.is_empty():
		print("[Pathfinding] ERROR: no cells found in map - map may not be generated yet")
		return
	
	if floor_cells.is_empty():
		print("[Pathfinding] ERROR: no walkable cells found in map")
		return
	
	var walkable_cells: Array = floor_cells
	
	# Add all walkable cells to AStar with appropriate weights
	var added_count: int = 0
	var depth_counts: Array[int] = [0, 0, 0, 0, 0]  # Track cells per depth level
	for cell in walkable_cells:
		if cell:
			var grid_pos: Vector2 = cell.position
			var point_id: int = _grid_to_id(grid_pos)
			_astar.add_point(point_id, grid_pos)
			
			# Set weight based on depth (Dijkstra-style weighted pathfinding)
			# Deeper cells (higher depth value) have higher cost
			var depth: int = cell.depth if "depth" in cell else 0
			var weight: float = _get_path_cost_for_depth(depth, 4.0)
			_astar.set_point_weight_scale(point_id, weight)
			_cell_depth_by_id[point_id] = depth
			
			if depth >= 0 and depth <= 4:
				depth_counts[depth] += 1
			
			added_count += 1
	
	print("[Pathfinding] Added ", added_count, " walkable cells to AStar grid")
	print("[Pathfinding] Depth distribution and costs:")
	for d in range(5):
		var cost: float = floor_base_cost + (d * depth_cost_multiplier)
		print("  - Depth ", d, ": ", depth_counts[d], " cells (cost: ", cost, ")")
	
	# Connect neighboring walkable cells (orthogonal only - up/down/left/right)
	# Movement rules:
	# - Same height is always allowed.
	# - Moving downhill is always allowed.
	# - Moving uphill is only allowed by one level.
	var connection_count := 0
	var blocked_connection_count: int = 0
	for cell in walkable_cells:
		if cell:
			# Connect all floor cells including lava
			var grid_pos: Vector2 = cell.position
			var point_id: int = _grid_to_id(grid_pos)
			var current_depth: int = int(_cell_depth_by_id.get(point_id, 0))
			
			# Check 4 orthogonal neighbors
			var neighbors: Array[Vector2] = [
				Vector2(grid_pos.x + 1, grid_pos.y),  # Right
				Vector2(grid_pos.x - 1, grid_pos.y),  # Left
				Vector2(grid_pos.x, grid_pos.y + 1),  # Down
				Vector2(grid_pos.x, grid_pos.y - 1),  # Up
			]
			
			for neighbor_pos in neighbors:
				var neighbor_id: int = _grid_to_id(neighbor_pos)
				if _astar.has_point(neighbor_id):
					var neighbor_depth: int = int(_cell_depth_by_id.get(neighbor_id, 0))
					if _can_traverse_depth(current_depth, neighbor_depth):
						if not _astar.are_points_connected(point_id, neighbor_id, false):
							_astar.connect_points(point_id, neighbor_id, false)
							connection_count += 1
					else:
						blocked_connection_count += 1
	
	print("[Pathfinding] Created ", connection_count, " connections between cells")
	print("[Pathfinding] Blocked ", blocked_connection_count, " depth-restricted connections")
	
	_pathfinding_initialized = true
	print("[Pathfinding] ✓ Initialization complete with ", _astar.get_point_count(), " walkable cells")


func _get_path_cost_for_depth(depth: int, current_lava_height_level: float) -> float:
	var path_cost: float = floor_base_cost + (float(depth) * depth_cost_multiplier)
	var submerged_depth_levels: float = maxf(0.0, float(depth) - current_lava_height_level)
	if submerged_depth_levels > 0.001:
		path_cost += submerged_lava_penalty_base_cost + (submerged_depth_levels * submerged_lava_penalty_per_level)
	return path_cost


func _get_current_lava_height_level() -> float:
	if procedural_map != null and procedural_map.has_method("get_lava_height_level"):
		return float(procedural_map.call("get_lava_height_level"))
	return 4.0


func _is_depth_submerged(depth: int, current_lava_height_level: float) -> bool:
	return (float(depth) - current_lava_height_level) > 0.001


func _refresh_pathfinding_costs() -> void:
	var current_lava_height_level: float = _get_current_lava_height_level()
	for point_id_variant in _cell_depth_by_id.keys():
		var point_id: int = int(point_id_variant)
		var depth: int = int(_cell_depth_by_id.get(point_id, 0))
		_astar.set_point_weight_scale(point_id, _get_path_cost_for_depth(depth, current_lava_height_level))


func _can_traverse_depth(from_depth: int, to_depth: int) -> bool:
	if to_depth == from_depth:
		return true

	if to_depth > from_depth:
		return true

	return to_depth == from_depth - 1


## Convert grid coordinates to unique point ID
func _grid_to_id(grid_pos: Vector2) -> int:
	# Use a large multiplier to ensure unique IDs
	return int(grid_pos.x) + int(grid_pos.y) * 10000


## Convert world position to grid coordinates  
func _world_to_grid(world_pos: Vector3) -> Vector2:
	if not procedural_map or not "edge_margin" in procedural_map:
		return Vector2.ZERO
	
	var edge_offset: float = procedural_map.edge_margin * _grid_cell_size
	return Vector2(
		floor((world_pos.x - edge_offset) / _grid_cell_size),
		floor((world_pos.z - edge_offset) / _grid_cell_size)
	)


## Convert grid coordinates to world position (center of cell)
func _grid_to_world(grid_pos: Vector2) -> Vector3:
	if not procedural_map or not "edge_margin" in procedural_map:
		return Vector3.ZERO
	
	# Use the same conversion as procedural_map._cell_to_world() for consistency
	var edge_offset: float = procedural_map.edge_margin * _grid_cell_size
	var floor_height: float = procedural_map.floor_height if "floor_height" in procedural_map else 0.1
	
	return Vector3(
		grid_pos.x * _grid_cell_size + _grid_cell_size * 0.5 + edge_offset,
		floor_height,  # Match the tile_center height
		grid_pos.y * _grid_cell_size + _grid_cell_size * 0.5 + edge_offset
	)


## Find path from current position to target using A* with weighted costs (Dijkstra-style)
## Lava tiles have much higher cost and will be avoided unless necessary
func _find_path(from_world: Vector3, to_world: Vector3) -> Array[Vector3]:
	var path: Array[Vector3] = []
	
	if not _pathfinding_initialized:
		print("[Pathfinding] ERROR: Pathfinding not initialized yet")
		return path

	_refresh_pathfinding_costs()
	var current_lava_height_level: float = _get_current_lava_height_level()
	
	print("[Pathfinding] Finding path from ", from_world, " to ", to_world)
	
	var from_grid := _world_to_grid(from_world)
	var to_grid := _world_to_grid(to_world)
	
	print("[Pathfinding] Grid coords - from: ", from_grid, " to: ", to_grid)
	
	var from_id := _grid_to_id(from_grid)
	var to_id := _grid_to_id(to_grid)
	
	print("[Pathfinding] Point IDs - from: ", from_id, " to: ", to_id)
	
	# Check if both positions are valid walkable cells
	if not _astar.has_point(from_id):
		print("[Pathfinding] ERROR: Start position not on walkable grid: ", from_grid, " (ID: ", from_id, ")")
		return path
	
	if not _astar.has_point(to_id):
		print("[Pathfinding] Target position not on walkable grid: ", to_grid, " - searching for nearest...")
		
		# Find nearest walkable cell to target
		to_id = _find_nearest_walkable_point(to_grid)
		if to_id == -1:
			print("[Pathfinding] ERROR: No walkable cells found near target")
			return path
		
		print("[Pathfinding] Found nearest walkable point ID: ", to_id)
	
	# Get path from AStar (uses Dijkstra-style weighted pathfinding)
	var grid_path := _astar.get_point_path(from_id, to_id)
	
	if grid_path.is_empty():
		print("[Pathfinding] ERROR: No path found from ", from_grid, " to ", to_grid)
		return path
	
	# Convert grid path to world positions and count currently submerged cells.
	var submerged_tiles_in_path: int = 0
	for grid_pos in grid_path:
		path.append(_grid_to_world(grid_pos))
		
		var point_id: int = _grid_to_id(grid_pos)
		var depth: int = int(_cell_depth_by_id.get(point_id, 0))
		if _is_depth_submerged(depth, current_lava_height_level):
			submerged_tiles_in_path += 1
	
	print("[Pathfinding] ✓ Path found with ", path.size(), " waypoints")
	if submerged_tiles_in_path > 0:
		print("[Pathfinding]   ⚠ Path crosses ", submerged_tiles_in_path, " currently submerged cells")
	else:
		print("[Pathfinding]   ✓ Path avoids all currently submerged cells")
	
	return path


## Find nearest walkable point to target grid position
func _find_nearest_walkable_point(target_grid: Vector2) -> int:
	var best_id := -1
	var best_distance := INF
	
	# Search in expanding square around target
	for radius in range(1, 20):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				# Only check perimeter of current radius
				if abs(dx) != radius and abs(dy) != radius:
					continue
				
				var check_pos := Vector2(target_grid.x + dx, target_grid.y + dy)
				var check_id := _grid_to_id(check_pos)
				
				if _astar.has_point(check_id):
					var distance := target_grid.distance_to(check_pos)
					if distance < best_distance:
						best_distance = distance
						best_id = check_id
		
		# If we found a point at this radius, return it
		if best_id != -1:
			return best_id
	
	return best_id


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		_toggle_fullscreen_mode()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.shift_pressed and (event.keycode == KEY_R or event.physical_keycode == KEY_R):
		_restart_current_scene()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_TAB or event.physical_keycode == KEY_TAB):
		_log_camera_orbit("Tab detected. keycode=%s physical_keycode=%s" % [event.keycode, event.physical_keycode])
		_rotate_camera_clockwise()
		return

	if not click_to_move or not can_move:
		return
	
	# Handle mouse motion for hover highlighting
	if event is InputEventMouseMotion:
		_handle_hover(event.position)
	
	# Handle mouse click for movement
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_click(event.position)


func _resolve_camera_orbit_rig() -> Node3D:
	if _camera_orbit_rig and is_instance_valid(_camera_orbit_rig):
		return _camera_orbit_rig

	if not camera_orbit_rig_path.is_empty():
		_camera_orbit_rig = get_node_or_null(camera_orbit_rig_path) as Node3D
		if _camera_orbit_rig:
			_log_camera_orbit("Resolved rig from configured path: " + str(camera_orbit_rig_path))

	if not _camera_orbit_rig and get_parent():
		_camera_orbit_rig = get_parent().get_node_or_null("PhantomCamera3D") as Node3D
		if _camera_orbit_rig:
			_log_camera_orbit("Resolved rig from parent fallback path ../PhantomCamera3D")

	if _camera_orbit_rig == null:
		_log_camera_orbit("Failed to resolve rig. Configured path: " + str(camera_orbit_rig_path))

	return _camera_orbit_rig


func _capture_camera_orbit_base_rotation() -> void:
	if _has_camera_orbit_base_horizontal_rotation:
		return

	var camera_orbit_rig: Node3D = _resolve_camera_orbit_rig()
	if camera_orbit_rig == null:
		_log_camera_orbit("Cannot capture base rotation because no rig is resolved")
		return

	var horizontal_rotation_value: Variant = camera_orbit_rig.get("horizontal_rotation_offset")
	if not horizontal_rotation_value is float:
		_log_camera_orbit("Rig '" + camera_orbit_rig.name + "' does not expose a float horizontal_rotation_offset")
		return

	_camera_orbit_base_horizontal_rotation = horizontal_rotation_value
	_has_camera_orbit_base_horizontal_rotation = true
	_log_camera_orbit("Captured base horizontal rotation: %.3f rad" % _camera_orbit_base_horizontal_rotation)


func _rotate_camera_clockwise() -> void:
	var camera_orbit_rig: Node3D = _resolve_camera_orbit_rig()
	if camera_orbit_rig == null:
		_log_camera_orbit("Rotate request ignored because no rig is resolved")
		return
	_capture_camera_orbit_base_rotation()
	if not _has_camera_orbit_base_horizontal_rotation:
		_log_camera_orbit("Rotate request ignored because base rotation was not captured")
		return

	var rotation_radians: float = deg_to_rad(camera_orbit_step_degrees)
	var current_horizontal_rotation_value: Variant = camera_orbit_rig.get("horizontal_rotation_offset")
	if not current_horizontal_rotation_value is float:
		_log_camera_orbit("Rotate request ignored because horizontal_rotation_offset is not readable as float")
		return

	var current_horizontal_rotation: float = current_horizontal_rotation_value
	var relative_rotation: float = current_horizontal_rotation - _camera_orbit_base_horizontal_rotation
	var snapped_step_index: int = int(round(relative_rotation / -rotation_radians))
	var snapped_horizontal_rotation: float = _camera_orbit_base_horizontal_rotation - (rotation_radians * float(snapped_step_index))
	var target_horizontal_rotation: float = snapped_horizontal_rotation - rotation_radians
	_log_camera_orbit(
		"Rotating rig '%s' from %.3f rad to %.3f rad (base=%.3f, step=%d, step_size=%.3f)" % [
			camera_orbit_rig.name,
			current_horizontal_rotation,
			target_horizontal_rotation,
			_camera_orbit_base_horizontal_rotation,
			snapped_step_index,
			rotation_radians
		]
	)

	if is_instance_valid(_camera_orbit_tween):
		_camera_orbit_tween.kill()
		_log_camera_orbit("Killed existing orbit tween before starting a new one")

	if camera_orbit_rotate_duration <= 0.0:
		camera_orbit_rig.set("horizontal_rotation_offset", target_horizontal_rotation)
		_log_camera_orbit("Applied horizontal rotation immediately")
		return

	_camera_orbit_tween = create_tween()
	_camera_orbit_tween.set_trans(Tween.TRANS_SINE)
	_camera_orbit_tween.set_ease(Tween.EASE_IN_OUT)
	_camera_orbit_tween.tween_property(camera_orbit_rig, "horizontal_rotation_offset", target_horizontal_rotation, camera_orbit_rotate_duration)
	_log_camera_orbit("Started tween over %.3f seconds" % camera_orbit_rotate_duration)


func _physics_process(delta: float) -> void:
	var position_before_move: Vector3 = global_position

	# Apply gravity
	if has_gravity and not is_on_floor():
		velocity += get_gravity() * delta

	# Handle movement
	if click_to_move:
		_handle_click_to_move(delta)
	else:
		_handle_direct_input(delta)
	
	# Move and slide
	move_and_slide()
	_align_visual_to_ground(delta)
	_update_visual_motion(delta)
	_update_terrain_footprints(delta, position_before_move)


func _align_visual_to_ground(delta: float) -> void:
	if not visual_root:
		return

	var target_normal: Vector3 = Vector3.UP
	if is_on_floor():
		target_normal = get_floor_normal()
	else:
		var ground_probe: Dictionary = _get_footprint_ground_probe()
		if not ground_probe.is_empty():
			target_normal = ground_probe.normal

	var player_basis: Basis = global_transform.basis.orthonormalized()
	var local_up: Vector3 = (player_basis.inverse() * target_normal).normalized()
	var local_forward: Vector3 = Vector3.FORWARD
	var projected_forward: Vector3 = local_forward - local_up * local_forward.dot(local_up)
	if projected_forward.length_squared() < 0.0001:
		projected_forward = Vector3.RIGHT.cross(local_up)
	if projected_forward.length_squared() < 0.0001:
		projected_forward = Vector3.FORWARD
	projected_forward = projected_forward.normalized()

	var target_back: Vector3 = -projected_forward
	var target_right: Vector3 = local_up.cross(target_back).normalized()
	var target_basis: Basis = Basis(target_right, local_up, target_back).orthonormalized()
	var current_quaternion: Quaternion = visual_root.transform.basis.get_rotation_quaternion()
	var target_quaternion: Quaternion = target_basis.get_rotation_quaternion()
	var weight: float = clamp(ground_alignment_speed * delta, 0.0, 1.0)
	visual_root.transform.basis = Basis(current_quaternion.slerp(target_quaternion, weight))


func _update_visual_motion(delta: float) -> void:
	if not visual_motion_root:
		return

	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var move_ratio: float = 0.0
	if move_speed > 0.001:
		move_ratio = clamp(horizontal_speed / move_speed, 0.0, 1.0)

	var is_moving: bool = move_ratio > 0.1
	var motion_frequency: float = walk_wobble_speed if is_moving else idle_float_speed
	_visual_motion_time += delta * motion_frequency

	var phase: float = _visual_motion_time * TAU
	var height_offset: float = sin(phase) * idle_float_height
	var yaw_radians: float = 0.0
	var roll_radians: float = 0.0
	if is_moving:
		height_offset = sin(phase) * walk_bob_height * move_ratio
		yaw_radians = sin(phase * 0.5) * deg_to_rad(walk_yaw_degrees) * move_ratio
		roll_radians = sin(phase) * deg_to_rad(walk_roll_degrees) * move_ratio

	visual_motion_root.position = _visual_motion_base_position + Vector3(0.0, height_offset, 0.0)
	visual_motion_root.rotation = Vector3(0.0, yaw_radians, roll_radians)


func _ensure_face_texture() -> void:
	if not face_sprite:
		return
	if face_sprite.texture != null:
		return

	face_sprite.texture = _create_face_texture()
	face_sprite.shaded = false


func _create_face_texture() -> ImageTexture:
	var face_image: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var transparent: Color = Color(0.0, 0.0, 0.0, 0.0)
	var face_color: Color = Color(1.0, 0.95, 0.88, 1.0)
	var feature_color: Color = Color(0.07, 0.03, 0.03, 1.0)

	face_image.fill(transparent)
	face_image.fill_rect(Rect2i(4, 6, 24, 20), face_color)
	face_image.fill_rect(Rect2i(9, 12, 4, 4), feature_color)
	face_image.fill_rect(Rect2i(19, 12, 4, 4), feature_color)
	face_image.fill_rect(Rect2i(10, 21, 12, 2), feature_color)
	face_image.fill_rect(Rect2i(8, 19, 2, 2), feature_color)
	face_image.fill_rect(Rect2i(22, 19, 2, 2), feature_color)

	return ImageTexture.create_from_image(face_image)


func _update_terrain_footprints(delta: float, position_before_move: Vector3) -> void:
	if not emit_terrain_footprints:
		return
	if not procedural_map or not procedural_map.has_method("register_terrain_footprint"):
		return

	var interval_duration: float = max(footstep_interval, 0.001)
	var current_position: Vector3 = global_position
	var horizontal_movement_segment: Vector3 = Vector3(
		current_position.x - position_before_move.x,
		0.0,
		current_position.z - position_before_move.z
	)
	var horizontal_distance: float = horizontal_movement_segment.length()
	var horizontal_speed: float = horizontal_distance / max(delta, 0.0001)
	var move_direction: Vector3 = Vector3.ZERO
	if horizontal_distance > 0.0001:
		move_direction = horizontal_movement_segment / horizontal_distance
	else:
		var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
		if horizontal_velocity.length_squared() > 0.0001:
			move_direction = horizontal_velocity.normalized()

	var ground_probe: Dictionary = _get_footprint_ground_probe()
	var has_ground_contact: bool = is_on_floor() or not ground_probe.is_empty()
	var should_emit_footprints: bool = has_ground_contact and horizontal_speed >= footstep_min_speed and move_direction.length_squared() > 0.0001
	if not should_emit_footprints:
		_was_emitting_terrain_footprints = false
		_footstep_interval_timer = 0.0
		_next_footstep_interval = _roll_next_footstep_interval()
		return

	if not _was_emitting_terrain_footprints:
		_emit_starting_terrain_footprints(position_before_move, move_direction)
		_use_left_footstep = true
		_was_emitting_terrain_footprints = true
		_next_footstep_interval = _roll_next_footstep_interval()
		_footstep_interval_timer = minf(_next_footstep_interval * 0.5, interval_duration)

	var remaining_frame_time: float = delta
	var elapsed_frame_time: float = 0.0
	while _footstep_interval_timer + remaining_frame_time >= _next_footstep_interval:
		var elapsed_until_next_footstep: float = _next_footstep_interval - _footstep_interval_timer
		elapsed_frame_time += elapsed_until_next_footstep
		var interpolation_weight: float = 1.0
		if delta > 0.0001:
			interpolation_weight = clamp(elapsed_frame_time / delta, 0.0, 1.0)
		var emit_position: Vector3 = position_before_move.lerp(current_position, interpolation_weight)
		_emit_terrain_footprint(emit_position, move_direction)
		remaining_frame_time -= elapsed_until_next_footstep
		_footstep_interval_timer = 0.0
		_next_footstep_interval = _roll_next_footstep_interval()

	_footstep_interval_timer += remaining_frame_time


func _emit_starting_terrain_footprints(current_position: Vector3, move_direction: Vector3) -> void:
	_emit_terrain_footprint_side(current_position, move_direction, -1.0)
	_emit_terrain_footprint_side(current_position, move_direction, 1.0)


func _emit_terrain_footprint(current_position: Vector3, move_direction: Vector3) -> void:
	var lateral_sign: float = -1.0 if _use_left_footstep else 1.0
	if _emit_terrain_footprint_side(current_position, move_direction, lateral_sign):
		_use_left_footstep = not _use_left_footstep


func _emit_terrain_footprint_side(current_position: Vector3, move_direction: Vector3, lateral_sign: float) -> bool:
	var footprint_direction: Vector3 = _get_footprint_direction(move_direction, lateral_sign)
	var lateral_direction: Vector3 = Vector3(-move_direction.z, 0.0, move_direction.x)
	var forward_offset: Vector3 = footprint_direction * footstep_forward_offset
	var footstep_position: Vector3 = current_position + lateral_direction * footstep_lateral_offset * lateral_sign + forward_offset
	if not _can_emit_terrain_footprint_at(footstep_position):
		return false

	procedural_map.register_terrain_footprint(
		footstep_position,
		footprint_direction,
		maxf(footstep_length, 0.01),
		maxf(footstep_width, 0.01)
	)
	_last_terrain_footprint_position = footstep_position
	_has_last_terrain_footprint_position = true
	return true


func _roll_next_footstep_interval() -> float:
	var randomized_interval: float = footstep_interval + _footstep_rng.randf_range(-footstep_interval_randomness, footstep_interval_randomness)
	return maxf(randomized_interval, 0.04)


func _get_footprint_direction(move_direction: Vector3, lateral_sign: float) -> Vector3:
	if move_direction.length_squared() <= 0.0001:
		return Vector3.FORWARD

	var angle_offset_degrees: float = (footstep_outward_angle_degrees * lateral_sign) + _footstep_rng.randf_range(-footstep_angle_randomness_degrees, footstep_angle_randomness_degrees)
	var rotated_direction: Vector3 = move_direction.rotated(Vector3.UP, deg_to_rad(angle_offset_degrees))
	rotated_direction.y = 0.0
	if rotated_direction.length_squared() <= 0.0001:
		return move_direction.normalized()
	return rotated_direction.normalized()


func _can_emit_terrain_footprint_at(footstep_position: Vector3) -> bool:
	if not _has_last_terrain_footprint_position or footstep_min_distance <= 0.0:
		return true

	var horizontal_offset: Vector2 = Vector2(
		footstep_position.x - _last_terrain_footprint_position.x,
		footstep_position.z - _last_terrain_footprint_position.z
	)
	return horizontal_offset.length() >= footstep_min_distance


func _get_footprint_ground_probe() -> Dictionary:
	var from: Vector3 = global_position + Vector3.UP * footstep_ground_probe_start_height
	var to: Vector3 = global_position - Vector3.UP * footstep_ground_probe_distance
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.exclude = [get_rid()]

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return {}

	var collider: Node = result.collider
	if collider == null:
		return {}
	if collider.is_in_group("base_platform") or collider.is_in_group("floor_tile"):
		return result
	return {}


## Handle traditional WASD-style input
func _handle_direct_input(delta: float) -> void:
	if not can_move:
		velocity.x = 0
		velocity.z = 0
		return
	
	var input_dir: Vector2 = Input.get_vector(input_left, input_right, input_forward, input_back)
	
	if input_dir.length() > 0:
		# Move in input direction
		velocity.x = input_dir.x * move_speed
		velocity.z = input_dir.y * move_speed
		
		# Rotate to face direction
		var target_rotation: float = atan2(input_dir.x, input_dir.y)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)
	else:
		# Stop moving
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)


## Handle click-to-move
func _handle_click_to_move(delta: float) -> void:
	if not can_move or not _has_target:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
		return
	
	# Check if we have a path to follow
	if _current_path.is_empty():
		_has_target = false
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
		_unhighlight_tile(_target_tile)
		_target_tile = null
		_clear_target_indicator()
		return
	
	# Get current waypoint
	var current_waypoint := _current_path[_current_path_index]
	
	# Calculate direction to current waypoint (only XZ plane)
	var target_pos_2d := Vector2(current_waypoint.x, current_waypoint.z)
	var current_pos_2d := Vector2(global_position.x, global_position.z)
	var distance := current_pos_2d.distance_to(target_pos_2d)
	
	# Check if we've reached current waypoint
	if distance < arrival_distance:
		# Move to next waypoint
		_current_path_index += 1
		
		if _current_path_index >= _current_path.size():
			# Reached final destination
			_has_target = false
			_current_path.clear()
			_current_path_index = 0
			_clear_target_indicator()  # Clear target indicator
			velocity.x = move_toward(velocity.x, 0, move_speed)
			velocity.z = move_toward(velocity.z, 0, move_speed)
			# Unhighlight target tile when reached
			_unhighlight_tile(_target_tile)
			_target_tile = null
			if debug_movement:
				print("Arrived at final destination!")
			return
		else:
			# Continue to next waypoint
			current_waypoint = _current_path[_current_path_index]
			target_pos_2d = Vector2(current_waypoint.x, current_waypoint.z)
			distance = current_pos_2d.distance_to(target_pos_2d)
			if debug_movement:
				print("Moving to waypoint ", _current_path_index, " of ", _current_path.size())
	
	# Move toward current waypoint
	var direction_2d := (target_pos_2d - current_pos_2d).normalized()
	
	# Force orthogonal movement (prioritize larger component)
	if abs(direction_2d.x) > abs(direction_2d.y):
		# Move horizontally (X axis)
		direction_2d.y = 0
		direction_2d.x = sign(direction_2d.x)
	else:
		# Move vertically (Z axis)
		direction_2d.x = 0
		direction_2d.y = sign(direction_2d.y)
	
	velocity.x = direction_2d.x * move_speed
	velocity.z = direction_2d.y * move_speed
	
	# Rotate to face movement direction
	if direction_2d.length() > 0.01:
		var target_rotation: float = atan2(direction_2d.x, direction_2d.y)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)


## Handle mouse click raycast
func _handle_click(screen_position: Vector2) -> void:
	if not camera:
		camera = get_viewport().get_camera_3d()
	
	if not camera:
		print("ERROR: No camera found!")
		return
	
	# Raycast from camera
	var from: Vector3 = camera.project_ray_origin(screen_position)
	var to: Vector3 = from + camera.project_ray_normal(screen_position) * 1000.0
	
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	
	var result := space_state.intersect_ray(query)
	
	if result:
		var collider: Node = result.collider
		
		# Check what was clicked and adjust target accordingly
		if collider.is_in_group("wall"):
			# Clicked on wall - no movement
			if debug_movement:
				print("Clicked on wall - ignoring")
			return
		elif collider.is_in_group("floor_tile"):
			# Clicked on floor tile - find path to tile center
			# Unhighlight previous target
			_unhighlight_tile(_target_tile)
			
			var target_pos: Vector3
			if collider.has_meta("tile_center"):
				target_pos = collider.get_meta("tile_center")
			else:
				target_pos = result.position
			
			# Recalculate path from current position to new target (Dijkstra with lava avoidance)
			var path := _find_path(global_position, target_pos)
			
			if path.is_empty():
				if debug_movement:
					print("No valid path to target")
				return
			
			# Set up path following
			_current_path = path
			_current_path_index = 0
			_target_position = _current_path[0] if not _current_path.is_empty() else target_pos
			_has_target = true
			_target_tile = collider
			_highlight_tile(_target_tile, target_color)
			_spawn_target_indicator(target_pos)  # Show floating indicator above target
			_spawn_click_indicator(target_pos)  # Show particles at clicked position
			
			if debug_movement:
				print("Path set to tile with ", path.size(), " waypoints")
		elif collider.is_in_group("base_platform"):
			# Clicked on base platform - find path to exact point
			# Unhighlight previous target tile (if any)
			_unhighlight_tile(_target_tile)
			_target_tile = null
			
			var target_pos: Vector3 = result.position
			
			# Recalculate path from current position to new target (Dijkstra with lava avoidance)
			var path := _find_path(global_position, target_pos)
			
			if path.is_empty():
				if debug_movement:
					print("No valid path to target")
				return
			
			# Set up path following
			_current_path = path
			_current_path_index = 0
			_target_position = _current_path[0] if not _current_path.is_empty() else target_pos
			_has_target = true
			_spawn_target_indicator(target_pos)  # Show floating indicator above target
			_spawn_click_indicator(target_pos)  # Show particles at clicked position
			
			if debug_movement:
				print("Path set to platform with ", path.size(), " waypoints")
		else:
			# Unknown object - try to find path
			# Unhighlight previous target tile (if any)
			_unhighlight_tile(_target_tile)
			_target_tile = null
			
			var target_pos: Vector3 = result.position
			
			# Recalculate path from current position to new target (Dijkstra with lava avoidance)
			var path := _find_path(global_position, target_pos)
			
			if path.is_empty():
				if debug_movement:
					print("No valid path to target")
				return
			
			# Set up path following
			_current_path = path
			_current_path_index = 0
			_target_position = _current_path[0] if not _current_path.is_empty() else target_pos
			_has_target = true
			_spawn_target_indicator(target_pos)  # Show floating indicator above target
			_spawn_click_indicator(target_pos)  # Show particles at clicked position
			
			if debug_movement:
				print("Path set with ", path.size(), " waypoints")
	else:
		if debug_movement:
			print("Click didn't hit anything")


## Handle mouse hover for tile highlighting
func _handle_hover(screen_position: Vector2) -> void:
	if not camera:
		camera = get_viewport().get_camera_3d()
	
	if not camera:
		return
	
	# Raycast from camera
	var from: Vector3 = camera.project_ray_origin(screen_position)
	var to: Vector3 = from + camera.project_ray_normal(screen_position) * 1000.0
	
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	
	var result := space_state.intersect_ray(query)
	
	if result:
		var collider: Node = result.collider
		
		# Only highlight floor tiles on hover
		if collider.is_in_group("floor_tile") and collider != _target_tile:
			if _hovered_tile != collider:
				# Unhighlight previous hovered tile
				_unhighlight_tile(_hovered_tile)
				
				# Highlight new tile
				_hovered_tile = collider
				_highlight_tile(_hovered_tile, hover_color)
		else:
			# Not hovering over a tile anymore
			_unhighlight_tile(_hovered_tile)
			_hovered_tile = null
	else:
		# Not hovering over anything
		_unhighlight_tile(_hovered_tile)
		_hovered_tile = null


## Highlights a tile with specified color
func _highlight_tile(tile: Node3D, color: Color) -> void:
	if not tile or not is_instance_valid(tile):
		return
	
	# Skip if already highlighted as target
	if tile == _target_tile and color == hover_color:
		return
	
	if tile is CSGBox3D:
		var csg_tile := tile as CSGBox3D
		
		# Store original material if not already stored
		if not _stored_materials.has(tile):
			_stored_materials[tile] = csg_tile.material
		
		# Create highlighted material
		var highlight_mat := StandardMaterial3D.new()
		highlight_mat.albedo_color = color
		highlight_mat.emission_enabled = true
		highlight_mat.emission = color
		highlight_mat.emission_energy = highlight_emission
		
		csg_tile.material = highlight_mat


## Removes highlight from a tile
func _unhighlight_tile(tile: Node3D) -> void:
	if not tile or not is_instance_valid(tile):
		return
	
	if tile is CSGBox3D:
		var csg_tile := tile as CSGBox3D
		
		# Restore original material
		if _stored_materials.has(tile):
			csg_tile.material = _stored_materials[tile]
			_stored_materials.erase(tile)


func _refresh_click_indicator_scene() -> void:
	_click_indicator_scene = null
	if is_inside_tree():
		_setup_click_indicator()


func _build_click_indicator_draw_material() -> Material:
	if click_effect_material != null:
		return click_effect_material.duplicate()

	var particle_material: StandardMaterial3D = StandardMaterial3D.new()
	particle_material.albedo_color = click_effect_color
	particle_material.emission_enabled = true
	particle_material.emission = click_effect_color
	particle_material.emission_energy = 0.5
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return particle_material


## Setup click indicator particle system
func _setup_click_indicator() -> void:
	_click_indicator_scene = null
	if not show_click_effect:
		return
	
	# Create a reusable particle scene (we'll instance it on demand)
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = click_particle_count
	particles.lifetime = 1.0
	particles.explosiveness = 1.0
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	
	# Create particle material
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 0.2
	process_material.direction = Vector3(0, 1, 0)
	process_material.spread = 45.0
	process_material.initial_velocity_min = 1.5
	process_material.initial_velocity_max = 3.0
	process_material.gravity = Vector3(0, -9.8, 0)
	process_material.damping_min = 0.5
	process_material.damping_max = 1.5
	process_material.scale_min = 0.04
	process_material.scale_max = 0.08
	
	particles.process_material = process_material
	
	# Create particle mesh (small spheres)
	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.06, 0.06)
	particle_mesh.material = _build_click_indicator_draw_material()
	particles.draw_pass_1 = particle_mesh
	
	# Store as packed scene for easy instantiation
	var packed: PackedScene = PackedScene.new()
	packed.pack(particles)
	_click_indicator_scene = packed


## Spawns a floating target indicator above the target position
func _spawn_target_indicator(target_pos: Vector3) -> void:
	if not show_target_indicator:
		return
	
	# Clear existing indicator
	_clear_target_indicator()
	
	# Create a torus (ring) mesh
	var torus_mesh := TorusMesh.new()
	torus_mesh.inner_radius = target_indicator_size * 0.5
	torus_mesh.outer_radius = target_indicator_size * 0.7
	torus_mesh.rings = 32
	torus_mesh.ring_segments = 16
	
	# Create material with emission
	var material := StandardMaterial3D.new()
	material.albedo_color = target_color
	material.emission_enabled = true
	material.emission = target_color
	material.emission_energy = 0.5
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.8
	
	# Create mesh instance
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = torus_mesh
	mesh_instance.material_override = material
	
	# Position above target
	get_tree().root.add_child(mesh_instance)
	mesh_instance.global_position = target_pos + Vector3(0, target_indicator_height, 0)
	mesh_instance.rotation.x = -PI / 2  # Rotate to lie flat
	
	_target_indicator = mesh_instance
	
	if debug_movement:
		print("[Target Indicator] Spawned ring at ", target_pos, " + height offset")
	
	# Add gentle pulsing animation
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(mesh_instance, "scale", Vector3(1.1, 1.1, 1.1), 0.8)
	tween.tween_property(mesh_instance, "scale", Vector3(1.0, 1.0, 1.0), 0.8)


## Clears the target indicator
func _clear_target_indicator() -> void:
	if _target_indicator and is_instance_valid(_target_indicator):
		_target_indicator.queue_free()
		_target_indicator = null


## Spawns a click indicator particle effect at position
func _spawn_click_indicator(spawn_position: Vector3) -> void:
	if not show_click_effect or not _click_indicator_scene:
		return
	
	var particles: GPUParticles3D = _click_indicator_scene.instantiate()
	get_tree().root.add_child(particles)
	# Spawn particles above the clicked position
	particles.global_position = spawn_position + Vector3(0, click_particle_height, 0)
	particles.emitting = true
	particles.restart()
	
	if debug_movement:
		print("[Click Effect] Spawned particles at ", spawn_position)
	
	# Auto-cleanup after lifetime
	await get_tree().create_timer(particles.lifetime + 0.5).timeout
	if is_instance_valid(particles):
		particles.queue_free()
