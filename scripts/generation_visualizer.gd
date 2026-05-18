extends Control

const DEFAULT_ROOM_FILL_COLOR: Color = Color(0.05098, 0.101961, 0.176471, 0.9)
const DEFAULT_ROOM_ACCENT_FILL_COLOR: Color = Color(0.070588, 0.129412, 0.219608, 0.94)
const DEFAULT_RAW_ROOM_STROKE_COLOR: Color = Color(0.109804, 0.188235, 0.305882, 0.95)
const WALL_SYMBOL_COLOR: Color = Color(0.86, 0.88, 0.92, 0.72)
const FLOOR_SYMBOL_COLOR: Color = Color(0.92, 0.94, 0.98, 0.82)
const WALL_FILL_COLOR: Color = Color(0.309804, 0.356863, 0.447059, 0.56)
const DEFAULT_LAVA_TINT_COLOR: Color = Color(1.0, 0.164706, 0.164706, 0.98)
const DEFAULT_WALL_CELL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const DEFAULT_FLOOR_LIGHTEST_CELL_COLOR: Color = Color(0.72, 0.8, 0.9, 1.0)
const DEFAULT_FLOOR_DARKEST_CELL_COLOR: Color = Color(0.109804, 0.188235, 0.305882, 1.0)
const VISUAL_SIDE_PADDING: float = 56.0
const VISUAL_TOP_PADDING: float = 152.0
const VISUAL_BOTTOM_PADDING: float = 104.0
const DEFAULT_CELL_FILL_ANIMATION_DURATION: float = 0.9
const DEFAULT_LAVA_TINT_ANIMATION_DURATION: float = 1.1
const ROOM_COLLAPSE_ANIMATION_DURATION: float = 0.3
const ROOM_FADE_DELAY_SECONDS: float = 0.18
const CELL_STROKE_FADE_DURATION: float = 0.32
const CELL_SPACING_PIXELS: float = 0.0
const SEED_SQUARE_SIZE_PIXELS: float = 2.0
const CELL_SQUARE_SIZE_PIXELS: float = 6.0
const CELL_STROKE_WIDTH: float = 1.35
const LAVA_OVERLAY_SIZE_PIXELS: float = 4.0
const ROOM_BLUR_EXPANSION_PIXELS: Array[float] = [8.0, 4.0]
const ROOM_BLUR_ALPHA_MULTIPLIERS: Array[float] = [0.16, 0.28]
const DEPTH_COLORS: Array[Color] = [
	Color(0.96, 0.96, 0.96, 0.56),
	Color(0.82, 0.82, 0.82, 0.56),
	Color(0.64, 0.64, 0.64, 0.58),
	Color(0.46, 0.46, 0.46, 0.6),
	Color(0.28, 0.28, 0.28, 0.64)
]

var _bounds_origin: Vector2 = Vector2.ZERO
var _bounds_size: Vector2 = Vector2.ONE
var _cell_world_size: float = 1.0
var _rooms: Array[Dictionary] = []
var _cells: Array[Dictionary] = []
var _raw_rooms: Array[Dictionary] = []
var _raw_room_progress: float = 1.0
var _raw_room_duration: float = 0.0
var _animated_room_indices: Array[int] = []
var _animated_room_progress: float = 1.0
var _animated_room_duration: float = 0.0
var _fill_progress: float = 0.0
var _fill_target: float = 0.0
var _lava_progress: float = 0.0
var _lava_target: float = 0.0
var _lava_depth_threshold: float = 3.0
var _wall_fill_revealed_count: int = 0
var _wall_fill_total_count: int = 0
var _wall_fill_interval_seconds: float = 0.005
var _wall_fill_timer: float = 0.0
var _fill_animation_duration: float = DEFAULT_CELL_FILL_ANIMATION_DURATION
var _lava_tint_animation_duration: float = DEFAULT_LAVA_TINT_ANIMATION_DURATION
var _room_visibility_progress: float = 1.0
var _room_visibility_target: float = 1.0
var _room_fade_delay_timer: float = 0.0
var _cell_stroke_progress: float = 1.0
var _cell_stroke_target: float = 1.0
var _current_phase: String = "reset"
var _room_fill_color: Color = DEFAULT_ROOM_FILL_COLOR
var _room_accent_fill_color: Color = DEFAULT_ROOM_ACCENT_FILL_COLOR
var _raw_room_stroke_color: Color = DEFAULT_RAW_ROOM_STROKE_COLOR
var _lava_tint_color: Color = DEFAULT_LAVA_TINT_COLOR
var _wall_cell_color: Color = DEFAULT_WALL_CELL_COLOR
var _floor_lightest_cell_color: Color = DEFAULT_FLOOR_LIGHTEST_CELL_COLOR
var _floor_darkest_cell_color: Color = DEFAULT_FLOOR_DARKEST_CELL_COLOR


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()


