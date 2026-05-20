extends Node3D

@export var anchor_offset: Vector3 = Vector3(0.0, 1.7356035, 0.0)
@export var starting_yaw_degrees: float = 45.0
@export var orbit_step_degrees: float = 90.0
@export var orbit_ease_speed: float = 8.0
@export_group("Mouse Orbit")
@export var right_mouse_drag_enabled: bool = true
@export_range(0.01, 1.0, 0.01) var mouse_drag_sensitivity_degrees: float = 0.12
@export_range(0.0, 89.0, 0.1) var max_pitch_up_deviation_degrees: float = 18.0
@export_range(0.0, 89.0, 0.1) var max_pitch_down_deviation_degrees: float = 18.0
@export_range(0.0, 32.0, 0.1) var minimum_camera_height_above_target: float = 4.0

var _follow_target: Node3D = null
var _spring_position: Node3D = null
var _spring_position_base_offset: Vector3 = Vector3.ZERO
var _initial_orbit_pitch_radians: float = 0.0
var _initial_orbit_yaw_radians: float = 0.0
var _target_orbit_pitch_radians: float = 0.0
var _target_orbit_yaw_radians: float = 0.0
var _is_right_mouse_dragging: bool = false


func _ready() -> void:
	top_level = true
	_follow_target = get_parent() as Node3D
	_spring_position = get_node_or_null("SpringArm3D/SpringPosition") as Node3D
	_initial_orbit_pitch_radians = rotation.x
	_initial_orbit_yaw_radians = deg_to_rad(starting_yaw_degrees)
	_target_orbit_pitch_radians = _clamp_pitch_to_constraints(_initial_orbit_pitch_radians, _initial_orbit_yaw_radians)
	_target_orbit_yaw_radians = _initial_orbit_yaw_radians
	_update_anchor_position()
	rotation.x = _target_orbit_pitch_radians
	rotation.y = _target_orbit_yaw_radians
	_capture_spring_position_base_offset()


func _physics_process(delta: float) -> void:
	_update_anchor_position()
	var weight: float = clamp(orbit_ease_speed * delta, 0.0, 1.0)
	rotation.x = lerp_angle(rotation.x, _target_orbit_pitch_radians, weight)
	rotation.y = lerp_angle(rotation.y, _target_orbit_yaw_radians, weight)
	if absf(wrapf(_target_orbit_pitch_radians - rotation.x, -PI, PI)) <= 0.001:
		rotation.x = _target_orbit_pitch_radians
	if absf(wrapf(_target_orbit_yaw_radians - rotation.y, -PI, PI)) <= 0.001:
		rotation.y = _target_orbit_yaw_radians


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_is_right_mouse_dragging = event.pressed and right_mouse_drag_enabled
		if right_mouse_drag_enabled:
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _is_right_mouse_dragging and right_mouse_drag_enabled:
		_apply_mouse_orbit_drag(event.relative)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB or event.physical_keycode == KEY_TAB:
			reset_orbit()
			get_viewport().set_input_as_handled()


func configure_player_orbit(
	drag_sensitivity_degrees: float,
	max_pitch_up_deviation_degrees_value: float,
	max_pitch_down_deviation_degrees_value: float,
	minimum_camera_height_above_target_value: float
) -> void:
	mouse_drag_sensitivity_degrees = maxf(drag_sensitivity_degrees, 0.01)
	max_pitch_up_deviation_degrees = maxf(max_pitch_up_deviation_degrees_value, 0.0)
	max_pitch_down_deviation_degrees = maxf(max_pitch_down_deviation_degrees_value, 0.0)
	minimum_camera_height_above_target = maxf(minimum_camera_height_above_target_value, 0.0)
	_target_orbit_pitch_radians = _clamp_pitch_to_constraints(_target_orbit_pitch_radians, _target_orbit_yaw_radians)


