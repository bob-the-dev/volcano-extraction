extends Control

const GENERATION_VISUALIZER_SCENE: PackedScene = preload("res://generation_visualizer.tscn")

var _generation_visualizer: Control = null
var _grid_background: ColorRect = null
var _visualization_surface: Control = null
var _border_panel: Panel = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_surface()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		return


func reset_visualization() -> void:
	if _generation_visualizer != null and _generation_visualizer.has_method("reset_visualization"):
		_generation_visualizer.call("reset_visualization")


func apply_snapshot(snapshot: Dictionary) -> void:
	if _generation_visualizer != null and _generation_visualizer.has_method("apply_snapshot"):
		_generation_visualizer.call("apply_snapshot", snapshot)


func apply_palette(palette: Dictionary) -> void:
	if palette.is_empty():
		return

	var background_value: Variant = palette.get("screen_background_color", null)
	if _grid_background != null and background_value is Color:
		_grid_background.color = background_value

	var border_value: Variant = palette.get("screen_border_color", null)
	if _border_panel != null and border_value is Color:
		_border_panel.add_theme_stylebox_override("panel", _create_border_stylebox(border_value))

	if _generation_visualizer != null and _generation_visualizer.has_method("apply_palette"):
		_generation_visualizer.call("apply_palette", palette)


func _build_surface() -> void:
	if _visualization_surface != null:
		return

	var center_container: CenterContainer = CenterContainer.new()
	center_container.name = "CenterContainer"
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_container.grow_vertical = Control.GROW_DIRECTION_BOTH
	center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center_container)

	_visualization_surface = Control.new()
	_visualization_surface.name = "VisualizationSurface"
	_visualization_surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	_visualization_surface.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_visualization_surface.grow_vertical = Control.GROW_DIRECTION_BOTH
	_visualization_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_visualization_surface)

	_border_panel = Panel.new()
	_border_panel.name = "BorderPanel"
	_border_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_border_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_border_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_border_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_border_panel.add_theme_stylebox_override("panel", _create_border_stylebox(Color(0.92, 0.97, 1.0, 0.95)))
	_visualization_surface.add_child(_border_panel)

	_grid_background = ColorRect.new()
	_grid_background.name = "GridBackground"
	_grid_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grid_background.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_grid_background.grow_vertical = Control.GROW_DIRECTION_BOTH
	_grid_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_background.color = Color(0.035, 0.073, 0.145, 0.94)
	_visualization_surface.add_child(_grid_background)

	_generation_visualizer = GENERATION_VISUALIZER_SCENE.instantiate() as Control
	if _generation_visualizer == null:
		return

	_generation_visualizer.name = "GenerationVisualizer"
	_generation_visualizer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_generation_visualizer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_generation_visualizer.grow_vertical = Control.GROW_DIRECTION_BOTH
	_generation_visualizer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visualization_surface.add_child(_generation_visualizer)


func _create_border_stylebox(border_color: Color) -> StyleBoxFlat:
	var stylebox: StyleBoxFlat = StyleBoxFlat.new()
	stylebox.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	stylebox.border_width_left = 2
	stylebox.border_width_top = 2
	stylebox.border_width_right = 2
	stylebox.border_width_bottom = 2
	stylebox.border_color = border_color
	return stylebox