func _process(delta: float) -> void:
	var needs_redraw: bool = false

	if not _raw_rooms.is_empty() and _raw_room_progress < 1.0:
		var raw_room_duration: float = maxf(_raw_room_duration, 0.001)
		_raw_room_progress = move_toward(_raw_room_progress, 1.0, delta / raw_room_duration)
		needs_redraw = true
	elif not _raw_rooms.is_empty() and _raw_room_progress >= 1.0:
		_raw_rooms.clear()
		needs_redraw = true

	if not _animated_room_indices.is_empty() and _animated_room_progress < 1.0:
		var room_duration: float = maxf(_animated_room_duration, 0.001)
		_animated_room_progress = move_toward(_animated_room_progress, 1.0, delta / room_duration)
		needs_redraw = true

	if _room_fade_delay_timer > 0.0:
		_room_fade_delay_timer = maxf(_room_fade_delay_timer - delta, 0.0)
		if is_zero_approx(_room_fade_delay_timer):
			_room_visibility_target = 0.0
			needs_redraw = true

	if _wall_fill_revealed_count < _wall_fill_total_count:
		_wall_fill_timer += delta
		while _wall_fill_revealed_count < _wall_fill_total_count and _wall_fill_timer >= _wall_fill_interval_seconds:
			_wall_fill_timer -= _wall_fill_interval_seconds
			_wall_fill_revealed_count += 1
			needs_redraw = true

	if not is_equal_approx(_fill_progress, _fill_target):
		_fill_progress = move_toward(_fill_progress, _fill_target, delta / maxf(_fill_animation_duration, 0.001))
		needs_redraw = true

	if not is_equal_approx(_lava_progress, _lava_target):
		_lava_progress = move_toward(_lava_progress, _lava_target, delta / maxf(_lava_tint_animation_duration, 0.001))
		needs_redraw = true

	if not is_equal_approx(_room_visibility_progress, _room_visibility_target):
		_room_visibility_progress = move_toward(_room_visibility_progress, _room_visibility_target, delta / ROOM_COLLAPSE_ANIMATION_DURATION)
		needs_redraw = true

	if not is_equal_approx(_cell_stroke_progress, _cell_stroke_target):
		_cell_stroke_progress = move_toward(_cell_stroke_progress, _cell_stroke_target, delta / CELL_STROKE_FADE_DURATION)
		needs_redraw = true

	if needs_redraw:
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func reset_visualization() -> void:
	_rooms.clear()
	_cells.clear()
	_raw_rooms.clear()
	_raw_room_progress = 1.0
	_raw_room_duration = 0.0
	_bounds_origin = Vector2.ZERO
	_bounds_size = Vector2.ONE
	_cell_world_size = 1.0
	_animated_room_indices.clear()
	_animated_room_progress = 1.0
	_animated_room_duration = 0.0
	_fill_progress = 0.0
	_fill_target = 0.0
	_lava_progress = 0.0
	_lava_target = 0.0
	_lava_depth_threshold = 3.0
	_wall_fill_revealed_count = 0
	_wall_fill_total_count = 0
	_wall_fill_interval_seconds = 0.005
	_wall_fill_timer = 0.0
	_fill_animation_duration = DEFAULT_CELL_FILL_ANIMATION_DURATION
	_lava_tint_animation_duration = DEFAULT_LAVA_TINT_ANIMATION_DURATION
	_room_visibility_progress = 1.0
	_room_visibility_target = 1.0
	_room_fade_delay_timer = 0.0
	_cell_stroke_progress = 1.0
	_cell_stroke_target = 1.0
	_current_phase = "reset"
	queue_redraw()


