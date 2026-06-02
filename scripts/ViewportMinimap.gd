extends Control

const INVALID_GRID_POSITION: Vector2i = Vector2i(-2147483648, -2147483648)
const REVEAL_MASK_SHADER: Shader = preload("res://shaders/minimap_reveal_mask.gdshader")

@export_group("Layout")
@export var minimap_size: int = 200
@export var minimap_width_override: int = 0
@export var minimap_height_override: int = 0
@export var border_margin: int = 4
@export_range(0.0, 32.0, 0.1) var camera_padding_world: float = 4.0
@export_range(8.0, 256.0, 0.1) var minimap_camera_height: float = 52.0

@export_group("Reveal")
@export_range(-1, 12, 1) var reveal_radius_cells_override: int = -1
@export_range(0.001, 0.5, 0.001) var revealed_edge_softness: float = 0.14
@export_range(0.0, 4.0, 0.05) var player_reveal_softness_cells: float = 1.0

@export_group("Terrain")
@export var terrain_albedo_color: Color = Color(0.05, 0.11, 0.22, 1.0)

@export_group("Lava")
@export var lava_albedo_color: Color = Color(0.82, 0.14, 0.06, 0.94)

@export_group("Player Indicator")
@export var player_indicator_color: Color = Color(0.98, 0.97, 0.92, 1.0)
@export var player_heading_color: Color = Color(1.0, 0.76, 0.28, 1.0)
@export_range(2.0, 24.0, 0.1) var player_marker_radius: float = 5.0
@export_range(4.0, 48.0, 0.1) var player_heading_length: float = 18.0
@export_range(1.0, 8.0, 0.1) var player_heading_width: float = 2.5
@export_range(2.0, 18.0, 0.1) var player_arrow_size: float = 8.0

var _viewport: SubViewport = null
var _display_rect: TextureRect = null
var _player_indicator_root: Node2D = null
var _player_heading_line: Line2D = null
var _player_marker: Polygon2D = null
var _player_arrow: Polygon2D = null
var _world_root: Node3D = null
var _world_environment: WorldEnvironment = null
var _camera: Camera3D = null
var _directional_light: DirectionalLight3D = null
var _terrain_mesh_instance: MeshInstance3D = null
var _lava_mesh_instance: MeshInstance3D = null
var _terrain_material: StandardMaterial3D = null
var _lava_material: StandardMaterial3D = null
var _mask_material: ShaderMaterial = null
var _mask_image: Image = null
var _mask_texture: ImageTexture = null
var _procedural_map: Node3D = null
var _player: Node3D = null
var _terrain_world_rect: Rect2 = Rect2(Vector2.ZERO, Vector2.ZERO)
var _terrain_grid_rect: Rect2i = Rect2i(0, 0, 0, 0)
var _focus_world_rect: Rect2 = Rect2(Vector2.ZERO, Vector2.ZERO)
var _cell_size: float = 1.0
var _last_explored_cell_count: int = -1
var _last_applied_reveal_radius_override: int = -1000000
var _is_updating_layout: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_build_minimap_viewport()
	_update_layout()
	_resolve_procedural_map()
	call_deferred("_refresh_from_procedural_map")


func _process(_delta: float) -> void:
	if _procedural_map == null or not is_instance_valid(_procedural_map):
		_resolve_procedural_map()
		return

	if _terrain_world_rect.size.x <= 0.0 or _terrain_world_rect.size.y <= 0.0 or _terrain_mesh_instance.mesh == null:
		_refresh_from_procedural_map()
		return

	_resolve_player()
	_apply_reveal_radius_override()
	_sync_live_lava_mesh()
	_sync_materials()
	_rebuild_exploration_mask(false)
	_update_mask_material_state()
	_update_player_indicator()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_layout()


