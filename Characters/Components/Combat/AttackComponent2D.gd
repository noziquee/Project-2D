extends Node
class_name AttackComponent2D
## Coordinates the attack lifecycle; authored weapon animation calls spawn_slash().

const CharacterContext2D = preload("res://Characters/Core/CharacterContext2D.gd")
const SLASH_ANIMATION := &"slash"
const RETURN_ANIMATION := &"sword_return"

signal attack_started(direction: Vector2)
signal attack_hit(target: Node, damage: int)
signal attack_finished

var context: CharacterContext2D
var definition: AttackDefinition2D
var slash_scene: PackedScene
var _cooldown_remaining := 0.0
var _initialized := false
var _active_slash: AttackSlash2D

func initialize(shared_context: CharacterContext2D, attack_definition: AttackDefinition2D, configured_slash_scene: PackedScene) -> void:
	context = shared_context
	definition = attack_definition
	slash_scene = configured_slash_scene
	_initialized = (
		context != null
		and context.character is CharacterBody2D
		and definition != null
		and slash_scene != null
		and is_instance_valid(context.weapon_animation_player)
		and slash_scene.can_instantiate()
	)
	if not _initialized:
		push_error("AttackComponent2D needs a character context, attack definition, slash scene, and weapon AnimationPlayer.")
		return

	var player := context.weapon_animation_player
	if not player.has_animation(SLASH_ANIMATION) or not player.has_animation(RETURN_ANIMATION):
		push_error("AttackComponent2D: weapon AnimationPlayer needs '%s' and '%s' clips." % [SLASH_ANIMATION, RETURN_ANIMATION])
		_initialized = false
		return
	if not player.animation_finished.is_connected(_on_weapon_animation_finished):
		player.animation_finished.connect(_on_weapon_animation_finished)


func set_attack_definition(new_definition: AttackDefinition2D) -> void:
	if new_definition != null:
		definition = new_definition

func set_slash_scene(new_scene: PackedScene) -> void:
	if new_scene != null and new_scene.can_instantiate():
		slash_scene = new_scene
	else:
		push_warning("AttackComponent2D ignored an invalid slash scene assignment.")

func try_start(requested: bool, direction: Vector2 = Vector2.ZERO) -> bool:
	if not _initialized or not requested or context.is_attacking or context.is_dashing or _cooldown_remaining > 0.0:
		return false
	var attack_direction := direction.normalized()
	if attack_direction.length_squared() < 0.0001:
		attack_direction = context.aim_direction.normalized()
	if attack_direction.length_squared() < 0.0001:
		attack_direction = context.facing_direction.normalized()
	if attack_direction.length_squared() < 0.0001:
		attack_direction = Vector2.RIGHT

	context.attack_direction = attack_direction
	context.aim_direction = attack_direction
	context.is_attacking = true
	_cooldown_remaining = maxf(definition.cooldown_duration, _weapon_cycle_duration())
	context.weapon_animation_player.play(SLASH_ANIMATION)
	attack_started.emit(attack_direction)
	return true

func physics_update(delta: float) -> void:
	if _initialized:
		_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)

## Called by the existing authored weapon animation method track.
func spawn_slash_from_animation() -> void:
	if not _initialized or not context.is_attacking:
		return
	if is_instance_valid(_active_slash):
		_active_slash.queue_free()
	var slash := slash_scene.instantiate() as AttackSlash2D
	if slash == null:
		push_error("AttackComponent2D: configured slash root must have AttackSlash2D.gd.")
		return
	slash.configure(context.character, definition.damage, context.attack_direction, definition.hitbox_size, definition.hitbox_offset)
	slash.hit_confirmed.connect(_on_slash_hit)
	var host: Node = context.character.get_tree().current_scene
	if host == null:
		host = context.character.get_parent()
	if host == null:
		host = context.character
	host.add_child(slash)
	slash.global_position = context.character.global_position
	_active_slash = slash

func cancel() -> void:
	if is_instance_valid(_active_slash):
		_active_slash.queue_free()
	_active_slash = null
	if context == null:
		return
	context.is_attacking = false
	if is_instance_valid(context.weapon_animation_player):
		context.weapon_animation_player.stop()
		if context.weapon_animation_player.has_animation(&"RESET"):
			context.weapon_animation_player.play(&"RESET")

func is_on_cooldown() -> bool:
	return _cooldown_remaining > 0.0

func _weapon_cycle_duration() -> float:
	var player := context.weapon_animation_player
	var slash_animation := player.get_animation(SLASH_ANIMATION)
	var return_animation := player.get_animation(RETURN_ANIMATION)
	var speed := maxf(absf(player.speed_scale), 0.001)
	return (slash_animation.length + return_animation.length) / speed

func _on_weapon_animation_finished(animation_name: StringName) -> void:
	if not _initialized or not context.is_attacking:
		return
	if animation_name == SLASH_ANIMATION:
		context.weapon_animation_player.play(RETURN_ANIMATION)
	elif animation_name == RETURN_ANIMATION:
		context.is_attacking = false
		_active_slash = null
		attack_finished.emit()

func _on_slash_hit(target: Node, dealt_damage: int) -> void:
	attack_hit.emit(target, dealt_damage)
