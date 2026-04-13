@tool
extends Node3D

## Spawns procedural walls in a grid pattern with randomized variations.
## Works in editor with @tool directive for instant preview.

@export_group("Grid Configuration")
@export var grid_width: int = 5:
	set(value):
		grid_width = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate_map")

@export var grid_depth: int = 5:
	set(value):
		grid_depth = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate_map")

@export var cell_size: float = 2.0:
	set(value):
		cell_size = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate_map")

@export_group("Randomization")
@export var random_seed: int = 12345:
	set(value):
		random_seed = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate_map")

@export_range(0.0, 1.0) var wall_density: float = 0.3:
	set(value):
		wall_density = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate_map")

@export_group("Wall Variation")
@export var min_base_height: float = 0.5
@export var max_base_height: float = 2.0
@export var min_corner_offset: float = -0.5
@export var max_corner_offset: float = 1.0
@export var min_base_radius: float = 0.3
@export var max_base_radius: float = 0.6
@export var min_top_radius: float = 0.05
@export var max_top_radius: float = 0.15
@export var min_top_inset: float = 0.0
@export var max_top_inset: float = 0.2

# Private variables
var _is_regenerating: bool = false
var _wall_scene: PackedScene
var _spawned_walls: Array = []


func _ready() -> void:
	# Load the wall scene
	_wall_scene = load("res://procedural_wall.tscn")
	
	if is_inside_tree():
		_regenerate_map()


## Regenerates the entire map when parameters change.
func _regenerate_map() -> void:
	if _is_regenerating:
		return
	
	if not is_inside_tree():
		return
	
	_is_regenerating = true
	_clear_walls()
	_spawn_walls()
	_is_regenerating = false


## Clears all previously spawned walls.
func _clear_walls() -> void:
	for wall in _spawned_walls:
		if is_instance_valid(wall):
			wall.queue_free()
	_spawned_walls.clear()
	
	# Also clear any direct children (in case queue_free hasn't processed yet)
	for child in get_children():
		child.queue_free()


## Spawns walls in a grid pattern with randomized parameters.
func _spawn_walls() -> void:
	if not _wall_scene:
		_wall_scene = load("res://procedural_wall.tscn")
		if not _wall_scene:
			push_error("ProceduralMap: Could not load procedural_wall.tscn!")
			return
	
	# Initialize random number generator with seed
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	
	# Spawn walls in grid pattern
	for x in range(grid_width):
		for z in range(grid_depth):
			# Check if we should spawn a wall here based on density
			if rng.randf() > wall_density:
				continue
			
			# Instantiate wall
			var wall: Node3D = _wall_scene.instantiate()
			add_child(wall)
			
			# Set owner for editor persistence
			if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
				wall.owner = get_tree().edited_scene_root
			
			# Position in grid (centered around origin)
			var offset_x: float = (grid_width - 1) * cell_size * 0.5
			var offset_z: float = (grid_depth - 1) * cell_size * 0.5
			wall.position = Vector3(
				x * cell_size - offset_x,
				0.0,
				z * cell_size - offset_z
			)
			
			# Randomize wall parameters
			_randomize_wall(wall, rng)
			
			# Force regeneration after all parameters are set (important for @tool scripts)
			if wall.has_method("_regenerate"):
				wall.call("_regenerate")
			
			_spawned_walls.append(wall)
	
	print("ProceduralMap: Spawned ", _spawned_walls.size(), " walls")


## Randomizes parameters of a wall instance.
func _randomize_wall(wall: Node3D, rng: RandomNumberGenerator) -> void:
	# Base height
	var base_h := rng.randf_range(min_base_height, max_base_height)
	wall.base_height = base_h
	
	# Corner height offsets (ensure variety)
	wall.corner_nw_offset = rng.randf_range(min_corner_offset, max_corner_offset)
	wall.corner_ne_offset = rng.randf_range(min_corner_offset, max_corner_offset)
	wall.corner_sw_offset = rng.randf_range(min_corner_offset, max_corner_offset)
	wall.corner_se_offset = rng.randf_range(min_corner_offset, max_corner_offset)
	
	# Individual pillar radii (each corner gets unique values)
	wall.corner_nw_base_radius = rng.randf_range(min_base_radius, max_base_radius)
	wall.corner_nw_top_radius = rng.randf_range(min_top_radius, max_top_radius)
	
	wall.corner_ne_base_radius = rng.randf_range(min_base_radius, max_base_radius)
	wall.corner_ne_top_radius = rng.randf_range(min_top_radius, max_top_radius)
	
	wall.corner_sw_base_radius = rng.randf_range(min_base_radius, max_base_radius)
	wall.corner_sw_top_radius = rng.randf_range(min_top_radius, max_top_radius)
	
	wall.corner_se_base_radius = rng.randf_range(min_base_radius, max_base_radius)
	wall.corner_se_top_radius = rng.randf_range(min_top_radius, max_top_radius)
	
	# Pillar top insets (creates leaning/converging effects)
	wall.corner_nw_top_inset = rng.randf_range(min_top_inset, max_top_inset)
	wall.corner_ne_top_inset = rng.randf_range(min_top_inset, max_top_inset)
	wall.corner_sw_top_inset = rng.randf_range(min_top_inset, max_top_inset)
	wall.corner_se_top_inset = rng.randf_range(min_top_inset, max_top_inset)
	
	# Debug output for first few walls
	if _spawned_walls.size() < 3:
		print("Wall #", _spawned_walls.size(), " - Base: ", base_h, 
			" NW radius: ", wall.corner_nw_base_radius, 
			" NE radius: ", wall.corner_ne_base_radius)
