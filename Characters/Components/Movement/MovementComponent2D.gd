extends Node
class_name MovementComponent2D
## Sole authority for applying velocity and CharacterBody2D movement.

const CharacterContext2D = preload("res://Characters/Core/CharacterContext2D.gd")

var context: CharacterContext2D
var move_speed: float = 200.0
var _initialized := false

func initialize(shared_context: CharacterContext2D, speed: float = 200.0) -> void:
	context = shared_context
	move_speed = maxf(speed, 0.0)
	_initialized = context != null and context.character is CharacterBody2D
	if not _initialized:
		push_error("MovementComponent2D requires a valid CharacterContext2D.")

func set_move_speed(value: float) -> void:
	move_speed = maxf(value, 0.0)

func physics_update(_delta: float) -> void:
	if not _initialized:
		return
	var body := context.character
	# Duck-typed on purpose: referencing Character2D here would create a script cycle.
	if body.has_method("is_alive") and not bool(body.call("is_alive")):
		body.velocity = Vector2.ZERO
		body.move_and_slide()
		return
	body.velocity = context.dash_velocity if context.is_dashing else context.movement_input * move_speed
	body.move_and_slide()
