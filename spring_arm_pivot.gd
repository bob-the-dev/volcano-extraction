extends Node3D

@export var anchor_offset: Vector3 = Vector3(0.0, 1.7356035, 0.0)
@export var starting_yaw_degrees: float = 45.0
@export var orbit_step_degrees: float = 90.0
@export var orbit_ease_speed: float = 8.0

var _follow_target: Node3D = null
var _target_orbit_yaw_radians: float = 0.0


func _ready() -> void:
	top_level = true
	_follow_target = get_parent() as Node3D
	_target_orbit_yaw_radians = deg_to_rad(starting_yaw_degrees)
	_update_anchor_position()
	rotation.y = _target_orbit_yaw_radians


func _physics_process(delta: float) -> void:
	_update_anchor_position()
	var weight: float = clamp(orbit_ease_speed * delta, 0.0, 1.0)
	rotation.y = lerp_angle(rotation.y, _target_orbit_yaw_radians, weight)
	if absf(wrapf(_target_orbit_yaw_radians - rotation.y, -PI, PI)) <= 0.001:
		rotation.y = _target_orbit_yaw_radians


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB or event.physical_keycode == KEY_TAB:
			var orbit_step_radians: float = deg_to_rad(orbit_step_degrees)
			if event.shift_pressed:
				_target_orbit_yaw_radians += orbit_step_radians
			else:
				_target_orbit_yaw_radians -= orbit_step_radians


func _update_anchor_position() -> void:
	if _follow_target == null:
		return

	global_position = _follow_target.global_position + anchor_offset
