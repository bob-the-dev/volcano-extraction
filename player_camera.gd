extends Camera3D

@export var spring_arm: Node3D
@export var easing: float = 10.0

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


func _ready() -> void:
	_resolve_perimeter_fog_height_target()
	_ensure_perimeter_fog_ring()
	_update_perimeter_fog_ring()


func _process(delta: float) -> void:
	if spring_arm == null:
		_update_perimeter_fog_ring()
		return

	var weight: float = clamp(easing * delta, 0.0, 1.0)
	global_position = global_position.lerp(spring_arm.global_position, weight)
	_update_perimeter_fog_ring()


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

	var outer_radius: float = maxf(far - perimeter_fog_far_margin, 1.0)
	var inner_radius: float = maxf(outer_radius - perimeter_fog_band_width, 0.0)
	var anchor_y: float = global_position.y
	if _perimeter_fog_height_target != null:
		anchor_y = _perimeter_fog_height_target.global_position.y

	var fog_center_y: float = lerpf(anchor_y, global_position.y, perimeter_fog_height_anchor_blend)
	var vertical_fade_start: float = maxf((perimeter_fog_height * 0.5) - 3.0, 0.0)
	var vertical_fade_end: float = perimeter_fog_height * 0.5
	var ring_mesh: CylinderMesh = _perimeter_fog_ring.mesh as CylinderMesh
	if ring_mesh != null:
		ring_mesh.top_radius = outer_radius
		ring_mesh.bottom_radius = outer_radius
		ring_mesh.height = perimeter_fog_height

	_perimeter_fog_ring.visible = true
	_perimeter_fog_ring.global_position = Vector3(global_position.x, fog_center_y, global_position.z)
	_perimeter_fog_ring.rotation = Vector3.ZERO
	_perimeter_fog_ring.extra_cull_margin = outer_radius + perimeter_fog_height
	_perimeter_fog_material.render_priority = perimeter_fog_render_priority

	_perimeter_fog_material.set_shader_parameter("fog_color", perimeter_fog_color)
	_perimeter_fog_material.set_shader_parameter("inner_radius", inner_radius)
	_perimeter_fog_material.set_shader_parameter("outer_radius", outer_radius)
	_perimeter_fog_material.set_shader_parameter("density", perimeter_fog_density)
	_perimeter_fog_material.set_shader_parameter("vertical_fade_start", vertical_fade_start)
	_perimeter_fog_material.set_shader_parameter("vertical_fade_end", vertical_fade_end)
