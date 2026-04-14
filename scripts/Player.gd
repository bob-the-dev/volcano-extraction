extends CharacterBody3D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var camera: Camera3D = get_viewport().get_camera_3d()

@export var can_move : bool = true
@export var has_gravity : bool = true

## Enable click-to-move functionality
@export var click_to_move : bool = true
## Show debug visualization
@export var debug_movement : bool = true

## Reference to the procedural map for pathfinding
@export var procedural_map: Node3D = null

@export_group("Movement Physics")
## Maximum height the player can step up automatically (in units)
@export var step_height : float = 0.3
## How long to snap to floor when going down slopes
@export var floor_snap : float = 0.1

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

@export_group("Click Indicator")
## Show particle effect when clicking
@export var show_click_effect : bool = true
## Color of click indicator particles
@export var click_effect_color : Color = Color(1.0, 0.95, 0.7, 0.8)
## Number of particles in puff
@export var click_particle_count : int = 15

@export_group("Debug")
## Show waypoint markers along path (controlled by procedural_map.show_grid_debug)
@export var waypoint_debug_color: Color = Color(1, 1, 0, 0.8)

@export_group("Pathfinding Costs")
## Cost multiplier for walking through lava (higher = more avoided)
@export var lava_cost_multiplier: float = 10.0
## Base cost for normal floor tiles
@export var floor_base_cost: float = 1.0

# Click-to-move variables
var _target_position: Vector3
var _has_target: bool = false
var _hovered_tile: Node3D = null
var _target_tile: Node3D = null
var _stored_materials: Dictionary = {}  # Store original materials
var _click_indicator_scene: PackedScene = null

# Pathfinding variables
var _astar: AStar2D = AStar2D.new()
var _pathfinding_initialized: bool = false
var _current_path: Array[Vector3] = []
var _current_path_index: int = 0
var _grid_cell_size: float = 2.0  # Default, will be updated from map
var _debug_waypoint_markers: Array[Node3D] = []

