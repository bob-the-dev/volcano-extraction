extends Control

const MAIN_SCENE_PATH: String = "res://main.tscn"
const ColorCombinationPickerScript: GDScript = preload("res://scripts/utils/color_combination_picker.gd")
const LOADING_TITLE: String = "Entering through the Gift Shop..."
const READY_PROMPT: String = "Press any key to continue"
const SCENE_LOAD_PROGRESS_WEIGHT: float = 0.18
const GENERATION_PROGRESS_START: float = 0.2
const GENERATION_PROGRESS_END: float = 0.96
const LOADING_WARMUP_FRAMES: int = 2
const BANNER_SWATCH_FALLBACK_SIZE: float = 112.0
const BANNER_SWATCH_WIDTH_INSET: float = 8.0
const BANNER_SWATCH_MIN_SIZE: float = 18.0
const BANNER_SWATCH_SEPARATION: float = 8.0
const PROGRESS_BAR_CORNER_RADIUS: int = 16

@onready var _background_rect: ColorRect = $Background
@onready var _title_label: Label = $Overlay/ContentMargin/VBoxContainer/TopOverlay/TitleCenter/VBoxContainer/TitleLabel
@onready var _subtitle_label: Label = $Overlay/ContentMargin/VBoxContainer/TopOverlay/TitleCenter/VBoxContainer/SubtitleLabel
@onready var _generation_visualizer: Control = $Overlay/GenerationVisualizer
@onready var _progress_bar: ProgressBar = $Overlay/ContentMargin/VBoxContainer/ProgressBar
@onready var _banner_squares_vbox: VBoxContainer = $Overlay/RightBanner/SquaresMargin/SquaresVBox

var _game_scene: Node = null
var _waiting_for_continue: bool = false
var _continue_requested: bool = false


func _toggle_fullscreen_mode() -> void:
	var current_window_mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	if current_window_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		return

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _ready() -> void:
	_apply_random_loading_palette()
	_title_label.text = LOADING_TITLE
	_progress_bar.value = 0.0
	if _generation_visualizer != null and _generation_visualizer.has_method("reset_visualization"):
		_generation_visualizer.call("reset_visualization")
	_show_loading_status("Preparing load", 0.02)
	call_deferred("_boot_game")


func _input(event: InputEvent) -> void:
	if not _waiting_for_continue or _continue_requested:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			_toggle_fullscreen_mode()
			get_viewport().set_input_as_handled()
			return

		_continue_requested = true
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		_continue_requested = true
		get_viewport().set_input_as_handled()
		return

	if event is InputEventJoypadButton and event.pressed:
		_continue_requested = true
		get_viewport().set_input_as_handled()


func _wait_for_continue() -> void:
	_waiting_for_continue = true
	_continue_requested = false
	while not _continue_requested:
		await get_tree().process_frame
	_waiting_for_continue = false


func _boot_game() -> void:
	await _warm_up_loading()

	var request_error: Error = ResourceLoader.load_threaded_request(MAIN_SCENE_PATH)
	if request_error != OK:
		_show_loading_error("Failed to start loading the main scene.")
		return

	while true:
		var progress: Array = []
		var load_status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(MAIN_SCENE_PATH, progress)
		var scene_progress: float = 0.0
		if not progress.is_empty():
			scene_progress = clampf(float(progress[0]), 0.0, 1.0)

		_show_loading_status("Loading main scene", scene_progress * SCENE_LOAD_PROGRESS_WEIGHT)

		if load_status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if load_status == ResourceLoader.THREAD_LOAD_FAILED or load_status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_show_loading_error("The main scene could not be loaded.")
			return

		await get_tree().process_frame

	var loaded_resource: Resource = ResourceLoader.load_threaded_get(MAIN_SCENE_PATH)
	if not loaded_resource is PackedScene:
		_show_loading_error("Loaded resource was not a scene.")
		return

	var main_scene: PackedScene = loaded_resource as PackedScene
	_game_scene = main_scene.instantiate()
	var procedural_map: Node = _game_scene.get_node_or_null("Procedural Map")
	var hud_layer: CanvasLayer = _game_scene.get_node_or_null("HUD") as CanvasLayer
	if procedural_map != null and "regenerate_on_ready" in procedural_map:
		procedural_map.regenerate_on_ready = false

	if _game_scene is Node3D:
		(_game_scene as Node3D).visible = false
	if hud_layer != null:
		hud_layer.visible = false

	get_tree().root.add_child(_game_scene)

	if procedural_map != null and procedural_map.has_signal("generation_stage_changed"):
		procedural_map.generation_stage_changed.connect(_on_generation_stage_changed)
	if procedural_map != null and procedural_map.has_signal("generation_visualization_updated"):
		procedural_map.generation_visualization_updated.connect(_on_generation_visualization_updated)

	if procedural_map != null and procedural_map.has_method("generate_map_with_loading"):
		_show_loading_status("Generating map", GENERATION_PROGRESS_START)
		await procedural_map.generate_map_with_loading()
	else:
		_show_loading_status("Finalizing setup", GENERATION_PROGRESS_END)
		await get_tree().process_frame

	_show_loading_status(READY_PROMPT, 1.0)
	await get_tree().process_frame
	await _wait_for_continue()

	if _game_scene is Node3D:
		(_game_scene as Node3D).visible = true
	if hud_layer != null:
		hud_layer.visible = true

	get_tree().current_scene = _game_scene
	queue_free()