func apply_palette(palette: Dictionary) -> void:
	if palette.is_empty():
		return

	_room_fill_color = _palette_color(palette, "room_fill_color", DEFAULT_ROOM_FILL_COLOR)
	_room_accent_fill_color = _palette_color(palette, "room_accent_fill_color", DEFAULT_ROOM_ACCENT_FILL_COLOR)
	_raw_room_stroke_color = _palette_color(palette, "raw_room_stroke_color", DEFAULT_RAW_ROOM_STROKE_COLOR)
	_lava_tint_color = _palette_color(palette, "lava_tint_color", DEFAULT_LAVA_TINT_COLOR)
	_wall_cell_color = _palette_color(palette, "wall_cell_color", DEFAULT_WALL_CELL_COLOR)
	_floor_lightest_cell_color = _palette_color(palette, "floor_lightest_cell_color", DEFAULT_FLOOR_LIGHTEST_CELL_COLOR)
	_floor_darkest_cell_color = _palette_color(palette, "floor_darkest_cell_color", DEFAULT_FLOOR_DARKEST_CELL_COLOR)
	queue_redraw()


func get_grid_metrics() -> Dictionary:
	var preview_rect: Rect2 = _get_preview_rect()
	if preview_rect.size.x <= 0.0 or preview_rect.size.y <= 0.0:
		return {
			"preview_position": Vector2.ZERO,
			"preview_size": Vector2.ZERO,
			"cell_size": Vector2.ONE
		}

	var grid_size: Vector2i = _get_grid_dimensions()
	var cell_canvas_size: Vector2 = Vector2(
		preview_rect.size.x / float(maxi(grid_size.x, 1)),
		preview_rect.size.y / float(maxi(grid_size.y, 1))
	)
	return {
		"preview_position": preview_rect.position,
		"preview_size": preview_rect.size,
		"cell_size": cell_canvas_size
	}


func apply_snapshot(snapshot: Dictionary) -> void:
	var phase: String = str(snapshot.get("phase", ""))
	if phase == "reset":
		reset_visualization()
		return
	_current_phase = phase

	_update_bounds_from_snapshot(snapshot)
	_update_rooms_from_snapshot(snapshot)
	_update_cells_from_snapshot(snapshot)

	if snapshot.has("cell_size"):
		_cell_world_size = float(snapshot.get("cell_size", 1.0))

	match phase:
		"raw_room_step":
			_raw_rooms = _dictionary_array_from_variant(snapshot.get("raw_rooms", []))
			_raw_room_duration = float(snapshot.get("animation_duration", 0.0))
			_raw_room_progress = 0.0 if not _raw_rooms.is_empty() and _raw_room_duration > 0.0 else 1.0
			_animated_room_indices.clear()
			_animated_room_progress = 1.0
			_fill_progress = 0.0
			_fill_target = 0.0
			_lava_progress = 0.0
			_lava_target = 0.0
			_room_visibility_progress = 1.0
			_room_visibility_target = 1.0
			_room_fade_delay_timer = 0.0
			_cell_stroke_progress = 1.0
			_cell_stroke_target = 1.0
		"room_step":
			_raw_rooms.clear()
			_raw_room_progress = 1.0
			_animated_room_indices = _int_array_from_variant(snapshot.get("animated_room_indices", []))
			_animated_room_duration = float(snapshot.get("animation_duration", 0.0))
			_animated_room_progress = 0.0 if not _animated_room_indices.is_empty() and _animated_room_duration > 0.0 else 1.0
			_fill_progress = 0.0
			_fill_target = 0.0
			_lava_progress = 0.0
			_lava_target = 0.0
			_room_visibility_progress = 1.0
			_room_visibility_target = 1.0
			_room_fade_delay_timer = 0.0
			_cell_stroke_progress = 1.0
			_cell_stroke_target = 1.0
		"cell_outlines":
			_animated_room_indices.clear()
			_animated_room_progress = 1.0
			_wall_fill_revealed_count = 0
			_wall_fill_total_count = _count_wall_cells()
			_wall_fill_timer = 0.0
			_fill_progress = 0.0
			_fill_target = 0.0
			_lava_progress = 0.0
			_lava_target = 0.0
			_room_visibility_progress = 1.0
			_room_visibility_target = 1.0
			_room_fade_delay_timer = 0.0
			_cell_stroke_progress = 1.0
			_cell_stroke_target = 1.0
		"wall_fill":
			_animated_room_indices.clear()
			_animated_room_progress = 1.0
			_wall_fill_revealed_count = 0
			_wall_fill_total_count = _count_wall_cells()
			_wall_fill_interval_seconds = maxf(float(snapshot.get("wall_fill_interval", _wall_fill_interval_seconds)), 0.001)
			_wall_fill_timer = 0.0
			_fill_progress = 0.0
			_fill_target = 0.0
			_lava_progress = 0.0
			_lava_target = 0.0
			_cell_stroke_progress = 1.0
			_cell_stroke_target = 1.0
		"depth_fill":
			_animated_room_indices.clear()
			_animated_room_progress = 1.0
			_wall_fill_revealed_count = _count_wall_cells()
			_wall_fill_total_count = _wall_fill_revealed_count
			_fill_progress = 0.0
			_fill_target = 1.0
			_fill_animation_duration = float(snapshot.get("fill_duration", DEFAULT_CELL_FILL_ANIMATION_DURATION))
			_lava_progress = 0.0
			_lava_target = 0.0
			_lava_depth_threshold = float(snapshot.get("lava_depth_threshold", _lava_depth_threshold))
			_cell_stroke_target = 0.0
		"lava_tint":
			_animated_room_indices.clear()
			_animated_room_progress = 1.0
			_wall_fill_revealed_count = _count_wall_cells()
			_wall_fill_total_count = _wall_fill_revealed_count
			_fill_progress = 1.0
			_fill_target = 1.0
			_lava_progress = 0.0
			_lava_target = 1.0
			_lava_tint_animation_duration = float(snapshot.get("lava_tint_duration", DEFAULT_LAVA_TINT_ANIMATION_DURATION))
			_lava_depth_threshold = float(snapshot.get("lava_depth_threshold", _lava_depth_threshold))
			_cell_stroke_target = 0.0
		"complete":
			_animated_room_indices.clear()
			_animated_room_progress = 1.0
			_wall_fill_revealed_count = _count_wall_cells()
			_wall_fill_total_count = _wall_fill_revealed_count
			_fill_progress = 1.0
			_fill_target = 1.0
			_lava_progress = 1.0
			_lava_target = 1.0
			_lava_depth_threshold = float(snapshot.get("lava_depth_threshold", _lava_depth_threshold))
			_cell_stroke_target = 0.0

	queue_redraw()


