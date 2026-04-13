extends CharacterBody3D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var camera: Camera3D = get_viewport().get_camera_3d()

@export var can_move : bool = true
@export var has_gravity : bool = true

## Enable click-to-move functionality
@export var click_to_move : bool = true
## Show debug visualization
@export var debug_movement : bool = true

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
@export var move_speed : float = 2.0
## How fast the character rotates to face movement direction.
@export var rotation_speed : float = 10.0
## How close to target before stopping
@export var arrival_distance : float = 0.3

# Click-to-move variables
var _target_position: Vector3
var _has_target: bool = false

func _ready() -> void:
	# Add to player group for easy lookup
	add_to_group("player")
	
	# Enable step-up for small ledges
	floor_stop_on_slope = false
	floor_snap_length = floor_snap
	
	var idle = animation_player.get_animation('idle')
	idle.loop_mode = Animation.LOOP_LINEAR
	animation_player.play('idle')


func _input(event: InputEvent) -> void:
	if not click_to_move or not can_move:
		return
	
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
	
	# Calculate direction to target (only XZ plane)
	var target_pos_2d := Vector2(_target_position.x, _target_position.z)
	var current_pos_2d := Vector2(global_position.x, global_position.z)
	var distance := current_pos_2d.distance_to(target_pos_2d)
	
	# Check if we've arrived
	if distance < arrival_distance:
		_has_target = false
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
		if animation_player.current_animation == 'walk':
			animation_player.play('idle')
		if debug_movement:
			print("Arrived at target!")
		return
	
	# Move toward target
	var direction_2d := (target_pos_2d - current_pos_2d).normalized()
	velocity.x = direction_2d.x * move_speed
	velocity.z = direction_2d.y * move_speed
	
	# Rotate to face target
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
		_target_position = result.position
		_has_target = true
		
		if debug_movement:
			print("Moving to: ", _target_position)
	else:
		if debug_movement:
			print("Click didn't hit anything")