func _on_generation_stage_changed(step_index: int, step_count: int, title: String, _description: String) -> void:
	var normalized_progress: float = 0.0
	if step_count > 0:
		normalized_progress = clampf(float(step_index) / float(step_count), 0.0, 1.0)

	var display_progress: float = lerpf(GENERATION_PROGRESS_START, GENERATION_PROGRESS_END, normalized_progress)
	_show_loading_status(title, display_progress)


func _on_generation_visualization_updated(snapshot: Dictionary) -> void:
	if _generation_visualizer == null:
		return
	if _generation_visualizer.has_method("apply_snapshot"):
		_generation_visualizer.call("apply_snapshot", snapshot)


func _warm_up_loading() -> void:
	for _i in range(LOADING_WARMUP_FRAMES):
		await get_tree().process_frame


func _show_loading_status(stage_title: String, progress: float) -> void:
	var safe_stage_title: String = stage_title
	if safe_stage_title.is_empty():
		safe_stage_title = "Loading"

	_subtitle_label.text = safe_stage_title
	_progress_bar.value = clampf(progress, 0.0, 1.0) * 100.0


func _show_loading_error(message: String) -> void:
	_waiting_for_continue = false
	_show_loading_status(message, 1.0)
	push_error(message)


func _apply_random_loading_palette() -> void:
	var combination_result: Dictionary = ColorCombinationPickerScript.get_random_combination()
	if combination_result.is_empty():
		return

	var color_values: Variant = combination_result.get("colors", [])
	var combination_colors: Array[Dictionary] = []
	if color_values is Array:
		for color_value in color_values:
			if color_value is Dictionary:
				combination_colors.append(color_value)

	var sorted_colors: Array[Dictionary] = ColorCombinationPickerScript.sort_colors_by_luminance(combination_colors)
	if sorted_colors.is_empty():
		return

	var darkest_entry: Dictionary = sorted_colors[0]
	if _background_rect != null:
		_background_rect.color = ColorCombinationPickerScript.get_color(darkest_entry)
	_populate_color_banner(sorted_colors)

	var visualization_palette: Dictionary = _build_visualization_palette(sorted_colors)
	if _generation_visualizer != null and _generation_visualizer.has_method("apply_palette"):
		_generation_visualizer.call("apply_palette", visualization_palette)
	_apply_progress_palette(visualization_palette)


func _build_visualization_palette(sorted_colors: Array[Dictionary]) -> Dictionary:
	var background_color: Color = ColorCombinationPickerScript.get_color(sorted_colors[0])
	var non_background_colors: Array[Color] = []
	for color_index in range(1, sorted_colors.size()):
		non_background_colors.append(ColorCombinationPickerScript.get_color(sorted_colors[color_index]))

	if non_background_colors.is_empty():
		non_background_colors.append(background_color.inverted())

	non_background_colors.shuffle()

	var remaining_colors: Array[Color] = non_background_colors.duplicate()
	var wall_color: Color = _take_next_palette_color(remaining_colors, _palette_color_at(non_background_colors, 0))
	var floor_primary_color: Color = _take_next_palette_color(remaining_colors, wall_color.darkened(0.14))
	var floor_secondary_color: Color = _take_next_palette_color(remaining_colors, floor_primary_color.darkened(0.38))
	var square_light_color: Color = floor_primary_color
	var square_dark_color: Color = floor_secondary_color
	if _color_luminance(square_dark_color) > _color_luminance(square_light_color):
		var swap_color: Color = square_light_color
		square_light_color = square_dark_color
		square_dark_color = swap_color

	var accent_color: Color = _take_next_palette_color(remaining_colors, square_light_color.lightened(0.06))
	var border_color: Color = _take_next_palette_color(remaining_colors, wall_color.lightened(0.1))
	var lava_color: Color = _choose_lava_palette_color(background_color, remaining_colors, non_background_colors)

	return {
		"screen_background_color": _with_alpha(background_color, 0.94),
		"screen_border_color": _with_alpha(border_color.lightened(0.1), 0.95),
		"room_fill_color": _with_alpha(square_dark_color.darkened(0.12), 1.0),
		"room_accent_fill_color": _with_alpha(accent_color, 1.0),
		"raw_room_stroke_color": _with_alpha(border_color.lightened(0.2), 0.95),
		"wall_cell_color": wall_color,
		"floor_lightest_cell_color": square_light_color,
		"floor_darkest_cell_color": square_dark_color,
		"lava_tint_color": _with_alpha(lava_color, 0.98)
	}


