extends Camera3D

@export var spring_arm: Node3D
@export var easing: float = 10.0
@export_range(0.0, 1.0, 0.01) var position_ease_blend: float = 0.35

@export_group("Screen Shake")
@export_range(0.0, 4.0, 0.01) var screenshake_strength: float = 0.0
@export_range(0.0, 4.0, 0.01) var lava_screenshake_strength: float = 0.45
@export_range(0.0, 1.0, 0.005) var screenshake_translation_amplitude: float = 0.12
@export_range(0.0, 10.0, 0.05) var screenshake_roll_amplitude_degrees: float = 0.9
@export_range(0.1, 40.0, 0.1) var screenshake_speed: float = 12.0
@export_range(0.1, 20.0, 0.1) var screenshake_response: float = 8.0

@export_group("Perimeter Fog")
@export var enable_perimeter_fog: bool = true
@export_range(0.1, 8.0, 0.1) var perimeter_fog_far_margin: float = 1.25
@export_range(1.0, 12.0, 0.1) var perimeter_fog_band_width: float = 6.0
@export_range(2.0, 40.0, 0.1) var perimeter_fog_height: float = 18.0
@export_range(0.0, 1.0, 0.01) var perimeter_fog_density: float = 0.55
@export_range(0.0, 1.0, 0.01) var perimeter_fog_height_anchor_blend: float = 0.42
@export_range(-128, 127, 1) var perimeter_fog_render_priority: int = 10
@export var perimeter_fog_color: Color = Color(0.48, 0.5, 0.53, 0.95)

var _perimeter_fog_shader: Shader = preload("res://shaders/perimeter_fog_ring.gdshader")
var _perimeter_fog_ring: MeshInstance3D = null
var _perimeter_fog_material: ShaderMaterial = null
var _perimeter_fog_height_target: Node3D = null
var _procedural_map: Node = null
var _smoothed_global_position: Vector3 = Vector3.ZERO
var _base_rotation: Vector3 = Vector3.ZERO
var _screenshake_time: float = 0.0
var _current_screenshake_strength: float = 0.0


func _ready() -> void:
	_resolve_spring_arm()
	_smoothed_global_position = global_position
	_base_rotation = rotation
	_resolve_perimeter_fog_height_target()
	_resolve_procedural_map()
	_ensure_perimeter_fog_ring()
	_update_perimeter_fog_ring()


func _process(delta: float) -> void:
	if spring_arm == null or not is_instance_valid(spring_arm):
		_resolve_spring_arm()

	if spring_arm == null:
		rotation = _base_rotation
		_update_perimeter_fog_ring()
		return

	var linear_weight: float = clamp(easing * delta, 0.0, 1.0)
	var smooth_weight: float = linear_weight * linear_weight * (3.0 - (2.0 * linear_weight))
	var follow_weight: float = lerpf(linear_weight, smooth_weight, position_ease_blend)
	_smoothed_global_position = _smoothed_global_position.lerp(spring_arm.global_position, follow_weight)

	var target_screenshake_strength: float = screenshake_strength + _get_lava_screenshake_strength()
	var screenshake_weight: float = clamp(screenshake_response * delta, 0.0, 1.0)
	_current_screenshake_strength = lerpf(_current_screenshake_strength, target_screenshake_strength, screenshake_weight)
	_screenshake_time += delta * screenshake_speed

	var screenshake_offset: Vector3 = _get_screenshake_offset()
	global_position = _smoothed_global_position + screenshake_offset
	rotation = Vector3(
		_base_rotation.x,
		_base_rotation.y,
		_base_rotation.z + deg_to_rad(_get_screenshake_roll_degrees())
	)
	_update_perimeter_fog_ring()


func _resolve_spring_arm() -> void:
	if spring_arm != null and is_instance_valid(spring_arm):
		return

	var parent_node: Node = get_parent()
	if parent_node == null:
		return

	var spring_position: Node3D = parent_node.get_node_or_null("SpringArm3D/SpringPosition") as Node3D
	if spring_position != null:
		spring_arm = spring_position
		return

	var spring_arm_node: Node3D = parent_node.get_node_or_null("SpringArm3D") as Node3D
	if spring_arm_node != null:
		spring_arm = spring_arm_node


func _resolve_procedural_map() -> void:
	var procedural_maps: Array = get_tree().get_nodes_in_group("procedural_map")
	if not procedural_maps.is_empty():
		_procedural_map = procedural_maps[0]


func _get_lava_screenshake_strength() -> float:
	if is_zero_approx(lava_screenshake_strength):
		return 0.0

	if _procedural_map == null or not is_instance_valid(_procedural_map):
		_resolve_procedural_map()
		if _procedural_map == null:
			return 0.0

	if _procedural_map.has_method("get_lava_height_normalized"):
		var lava_height_normalized: float = float(_procedural_map.call("get_lava_height_normalized"))
		return lava_height_normalized * lava_screenshake_strength

	return 0.0


