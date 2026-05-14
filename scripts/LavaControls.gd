extends PanelContainer

## Simple HUD controls for raising and lowering the procedural lava level.

@onready var _raise_button: Button = $MarginContainer/HBoxContainer/RaiseButton
@onready var _value_label: Label = $MarginContainer/HBoxContainer/ValueLabel
@onready var _lower_button: Button = $MarginContainer/HBoxContainer/LowerButton

var _procedural_map: Node = null


func _ready() -> void:
	anchors_preset = Control.PRESET_TOP_LEFT
	offset_left = 16.0
	offset_top = 16.0

	_raise_button.pressed.connect(_on_raise_pressed)
	_lower_button.pressed.connect(_on_lower_pressed)

	call_deferred("_initialize_controls")


func _process(_delta: float) -> void:
	if _procedural_map != null:
		_update_label()


func _initialize_controls() -> void:
	var procedural_maps: Array = get_tree().get_nodes_in_group("procedural_map")
	if not procedural_maps.is_empty():
		_procedural_map = procedural_maps[0]

	_update_controls_state()
	_update_label()


func _update_controls_state() -> void:
	var has_map: bool = _procedural_map != null
	_raise_button.disabled = not has_map
	_lower_button.disabled = not has_map


func _update_label() -> void:
	if _procedural_map == null:
		_value_label.text = "Lava unavailable"
		return

	var current_level: float = 0.0
	var target_level: float = 0.0
	if _procedural_map.has_method("get_lava_height_level"):
		current_level = float(_procedural_map.call("get_lava_height_level"))
	if _procedural_map.has_method("get_target_lava_height_level"):
		target_level = float(_procedural_map.call("get_target_lava_height_level"))
	else:
		target_level = current_level

	_value_label.text = "Lava %.2f -> %.2f" % [current_level, target_level]


func _on_raise_pressed() -> void:
	if _procedural_map == null:
		return

	_procedural_map.call("raise_lava_height")
	_update_label()


func _on_lower_pressed() -> void:
	if _procedural_map == null:
		return

	_procedural_map.call("lower_lava_height")
	_update_label()
