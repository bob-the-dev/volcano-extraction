# Godot Game Development Guidelines for AI Assistants

## Project Context

- **Engine:** Godot 4.5 (GDScript 2.0)
- **Game Name:** Volcano Extraction
- **Game Type:** 3D action/exploration game
- **Key Systems:** Character movement, enemy AI with navigation, camera management
- **Player Character:** Blobby figure without distinct head/neck separation, has distinct arms with 4-fingered hands (not compatible with Mixamo auto-rigging)

## Current Work in Progress

**Status:** Rigging fatman character in Blender (March 15, 2026)

**Completed Phases:**

- ✅ Phase 1: Preparation & Understanding
  - Downloaded Mixamo Y Bot reference rig (y_bot.fbx)
  - Understood current character structure (Skin modifier ≠ rigging)
  - Learned essential Blender hotkeys (Tab, Shift+A, G/R/S, Alt+Z, Ctrl+A for skin resize)
  - Fixed mirror modifier issues on fatman character

**Next Step:**

- 📍 **Phase 2, Step 2.1:** Import Mixamo FBX into new Blender file to study bone structure
  - Location: `blender/mixamo_reference/y_bot.fbx`
  - Action: File → Import → FBX in new Blender window
  - Goal: Study professional bone hierarchy for manual rig creation

**Remaining Phases:**

- Phase 2 (remainder): Study Mixamo bone structure and hierarchy
- Phase 3: Create custom armature for fatman (spine chain + arms + 4-finger hands)
- Phase 4: Weight painting (parent mesh to armature)
- Phase 5: Add Mixamo animations via retargeting
- Phase 6: Export to Godot
- Phase 7: Verification & testing

**Reference:** Full detailed plan saved in `/memories/session/plan.md`

**Working Files:**

- `blender/fatman.blend` - Character mesh (ready for rigging)
- `blender/mixamo_reference/y_bot.fbx` - Bone structure reference
- `playable_fatman.tscn` - Godot scene (will update with rigged version)

---

## Code Style & Conventions

### GDScript Standards

- **Always use type hints** for variables and function returns: `var speed: float = 5.0`, `func get_position() -> Vector3:`
- **Prefer `@export`** for inspector-editable variables
- **Use `@onready`** for node references to avoid null references in `_ready()`
- **Group related exports** with `@export_group("Group Name")`
- **Naming conventions:**
  - PascalCase for classes and scene names
  - snake_case for functions, variables, and signals
  - SCREAMING_SNAKE_CASE for constants
  - Private members prefix with underscore: `_private_var`

### Node & Scene Patterns

- Cache node references with `@onready var player: CharacterBody3D = $Player`
- Avoid `get_node()` or `$` in loops - cache references instead
- Use `queue_free()` instead of direct deletion
- Prefer scene composition over inheritance
- Use unique names (`%NodeName`) for important nodes you'll reference frequently

### Signal Best Practices

- Define signals at the top of scripts with descriptive names
- Use signals for decoupled communication between nodes
- Document signal parameters with comments
- Connect signals in `_ready()` or use the editor

## Godot-Specific Best Practices

### Physics & Movement

- Use `_physics_process(delta)` for movement and physics calculations
- Use `_process(delta)` for non-physics logic (UI updates, timers, etc.)
- Always check `is_on_floor()` before allowing jumps
- Use `move_and_slide()` for character controllers (handles collision automatically)
- Apply gravity in `_physics_process()` before movement: `velocity += get_gravity() * delta`
- Use `lerp()` and `move_toward()` for smooth transitions

### Performance Considerations

- Cache expensive calculations and node lookups
- Use object pooling for frequently spawned objects (projectiles, particles)
- Minimize `get_node()` calls - use `@onready` instead
- Avoid string comparisons in hot paths
- Use `is_instance_valid()` before accessing potentially freed nodes
- Profile with Godot's built-in profiler before optimizing

### Resource Management

- Use `preload()` for assets needed at compile time
- Use `load()` for runtime asset loading
- Create `.tres` resource files for reusable data
- Free resources when no longer needed to prevent memory leaks

## Current Project Addons

### Phantom Camera

- Advanced camera management system
- Autoloaded as `PhantomCameraManager`
- Provides smooth camera transitions and following
- Configure camera behavior through inspector properties

### Proto Controller

- Custom input handling addon
- Located in `res://addons/proto_controller/`

## Architecture Guidelines

### Player Controller

- Base class: `CharacterBody3D`
- Handle input in `_physics_process()`
- Support configurable input actions via `@export var input_jump: String = "jump"`
- Implement state machine for complex behaviors (idle, walking, jumping, etc.)

### Enemy AI

- Use `NavigationAgent3D` for pathfinding
- Throttle path recalculation (don't update every frame - use timers)
- Check `is_navigation_finished()` before moving
- Enable avoidance for multiple agents
- Verify enemies are on nav mesh with `NavigationServer3D.map_get_closest_point()`

### Procedural Generation

- Use `FastNoiseLite` for noise-based generation
- Generate in chunks/regions for performance
- Use `await` for texture generation to prevent freezing
- Store generation parameters for reproducibility

## When Suggesting Code

### Always Provide

- Complete, working GDScript functions (not pseudocode)
- Proper type hints for all variables and returns
- Comments explaining complex logic
- Error handling for common edge cases
- Always check for types, as infering won't work every time.

### Consider Context

- Suggest appropriate node types for the task
- Recommend scene structure when relevant
- Mention inspector properties that need configuration
- Warn about performance implications for expensive operations

### Code Template Example

```gdscript
extends CharacterBody3D

## Brief description of what this script does.

# Signals
signal health_changed(new_health: int)
signal died()

# Constants
const MAX_HEALTH: int = 100

# Exports
@export_group("Movement")
@export var move_speed: float = 5.0
@export var jump_velocity: float = 4.5

# Private variables
@onready var _animation_player: AnimationPlayer = $AnimationPlayer
var _current_health: int = MAX_HEALTH


func _ready() -> void:
	# Initialization code
	pass


func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle movement
	move_and_slide()


## Takes damage and emits signals.
func take_damage(amount: int) -> void:
	_current_health -= amount
	health_changed.emit(_current_health)

	if _current_health <= 0:
		died.emit()
```

## Common Tasks & Patterns

### Implementing a Timer

```gdscript
var _timer: float = 0.0
const COOLDOWN: float = 1.5

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= COOLDOWN:
		_timer = 0.0
		# Do timed action
```

### Input Handling

```gdscript
func _physics_process(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
```

## Testing & Debugging

- Use `print()` and `print_debug()` for logging
- Enable debug visualization: Debug → Visible Collision Shapes / Navigation
- Use `assert()` for development-time checks
- Test in both editor and standalone builds
- Check console for errors and warnings

## Off limits

- Do not ever update content in addons, as long as you are not instructed to do so.
- Updating .tscn while godot is running is a no go, as long as you are not instructed to do so, as it seems the editor will automatically override most of the changes.

## Version Control

- Commit `.import` files (required for asset metadata)
- `.gitignore` should exclude `.godot/` folder
- Scene files (`.tscn`) are text-based and diff-friendly
- Prefer text-based resources over binary when possible