func _build_minimap_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "MinimapViewport"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(_viewport)

	_display_rect = TextureRect.new()
	_display_rect.name = "MinimapDisplay"
	_display_rect.texture = _viewport.get_texture()
	_display_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_display_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_display_rect)

	_world_root = Node3D.new()
	_world_root.name = "MinimapWorldRoot"
	_viewport.add_child(_world_root)

	_world_environment = WorldEnvironment.new()
	_world_environment.name = "MinimapWorldEnvironment"
	_world_environment.environment = _build_minimap_environment()
	_world_root.add_child(_world_environment)

	_directional_light = DirectionalLight3D.new()
	_directional_light.name = "MinimapLight"
	_directional_light.light_energy = 0.8
	_directional_light.rotation_degrees = Vector3(-65.0, 25.0, 0.0)
	_directional_light.shadow_enabled = false
	_world_root.add_child(_directional_light)

	_camera = Camera3D.new()
	_camera.name = "MinimapCamera"
	_camera.current = true
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.1
	_camera.far = 2048.0
	_world_root.add_child(_camera)

	_terrain_mesh_instance = MeshInstance3D.new()
	_terrain_mesh_instance.name = "MinimapTerrain"
	_terrain_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_terrain_mesh_instance.extra_cull_margin = 1000.0
	_world_root.add_child(_terrain_mesh_instance)

	_lava_mesh_instance = MeshInstance3D.new()
	_lava_mesh_instance.name = "MinimapLava"
	_lava_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lava_mesh_instance.extra_cull_margin = 1000.0
	_world_root.add_child(_lava_mesh_instance)

	_build_player_indicator_overlay()

	_sync_materials()
	_configure_mask_material()


func _update_layout() -> void:
	if _is_updating_layout:
		return

	_is_updating_layout = true
	var minimap_dimensions: Vector2i = _get_minimap_dimensions()
	var target_size: Vector2 = Vector2(float(minimap_dimensions.x), float(minimap_dimensions.y))
	anchors_preset = Control.PRESET_TOP_RIGHT
	offset_left = -target_size.x - float(border_margin)
	offset_top = float(border_margin)
	custom_minimum_size = target_size
	if size != target_size:
		size = target_size

	if _viewport != null:
		_viewport.size = minimap_dimensions

	if _display_rect != null:
		_display_rect.position = Vector2.ZERO
		_display_rect.custom_minimum_size = target_size
		if _display_rect.size != target_size:
			_display_rect.size = target_size

	_update_camera_from_focus_rect()
	_update_mask_material_state()
	_update_player_indicator()
	_is_updating_layout = false


func _resolve_procedural_map() -> void:
	if _procedural_map != null and is_instance_valid(_procedural_map):
		return

	var procedural_maps: Array = get_tree().get_nodes_in_group("procedural_map")
	if procedural_maps.is_empty():
		return

	var procedural_map_candidate: Variant = procedural_maps[0]
	if procedural_map_candidate is Node3D:
		_procedural_map = procedural_map_candidate

	if _procedural_map == null:
		return

	var regenerate_callable: Callable = Callable(self, "_on_map_regenerated")
	if _procedural_map.has_signal("map_regenerated") and not _procedural_map.is_connected("map_regenerated", regenerate_callable):
		_procedural_map.connect("map_regenerated", regenerate_callable)

	_apply_reveal_radius_override()
	_resolve_player()


func _resolve_player() -> void:
	if _player != null and is_instance_valid(_player):
		return

	if _procedural_map != null and is_instance_valid(_procedural_map) and _procedural_map.has_method("get_exploration_player"):
		var player_variant: Variant = _procedural_map.call("get_exploration_player")
		if player_variant is Node3D:
			_player = player_variant
			return

	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return

	var player_candidate: Variant = players[0]
	if player_candidate is Node3D:
		_player = player_candidate


func _on_map_regenerated() -> void:
	_last_explored_cell_count = -1
	call_deferred("_refresh_from_procedural_map")