func _palette_color_at(colors: Array[Color], index: int) -> Color:
	if colors.is_empty():
		return Color.WHITE
	var safe_index: int = clampi(index, 0, colors.size() - 1)
	return colors[safe_index]


func _take_next_palette_color(colors: Array[Color], fallback: Color) -> Color:
	if colors.is_empty():
		return fallback

	var next_color: Color = colors[0]
	colors.remove_at(0)
	return next_color


func _choose_lava_palette_color(background_color: Color, remaining_colors: Array[Color], non_background_colors: Array[Color]) -> Color:
	if not remaining_colors.is_empty():
		return _take_next_palette_color(remaining_colors, background_color)
	if not non_background_colors.is_empty():
		return non_background_colors[0]
	return background_color


func _color_luminance(color_value: Color) -> float:
	return (0.2126 * color_value.r) + (0.7152 * color_value.g) + (0.0722 * color_value.b)


func _with_alpha(color_value: Color, alpha: float) -> Color:
	var adjusted_color: Color = color_value
	adjusted_color.a = alpha
	return adjusted_color


func _populate_color_banner(sorted_colors: Array[Dictionary]) -> void:
	if _banner_squares_vbox == null:
		return

	_banner_squares_vbox.add_theme_constant_override("separation", int(BANNER_SWATCH_SEPARATION))

	for child in _banner_squares_vbox.get_children():
		child.queue_free()

	var swatch_count: int = maxi(sorted_colors.size(), 1)
	var available_width: float = maxf(_banner_squares_vbox.size.x - BANNER_SWATCH_WIDTH_INSET, BANNER_SWATCH_FALLBACK_SIZE)
	var available_height: float = maxf(
		_banner_squares_vbox.size.y - (float(maxi(swatch_count - 1, 0)) * BANNER_SWATCH_SEPARATION),
		BANNER_SWATCH_FALLBACK_SIZE * float(swatch_count)
	)
	var swatch_side: float = minf(available_width, available_height / float(swatch_count))
	swatch_side = maxf(swatch_side, BANNER_SWATCH_MIN_SIZE)

	for color_entry in sorted_colors:
		var color_swatch: ColorRect = ColorRect.new()
		color_swatch.custom_minimum_size = Vector2(0.0, swatch_side)
		color_swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		color_swatch.color = ColorCombinationPickerScript.get_color(color_entry)
		_banner_squares_vbox.add_child(color_swatch)


func _apply_progress_palette(palette: Dictionary) -> void:
	if _progress_bar == null:
		return

	var background_color: Color = _palette_dictionary_color(palette, "room_fill_color", Color(0.0862745, 0.0980392, 0.121569, 0.88))
	var border_color: Color = _palette_dictionary_color(palette, "screen_border_color", Color(0.286275, 0.321569, 0.384314, 0.9))
	var fill_color: Color = _palette_dictionary_color(palette, "room_accent_fill_color", Color(0.85098, 0.611765, 0.345098, 0.96))
	var text_color: Color = _palette_dictionary_color(palette, "wall_cell_color", Color(0.972549, 0.964706, 0.94902, 1.0))

	var background_style: StyleBoxFlat = StyleBoxFlat.new()
	background_style.bg_color = background_color
	background_style.border_width_left = 1
	background_style.border_width_top = 1
	background_style.border_width_right = 1
	background_style.border_width_bottom = 1
	background_style.border_color = border_color
	background_style.corner_radius_top_left = PROGRESS_BAR_CORNER_RADIUS
	background_style.corner_radius_top_right = PROGRESS_BAR_CORNER_RADIUS
	background_style.corner_radius_bottom_right = PROGRESS_BAR_CORNER_RADIUS
	background_style.corner_radius_bottom_left = PROGRESS_BAR_CORNER_RADIUS

	var fill_style: StyleBoxFlat = StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.corner_radius_top_left = PROGRESS_BAR_CORNER_RADIUS
	fill_style.corner_radius_top_right = PROGRESS_BAR_CORNER_RADIUS
	fill_style.corner_radius_bottom_right = PROGRESS_BAR_CORNER_RADIUS
	fill_style.corner_radius_bottom_left = PROGRESS_BAR_CORNER_RADIUS

	_progress_bar.add_theme_stylebox_override("background", background_style)
	_progress_bar.add_theme_stylebox_override("fill", fill_style)
	_progress_bar.add_theme_color_override("font_color", text_color)


func _palette_dictionary_color(palette: Dictionary, key: String, fallback: Color) -> Color:
	var palette_value: Variant = palette.get(key, fallback)
	if palette_value is Color:
		return palette_value
	return fallback
