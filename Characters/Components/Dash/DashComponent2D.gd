extends Node
class_name DashComponent2D
## Owns dash timing/cooldown; movement remains centralized in MovementComponent2D.

signal dash_started(direction: Vector2)
signal dash_ended

@export_range(0.0, 3000.0, 1.0) var dash_speed: float = 600.0
@export_range(0.01, 2.0, 0.01) var dash_duration: float = 0.16
@export_range(0.0, 5.0, 0.05) var dash_cooldown: float = 0.45

var context: CharacterContext2D
var _remaining_duration := 0.0
var _cooldown_remaining := 0.0
var _initialized := false

func initialize(shared_context: CharacterContext2D) -> void:
	context = shared_context
	_initialized = context != null and context.character is CharacterBody2D
	if not _initialized:
		push_error("DashComponent2D requires a valid CharacterContext2D.")

func try_start(requested: bool, direction: Vector2 = Vector2.ZERO) -> bool:
	if not _initialized or not requested or context.is_dashing or context.is_attacking or context.is_casting or context.hit_stun_remaining > 0.0 or _cooldown_remaining > 0.0:
		return false
	var dash_direction := _resolve_direction(direction)
	context.is_dashing = true
	context.dash_velocity = dash_direction * maxf(dash_speed, 0.0)
	_remaining_duration = maxf(dash_duration, 0.01)
	_cooldown_remaining = maxf(dash_cooldown, 0.0)
	dash_started.emit(dash_direction)
	return true

## Starts a dash for an active skill (13.3.3) with the skill's own speed and duration. The skill owns its cooldown, so this
## neither checks nor starts this component's dash cooldown. It is refused (Vector2.ZERO) while dashing, attacking,
## casting or stunned; otherwise it returns the direction the dash goes in (the given one, else the movement input, else
## the facing, else right). Movement is still applied by MovementComponent2D through context.dash_velocity.
func start_skill_dash(direction: Vector2, speed: float, duration: float) -> Vector2:
	if not _initialized or context.is_dashing or context.is_attacking or context.is_casting or context.hit_stun_remaining > 0.0:
		return Vector2.ZERO
	var dash_direction := _resolve_direction(direction)
	context.is_dashing = true
	context.dash_velocity = dash_direction * maxf(speed, 0.0)
	_remaining_duration = maxf(duration, 0.01)
	dash_started.emit(dash_direction)
	return dash_direction

func _resolve_direction(direction: Vector2) -> Vector2:
	var dash_direction := direction.normalized()
	if dash_direction.length_squared() < 0.0001:
		dash_direction = context.movement_input.normalized()
	if dash_direction.length_squared() < 0.0001:
		dash_direction = context.facing_direction.normalized()
	if dash_direction.length_squared() < 0.0001:
		dash_direction = Vector2.RIGHT
	return dash_direction

func physics_update(delta: float) -> void:
	if not _initialized:
		return
	_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)
	if not context.is_dashing:
		return
	_remaining_duration -= delta
	if _remaining_duration <= 0.0:
		context.is_dashing = false
		context.dash_velocity = Vector2.ZERO
		dash_ended.emit()

func cancel() -> void:
	if not _initialized:
		return
	var was_dashing: bool = context.is_dashing
	context.is_dashing = false
	context.dash_velocity = Vector2.ZERO
	_remaining_duration = 0.0
	if was_dashing:
		dash_ended.emit()

func is_on_cooldown() -> bool:
	return _cooldown_remaining > 0.0