func _refresh_from_procedural_map() -> void:
	if _procedural_map == null or not is_instance_valid(_procedural_map):
		return

	var render_data_variant: Variant = _procedural_map.call("get_minimap_render_data")
	if not (render_data_variant is Dictionary):
		return

	var render_data: Dictionary = render_data_variant
	if render_data.is_empty():
		return

	_apply_render_data(render_data)
	_rebuild_baked_terrain_mesh(render_data)
	_sync_live_lava_mesh(true)
	_sync_materials()
	_rebuild_exploration_mask(true)
	_update_mask_material_state()
	_update_player_indicator()


func _build_minimap_environment() -> Environment:
	var minimap_environment: Environment = Environment.new()
	minimap_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	minimap_environment.ambient_light_color = Color(1.0, 1.0, 1.0, 1.0)
	minimap_environment.ambient_light_energy = 1.35
	return minimap_environment


func _build_player_indicator_overlay() -> void:
	_player_indicator_root = Node2D.new()
	_player_indicator_root.name = "PlayerIndicatorOverlay"
	add_child(_player_indicator_root)

	_player_heading_line = Line2D.new()
	_player_heading_line.name = "PlayerHeading"
	_player_heading_line.closed = false
	_player_heading_line.antialiased = true
	_player_indicator_root.add_child(_player_heading_line)

	_player_marker = Polygon2D.new()
	_player_marker.name = "PlayerMarker"
	_player_indicator_root.add_child(_player_marker)

	_player_arrow = Polygon2D.new()
	_player_arrow.name = "PlayerArrow"
	_player_indicator_root.add_child(_player_arrow)

	_update_player_indicator_visuals()


func _update_player_indicator_visuals() -> void:
	if _player_indicator_root == null:
		return

	if _player_heading_line != null:
		var heading_points: PackedVector2Array = PackedVector2Array()
		heading_points.append(Vector2.ZERO)
		heading_points.append(Vector2(0.0, -player_heading_length))
		_player_heading_line.points = heading_points
		_player_heading_line.default_color = player_heading_color
		_player_heading_line.width = player_heading_width

	if _player_marker != null:
		var marker_polygon: PackedVector2Array = PackedVector2Array()
		marker_polygon.append(Vector2(0.0, -player_marker_radius))
		marker_polygon.append(Vector2(player_marker_radius, 0.0))
		marker_polygon.append(Vector2(0.0, player_marker_radius))
		marker_polygon.append(Vector2(-player_marker_radius, 0.0))
		_player_marker.polygon = marker_polygon
		_player_marker.color = player_indicator_color

	if _player_arrow != null:
		var arrow_polygon: PackedVector2Array = PackedVector2Array()
		var arrow_tip_y: float = -player_heading_length - player_arrow_size
		var arrow_base_y: float = -player_heading_length + (player_arrow_size * 0.2)
		var arrow_half_width: float = player_arrow_size * 0.65
		arrow_polygon.append(Vector2(0.0, arrow_tip_y))
		arrow_polygon.append(Vector2(arrow_half_width, arrow_base_y))
		arrow_polygon.append(Vector2(-arrow_half_width, arrow_base_y))
		_player_arrow.polygon = arrow_polygon
		_player_arrow.color = player_heading_color


func _update_player_indicator() -> void:
	if _player_indicator_root == null:
		return

	_update_player_indicator_visuals()

	if _player == null or not is_instance_valid(_player):
		_player_indicator_root.visible = false
		return

	var player_uv: Vector2 = _world_xz_to_focus_uv(Vector2(_player.global_position.x, _player.global_position.z))
	if player_uv.x < 0.0 or player_uv.x > 1.0 or player_uv.y < 0.0 or player_uv.y > 1.0:
		_player_indicator_root.visible = false
		return

	var minimap_dimensions: Vector2i = _get_minimap_dimensions()
	var player_screen_position: Vector2 = Vector2(
		player_uv.x * float(minimap_dimensions.x),
		player_uv.y * float(minimap_dimensions.y)
	)
	var forward_vector: Vector3 = -_player.global_basis.z
	var forward_flat: Vector2 = Vector2(forward_vector.x, forward_vector.z)
	if forward_flat.length_squared() <= 0.0001:
		forward_flat = Vector2.UP
	else:
		forward_flat = forward_flat.normalized()

	_player_indicator_root.position = player_screen_position
	_player_indicator_root.rotation = forward_flat.angle() - (PI * 0.5)
	_player_indicator_root.visible = true


