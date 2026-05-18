extends Control

## Minimap HUD that displays walls and player position.

@export var minimap_size: int = 150
@export var border_margin: int = 20
@export var wall_color: Color = Color.WHITE
@export var floor_color: Color = Color(0.3, 0.3, 0.3)
@export var background_color: Color = Color.BLACK
@export var player_color: Color = Color.GREEN
@export var player_dot_size: int = 2
@export var camera_direction_color: Color = Color(1.0, 0.95, 0.2, 1.0)
@export var camera_direction_length: int = 14
@export var camera_direction_tip_size: int = 2
@export var lava_source_color: Color = Color.RED
@export var lava_source_dot_size: int = 3
@export var highground_color: Color = Color(0.0, 1.0, 0.0)  # Bright green
@export var highground_dot_size: int = 3
@export_range(-180.0, 180.0, 0.1) var minimap_rotation_degrees: float = 45.0

var _minimap_image: Image
var _minimap_texture: ImageTexture
var _texture_rect: TextureRect
var _procedural_map: Node3D
var _player: Node3D
var _camera: Camera3D
var _map_bounds: Dictionary = {}
var _grid_width: int = 0
var _grid_height: int = 0


func _ready() -> void:
	# Position in top-right corner
	anchors_preset = Control.PRESET_TOP_RIGHT
	offset_left = -minimap_size - border_margin
	offset_top = border_margin
	custom_minimum_size = Vector2(minimap_size, minimap_size)
	
	# Create texture rect for minimap display
	_texture_rect = TextureRect.new()
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # Disable blur for crisp pixels
	_texture_rect.custom_minimum_size = Vector2(minimap_size, minimap_size)
	_texture_rect.position = Vector2.ZERO
	_texture_rect.size = Vector2(minimap_size, minimap_size)
	add_child(_texture_rect)
	_apply_minimap_rotation()
	
	# Find procedural map and player
	_procedural_map = NodeUtils.find(self, "procedural_map", ["/root/Main/Procedural Map"])
	if not _procedural_map:
		push_warning("Minimap: ProceduralMap not found!")
		return

	var regenerate_callable: Callable = Callable(self, "_generate_minimap")
	if _procedural_map.has_signal("map_regenerated") and not _procedural_map.is_connected("map_regenerated", regenerate_callable):
		_procedural_map.connect("map_regenerated", regenerate_callable)
	
	# Wait a frame for player to be placed
	await get_tree().process_frame
	_find_player()
	
	# Generate initial minimap
	_generate_minimap()


func _apply_minimap_rotation() -> void:
	if _texture_rect == null:
		return

	var rotation_radians: float = deg_to_rad(minimap_rotation_degrees)
	var fit_scale: float = 1.0 / maxf(absf(cos(rotation_radians)) + absf(sin(rotation_radians)), 1.0)
	_texture_rect.pivot_offset = Vector2(minimap_size * 0.5, minimap_size * 0.5)
	_texture_rect.rotation_degrees = minimap_rotation_degrees
	_texture_rect.scale = Vector2(fit_scale, fit_scale)


func _process(_delta: float) -> void:
	_update_camera_reference()
	if _minimap_image and _player:
		_update_player_position()


func _update_camera_reference() -> void:
	var viewport_camera: Camera3D = get_viewport().get_camera_3d()
	if viewport_camera != null:
		_camera = viewport_camera


## Finds the player node in the scene.
func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
	else:
		push_warning("Minimap: Player not found!")


## Generates the minimap from procedural map data.
func _generate_minimap() -> void:
	if not _procedural_map:
		return
	
	# Guard dynamic property access so a missing or invalid map script does not assign Nil to typed locals.
	var map_width_value: Variant = _procedural_map.get("map_width")
	var map_height_value: Variant = _procedural_map.get("map_height")
	var cell_size_value: Variant = _procedural_map.get("cell_size")
	var edge_margin_value: Variant = _procedural_map.get("edge_margin")
	if map_width_value == null or map_height_value == null or cell_size_value == null:
		push_warning("Minimap: Procedural map properties unavailable, skipping minimap generation.")
		return

	var map_width: float = float(map_width_value)
	var map_height: float = float(map_height_value)
	var cell_size: float = float(cell_size_value)
	if cell_size <= 0.0:
		push_warning("Minimap: Invalid cell_size, skipping minimap generation.")
		return

	var edge_margin: int = 3
	if edge_margin_value != null:
		edge_margin = int(edge_margin_value)
	
	# Calculate grid dimensions
	var grid_w: int = int(floor(map_width / cell_size)) - 4
	var grid_h: int = int(floor(map_height / cell_size)) - 4
	_grid_width = grid_w
	_grid_height = grid_h
	
	# Calculate edge offset (tiles are placed starting from edge_margin * cell_size)
	var edge_offset: float = edge_margin * cell_size
	
	# Store bounds for position mapping (must match procedural map's coordinate system)
	_map_bounds = {
		"min_x": edge_offset,
		"max_x": edge_offset + grid_w * cell_size,
		"min_z": edge_offset,
		"max_z": edge_offset + grid_h * cell_size,
		"width": grid_w * cell_size,
		"height": grid_h * cell_size
	}
	
	# Create image with alpha channel to support transparency
	_minimap_image = Image.create(grid_w, grid_h, false, Image.FORMAT_RGBA8)
	_minimap_image.fill(background_color)
	
	# Create texture
	_minimap_texture = ImageTexture.create_from_image(_minimap_image)
	_texture_rect.texture = _minimap_texture


