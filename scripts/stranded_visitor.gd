extends CharacterBody3D

signal rescued(visitor: CharacterBody3D)

@export_group("Movement")
@export var move_speed: float = 3.4
@export var rotation_speed: float = 8.0
@export var arrival_distance: float = 0.4
@export var floor_snap: float = 0.3

@export_group("Interaction")
@export var interact_action: String = "ui_accept"
@export var interaction_distance: float = 3.2
@export var rescue_prompt_text: String = "Press Space to help"
@export var rescued_prompt_text: String = "Stay close. I am following you."
@export var rescued_prompt_duration: float = 2.2

@export_group("Follow")
@export var follow_distance: float = 2.4
@export var avoidance_probe_distance: float = 1.4
@export_range(5.0, 90.0, 1.0) var avoidance_angle_step_degrees: float = 18.0
@export_range(15.0, 180.0, 1.0) var avoidance_max_angle_degrees: float = 108.0

@export_group("Roaming")
@export var roam_min_distance_world: float = 3.0
@export var roam_max_distance_world: float = 14.0
@export var roam_pause_duration_min: float = 1.4
@export var roam_pause_duration_max: float = 4.2
@export_range(0, 4, 1) var roam_max_depth: int = 3

@export_group("Look")
@export var visitor_tint: Color = Color(0.47, 0.89, 1.08, 1.0)
@export_range(0.0, 4.0, 0.05) var visitor_emission_energy: float = 0.18

@onready var visual_root: Node3D = $VisualRoot
@onready var prompt_label: Label3D = $PromptLabel

var procedural_map: Node3D = null
var player: CharacterBody3D = null

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _follow_enabled: bool = false
var _interaction_available: bool = false
var _roam_decision_timer: float = 0.0
var _rescued_prompt_timer: float = 0.0
var _spawn_anchor_position: Vector3 = Vector3.ZERO
var _has_spawn_anchor_position: bool = false
var _move_target: Vector3 = Vector3.ZERO
var _has_move_target: bool = false


func _ready() -> void:
	add_to_group("stranded_visitor")
	floor_snap_length = floor_snap
	_resolve_dependencies()
	_sync_rng_to_map_seed()
	_apply_visitor_tint()
	if prompt_label != null:
		prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		prompt_label.visible = false
	_schedule_next_roam_decision()


func _physics_process(delta: float) -> void:
	_resolve_dependencies()

	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0

	_update_interaction_state(delta)

	if _follow_enabled:
		_update_follow_path(delta)
	else:
		_update_roaming(delta)

	_move_toward_target(delta)
	move_and_slide()


func set_spawn_anchor_position(anchor_world_position: Vector3) -> void:
	_spawn_anchor_position = anchor_world_position
	_has_spawn_anchor_position = true


func is_rescued() -> bool:
	return _follow_enabled


func _resolve_dependencies() -> void:
	if procedural_map == null:
		procedural_map = get_parent() as Node3D

	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D


func _sync_rng_to_map_seed() -> void:
	if procedural_map != null and "random_seed" in procedural_map:
		_rng.seed = int(procedural_map.random_seed) + 700021
		return

	_rng.randomize()


func _apply_visitor_tint() -> void:
	var visitor_material: StandardMaterial3D = StandardMaterial3D.new()
	visitor_material.albedo_color = visitor_tint
	visitor_material.emission_enabled = true
	visitor_material.emission = visitor_tint * visitor_emission_energy
	visitor_material.roughness = 1.0
	_apply_material_override_recursive(visual_root, visitor_material)


func _apply_material_override_recursive(current_node: Node, visitor_material: Material) -> void:
	if current_node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = current_node as MeshInstance3D
		mesh_instance.material_override = visitor_material

	for child in current_node.get_children():
		var child_node: Node = child
		_apply_material_override_recursive(child_node, visitor_material)


func _update_interaction_state(delta: float) -> void:
	if _follow_enabled:
		_interaction_available = false
		_rescued_prompt_timer = maxf(_rescued_prompt_timer - delta, 0.0)
		if prompt_label != null:
			prompt_label.text = rescued_prompt_text
			prompt_label.visible = _rescued_prompt_timer > 0.0
		return

	if player == null:
		_interaction_available = false
		if prompt_label != null:
			prompt_label.visible = false
		return

	var player_distance: float = _get_horizontal_distance_to(player.global_position)
	_interaction_available = player_distance <= interaction_distance
	if prompt_label != null:
		prompt_label.text = rescue_prompt_text
		prompt_label.visible = _interaction_available

	if _interaction_available and Input.is_action_just_pressed(interact_action):
		_follow_enabled = true
		_rescued_prompt_timer = rescued_prompt_duration
		_clear_move_target()
		rescued.emit(self)


func _update_follow_path(_delta: float) -> void:
	if player == null:
		_clear_move_target()
		return

	if _get_horizontal_distance_to(player.global_position) <= follow_distance:
		_clear_move_target()
		return

	_set_move_target(player.global_position)


