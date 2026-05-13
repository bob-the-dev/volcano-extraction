Hi everyone! 👣

I wanted to share a simple footprint system I made for a 2D top-down game using Godot 4. I was looking for a way to make the player leave fading footprints while walking, but I couldn’t find much information or examples on how to do it. So I decided to make my own version and share it in case it helps someone else!

The script is fully functional (although it might have some small things to improve), and it creates footprints at regular intervals while the player is moving. They fade out over time and are removed once a maximum number is reached.

The footprints themselves are instances of a simple scene made with a Sprite2D, using a footprint texture — it's the same sprite repeated each time a step is made.

For demonstration purposes, I added the logic directly into the player node, but it can easily be made into its own scene or reusable component if needed.

Hope this helps someone out there! And if you have suggestions to improve it, feel free to share!

```
footprint showcase
class_name Player
extends CharacterBody2D

# Direction of the player's movement.

var player_direction: Vector2

# Maximum number of footprints allowed.

@export var max_footprints := 10

# Spacing between consecutive footprints.

@export var footprint_spacing := 0.25

# Lifetime of each footprint before fading out.

@export var footprint_lifetime := 2.0 # Time until disappearance

# Scene for footprint instantiation.

var footprint_scene = preload("res://scenes/foot_print.tscn")

# Container node for footprints.

var footprint_container: Node

# Time accumulator for spacing footprints.

var time := 0.0

func \_ready():

# Create a container to organize footprints.

footprint_container = Node2D.new()
footprint_container.name = "FootprintContainer"
get_tree().current_scene.add_child.call_deferred(footprint_container)

func \_process(delta):

# Only create footprints when moving.

if velocity.length() == 0:
return

time += delta

# Create new footprint if enough time has passed.

if time >= footprint_spacing:
time = 0.0
create_footprint()
clean_old_footprints()

func create_footprint():

# Instantiate a footprint scene.

var footprint = footprint_scene.instantiate()
footprint_container.add_child(footprint)

# Calculate movement direction.

var move_direction = velocity.normalized()

# Add slight offset to avoid overlapping with player.

var \_move_direction = move_direction # Adjust this based on your sprite
var offset = Vector2(randf_range(-1, 1), randf_range(-1, 1))

# Position footprint slightly offset from player.

footprint.global_position = global_position + offset
footprint.global_position.y = footprint.global_position.y + 7 # Specific adjustments for my sprite (you can omit or change this)

# Rotate footprint based on movement direction.

if velocity.length() > 0:
footprint.global_rotation = velocity.angle() + deg_to_rad(90)
else:
footprint.global_rotation = global_rotation # Use current rotation if stationary

# Configure fading effect.

var tween = create_tween()
tween.tween_property(footprint, "modulate:a", 0.0, footprint_lifetime)
tween.tween_callback(footprint.queue_free)

func clean_old_footprints():

# Limit the number of footprints.

if footprint_container.get_child_count() > max_footprints:
var oldest = footprint_container.get_children()[0]
oldest.queue_free()
```