## Helper function to draw a circular marker on the minimap.
func _draw_marker(image: Image, center_x: int, center_y: int, color: Color, marker_size: int, width: int, height: int) -> void:
	for dx in range(-marker_size, marker_size + 1):
		for dy in range(-marker_size, marker_size + 1):
			var px: int = center_x + dx
			var py: int = center_y + dy
			if px >= 0 and px < width and py >= 0 and py < height:
				# Only draw if within dot radius
				if dx * dx + dy * dy <= marker_size * marker_size:
					image.set_pixel(px, py, color)


## Updates player position on minimap.
func _update_player_position() -> void:
	if not _player or _map_bounds.is_empty() or _grid_width <= 0 or _grid_height <= 0:
		return
	
	# Redraw base minimap (copy original)
	var temp_image: Image = _minimap_image.duplicate()
	_draw_explored_map(temp_image)
	
	# Convert player world position to minimap pixel coordinates
	var player_pos: Vector3 = _player.global_position
	var normalized_x: float = (player_pos.x - float(_map_bounds.min_x)) / float(_map_bounds.width)
	var normalized_z: float = (player_pos.z - float(_map_bounds.min_z)) / float(_map_bounds.height)
	
	var pixel_x: int = int(normalized_x * temp_image.get_width())
	var pixel_y: int = int(normalized_z * temp_image.get_height())
	
	# Draw player dot using helper function
	_draw_marker(temp_image, pixel_x, pixel_y, player_color, player_dot_size, temp_image.get_width(), temp_image.get_height())
	_draw_camera_direction(temp_image, pixel_x, pixel_y)
	
	# Update texture
	_minimap_texture.update(temp_image)


func _draw_explored_map(image: Image) -> void:
	if _procedural_map == null:
		return

	var explored_cells_variant: Variant = _procedural_map.call("get_explored_cells")
	var explored_cells: Dictionary = {}
	if explored_cells_variant is Dictionary:
		explored_cells = explored_cells_variant

	var cells_variant: Variant = _procedural_map.call("get_cells")
	if cells_variant is Array:
		var cells: Array = cells_variant
		for cell in cells:
			var x: int = int(cell.position.x)
			var y: int = int(cell.position.y)
			if x < 0 or x >= _grid_width or y < 0 or y >= _grid_height:
				continue

			var grid_key: String = _grid_position_key(Vector2i(x, y))
			if not explored_cells.has(grid_key):
				continue

			if cell.is_wall:
				image.set_pixel(x, y, wall_color)
			elif cell.is_floor:
				image.set_pixel(x, y, floor_color)

	var lava_sources_variant: Variant = _procedural_map.call("get_lava_sources")
	if lava_sources_variant is Array:
		var lava_sources: Array = lava_sources_variant
		for lava_pos in lava_sources:
			var lava_grid_pos: Vector2i = Vector2i(int(lava_pos.x), int(lava_pos.y))
			if explored_cells.has(_grid_position_key(lava_grid_pos)):
				_draw_marker(image, lava_grid_pos.x, lava_grid_pos.y, lava_source_color, lava_source_dot_size, _grid_width, _grid_height)

	var highground_positions_variant: Variant = _procedural_map.call("get_highground_positions")
	if highground_positions_variant is Array:
		var highground_positions: Array = highground_positions_variant
		for high_pos in highground_positions:
			var highground_grid_pos: Vector2i = Vector2i(int(high_pos.x), int(high_pos.y))
			if explored_cells.has(_grid_position_key(highground_grid_pos)):
				_draw_marker(image, highground_grid_pos.x, highground_grid_pos.y, highground_color, highground_dot_size, _grid_width, _grid_height)


func _grid_position_key(grid_pos: Vector2i) -> String:
	return "%d,%d" % [grid_pos.x, grid_pos.y]


func _draw_camera_direction(image: Image, start_x: int, start_y: int) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return

	var camera_forward: Vector3 = -_camera.global_basis.z
	camera_forward.y = 0.0
	if camera_forward.length_squared() <= 0.0001:
		return

	camera_forward = camera_forward.normalized()
	var direction_2d: Vector2 = Vector2(camera_forward.x, camera_forward.z)
	var tip_offset: Vector2 = direction_2d * float(camera_direction_length)
	var tip_x: int = start_x + int(round(tip_offset.x))
	var tip_y: int = start_y + int(round(tip_offset.y))

	_draw_image_line(image, start_x, start_y, tip_x, tip_y, camera_direction_color)
	_draw_marker(
		image,
		tip_x,
		tip_y,
		camera_direction_color,
		camera_direction_tip_size,
		image.get_width(),
		image.get_height()
	)


func _draw_image_line(image: Image, start_x: int, start_y: int, end_x: int, end_y: int, color: Color) -> void:
	var delta_x: int = end_x - start_x
	var delta_y: int = end_y - start_y
	var step_count: int = maxi(abs(delta_x), abs(delta_y))
	if step_count <= 0:
		if start_x >= 0 and start_x < image.get_width() and start_y >= 0 and start_y < image.get_height():
			image.set_pixel(start_x, start_y, color)
		return

	for step_index: int in range(step_count + 1):
		var weight: float = float(step_index) / float(step_count)
		var pixel_x: int = int(round(lerpf(float(start_x), float(end_x), weight)))
		var pixel_y: int = int(round(lerpf(float(start_y), float(end_y), weight)))
		if pixel_x >= 0 and pixel_x < image.get_width() and pixel_y >= 0 and pixel_y < image.get_height():
			image.set_pixel(pixel_x, pixel_y, color)