func _apply_render_data(render_data: Dictionary) -> void:
	_terrain_world_rect = _variant_to_rect2(render_data.get("terrain_world_rect", Rect2(Vector2.ZERO, Vector2.ZERO)))
	_terrain_grid_rect = _variant_to_rect2i(render_data.get("terrain_grid_rect", Rect2i(0, 0, 0, 0)))
	_focus_world_rect = _build_focus_world_rect(render_data)
	_cell_size = maxf(float(render_data.get("cell_size", 1.0)), 0.001)
	_update_camera_from_focus_rect()


func _rebuild_baked_terrain_mesh(render_data: Dictionary) -> void:
	var heightmap_texture: Texture2D = _variant_to_texture2d(render_data.get("heightmap_texture", null))
	if heightmap_texture == null:
		_terrain_mesh_instance.mesh = null
		_terrain_mesh_instance.visible = false
		return

	var wall_heightmap_texture: Texture2D = _variant_to_texture2d(render_data.get("wall_heightmap_texture", null))
	var heightmap_image: Image = _get_texture_image(heightmap_texture)
	var wall_heightmap_image: Image = _get_texture_image(wall_heightmap_texture)
	if heightmap_image == null:
		_terrain_mesh_instance.mesh = null
		_terrain_mesh_instance.visible = false
		return

	var subdivisions_width: int = clampi(
		_terrain_grid_rect.size.x * int(render_data.get("mesh_subdivisions", 1)),
		1,
		maxi(int(render_data.get("max_mesh_subdivisions_per_axis", 256)), 1)
	)
	var subdivisions_depth: int = clampi(
		_terrain_grid_rect.size.y * int(render_data.get("mesh_subdivisions", 1)),
		1,
		maxi(int(render_data.get("max_mesh_subdivisions_per_axis", 256)), 1)
	)

	var baked_mesh: ArrayMesh = _build_baked_terrain_mesh(
		heightmap_image,
		wall_heightmap_image,
		_terrain_world_rect.size,
		float(render_data.get("terrain_amplitude", 0.0)),
		float(render_data.get("wall_amplitude", 0.0)),
		subdivisions_width,
		subdivisions_depth
	)
	_terrain_mesh_instance.mesh = baked_mesh
	_terrain_mesh_instance.position = Vector3(
		_terrain_world_rect.position.x + (_terrain_world_rect.size.x * 0.5),
		float(render_data.get("terrain_base_y", 0.0)),
		_terrain_world_rect.position.y + (_terrain_world_rect.size.y * 0.5)
	)
	_terrain_mesh_instance.visible = baked_mesh != null