func _draw() -> void:
	var preview_rect: Rect2 = _get_preview_rect()
	if preview_rect.size.x <= 0.0 or preview_rect.size.y <= 0.0:
		return

	_draw_raw_room(preview_rect)
	_draw_rooms(preview_rect)
	_draw_cells(preview_rect)


func _draw_raw_room(preview_rect: Rect2) -> void:
	if _raw_rooms.is_empty():
		return
	var pulse_progress: float = clampf(_raw_room_progress, 0.0, 1.0)
	var draw_scale: float = 0.0
	if pulse_progress < 0.5:
		draw_scale = _ease_out_cubic(pulse_progress / 0.5)
	else:
		draw_scale = 1.0 - _ease_in_cubic((pulse_progress - 0.5) / 0.5)

	if draw_scale <= 0.0:
		return

	for raw_room in _raw_rooms:
		var room_position: Vector2 = raw_room.get("position", Vector2.ZERO)
		var room_radius: float = float(raw_room.get("radius", 0.0))
		var stroke_color: Color = _raw_room_stroke_color
		stroke_color.a *= clampf(draw_scale, 0.0, 1.0)
		var center: Vector2 = _snap_point(_world_to_canvas(room_position, preview_rect))
		var canvas_radius: float = _world_scalar_to_canvas(room_radius * draw_scale, preview_rect)
		canvas_radius = maxf(canvas_radius, 1.0)
		draw_arc(center, canvas_radius, 0.0, TAU, 72, stroke_color, 2.0, false)


