extends Control

## Minimap HUD that displays walls and player position.

@export var minimap_size: int = 150
@export var border_margin: int = 20
@export var wall_color: Color = Color.WHITE
@export var floor_color: Color = Color(0.3, 0.3, 0.3)
@export var background_color: Color = Color.BLACK
@export var player_color: Color = Color.GREEN
@export var player_dot_size: int = 2
@export var lava_source_color: Color = Color.RED
@export var lava_source_dot_size: int = 3
@export var highground_color: Color = Color(0.0, 1.0, 0.0)  # Bright green
@export var highground_dot_size: int = 3

var _minimap_image: Image
var _minimap_texture: ImageTexture
var _texture_rect: TextureRect
var _procedural_map: Node3D
var _player: Node3D
var _map_bounds: Dictionary = {}


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
	add_child(_texture_rect)
	
	# Find procedural map and player
	_procedural_map = NodeUtils.find(self, "procedural_map", ["/root/Main/Procedural Map"])
	if not _procedural_map:
		push_warning("Minimap: ProceduralMap not found!")
		return
	
	# Wait a frame for player to be placed
	await get_tree().process_frame
	_find_player()
	
	# Generate initial minimap
	_generate_minimap()


func _process(_delta: float) -> void:
	if _minimap_image and _player:
		_update_player_position()


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
	
	# Get map properties (using get() for dynamic access)
	var map_width: float = _procedural_map.get("map_width")
	var map_height: float = _procedural_map.get("map_height")
	var cell_size: float = _procedural_map.get("cell_size")
	var edge_margin: int = _procedural_map.get("edge_margin") if "edge_margin" in _procedural_map else 3
	
	# Calculate grid dimensions
	var grid_w := int(floor(map_width / cell_size)) - 4
	var grid_h := int(floor(map_height / cell_size)) - 4
	
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
	
	# Get cells from procedural map
	var cells: Array = _procedural_map.get_cells()
	
	# Draw walls and floors
	for cell in cells:
		var x := int(cell.position.x)
		var y := int(cell.position.y)
		
		if x >= 0 and x < grid_w and y >= 0 and y < grid_h:
			if cell.is_wall:
				_minimap_image.set_pixel(x, y, wall_color)
			elif cell.is_floor:
				_minimap_image.set_pixel(x, y, floor_color)
	
	# Draw lava source markers
	var lava_sources: Array = _procedural_map.get_lava_sources()
	for lava_pos in lava_sources:
		var x: int = int(lava_pos.x)
		var y: int = int(lava_pos.y)
		_draw_marker(_minimap_image, x, y, lava_source_color, lava_source_dot_size, grid_w, grid_h)
	
	# Draw highground markers
	var highground_positions: Array = _procedural_map.get_highground_positions()
	for high_pos in highground_positions:
		var x: int = int(high_pos.x)
		var y: int = int(high_pos.y)
		_draw_marker(_minimap_image, x, y, highground_color, highground_dot_size, grid_w, grid_h)
	
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
	if not _player or _map_bounds.is_empty():
		return
	
	# Redraw base minimap (copy original)
	var temp_image := _minimap_image.duplicate()
	
	# Convert player world position to minimap pixel coordinates
	var player_pos := _player.global_position
	var normalized_x: float = (player_pos.x - float(_map_bounds.min_x)) / float(_map_bounds.width)
	var normalized_z: float = (player_pos.z - float(_map_bounds.min_z)) / float(_map_bounds.height)
	
	var pixel_x := int(normalized_x * temp_image.get_width())
	var pixel_y := int(normalized_z * temp_image.get_height())
	
	# Draw player dot using helper function
	_draw_marker(temp_image, pixel_x, pixel_y, player_color, player_dot_size, temp_image.get_width(), temp_image.get_height())
	
	# Update texture
	_minimap_texture.update(temp_image)