func _build_baked_terrain_mesh(
		heightmap_image: Image,
		wall_heightmap_image: Image,
		terrain_size: Vector2,
		terrain_amplitude: float,
		wall_amplitude: float,
		subdivisions_width: int,
		subdivisions_depth: int
	) -> ArrayMesh:
	var vertex_count_width: int = subdivisions_width + 1
	var vertex_count_depth: int = subdivisions_depth + 1
	var total_vertex_count: int = vertex_count_width * vertex_count_depth
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var heights: PackedFloat32Array = PackedFloat32Array()
	vertices.resize(total_vertex_count)
	normals.resize(total_vertex_count)
	uvs.resize(total_vertex_count)
	heights.resize(total_vertex_count)

	var half_width: float = terrain_size.x * 0.5
	var half_depth: float = terrain_size.y * 0.5
	var step_width: float = terrain_size.x / float(subdivisions_width)
	var step_depth: float = terrain_size.y / float(subdivisions_depth)

	for depth_index in range(vertex_count_depth):
		var depth_ratio: float = float(depth_index) / float(subdivisions_depth)
		for width_index in range(vertex_count_width):
			var width_ratio: float = float(width_index) / float(subdivisions_width)
			var uv: Vector2 = Vector2(width_ratio, depth_ratio)
			var vertex_index: int = (depth_index * vertex_count_width) + width_index
			var sampled_height: float = _sample_combined_height(heightmap_image, wall_heightmap_image, uv, terrain_amplitude, wall_amplitude)
			heights[vertex_index] = sampled_height
			vertices[vertex_index] = Vector3(
				lerpf(-half_width, half_width, width_ratio),
				sampled_height,
				lerpf(-half_depth, half_depth, depth_ratio)
			)
			uvs[vertex_index] = uv

	for depth_index in range(vertex_count_depth):
		for width_index in range(vertex_count_width):
			var vertex_index: int = (depth_index * vertex_count_width) + width_index
			var left_index: int = (depth_index * vertex_count_width) + maxi(width_index - 1, 0)
			var right_index: int = (depth_index * vertex_count_width) + mini(width_index + 1, vertex_count_width - 1)
			var down_index: int = (maxi(depth_index - 1, 0) * vertex_count_width) + width_index
			var up_index: int = (mini(depth_index + 1, vertex_count_depth - 1) * vertex_count_width) + width_index
			var left_height: float = heights[left_index]
			var right_height: float = heights[right_index]
			var down_height: float = heights[down_index]
			var up_height: float = heights[up_index]
			normals[vertex_index] = Vector3(left_height - right_height, step_width + step_depth, down_height - up_height).normalized()

	var indices: PackedInt32Array = PackedInt32Array()
	for depth_index in range(subdivisions_depth):
		for width_index in range(subdivisions_width):
			var top_left_index: int = (depth_index * vertex_count_width) + width_index
			var top_right_index: int = top_left_index + 1
			var bottom_left_index: int = top_left_index + vertex_count_width
			var bottom_right_index: int = bottom_left_index + 1
			indices.append(top_left_index)
			indices.append(bottom_left_index)
			indices.append(bottom_right_index)
			indices.append(top_left_index)
			indices.append(bottom_right_index)
			indices.append(top_right_index)

	var mesh_arrays: Array = []
	mesh_arrays.resize(Mesh.ARRAY_MAX)
	mesh_arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh_arrays[Mesh.ARRAY_NORMAL] = normals
	mesh_arrays[Mesh.ARRAY_TEX_UV] = uvs
	mesh_arrays[Mesh.ARRAY_INDEX] = indices

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
	return mesh


func _sample_combined_height(heightmap_image: Image, wall_heightmap_image: Image, uv: Vector2, terrain_amplitude: float, wall_amplitude: float) -> float:
	var terrain_height: float = _sample_image_red_linear(heightmap_image, uv) * terrain_amplitude
	var wall_height: float = 0.0
	if wall_heightmap_image != null:
		wall_height = _sample_image_red_linear(wall_heightmap_image, uv) * wall_amplitude
	return terrain_height + wall_height