func _draw_rooms(preview_rect: Rect2) -> void:
	if _room_visibility_progress <= 0.0:
		return

	for room_index in range(_rooms.size()):
		var room_data: Dictionary = _rooms[room_index]
		var room_position: Vector2 = room_data.get("position", Vector2.ZERO)
		var room_radius: float = float(room_data.get("radius", 0.0))
		var outline_points: Array = room_data.get("outline_points", [])
		var draw_scale: float = _room_visibility_progress
		var fill_color: Color = _room_fill_color
		if _animated_room_indices.has(room_index):
			draw_scale *= _ease_out_cubic(_animated_room_progress)
			fill_color = _room_accent_fill_color

		fill_color.a *= _room_visibility_progress

		var center: Vector2 = _snap_point(_world_to_canvas(room_position, preview_rect))
		if outline_points.is_empty():
			var canvas_radius: float = _world_scalar_to_canvas(room_radius * draw_scale, preview_rect)
			canvas_radius = maxf(canvas_radius, 1.0)
			_draw_blurred_circle(center, canvas_radius, fill_color)
			continue

		var scaled_points: PackedVector2Array = PackedVector2Array()
		for outline_point_value in outline_points:
			var outline_point: Vector2 = outline_point_value as Vector2
			var scaled_world_point: Vector2 = room_position + ((outline_point - room_position) * draw_scale)
			scaled_points.append(_snap_point(_world_to_canvas(scaled_world_point, preview_rect)))

		if scaled_points.size() >= 3:
			_draw_blurred_polygon(scaled_points, center, fill_color)


func _draw_cells(preview_rect: Rect2) -> void:
	for cell_data in _cells:
		var cell_rect: Rect2 = _snap_rect(_cell_to_canvas_rect(cell_data, preview_rect))
		if cell_rect.size.x <= 0.0 or cell_rect.size.y <= 0.0:
			continue
		if not bool(cell_data.get("is_wall", false)):
			continue

		_draw_cell_square(cell_data, cell_rect)

	for cell_data in _cells:
		var cell_rect: Rect2 = _snap_rect(_cell_to_canvas_rect(cell_data, preview_rect))
		if cell_rect.size.x <= 0.0 or cell_rect.size.y <= 0.0:
			continue
		if bool(cell_data.get("is_wall", false)):
			continue

		_draw_cell_square(cell_data, cell_rect)

	for cell_data in _cells:
		var cell_rect: Rect2 = _snap_rect(_cell_to_canvas_rect(cell_data, preview_rect))
		if cell_rect.size.x <= 0.0 or cell_rect.size.y <= 0.0:
			continue

		_draw_lava_overlay_square(cell_data, cell_rect)


func _draw_cell_square(cell_data: Dictionary, cell_rect: Rect2) -> void:
	var side_pixels: float = _get_cell_square_size_pixels(cell_data, cell_rect)
	if side_pixels <= 0.0:
		return

	var square_rect: Rect2 = _build_centered_square_rect(cell_rect, side_pixels, CELL_SPACING_PIXELS)
	if square_rect.size.x <= 0.0 or square_rect.size.y <= 0.0:
		return

	var fill_color: Color = _get_cell_fill_color(cell_data)
	draw_rect(square_rect, fill_color, true)


func _draw_lava_overlay_square(cell_data: Dictionary, cell_rect: Rect2) -> void:
	if not bool(cell_data.get("is_floor", false)) or not cell_data.has("depth") or _lava_progress <= 0.0:
		return

	var depth_index: int = clampi(int(cell_data.get("depth", 0)), 0, DEPTH_COLORS.size() - 1)
	if float(depth_index) < _lava_depth_threshold:
		return

	var overlay_rect: Rect2 = _build_centered_square_rect(
		cell_rect,
		LAVA_OVERLAY_SIZE_PIXELS * _lava_progress,
		CELL_SPACING_PIXELS
	)
	if overlay_rect.size.x <= 0.0 or overlay_rect.size.y <= 0.0:
		return

	var dot_color: Color = _lava_tint_color
	dot_color.a *= _lava_progress
	draw_rect(overlay_rect, dot_color, true)


func _snap_point(point: Vector2) -> Vector2:
	return point.round()


func _snap_rect(rect: Rect2) -> Rect2:
	var snapped_position: Vector2 = rect.position.floor()
	var snapped_end: Vector2 = rect.end.ceil()
	var snapped_size: Vector2 = Vector2(
		maxf(snapped_end.x - snapped_position.x, 1.0),
		maxf(snapped_end.y - snapped_position.y, 1.0)
	)
	return Rect2(snapped_position, snapped_size)


func _build_centered_square_rect(cell_rect: Rect2, side_pixels: float, spacing_pixels: float) -> Rect2:
	var max_side: float = minf(cell_rect.size.x, cell_rect.size.y) - (spacing_pixels * 2.0)
	if max_side <= 0.0:
		return Rect2(cell_rect.get_center(), Vector2.ZERO)

	var side: float = maxf(minf(round(side_pixels), round(max_side)), 1.0)
	var position: Vector2 = (cell_rect.get_center() - (Vector2.ONE * side * 0.5)).round()
	return Rect2(position, Vector2.ONE * side)


