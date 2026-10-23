extends Node
class_name MovementComponent2D
## Sole authority for applying velocity and CharacterBody2D movement.

@export_range(0.0, 2000.0, 1.0) var move_speed: float = 200.0:
	set(value):
		move_speed = maxf(value, 0.0)

var context: CharacterContext2D
var _initialized := false

func initialize(shared_context: CharacterContext2D) -> void:
	context = shared_context
	_initialized = context != null and context.character is CharacterBody2D
	if not _initialized:
		push_error("MovementComponent2D requires a valid CharacterContext2D.")

func physics_update(_delta: float) -> void:
	if not _initialized:
		return
	var body := context.character
	# Duck-typed on purpose: referencing Character2D here would create a script cycle.
	if body.has_method("is_alive") and not bool(body.call("is_alive")):
		body.velocity = Vector2.ZERO
		body.move_and_slide()
		return
	var base_velocity: Vector2 = context.dash_velocity if context.is_dashing else context.movement_input * move_speed * context.move_multiplier
	body.velocity = base_velocity + context.knockback_velocity
	body.move_and_slide()