func _update_roaming(delta: float) -> void:
	if _has_move_target:
		return

	_roam_decision_timer -= delta
	if _roam_decision_timer > 0.0:
		return

	if _pick_roam_destination():
		_schedule_next_roam_decision()
		return

	_roam_decision_timer = 1.0


func _pick_roam_destination() -> bool:
	if procedural_map == null:
		return false

	if not procedural_map.has_method("get_random_walkable_surface_position_near"):
		return false

	var roam_origin: Vector3 = global_position
	if _has_spawn_anchor_position:
		roam_origin = _spawn_anchor_position

	var target_variant: Variant = procedural_map.call(
		"get_random_walkable_surface_position_near",
		roam_origin,
		roam_min_distance_world,
		roam_max_distance_world,
		roam_max_depth
	)
	if not target_variant is Vector3:
		return false

	var roam_target: Vector3 = target_variant as Vector3
	if _get_horizontal_distance_to(roam_target) < arrival_distance:
		return false

	_set_move_target(roam_target)
	return true


func _set_move_target(target_world_position: Vector3) -> void:
	_move_target = target_world_position
	_has_move_target = true


func _move_toward_target(delta: float) -> void:
	if not _has_move_target:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)
		return

	var waypoint: Vector3 = _move_target
	var waypoint_xz: Vector2 = Vector2(waypoint.x, waypoint.z)
	var current_xz: Vector2 = Vector2(global_position.x, global_position.z)
	var distance_to_waypoint: float = current_xz.distance_to(waypoint_xz)

	if distance_to_waypoint <= arrival_distance:
		_clear_move_target()
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)
		return

	var direction: Vector2 = _find_steering_direction(_move_target)
	if direction.length_squared() <= 0.0001:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)
		return

	velocity.x = direction.x * move_speed
	velocity.z = direction.y * move_speed

	if direction.length_squared() > 0.0001:
		var target_rotation: float = atan2(direction.x, direction.y)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)


func _find_steering_direction(target_world_position: Vector3) -> Vector2:
	var current_xz: Vector2 = Vector2(global_position.x, global_position.z)
	var target_xz: Vector2 = Vector2(target_world_position.x, target_world_position.z)
	var desired_direction: Vector2 = target_xz - current_xz
	if desired_direction.length_squared() <= 0.0001:
		return Vector2.ZERO

	desired_direction = desired_direction.normalized()
	if _is_direction_walkable(desired_direction, target_world_position):
		return desired_direction

	var angle_step_radians: float = deg_to_rad(maxf(avoidance_angle_step_degrees, 1.0))
	var max_angle_radians: float = deg_to_rad(maxf(avoidance_max_angle_degrees, avoidance_angle_step_degrees))
	var attempt_count: int = int(ceili(max_angle_radians / angle_step_radians))
	for attempt_index in range(1, attempt_count + 1):
		var angle_offset: float = angle_step_radians * float(attempt_index)
		var left_direction: Vector2 = desired_direction.rotated(angle_offset)
		if _is_direction_walkable(left_direction, target_world_position):
			return left_direction

		var right_direction: Vector2 = desired_direction.rotated(-angle_offset)
		if _is_direction_walkable(right_direction, target_world_position):
			return right_direction

	return Vector2.ZERO


func _is_direction_walkable(direction: Vector2, target_world_position: Vector3) -> bool:
	var current_xz: Vector2 = Vector2(global_position.x, global_position.z)
	var target_xz: Vector2 = Vector2(target_world_position.x, target_world_position.z)
	var distance_to_target: float = current_xz.distance_to(target_xz)
	var probe_distances: Array[float] = []
	probe_distances.append(minf(avoidance_probe_distance * 0.5, distance_to_target))
	probe_distances.append(minf(avoidance_probe_distance, distance_to_target))

	for probe_distance in probe_distances:
		if probe_distance <= 0.001:
			continue

		var probe_world_position: Vector3 = global_position + Vector3(direction.x * probe_distance, 0.0, direction.y * probe_distance)
		if not _is_walkable_world_position(probe_world_position):
			return false

	if distance_to_target <= avoidance_probe_distance:
		return _is_walkable_world_position(target_world_position)

	return true


func _is_walkable_world_position(world_position: Vector3) -> bool:
	if procedural_map == null or not procedural_map.has_method("is_world_position_walkable"):
		return true

	var walkable_variant: Variant = procedural_map.call("is_world_position_walkable", world_position, 4)
	if walkable_variant is bool:
		return bool(walkable_variant)

	return true


func _clear_move_target() -> void:
	_has_move_target = false
	_move_target = global_position


func _schedule_next_roam_decision() -> void:
	_roam_decision_timer = _rng.randf_range(roam_pause_duration_min, roam_pause_duration_max)


func _get_horizontal_distance_to(target_world_position: Vector3) -> float:
	var current_xz: Vector2 = Vector2(global_position.x, global_position.z)
	var target_xz: Vector2 = Vector2(target_world_position.x, target_world_position.z)
	return current_xz.distance_to(target_xz)