func _draw_blurred_circle(center: Vector2, radius: float, color: Color) -> void:
	var solid_color: Color = color
	solid_color.a = 1.0
	draw_circle(center, radius, solid_color)


func _draw_blurred_polygon(points: PackedVector2Array, center: Vector2, color: Color) -> void:
	var solid_color: Color = color
	solid_color.a = 1.0
	draw_colored_polygon(points, solid_color)


func _dictionary_array_from_variant(value: Variant) -> Array[Dictionary]:
	var dictionaries: Array[Dictionary] = []
	if value is Array:
		for element in value:
			if element is Dictionary:
				dictionaries.append(element)
	return dictionaries


func _int_array_from_variant(value: Variant) -> Array[int]:
	var indices: Array[int] = []
	if value is Array:
		for element in value:
			indices.append(int(element))
	return indices


func _get_cell_square_size_pixels(cell_data: Dictionary, _cell_rect: Rect2) -> float:
	if not _should_draw_cells_in_phase():
		return 0.0

	if not cell_data.has("depth"):
		return SEED_SQUARE_SIZE_PIXELS

	if bool(cell_data.get("is_wall", false)):
		return _get_wall_square_size_pixels(cell_data)

	match _current_phase:
		"cell_outlines", "wall_fill":
			return SEED_SQUARE_SIZE_PIXELS
		"depth_fill", "lava_tint", "complete":
			return lerpf(SEED_SQUARE_SIZE_PIXELS, CELL_SQUARE_SIZE_PIXELS, _fill_progress)
		_:
			return 0.0


func _get_wall_square_size_pixels(cell_data: Dictionary) -> float:
	match _current_phase:
		"cell_outlines":
			return SEED_SQUARE_SIZE_PIXELS
		"wall_fill":
			var wall_sequence_index: int = int(cell_data.get("wall_sequence_index", -1))
			if wall_sequence_index < 0:
				return SEED_SQUARE_SIZE_PIXELS
			if wall_sequence_index < _wall_fill_revealed_count:
				return CELL_SQUARE_SIZE_PIXELS
			if wall_sequence_index == _wall_fill_revealed_count and _wall_fill_revealed_count < _wall_fill_total_count:
				var step_progress: float = clampf(_wall_fill_timer / maxf(_wall_fill_interval_seconds, 0.001), 0.0, 1.0)
				return lerpf(SEED_SQUARE_SIZE_PIXELS, CELL_SQUARE_SIZE_PIXELS, step_progress)
			return SEED_SQUARE_SIZE_PIXELS
		"depth_fill", "lava_tint", "complete":
			return CELL_SQUARE_SIZE_PIXELS
		_:
			return 0.0


func _get_cell_fill_color(cell_data: Dictionary) -> Color:
	if bool(cell_data.get("is_wall", false)):
		return _wall_cell_color

	if not cell_data.has("depth"):
		return _wall_cell_color

	var depth_index: int = clampi(int(cell_data.get("depth", 0)), 0, DEPTH_COLORS.size() - 1)
	var target_color: Color = _get_floor_depth_color(depth_index)

	match _current_phase:
		"depth_fill", "lava_tint", "complete":
			return _wall_cell_color.lerp(target_color, _fill_progress)
		"cell_outlines", "wall_fill":
			return _wall_cell_color
		_:
			return _wall_cell_color


func _get_floor_depth_color(depth_index: int) -> Color:
	var depth_count: int = maxi(DEPTH_COLORS.size() - 1, 1)
	var depth_ratio: float = float(depth_index) / float(depth_count)
	return _floor_lightest_cell_color.lerp(_floor_darkest_cell_color, depth_ratio)


func _palette_color(palette: Dictionary, key: String, fallback: Color) -> Color:
	var palette_value: Variant = palette.get(key, fallback)
	if palette_value is Color:
		return palette_value
	return fallback


func _should_draw_cells_in_phase() -> bool:
	return _current_phase in ["cell_outlines", "wall_fill", "depth_fill", "lava_tint", "complete"]


func _count_wall_cells() -> int:
	var wall_count: int = 0
	for cell_data in _cells:
		if bool(cell_data.get("is_wall", false)):
			wall_count += 1
	return wall_count