func _sample_image_red_linear(image: Image, uv: Vector2) -> float:
	if image == null:
		return 0.0
	if image.get_width() <= 0 or image.get_height() <= 0:
		return 0.0

	var clamped_uv: Vector2 = Vector2(clampf(uv.x, 0.0, 1.0), clampf(uv.y, 0.0, 1.0))
	var max_x_index: int = maxi(image.get_width() - 1, 0)
	var max_y_index: int = maxi(image.get_height() - 1, 0)
	var sample_x: float = clamped_uv.x * float(max_x_index)
	var sample_y: float = clamped_uv.y * float(max_y_index)
	var x0: int = int(floor(sample_x))
	var y0: int = int(floor(sample_y))
	var x1: int = mini(x0 + 1, max_x_index)
	var y1: int = mini(y0 + 1, max_y_index)
	var blend_x: float = sample_x - float(x0)
	var blend_y: float = sample_y - float(y0)

	var top_left: float = image.get_pixel(x0, y0).r
	var top_right: float = image.get_pixel(x1, y0).r
	var bottom_left: float = image.get_pixel(x0, y1).r
	var bottom_right: float = image.get_pixel(x1, y1).r
	var top_blend: float = lerpf(top_left, top_right, blend_x)
	var bottom_blend: float = lerpf(bottom_left, bottom_right, blend_x)
	return lerpf(top_blend, bottom_blend, blend_y)


func _get_texture_image(texture: Texture2D) -> Image:
	if texture == null:
		return null

	var image: Image = texture.get_image()
	if image == null:
		return null

	if image.is_compressed():
		var decompress_error: Error = image.decompress()
		if decompress_error != OK:
			return null

	return image


func _sync_live_lava_mesh(force_refresh: bool = false) -> void:
	if _procedural_map == null or not is_instance_valid(_procedural_map):
		return

	var lava_mesh_variant: Variant = _procedural_map.call("get_minimap_lava_mesh_instance")
	if not (lava_mesh_variant is MeshInstance3D):
		_lava_mesh_instance.mesh = null
		_lava_mesh_instance.visible = false
		return

	var source_lava_mesh: MeshInstance3D = lava_mesh_variant
	if source_lava_mesh == null or not is_instance_valid(source_lava_mesh) or source_lava_mesh.mesh == null or not source_lava_mesh.visible:
		_lava_mesh_instance.mesh = null
		_lava_mesh_instance.visible = false
		return

	if force_refresh or _lava_mesh_instance.mesh != source_lava_mesh.mesh:
		_lava_mesh_instance.mesh = source_lava_mesh.mesh

	_lava_mesh_instance.global_transform = source_lava_mesh.global_transform
	_lava_mesh_instance.visible = true


func _sync_materials() -> void:
	if _terrain_material == null:
		_terrain_material = StandardMaterial3D.new()
		_terrain_material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		_terrain_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_terrain_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_terrain_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_terrain_material.roughness = 1.0

	_terrain_material.albedo_color = terrain_albedo_color
	_terrain_material.emission_enabled = true
	_terrain_material.emission = terrain_albedo_color * 0.2
	_terrain_material.emission_energy_multiplier = 0.35
	if _terrain_mesh_instance != null:
		_terrain_mesh_instance.material_override = _terrain_material

	if _lava_material == null:
		_lava_material = StandardMaterial3D.new()
		_lava_material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		_lava_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_lava_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_lava_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_lava_material.roughness = 1.0

	_lava_material.albedo_color = lava_albedo_color
	if lava_albedo_color.a < 0.999:
		_lava_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		_lava_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	if _lava_mesh_instance != null:
		_lava_mesh_instance.material_override = _lava_material


func _configure_mask_material() -> void:
	if _mask_material == null:
		_mask_material = ShaderMaterial.new()
		_mask_material.shader = REVEAL_MASK_SHADER

	if _display_rect != null:
		_display_rect.material = _mask_material