func reset_orbit() -> void:
	_target_orbit_yaw_radians = _initial_orbit_yaw_radians
	_target_orbit_pitch_radians = _clamp_pitch_to_constraints(_initial_orbit_pitch_radians, _initial_orbit_yaw_radians)


func _apply_mouse_orbit_drag(relative_motion: Vector2) -> void:
	var yaw_delta_radians: float = deg_to_rad(relative_motion.x * mouse_drag_sensitivity_degrees)
	var pitch_delta_radians: float = deg_to_rad(relative_motion.y * mouse_drag_sensitivity_degrees)
	_target_orbit_yaw_radians = wrapf(_target_orbit_yaw_radians - yaw_delta_radians, -PI, PI)
	_target_orbit_pitch_radians = _clamp_pitch_to_constraints(_target_orbit_pitch_radians - pitch_delta_radians, _target_orbit_yaw_radians)


func _capture_spring_position_base_offset() -> void:
	if _spring_position == null or not is_instance_valid(_spring_position):
		return

	var spring_position_offset: Vector3 = _spring_position.global_position - global_position
	var initial_basis: Basis = Basis.from_euler(Vector3(_target_orbit_pitch_radians, _target_orbit_yaw_radians, 0.0))
	_spring_position_base_offset = initial_basis.inverse() * spring_position_offset


func _get_min_pitch_radians() -> float:
	var min_pitch_limit_radians: float = deg_to_rad(-89.0)
	var max_up_deviation_radians: float = deg_to_rad(max_pitch_up_deviation_degrees)
	return maxf(_initial_orbit_pitch_radians - max_up_deviation_radians, min_pitch_limit_radians)


func _get_max_pitch_radians() -> float:
	var max_pitch_limit_radians: float = deg_to_rad(89.0)
	var max_down_deviation_radians: float = deg_to_rad(max_pitch_down_deviation_degrees)
	return minf(_initial_orbit_pitch_radians + max_down_deviation_radians, max_pitch_limit_radians)


func _clamp_pitch_to_constraints(pitch_radians: float, yaw_radians: float) -> float:
	var min_pitch_radians: float = _get_min_pitch_radians()
	var max_pitch_radians: float = _get_max_pitch_radians()
	var clamped_pitch_radians: float = clampf(pitch_radians, min_pitch_radians, max_pitch_radians)
	if _spring_position_base_offset == Vector3.ZERO or _follow_target == null:
		return clamped_pitch_radians

	var anchor_position: Vector3 = _follow_target.global_position + anchor_offset
	var target_basis: Basis = Basis.from_euler(Vector3(clamped_pitch_radians, yaw_radians, 0.0))
	var predicted_spring_position: Vector3 = anchor_position + (target_basis * _spring_position_base_offset)
	var minimum_camera_y: float = _follow_target.global_position.y + minimum_camera_height_above_target
	if predicted_spring_position.y >= minimum_camera_y:
		return clamped_pitch_radians

	var best_pitch_radians: float = clamped_pitch_radians
	var best_pitch_delta: float = INF
	var sample_count: int = 48
	for sample_index in range(sample_count + 1):
		var sample_weight: float = float(sample_index) / float(sample_count)
		var sampled_pitch_radians: float = lerpf(min_pitch_radians, max_pitch_radians, sample_weight)
		var sampled_basis: Basis = Basis.from_euler(Vector3(sampled_pitch_radians, yaw_radians, 0.0))
		var sampled_spring_position: Vector3 = anchor_position + (sampled_basis * _spring_position_base_offset)
		if sampled_spring_position.y < minimum_camera_y:
			continue

		var sampled_pitch_delta: float = absf(sampled_pitch_radians - clamped_pitch_radians)
		if sampled_pitch_delta < best_pitch_delta:
			best_pitch_delta = sampled_pitch_delta
			best_pitch_radians = sampled_pitch_radians

	if best_pitch_delta == INF:
		return clamped_pitch_radians

	return best_pitch_radians


func _update_anchor_position() -> void:
	if _follow_target == null:
		return

	global_position = _follow_target.global_position + anchor_offset
