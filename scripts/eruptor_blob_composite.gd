extends Control

const BLOB_COMPOSITE_SHADER: Shader = preload("res://shaders/eruptor_blob_composite.gdshader")

@export_group("Composite")
@export var composite_enabled: bool = true
@export_range(1, 20, 1) var blob_render_layer: int = 2
@export_range(0.25, 1.0, 0.05) var viewport_scale: float = 0.5
@export_enum("Composite", "Raw Source") var debug_view_mode: int = 0
@export var show_debug_status: bool = false

@export_group("Blob Look")
@export_range(0.0, 12.0, 0.1) var blur_radius: float = 3.6
@export_range(0.0, 1.0, 0.01) var merge_threshold: float = 0.22
@export_range(0.001, 0.5, 0.001) var edge_softness: float = 0.09
@export_range(0.0, 2.0, 0.01) var blob_opacity: float = 0.95
@export var source_key_color: Color = Color(1.0, 0.0, 1.0, 1.0)
@export var deep_color: Color = Color(0.22, 0.02, 0.01, 1.0)
@export var hot_color: Color = Color(1.0, 0.45, 0.11, 1.0)
@export var rim_color: Color = Color(1.0, 0.86, 0.48, 1.0)
@export_range(0.0, 6.0, 0.01) var glow_strength: float = 1.35
@export_range(0.0, 1.0, 0.01) var noise_strength: float = 0.18
@export_range(0.1, 32.0, 0.1) var noise_scale: float = 9.0

var _blob_viewport: SubViewport = null
var _blob_camera: Camera3D = null
var _display_rect: TextureRect = null
var _debug_label: Label = null
var _blob_material: ShaderMaterial = null
var _blob_source_material: StandardMaterial3D = null
var _source_camera: Camera3D = null
var _last_viewport_size: Vector2i = Vector2i.ZERO
var _last_debug_signature: String = ""
var _did_log_ready: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_blob_viewport()
	_apply_shader_settings()
	_update_layout()
	if not _did_log_ready:
		_did_log_ready = true
		print("[Eruptor HUD] _ready path=", get_path())


func _process(_delta: float) -> void:
	visible = composite_enabled
	if not composite_enabled:
		return

	_apply_shader_settings()
	_update_layout()
	_resolve_source_camera()
	_ensure_blob_source_material_on_eruptors()
	_sync_blob_world()
	_sync_blob_camera()
	_exclude_blob_layer_from_source_camera()
	_update_debug_presentation()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_layout()


func _build_blob_viewport() -> void:
	_blob_viewport = SubViewport.new()
	_blob_viewport.name = "EruptorBlobViewport"
	_blob_viewport.transparent_bg = true
	_blob_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_blob_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(_blob_viewport)

	_blob_camera = Camera3D.new()
	_blob_camera.name = "EruptorBlobCamera"
	_blob_camera.current = true
	_blob_viewport.add_child(_blob_camera)
	_configure_blob_camera_layers()

	_display_rect = TextureRect.new()
	_display_rect.name = "EruptorBlobDisplay"
	_display_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_display_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_display_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_display_rect.texture = _blob_viewport.get_texture()
	add_child(_display_rect)

	_debug_label = Label.new()
	_debug_label.name = "EruptorBlobDebugLabel"
	_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_debug_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_debug_label.position = Vector2(16.0, 16.0)
	_debug_label.size = Vector2(520.0, 120.0)
	_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_debug_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.78, 1.0))
	_debug_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	_debug_label.add_theme_constant_override("shadow_offset_x", 2)
	_debug_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_debug_label)

	_blob_material = ShaderMaterial.new()
	_blob_material.shader = BLOB_COMPOSITE_SHADER
	_display_rect.material = _blob_material
	_blob_source_material = _build_blob_source_material()
	_sync_blob_shader_texture()


func _configure_blob_camera_layers() -> void:
	if _blob_camera == null:
		return

	for layer_number in range(1, 21):
		_blob_camera.set_cull_mask_value(layer_number, true)


func _apply_shader_settings() -> void:
	if _blob_material == null:
		return

	_blob_material.set_shader_parameter("blur_radius", blur_radius)
	_blob_material.set_shader_parameter("merge_threshold", merge_threshold)
	_blob_material.set_shader_parameter("edge_softness", edge_softness)
	_blob_material.set_shader_parameter("blob_opacity", blob_opacity)
	_blob_material.set_shader_parameter("source_key_color", source_key_color)
	_blob_material.set_shader_parameter("deep_color", deep_color)
	_blob_material.set_shader_parameter("hot_color", hot_color)
	_blob_material.set_shader_parameter("rim_color", rim_color)
	_blob_material.set_shader_parameter("glow_strength", glow_strength)
	_blob_material.set_shader_parameter("noise_strength", noise_strength)
	_blob_material.set_shader_parameter("noise_scale", noise_scale)
	_sync_blob_shader_texture()


func _update_layout() -> void:
	if _blob_viewport == null or _display_rect == null:
		return

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_display_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root_rect_size: Vector2 = get_viewport_rect().size
	var scaled_width: int = maxi(int(round(root_rect_size.x * viewport_scale)), 1)
	var scaled_height: int = maxi(int(round(root_rect_size.y * viewport_scale)), 1)
	var target_size: Vector2i = Vector2i(scaled_width, scaled_height)
	if target_size == _last_viewport_size:
		return

	_last_viewport_size = target_size
	_blob_viewport.size = target_size
	_sync_blob_shader_texture()
	if _debug_label != null:
		_debug_label.size = Vector2(maxf(root_rect_size.x - 32.0, 240.0), 120.0)


