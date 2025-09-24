extends CharacterBody3D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@export var can_move : bool = true
@export var has_gravity : bool = true
@export var can_jump : bool = true
@export var can_sprint : bool = true


@export_group("Input Actions")
## Name of Input Action to move Left.
@export var input_left : String = "move_left"
## Name of Input Action to move Right.
@export var input_right : String = "move_right"
## Name of Input Action to move Forward.
@export var input_forward : String = "move_up"
## Name of Input Action to move Backward.
@export var input_back : String = "move_down"
## Name of Input Action to Jump.
@export var input_jump : String = "jump"
## Name of Input Action to Sprint.
@export var input_sprint : String = "sprint"

@export_group("Speeds")
## Move speed.
@export var move_speed : float = 2.0
## Normal speed.
@export var base_speed : float = 2.0
## Speed of jump.
@export var jump_velocity : float = 4.5
## How fast do we run?
@export var sprint_speed : float = 4.0

func _ready() -> void:
	#animation_player.play('idle')
	var idle = animation_player.get_animation('idle')
	idle.loop_mode = Animation.LOOP_LINEAR
	animation_player.play('idle')
	pass

func _physics_process(delta: float) -> void:
	
	if velocity.y != 0:
		animation_player.play('jump')
	#if is_on_floor() :
		#animation_player.play("idle")
		

	
	# Apply gravity to velocity
	if has_gravity:
		if not is_on_floor():
			velocity += get_gravity() * delta

	# Apply jumping
	if can_jump:
		if Input.is_action_just_pressed(input_jump) and is_on_floor():
			velocity.y = jump_velocity

	# Modify speed based on sprinting
	if can_sprint and Input.is_action_pressed(input_sprint):
			move_speed = sprint_speed
	else:
		move_speed = base_speed

	# Apply desired movement to velocity
	if can_move:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		if input_dir.length() != 0:
			if animation_player.current_animation != 'walk':
				animation_player.play('walk');
		var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		if move_dir:
			velocity.x = move_dir.x * -1 * move_speed
			velocity.z = move_dir.z * -1 * move_speed
		else:
			velocity.x = move_toward(velocity.x, 0, move_speed)
			velocity.z = move_toward(velocity.z, 0, move_speed)
	else:
		velocity.x = 0
		velocity.y = 0
	
	# Use velocity to actually move

	move_and_slide()
