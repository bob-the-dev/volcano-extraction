extends Control

const MAIN_SCENE_PATH: String = "res://main.tscn"
const SCENE_LOAD_PROGRESS_WEIGHT: float = 0.18
const GENERATION_PROGRESS_START: float = 0.2
const GENERATION_PROGRESS_END: float = 0.96
const MIN_STAGE_DISPLAY_SECONDS: float = 1.0
const PREVIEW_WARMUP_FRAMES: int = 2

@onready var _headline_label: Label = $MarginContainer/HBoxContainer/InfoPanel/MarginContainer/VBoxContainer/HeadlineLabel
@onready var _stage_title_label: Label = $MarginContainer/HBoxContainer/InfoPanel/MarginContainer/VBoxContainer/StageTitleLabel
@onready var _stage_description_label: Label = $MarginContainer/HBoxContainer/InfoPanel/MarginContainer/VBoxContainer/StageDescriptionLabel
@onready var _progress_bar: ProgressBar = $MarginContainer/HBoxContainer/InfoPanel/MarginContainer/VBoxContainer/ProgressBar
@onready var _progress_label: Label = $MarginContainer/HBoxContainer/InfoPanel/MarginContainer/VBoxContainer/ProgressLabel
@onready var _continue_label: Label = $MarginContainer/HBoxContainer/InfoPanel/MarginContainer/VBoxContainer/ContinueLabel
@onready var _preview_pivot: Node3D = $MarginContainer/HBoxContainer/PreviewPanel/SubViewportContainer/SubViewport/PreviewRoot/PreviewPivot

var _game_scene: Node = null
var _waiting_for_continue: bool = false
var _continue_requested: bool = false
var _preview_time: float = 0.0
var _preview_base_position: Vector3 = Vector3.ZERO
var _preview_base_rotation: Vector3 = Vector3.ZERO
var _last_stage_change_time_seconds: float = -MIN_STAGE_DISPLAY_SECONDS
var _last_stage_title: String = ""
var _last_stage_description: String = ""


func _ready() -> void:
	_preview_base_position = _preview_pivot.position
	_preview_base_rotation = _preview_pivot.rotation
	_progress_bar.value = 0.0
	_continue_label.visible = false
	_set_loading_status(
		"Preparing the island",
		"Opening the crate and checking whether the volcano signed the waiver this time.",
		0.02
	)
	call_deferred("_boot_game")


func _process(delta: float) -> void:
	_preview_time += delta
	_preview_pivot.position = _preview_base_position + Vector3(0.0, sin(_preview_time * 1.35) * 0.18, 0.0)
	_preview_pivot.rotation = Vector3(
		_preview_base_rotation.x + (sin(_preview_time * 0.9) * 0.045),
		_preview_base_rotation.y + (_preview_time * 0.55),
		_preview_base_rotation.z + (cos(_preview_time * 1.1) * 0.035)
	)
	if _waiting_for_continue:
		var pulse_alpha: float = 0.55 + (0.45 * (0.5 + (0.5 * sin(Time.get_ticks_msec() * 0.006))))
		_continue_label.modulate.a = pulse_alpha
	else:
		_continue_label.modulate.a = 0.0


func _input(event: InputEvent) -> void:
	if not _waiting_for_continue or _continue_requested:
		return

	if event is InputEventKey and event.pressed and not event.echo:
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
	_continue_label.visible = true
	while not _continue_requested:
		await get_tree().process_frame
	_waiting_for_continue = false
	_continue_label.visible = false


func _boot_game() -> void:
	await _warm_up_preview()

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

		await _show_loading_status(
			"Unpacking the emergency route",
			"Convincing the island to reveal where the safe-ish ground used to be.",
			scene_progress * SCENE_LOAD_PROGRESS_WEIGHT
		)

		if load_status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if load_status == ResourceLoader.THREAD_LOAD_FAILED or load_status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_show_loading_error("The main scene refused to come out of the crate.")
			return

		await get_tree().process_frame

	var loaded_resource: Resource = ResourceLoader.load_threaded_get(MAIN_SCENE_PATH)
	if not loaded_resource is PackedScene:
		_show_loading_error("Loaded something, but it was not the game scene.")
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

	if procedural_map != null and procedural_map.has_method("generate_map_with_loading"):
		await _show_loading_status(
			"Waking the crater",
			"Asking the mountain to build a maze without taking it personally.",
			GENERATION_PROGRESS_START
		)
		await procedural_map.generate_map_with_loading()
	else:
		await _show_loading_status(
			"Skipping the grand tour",
			"The map generator declined to narrate its feelings.",
			GENERATION_PROGRESS_END
		)
		await get_tree().process_frame

	await _show_loading_status(
		"Sealing the harness",
		"Everything looks survivable from exactly this one flattering angle. Press any key when you are emotionally prepared.",
		1.0
	)
	await get_tree().process_frame
	await _wait_for_continue()

	if _game_scene is Node3D:
		(_game_scene as Node3D).visible = true
	if hud_layer != null:
		hud_layer.visible = true

	get_tree().current_scene = _game_scene
	queue_free()


func _on_generation_stage_changed(step_index: int, step_count: int, title: String, description: String) -> void:
	await _wait_for_minimum_stage_time()

	var normalized_progress: float = 0.0
	if step_count > 0:
		normalized_progress = clampf(float(step_index) / float(step_count), 0.0, 1.0)

	var display_progress: float = lerpf(GENERATION_PROGRESS_START, GENERATION_PROGRESS_END, normalized_progress)
	_set_loading_status(title, description, display_progress)


func _warm_up_preview() -> void:
	for _i in range(PREVIEW_WARMUP_FRAMES):
		await get_tree().process_frame


func _wait_for_minimum_stage_time() -> void:
	var elapsed_seconds: float = Time.get_ticks_msec() * 0.001 - _last_stage_change_time_seconds
	if elapsed_seconds >= MIN_STAGE_DISPLAY_SECONDS:
		return

	while Time.get_ticks_msec() * 0.001 - _last_stage_change_time_seconds < MIN_STAGE_DISPLAY_SECONDS:
		await get_tree().process_frame


func _show_loading_status(stage_title: String, stage_description: String, progress: float) -> void:
	var is_new_message: bool = stage_title != _last_stage_title or stage_description != _last_stage_description
	if is_new_message:
		await _wait_for_minimum_stage_time()
	_set_loading_status(stage_title, stage_description, progress)


func _set_loading_status(stage_title: String, stage_description: String, progress: float) -> void:
	_stage_title_label.text = stage_title
	_stage_description_label.text = stage_description
	_progress_bar.value = clampf(progress, 0.0, 1.0) * 100.0
	_progress_label.text = "%d%% ready for extraction" % int(round(_progress_bar.value))
	_headline_label.text = "Preparing the island"
	if stage_title != _last_stage_title or stage_description != _last_stage_description:
		_last_stage_change_time_seconds = Time.get_ticks_msec() * 0.001
		_last_stage_title = stage_title
		_last_stage_description = stage_description


func _show_loading_error(message: String) -> void:
	_waiting_for_continue = false
	_continue_label.visible = false
	_set_loading_status("Loading stalled", message, 1.0)
	push_error(message)