func _get_preview_rect() -> Rect2:
	var available_rect: Rect2 = Rect2(
		Vector2(VISUAL_SIDE_PADDING, VISUAL_TOP_PADDING),
		size - Vector2(VISUAL_SIDE_PADDING * 2.0, VISUAL_TOP_PADDING + VISUAL_BOTTOM_PADDING)
	)
	if available_rect.size.x <= 0.0 or available_rect.size.y <= 0.0:
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	var grid_size: Vector2i = _get_grid_dimensions()
	var desired_preview_size: Vector2 = Vector2(
		float(maxi(grid_size.x, 1)) * CELL_SQUARE_SIZE_PIXELS,
		float(maxi(grid_size.y, 1)) * CELL_SQUARE_SIZE_PIXELS
	)
	var preview_size: Vector2 = Vector2(
		minf(desired_preview_size.x, available_rect.size.x),
		minf(desired_preview_size.y, available_rect.size.y)
	)

	var preview_position: Vector2 = (available_rect.position + (available_rect.size - preview_size) * 0.5).round()
	return Rect2(preview_position, preview_size)


func _world_to_canvas(world_position: Vector2, preview_rect: Rect2) -> Vector2:
	var safe_bounds: Vector2 = Vector2(maxf(_bounds_size.x, 0.001), maxf(_bounds_size.y, 0.001))
	var normalized: Vector2 = Vector2(
		(world_position.x - _bounds_origin.x) / safe_bounds.x,
		(world_position.y - _bounds_origin.y) / safe_bounds.y
	)
	return preview_rect.position + Vector2(normalized.x * preview_rect.size.x, normalized.y * preview_rect.size.y)


func _world_scalar_to_canvas(world_scalar: float, preview_rect: Rect2) -> float:
	var safe_bounds: Vector2 = Vector2(maxf(_bounds_size.x, 0.001), maxf(_bounds_size.y, 0.001))
	var scale_x: float = preview_rect.size.x / safe_bounds.x
	var scale_y: float = preview_rect.size.y / safe_bounds.y
	return world_scalar * minf(scale_x, scale_y)


func _world_rect_to_canvas_rect(world_origin: Vector2, world_size: Vector2, preview_rect: Rect2) -> Rect2:
	var top_left: Vector2 = _world_to_canvas(world_origin, preview_rect)
	var bottom_right: Vector2 = _world_to_canvas(world_origin + world_size, preview_rect)
	return Rect2(top_left, bottom_right - top_left)


func _cell_to_canvas_rect(cell_data: Dictionary, preview_rect: Rect2) -> Rect2:
	var world_origin: Vector2 = cell_data.get("world_origin", Vector2.ZERO)
	var world_size: Vector2 = cell_data.get("world_size", Vector2(_cell_world_size, _cell_world_size))
	return _world_rect_to_canvas_rect(world_origin, world_size, preview_rect)


func _get_grid_dimensions() -> Vector2i:
	var safe_cell_world_size: float = maxf(_cell_world_size, 0.001)
	return Vector2i(
		maxi(int(round(_bounds_size.x / safe_cell_world_size)), 1),
		maxi(int(round(_bounds_size.y / safe_cell_world_size)), 1)
	)


func _update_bounds_from_snapshot(snapshot: Dictionary) -> void:
	if snapshot.has("bounds_origin"):
		_bounds_origin = snapshot.get("bounds_origin", Vector2.ZERO)
	if snapshot.has("bounds_size"):
		_bounds_size = snapshot.get("bounds_size", Vector2.ONE)


func _update_rooms_from_snapshot(snapshot: Dictionary) -> void:
	if not snapshot.has("rooms"):
		return

	_rooms.clear()
	var room_values: Array = snapshot.get("rooms", [])
	for room_value in room_values:
		if room_value is Dictionary:
			_rooms.append(room_value)


func _update_cells_from_snapshot(snapshot: Dictionary) -> void:
	if not snapshot.has("cells"):
		return

	_cells.clear()
	var cell_values: Array = snapshot.get("cells", [])
	for cell_value in cell_values:
		if cell_value is Dictionary:
			_cells.append(cell_value)


func _ease_out_cubic(value: float) -> float:
	var clamped_value: float = clampf(value, 0.0, 1.0)
	return 1.0 - pow(1.0 - clamped_value, 3.0)


func _ease_in_cubic(value: float) -> float:
	var clamped_value: float = clampf(value, 0.0, 1.0)
	return clamped_value * clamped_value * clamped_value