func _rebuild_exploration_mask(force_refresh: bool) -> void:
	if _procedural_map == null or not is_instance_valid(_procedural_map):
		return
	if _terrain_grid_rect.size.x <= 0 or _terrain_grid_rect.size.y <= 0:
		return

	var explored_cells_variant: Variant = _procedural_map.call("get_explored_cells")
	if not (explored_cells_variant is Dictionary):
		return

	var explored_cells: Dictionary = explored_cells_variant
	if not force_refresh and _mask_texture != null and explored_cells.size() == _last_explored_cell_count:
		return

	var required_width: int = maxi(_terrain_grid_rect.size.x, 1)
	var required_height: int = maxi(_terrain_grid_rect.size.y, 1)
	if _mask_image == null or _mask_image.get_width() != required_width or _mask_image.get_height() != required_height:
		_mask_image = Image.create(required_width, required_height, false, Image.FORMAT_RGBA8)

	_mask_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	for grid_key_variant in explored_cells.keys():
		var grid_key: String = str(grid_key_variant)
		var grid_position: Vector2i = _parse_grid_key(grid_key)
		if grid_position == INVALID_GRID_POSITION:
			continue

		var pixel_x: int = grid_position.x - _terrain_grid_rect.position.x
		var pixel_y: int = grid_position.y - _terrain_grid_rect.position.y
		if pixel_x < 0 or pixel_x >= required_width or pixel_y < 0 or pixel_y >= required_height:
			continue

		_mask_image.set_pixel(pixel_x, pixel_y, Color(1.0, 1.0, 1.0, 1.0))

	if _mask_texture == null:
		_mask_texture = ImageTexture.create_from_image(_mask_image)
	else:
		_mask_texture.update(_mask_image)

	_last_explored_cell_count = explored_cells.size()
	_update_mask_material_state()


func _update_mask_material_state() -> void:
	if _mask_material == null:
		return

	var mask_uv_origin: Vector2 = _get_mask_uv_origin()
	var mask_uv_size: Vector2 = _get_mask_uv_size()
	var player_uv: Vector2 = Vector2(-1.0, -1.0)
	if _player != null and is_instance_valid(_player):
		player_uv = _world_xz_to_focus_uv(Vector2(_player.global_position.x, _player.global_position.z))

	var player_radius_world: float = maxf((float(_get_current_reveal_radius_cells()) + 0.35) * _cell_size, 0.0)
	var player_softness_world: float = maxf(player_reveal_softness_cells * _cell_size, 0.001)

	_mask_material.set_shader_parameter("exploration_mask", _mask_texture)
	_mask_material.set_shader_parameter("mask_uv_origin", mask_uv_origin)
	_mask_material.set_shader_parameter("mask_uv_size", mask_uv_size)
	_mask_material.set_shader_parameter("reveal_softness", revealed_edge_softness)
	_mask_material.set_shader_parameter("player_uv", player_uv)
	_mask_material.set_shader_parameter("focus_world_size", _focus_world_rect.size)
	_mask_material.set_shader_parameter("player_reveal_radius_world", player_radius_world)
	_mask_material.set_shader_parameter("player_reveal_softness_world", player_softness_world)


func _apply_reveal_radius_override() -> void:
	if _procedural_map == null or not is_instance_valid(_procedural_map):
		return
	if reveal_radius_cells_override < 0:
		return
	if reveal_radius_cells_override == _last_applied_reveal_radius_override:
		return
	if _procedural_map.has_method("set_exploration_reveal_radius_cells"):
		_procedural_map.call("set_exploration_reveal_radius_cells", reveal_radius_cells_override)
		_last_applied_reveal_radius_override = reveal_radius_cells_override


func _update_camera_from_focus_rect() -> void:
	if _camera == null:
		return
	if _focus_world_rect.size.x <= 0.0 or _focus_world_rect.size.y <= 0.0:
		return

	var minimap_dimensions: Vector2i = _get_minimap_dimensions()
	var aspect_ratio: float = 1.0
	if minimap_dimensions.y > 0:
		aspect_ratio = float(minimap_dimensions.x) / float(minimap_dimensions.y)

	var camera_span: float = maxf(_focus_world_rect.size.y, _focus_world_rect.size.x / maxf(aspect_ratio, 0.001))
	var camera_center_x: float = _focus_world_rect.position.x + (_focus_world_rect.size.x * 0.5)
	var camera_center_z: float = _focus_world_rect.position.y + (_focus_world_rect.size.y * 0.5)
	_camera.size = camera_span + (camera_padding_world * 2.0)
	_camera.global_position = Vector3(camera_center_x, minimap_camera_height, camera_center_z)
	_camera.global_rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)