func _ready() -> void:
	# Add to player group for easy lookup
	add_to_group("player")
	
	# Enable step-up for small ledges
	floor_stop_on_slope = false
	floor_snap_length = floor_snap
	
	# Setup click indicator particle system
	_setup_click_indicator()
	
	# Find procedural map if not set - try multiple methods
	print("[Player] Looking for procedural map...")
	if not procedural_map:
		# Method 1: Try as sibling node (most common in scenes)
		procedural_map = get_node_or_null("../Procedural Map")
		if procedural_map:
			print("[Player] Found procedural map as sibling: ", procedural_map.name)
		else:
			# Method 2: Try by group
			procedural_map = get_tree().get_first_node_in_group("procedural_map")
			if procedural_map:
				print("[Player] Found procedural map by group: ", procedural_map.name)
			else:
				# Method 3: Search parent's children
				var parent := get_parent()
				if parent:
					for child in parent.get_children():
						if child.get_script() and child.get_script().resource_path.contains("procedural_map"):
							procedural_map = child
							print("[Player] Found procedural map by script search: ", procedural_map.name)
							break
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
			var lava_cells: Array = procedural_map._lava_cells if "_lava_cells" in procedural_map else []
			if not floor_cells.is_empty() or not lava_cells.is_empty():
				print("[Player] Map already generated, initializing pathfinding immediately")
				call_deferred("_initialize_pathfinding")
			else:
				print("[Player] Map not yet generated, waiting for map_regenerated signal")
		else:
			print("[Player] Map not yet generated, waiting for map_regenerated signal")
	else:
		print("[Player] ERROR: No procedural map found - pathfinding will not work!")
	
	var idle = animation_player.get_animation('idle')
	idle.loop_mode = Animation.LOOP_LINEAR
	animation_player.play('idle')


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
	
	# Get cell size from map
	if "cell_size" in procedural_map:
		_grid_cell_size = procedural_map.cell_size
		print("[Pathfinding] Cell size: ", _grid_cell_size)
	else:
		print("[Pathfinding] WARNING: No cell_size property found, using default: ", _grid_cell_size)
	
	# Get cells from map
	var cells: Array = procedural_map._cells if "_cells" in procedural_map else []
	var floor_cells: Array = procedural_map._floor_cells if "_floor_cells" in procedural_map else []
	var lava_cells: Array = procedural_map._lava_cells if "_lava_cells" in procedural_map else []
	
	print("[Pathfinding] Total cells: ", cells.size(), " | Floor cells: ", floor_cells.size(), " | Lava cells: ", lava_cells.size())
	
	if cells.is_empty():
		print("[Pathfinding] ERROR: no cells found in map - map may not be generated yet")
		return
	
	if floor_cells.is_empty() and lava_cells.is_empty():
		print("[Pathfinding] ERROR: no walkable cells found in map")
		return
	
	# Combine floor and lava cells for pathfinding
	var walkable_cells: Array = floor_cells + lava_cells
	
	# Add all walkable cells to AStar with appropriate weights
	var added_count := 0
	var lava_count := 0
	for cell in walkable_cells:
		if cell:
			var grid_pos: Vector2 = cell.position
			var point_id := _grid_to_id(grid_pos)
			_astar.add_point(point_id, grid_pos)
			
			# Set weight based on cell type (Dijkstra-style weighted pathfinding)
			if cell.is_lava:
				_astar.set_point_weight_scale(point_id, lava_cost_multiplier)
				lava_count += 1
			else:
				_astar.set_point_weight_scale(point_id, floor_base_cost)
			
			added_count += 1
	
	print("[Pathfinding] Added ", added_count, " walkable cells to AStar grid")
	print("[Pathfinding] - Floor cells: ", added_count - lava_count, " (cost: ", floor_base_cost, ")")
	print("[Pathfinding] - Lava cells: ", lava_count, " (cost: ", lava_cost_multiplier, "x)")
	
	# Connect neighboring walkable cells (orthogonal only - up/down/left/right)
	var connection_count := 0
	for cell in walkable_cells:
		if cell:
			# Connect all floor cells including lava
			var grid_pos: Vector2 = cell.position
			var point_id := _grid_to_id(grid_pos)
			
			# Check 4 orthogonal neighbors
			var neighbors := [
				Vector2(grid_pos.x + 1, grid_pos.y),  # Right
				Vector2(grid_pos.x - 1, grid_pos.y),  # Left
				Vector2(grid_pos.x, grid_pos.y + 1),  # Down
				Vector2(grid_pos.x, grid_pos.y - 1),  # Up
			]
			
			for neighbor_pos in neighbors:
				var neighbor_id := _grid_to_id(neighbor_pos)
				if _astar.has_point(neighbor_id):
					# Only connect if not already connected
					if not _astar.are_points_connected(point_id, neighbor_id):
						_astar.connect_points(point_id, neighbor_id)
						connection_count += 1
	
	print("[Pathfinding] Created ", connection_count, " connections between cells")
	
	_pathfinding_initialized = true
	print("[Pathfinding] ✓ Initialization complete with ", _astar.get_point_count(), " walkable cells")


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
	
	# Convert grid path to world positions and count lava tiles
	var lava_tiles_in_path := 0
	for grid_pos in grid_path:
		path.append(_grid_to_world(grid_pos))
		
		# Check if this waypoint is on a lava tile
		var point_id := _grid_to_id(grid_pos)
		var weight := _astar.get_point_weight_scale(point_id)
		if weight > floor_base_cost * 2.0:  # If weight is significantly higher, it's lava
			lava_tiles_in_path += 1
	
	print("[Pathfinding] ✓ Path found with ", path.size(), " waypoints")
	if lava_tiles_in_path > 0:
		print("[Pathfinding]   ⚠ Path crosses ", lava_tiles_in_path, " lava tiles (unavoidable)")
	else:
		print("[Pathfinding]   ✓ Path avoids all lava tiles")
	
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
	if not click_to_move or not can_move:
		return
	
	# Handle mouse motion for hover highlighting
	if event is InputEventMouseMotion:
		_handle_hover(event.position)
	
	# Handle mouse click for movement
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_click(event.position)


func _physics_process(delta: float) -> void:
	# Apply gravity
	if has_gravity and not is_on_floor():
		velocity += get_gravity() * delta

	# Handle movement
	if click_to_move:
		_handle_click_to_move(delta)
	else:
		_handle_direct_input(delta)
	
	# Store state before moving
	var was_on_floor := is_on_floor()
	var horizontal_velocity := Vector2(velocity.x, velocity.z).length()
	
	# Move and slide
	move_and_slide()
	
	# Step-up assist: if on floor, trying to move, but hit a wall, boost upward
	if was_on_floor and is_on_wall() and horizontal_velocity > 0.1:
		# Apply upward boost to climb small ledges
		velocity.y = step_height * 10.0
		move_and_slide()


## Handle traditional WASD-style input
func _handle_direct_input(delta: float) -> void:
	if not can_move:
		velocity.x = 0
		velocity.z = 0
		return
	
	var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
	
	if input_dir.length() > 0:
		# Move in input direction
		velocity.x = input_dir.x * move_speed
		velocity.z = input_dir.y * move_speed
		
		# Rotate to face direction
		var target_rotation := atan2(input_dir.x, input_dir.y)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)
		
		# Play walk animation
		if animation_player.current_animation != 'walk':
			animation_player.play('walk')
	else:
		# Stop moving
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
		
		if animation_player.current_animation == 'walk':
			animation_player.play('idle')


