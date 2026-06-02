extends Node3D

@export_group("Interaction")
@export var interact_action: String = "ui_accept"
@export var interaction_distance: float = 3.6
@export var ready_prompt_text: String = "Press Space to leave safely"
@export var blocked_prompt_text: String = "Rescue the stranded visitor first"
@export var extracting_prompt_text: String = "Leaving the level..."

@onready var prompt_label: Label3D = $PromptLabel

var procedural_map: Node3D = null
var player: CharacterBody3D = null
var _is_extracting: bool = false


func _ready() -> void:
	add_to_group("exit_point")
	_resolve_dependencies()
	if prompt_label != null:
		prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		prompt_label.visible = false


func _physics_process(_delta: float) -> void:
	_resolve_dependencies()
	if player == null:
		if prompt_label != null:
			prompt_label.visible = false
		return

	var player_distance: float = _get_horizontal_distance_to(player.global_position)
	var is_in_range: bool = player_distance <= interaction_distance
	if prompt_label != null:
		prompt_label.visible = is_in_range

	if not is_in_range:
		return

	var extraction_available: bool = _can_extract()
	if prompt_label != null:
		if _is_extracting:
			prompt_label.text = extracting_prompt_text
		elif extraction_available:
			prompt_label.text = ready_prompt_text
		else:
			prompt_label.text = blocked_prompt_text

	if _is_extracting or not Input.is_action_just_pressed(interact_action):
		return

	if extraction_available and _try_extract():
		_is_extracting = true
		if prompt_label != null:
			prompt_label.text = extracting_prompt_text


func set_procedural_map(map_node: Node3D) -> void:
	procedural_map = map_node


func _resolve_dependencies() -> void:
	if procedural_map == null:
		procedural_map = get_parent() as Node3D

	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D


func _can_extract() -> bool:
	if procedural_map != null and procedural_map.has_method("can_player_extract"):
		return bool(procedural_map.call("can_player_extract"))
	return false


func _try_extract() -> bool:
	if procedural_map != null and procedural_map.has_method("try_extract_player"):
		return bool(procedural_map.call("try_extract_player"))

	var reload_error: Error = get_tree().reload_current_scene()
	if reload_error != OK:
		push_error("Failed to reload the current scene from the exit point.")
		return false
	return true


func _get_horizontal_distance_to(target_world_position: Vector3) -> float:
	var current_xz: Vector2 = Vector2(global_position.x, global_position.z)
	var target_xz: Vector2 = Vector2(target_world_position.x, target_world_position.z)
	return current_xz.distance_to(target_xz)