func _build_focus_world_rect(render_data: Dictionary) -> Rect2:
	var lava_bounds: Rect2 = _variant_dictionary_to_rect2(render_data.get("lava_surface_bounds", {}))
	if lava_bounds.size.x > 0.0 and lava_bounds.size.y > 0.0:
		return lava_bounds
	return _terrain_world_rect


func _get_mask_uv_origin() -> Vector2:
	if _focus_world_rect.size.x <= 0.0 or _focus_world_rect.size.y <= 0.0:
		return Vector2.ZERO

	return Vector2(
		(_terrain_world_rect.position.x - _focus_world_rect.position.x) / _focus_world_rect.size.x,
		(_terrain_world_rect.position.y - _focus_world_rect.position.y) / _focus_world_rect.size.y
	)


func _get_mask_uv_size() -> Vector2:
	if _focus_world_rect.size.x <= 0.0 or _focus_world_rect.size.y <= 0.0:
		return Vector2.ONE

	return Vector2(
		_terrain_world_rect.size.x / _focus_world_rect.size.x,
		_terrain_world_rect.size.y / _focus_world_rect.size.y
	)


func _world_xz_to_focus_uv(world_xz: Vector2) -> Vector2:
	if _focus_world_rect.size.x <= 0.0 or _focus_world_rect.size.y <= 0.0:
		return Vector2(-1.0, -1.0)

	return Vector2(
		(world_xz.x - _focus_world_rect.position.x) / _focus_world_rect.size.x,
		(world_xz.y - _focus_world_rect.position.y) / _focus_world_rect.size.y
	)


func _get_current_reveal_radius_cells() -> int:
	if reveal_radius_cells_override >= 0:
		return reveal_radius_cells_override
	if _procedural_map != null and is_instance_valid(_procedural_map) and _procedural_map.has_method("get_exploration_reveal_radius_cells"):
		return int(_procedural_map.call("get_exploration_reveal_radius_cells"))
	return 0


func _get_minimap_dimensions() -> Vector2i:
	var resolved_width: int = minimap_width_override
	if resolved_width <= 0:
		resolved_width = minimap_size

	var resolved_height: int = minimap_height_override
	if resolved_height <= 0:
		resolved_height = minimap_size

	return Vector2i(maxi(resolved_width, 1), maxi(resolved_height, 1))


func _variant_to_rect2(value: Variant) -> Rect2:
	if value is Rect2:
		return value
	return Rect2(Vector2.ZERO, Vector2.ZERO)


func _variant_to_rect2i(value: Variant) -> Rect2i:
	if value is Rect2i:
		return value
	return Rect2i(0, 0, 0, 0)


func _variant_to_texture2d(value: Variant) -> Texture2D:
	if value is Texture2D:
		return value
	return null


func _variant_dictionary_to_rect2(value: Variant) -> Rect2:
	if not (value is Dictionary):
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	var bounds: Dictionary = value
	var center: Vector3 = Vector3.ZERO
	var bounds_size: Vector2 = Vector2.ZERO
	var center_variant: Variant = bounds.get("center", Vector3.ZERO)
	var size_variant: Variant = bounds.get("size", Vector2.ZERO)
	if center_variant is Vector3:
		center = center_variant
	if size_variant is Vector2:
		bounds_size = size_variant

	if bounds_size.x <= 0.0 or bounds_size.y <= 0.0:
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	return Rect2(
		Vector2(center.x - (bounds_size.x * 0.5), center.z - (bounds_size.y * 0.5)),
		bounds_size
	)


func _parse_grid_key(grid_key: String) -> Vector2i:
	var parts: PackedStringArray = grid_key.split(",")
	if parts.size() != 2:
		return INVALID_GRID_POSITION
	return Vector2i(int(parts[0]), int(parts[1]))