## Handle click-to-move
func _handle_click_to_move(delta: float) -> void:
	if not can_move or not _has_target:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
		if animation_player.current_animation == 'walk':
			animation_player.play('idle')
		return
	
	# Check if we have a path to follow
	if _current_path.is_empty():
		_has_target = false
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
		if animation_player.current_animation == 'walk':
			animation_player.play('idle')
		_unhighlight_tile(_target_tile)
		_target_tile = null
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
			_clear_waypoint_debug()  # Clear debug markers
			velocity.x = move_toward(velocity.x, 0, move_speed)
			velocity.z = move_toward(velocity.z, 0, move_speed)
			if animation_player.current_animation == 'walk':
				animation_player.play('idle')
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
		var target_rotation := atan2(direction_2d.x, direction_2d.y)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)
	
	# Play walk animation
	if animation_player.current_animation != 'walk':
		animation_player.play('walk')


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
			_spawn_click_indicator(path[-1])  # Show indicator at final destination
			_show_waypoint_debug(path)  # Show debug waypoint markers
			
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
			_spawn_click_indicator(path[-1])  # Show indicator at final destination
			_show_waypoint_debug(path)  # Show debug waypoint markers
			
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
			_spawn_click_indicator(path[-1])  # Show indicator at final destination
			_show_waypoint_debug(path)  # Show debug waypoint markers
			
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


## Setup click indicator particle system
func _setup_click_indicator() -> void:
	if not show_click_effect:
		return
	
	# Create a reusable particle scene (we'll instance it on demand)
	var particles := GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = click_particle_count
	particles.lifetime = 100.0	
	particles.explosiveness = 1.0
	particles.local_coords = false
	
	# Create particle material
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 0.3
	process_material.direction = Vector3(0, 1, 0)
	process_material.spread = 65.0
	process_material.initial_velocity_min = 1.0
	process_material.initial_velocity_max = 2.5
	process_material.gravity = Vector3(0, -5.0, 0)
	process_material.damping_min = 1.0
	process_material.damping_max = 2.0
	process_material.scale_min = 0.02
	process_material.scale_max = 0.06
	
	particles.process_material = process_material
	
	# Create particle mesh (small spheres)
	var particle_mesh := QuadMesh.new()
	particle_mesh.size = Vector2(0.06, 0.06)
	
	# Create particle material with color
	var particle_material := StandardMaterial3D.new()
	particle_material.albedo_color = click_effect_color
	particle_material.emission_enabled = false
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	
	particle_mesh.material = particle_material
	particles.draw_pass_1 = particle_mesh
	
	# Store as packed scene for easy instantiation
	var packed := PackedScene.new()
	packed.pack(particles)
	_click_indicator_scene = packed


## Spawns a click indicator particle effect at position
func _spawn_click_indicator(spawn_position: Vector3) -> void:
	if not show_click_effect or not _click_indicator_scene:
		return
	
	var particles: GPUParticles3D = _click_indicator_scene.instantiate()
	get_tree().root.add_child(particles)
	particles.global_position = spawn_position
	particles.emitting = true
	
	# Auto-cleanup after lifetime
	await get_tree().create_timer(particles.lifetime + 0.5).timeout
	if is_instance_valid(particles):
		particles.queue_free()


## Clear debug waypoint markers
func _clear_waypoint_debug() -> void:
	for marker in _debug_waypoint_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_debug_waypoint_markers.clear()


## Show debug markers for waypoints along path
func _show_waypoint_debug(path: Array[Vector3]) -> void:
	# Only show if procedural map has debug enabled
	if not procedural_map or not ("show_grid_debug" in procedural_map):
		return
	
	if not procedural_map.show_grid_debug:
		return
	
	_clear_waypoint_debug()
	
	var index := 0
	for waypoint in path:
		var marker := CSGSphere3D.new()
		marker.radius = 0.15
		marker.material = StandardMaterial3D.new()
		marker.material.albedo_color = waypoint_debug_color
		marker.material.emission_enabled = true
		marker.material.emission = waypoint_debug_color
		marker.material.emission_energy = 0.5
		
		get_tree().root.add_child(marker)
		marker.global_position = waypoint
		_debug_waypoint_markers.append(marker)
		
		# Add text label with waypoint number
		if index < 10:  # Only label first 10 to avoid clutter
			var label := Label3D.new()
			label.text = str(index)
			label.pixel_size = 0.01
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.modulate = Color(1, 1, 0, 1)
			marker.add_child(label)
			label.position = Vector3(0, 0.3, 0)
		
		index += 1
	
	print("[Debug] Showing ", path.size(), " waypoint markers")