func _resolve_source_camera() -> void:
	var viewport_camera: Camera3D = get_viewport().get_camera_3d()
	if viewport_camera == null or viewport_camera == _blob_camera:
		_source_camera = null
		if _display_rect != null:
			_display_rect.visible = false
		return

	_source_camera = viewport_camera
	if _display_rect != null:
		_display_rect.visible = true


func _sync_blob_world() -> void:
	if _blob_viewport == null:
		return

	var main_world: World3D = get_viewport().world_3d
	if main_world != null and _blob_viewport.world_3d != main_world:
		_blob_viewport.world_3d = main_world


func _sync_blob_camera() -> void:
	if _source_camera == null or _blob_camera == null:
		return

	_configure_blob_camera_layers()
	_blob_camera.global_transform = _source_camera.global_transform
	_blob_camera.projection = _source_camera.projection
	_blob_camera.keep_aspect = _source_camera.keep_aspect
	_blob_camera.near = _source_camera.near
	_blob_camera.far = _source_camera.far
	_blob_camera.fov = _source_camera.fov
	_blob_camera.size = _source_camera.size
	_blob_camera.h_offset = _source_camera.h_offset
	_blob_camera.v_offset = _source_camera.v_offset
	_blob_camera.frustum_offset = _source_camera.frustum_offset


func _exclude_blob_layer_from_source_camera() -> void:
	if _source_camera == null:
		return

	_source_camera.set_cull_mask_value(blob_render_layer, false)


func _sync_blob_shader_texture() -> void:
	if _blob_material == null or _blob_viewport == null:
		return

	_blob_material.set_shader_parameter("source_texture", _blob_viewport.get_texture())
	var viewport_size: Vector2i = _blob_viewport.size
	var texel_size: Vector2 = Vector2(
		1.0 / maxf(float(viewport_size.x), 1.0),
		1.0 / maxf(float(viewport_size.y), 1.0)
	)
	_blob_material.set_shader_parameter("source_texel_size", texel_size)


func _build_blob_source_material() -> StandardMaterial3D:
	var source_material: StandardMaterial3D = StandardMaterial3D.new()
	source_material.albedo_color = source_key_color
	source_material.emission_enabled = true
	source_material.emission = source_key_color
	source_material.emission_energy_multiplier = 1.0
	source_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	source_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	source_material.no_depth_test = false
	return source_material


func _ensure_blob_source_material_on_eruptors() -> void:
	if _blob_source_material == null:
		return

	var eruptor_nodes: Array = get_tree().get_nodes_in_group("eruptor_scene")
	for eruptor_variant: Variant in eruptor_nodes:
		if not (eruptor_variant is Node):
			continue

		var eruptor_node: Node = eruptor_variant as Node
		var emitter: GPUParticles3D = eruptor_node.get_node_or_null("Lava Emitter") as GPUParticles3D
		if emitter == null:
			continue

		var emitter_draw_mesh: Mesh = emitter.draw_pass_1
		if not (emitter_draw_mesh is PrimitiveMesh):
			continue

		var primitive_mesh: PrimitiveMesh = emitter_draw_mesh as PrimitiveMesh
		if primitive_mesh.material == _blob_source_material:
			continue

		var mesh_copy: PrimitiveMesh = primitive_mesh.duplicate() as PrimitiveMesh
		if mesh_copy == null:
			continue

		mesh_copy.material = _blob_source_material
		emitter.draw_pass_1 = mesh_copy


func _update_debug_presentation() -> void:
	if _display_rect == null:
		return

	if debug_view_mode == 0:
		_display_rect.material = _blob_material
	else:
		_display_rect.material = null

	if _debug_label == null:
		return

	_debug_label.visible = show_debug_status
	if not show_debug_status:
		return

	var eruptor_count: int = get_tree().get_nodes_in_group("eruptor_scene").size()
	var source_camera_name: String = "none"
	if _source_camera != null:
		source_camera_name = _source_camera.name

	var viewport_size: Vector2i = Vector2i.ZERO
	if _blob_viewport != null:
		viewport_size = _blob_viewport.size

	var display_mode_name: String = "Composite"
	if debug_view_mode == 1:
		display_mode_name = "Raw Source"

	var status_lines: PackedStringArray = PackedStringArray([
		"Eruptor HUD Debug",
		"mode=%s visible=%s display=%s" % [display_mode_name, str(visible), str(_display_rect.visible)],
		"source_camera=%s eruptors=%d viewport=%dx%d" % [source_camera_name, eruptor_count, viewport_size.x, viewport_size.y],
		"layer=%d source_texture=%s" % [blob_render_layer, str(_blob_viewport != null and _blob_viewport.get_texture() != null)]
	])
	var status_text: String = "\n".join(status_lines)
	_debug_label.text = status_text

	if status_text == _last_debug_signature:
		return

	_last_debug_signature = status_text
	print("[Eruptor HUD] ", status_text.replace("\n", " | "))