extends Camera3D

@export var spring_arm: Node3D
@export var easing: float = 10.0


func _process(delta: float) -> void:
	if spring_arm == null:
		return

	var weight: float = clamp(easing * delta, 0.0, 1.0)
	global_position = global_position.lerp(spring_arm.global_position, weight)