func _get_screenshake_offset() -> Vector3:
	if is_zero_approx(_current_screenshake_strength) or is_zero_approx(screenshake_translation_amplitude):
		return Vector3.ZERO

	var horizontal_noise: float = _sample_screenshake_noise(0.0)
	var vertical_noise: float = _sample_screenshake_noise(9.1)
	var horizontal_offset: float = horizontal_noise * screenshake_translation_amplitude * _current_screenshake_strength
	var vertical_offset: float = vertical_noise * screenshake_translation_amplitude * _current_screenshake_strength
	return (global_transform.basis.x * horizontal_offset) + (global_transform.basis.y * vertical_offset)


func _get_screenshake_roll_degrees() -> float:
	if is_zero_approx(_current_screenshake_strength) or is_zero_approx(screenshake_roll_amplitude_degrees):
		return 0.0

	return _sample_screenshake_noise(17.3) * screenshake_roll_amplitude_degrees * _current_screenshake_strength


func _sample_screenshake_noise(phase_offset: float) -> float:
	var primary_wave: float = sin(_screenshake_time + phase_offset)
	var secondary_wave: float = sin((_screenshake_time * 1.73) + (phase_offset * 1.37))
	var tertiary_wave: float = cos((_screenshake_time * 2.41) - (phase_offset * 0.73))
	return (primary_wave * 0.6) + (secondary_wave * 0.3) + (tertiary_wave * 0.1)


func _resolve_perimeter_fog_height_target() -> void:
	var parent_node: Node = get_parent()
	if parent_node == null:
		return

	var grandparent_node: Node = parent_node.get_parent()
	if grandparent_node is Node3D:
		_perimeter_fog_height_target = grandparent_node as Node3D


func _ensure_perimeter_fog_ring() -> void:
	if not enable_perimeter_fog:
		if _perimeter_fog_ring != null:
			_perimeter_fog_ring.visible = false
		return

	if _perimeter_fog_ring != null:
		_perimeter_fog_ring.visible = true
		return

	var cylinder_mesh: CylinderMesh = CylinderMesh.new()
	cylinder_mesh.top_radius = 1.0
	cylinder_mesh.bottom_radius = 1.0
	cylinder_mesh.height = 1.0
	cylinder_mesh.radial_segments = 48
	cylinder_mesh.rings = 4

	_perimeter_fog_material = ShaderMaterial.new()
	_perimeter_fog_material.shader = _perimeter_fog_shader
	_perimeter_fog_material.render_priority = perimeter_fog_render_priority

	_perimeter_fog_ring = MeshInstance3D.new()
	_perimeter_fog_ring.name = "PerimeterFogRing"
	_perimeter_fog_ring.top_level = true
	_perimeter_fog_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_perimeter_fog_ring.mesh = cylinder_mesh
	_perimeter_fog_ring.material_override = _perimeter_fog_material
	add_child(_perimeter_fog_ring)


func _update_perimeter_fog_ring() -> void:
	if not enable_perimeter_fog or not current:
		if _perimeter_fog_ring != null:
			_perimeter_fog_ring.visible = false
		return

	_ensure_perimeter_fog_ring()
	if _perimeter_fog_ring == null or _perimeter_fog_material == null:
		return

	if _perimeter_fog_height_target == null or not is_instance_valid(_perimeter_fog_height_target):
		_resolve_perimeter_fog_height_target()

	var fog_anchor_position: Vector3 = _smoothed_global_position
	var outer_radius: float = maxf(far - perimeter_fog_far_margin, 1.0)
	var inner_radius: float = maxf(outer_radius - perimeter_fog_band_width, 0.0)
	var anchor_y: float = fog_anchor_position.y
	if _perimeter_fog_height_target != null:
		anchor_y = _perimeter_fog_height_target.global_position.y

	var fog_center_y: float = lerpf(anchor_y, fog_anchor_position.y, perimeter_fog_height_anchor_blend)
	var vertical_fade_start: float = maxf((perimeter_fog_height * 0.5) - 3.0, 0.0)
	var vertical_fade_end: float = perimeter_fog_height * 0.5
	var ring_mesh: CylinderMesh = _perimeter_fog_ring.mesh as CylinderMesh
	if ring_mesh != null:
		ring_mesh.top_radius = outer_radius
		ring_mesh.bottom_radius = outer_radius
		ring_mesh.height = perimeter_fog_height

	_perimeter_fog_ring.visible = true
	_perimeter_fog_ring.global_position = Vector3(fog_anchor_position.x, fog_center_y, fog_anchor_position.z)
	_perimeter_fog_ring.rotation = Vector3.ZERO
	_perimeter_fog_ring.extra_cull_margin = outer_radius + perimeter_fog_height
	_perimeter_fog_material.render_priority = perimeter_fog_render_priority

	_perimeter_fog_material.set_shader_parameter("fog_color", perimeter_fog_color)
	_perimeter_fog_material.set_shader_parameter("inner_radius", inner_radius)
	_perimeter_fog_material.set_shader_parameter("outer_radius", outer_radius)
	_perimeter_fog_material.set_shader_parameter("density", perimeter_fog_density)
	_perimeter_fog_material.set_shader_parameter("vertical_fade_start", vertical_fade_start)
	_perimeter_fog_material.set_shader_parameter("vertical_fade_end", vertical_fade_end)
