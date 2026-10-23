extends Node
class_name AttackComponent2D
## Coordinates the attack lifecycle. The AttackDefinition2D names the weapon clips and
## effect scene; the authored weapon animation fires named events through
## Character2D.attack_event(event), which arrive here in handle_event().
##
## Events:
##   spawn_effect        spawns one effect scene. Put several keys in a clip for a flurry.
##   combo_window_open   reserved for Phase 9 (combos); accepted and ignored for now.
##   combo_window_close  reserved for Phase 9; accepted and ignored for now.

signal attack_started(direction: Vector2)
signal attack_hit(target: Node, damage: int)
signal attack_finished

const EVENT_SPAWN_EFFECT := &"spawn_effect"
const EVENT_COMBO_WINDOW_OPEN := &"combo_window_open"
const EVENT_COMBO_WINDOW_CLOSE := &"combo_window_close"

const DEFAULT_ATTACK = preload("res://Characters/Components/Combat/DefaultAttackDefinition.tres")
const DEFAULT_SLASH = preload("res://Characters/Components/Combat/AttackSlash2D.tscn")

## The attack this component starts with (edit it per character in the Scene dock).
## Empty falls back to DefaultAttackDefinition.tres.
@export var attack_definition: AttackDefinition2D = DEFAULT_ATTACK
## DEPRECATED: set AttackDefinition2D.effect_scene instead. Only used as a fallback when
## the active attack definition has no effect_scene of its own.
@export var attack_slash_scene: PackedScene = DEFAULT_SLASH

var context: CharacterContext2D
## The attack currently in effect at runtime (starts as attack_definition; see
## set_attack_definition()).
var definition: AttackDefinition2D
## Runtime copy of attack_slash_scene.
var slash_scene: PackedScene
## Counts down the definition's cooldown_duration. It starts when the swing ENDS
## (recovery clip finished), so the resource value is the real gap between attacks.
var _cooldown_remaining := 0.0
var _initialized := false
## Effects spawned by the swing in progress. An entry removes itself when its effect
## leaves the tree; cancel() frees whatever is still alive.
var _active_effects: Array[AttackSlash2D] = []
## The definition the swing in progress started with. Swapping `definition` mid-swing
## therefore cannot strand the running attack waiting for a clip that no longer applies.
var _active_definition: AttackDefinition2D

func initialize(shared_context: CharacterContext2D) -> void:
	context = shared_context
	definition = attack_definition if attack_definition != null else DEFAULT_ATTACK
	slash_scene = attack_slash_scene if attack_slash_scene != null else DEFAULT_SLASH
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

	var problem := validate_definition(definition)
	if problem != "":
		push_error("AttackComponent2D: %s" % problem)
		_initialized = false
		return
	var player := context.weapon_animation_player
	if not player.animation_finished.is_connected(_on_weapon_animation_finished):
		player.animation_finished.connect(_on_weapon_animation_finished)

## Returns an empty string when `candidate` can run on this character's weapon
## AnimationPlayer, otherwise a message naming what is missing.
func validate_definition(candidate: AttackDefinition2D) -> String:
	if candidate == null:
		return "attack definition is null."
	if context == null or not is_instance_valid(context.weapon_animation_player):
		return "attack '%s': character has no weapon AnimationPlayer." % candidate.id
	var player := context.weapon_animation_player
	var owner_name: String = context.character.name if context.character != null else "?"
	if not player.has_animation(candidate.weapon_animation):
		return "attack '%s' on '%s': weapon AnimationPlayer has no clip '%s' (weapon_animation)." % [candidate.id, owner_name, candidate.weapon_animation]
	if candidate.recovery_animation != &"":
		if not player.has_animation(candidate.recovery_animation):
			return "attack '%s' on '%s': weapon AnimationPlayer has no clip '%s' (recovery_animation)." % [candidate.id, owner_name, candidate.recovery_animation]
		if candidate.recovery_animation == candidate.weapon_animation:
			return "attack '%s' on '%s': recovery_animation must differ from weapon_animation ('%s')." % [candidate.id, owner_name, candidate.weapon_animation]
	if candidate.effect_scene != null and not candidate.effect_scene.can_instantiate():
		return "attack '%s' on '%s': effect_scene cannot be instantiated." % [candidate.id, owner_name]
	return ""

## Swaps the attack definition. A definition that references a missing clip is rejected
## (with an error naming the clip) and the previous one stays in effect.
func set_attack_definition(new_definition: AttackDefinition2D) -> bool:
	if new_definition == null:
		return false
	var problem := validate_definition(new_definition)
	if problem != "":
		push_error("AttackComponent2D rejected definition: %s" % problem)
		return false
	definition = new_definition
	return true

func set_slash_scene(new_scene: PackedScene) -> void:
	if new_scene != null and new_scene.can_instantiate():
		slash_scene = new_scene
	else:
		push_warning("AttackComponent2D ignored an invalid slash scene assignment.")

func try_start(requested: bool, direction: Vector2 = Vector2.ZERO) -> bool:
	if not _initialized or not requested or context.is_attacking or context.is_dashing or context.hit_stun_remaining > 0.0 or _cooldown_remaining > 0.0:
		return false
	var attack_direction := direction.normalized()
	if attack_direction.length_squared() < 0.0001:
		attack_direction = context.aim_direction.normalized()
	if attack_direction.length_squared() < 0.0001:
		attack_direction = context.facing_direction.normalized()
	if attack_direction.length_squared() < 0.0001:
		attack_direction = Vector2.RIGHT

	_active_definition = definition
	context.attack_direction = attack_direction
	context.aim_direction = attack_direction
	context.is_attacking = true
	context.move_multiplier = _active_definition.movement_multiplier
	context.weapon_animation_player.play(_active_definition.weapon_animation)
	attack_started.emit(attack_direction)
	return true

func physics_update(delta: float) -> void:
	if _initialized:
		_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)

## True for event names this component understands (including the reserved combo ones).
static func is_known_event(event: StringName) -> bool:
	return event == EVENT_SPAWN_EFFECT or event == EVENT_COMBO_WINDOW_OPEN or event == EVENT_COMBO_WINDOW_CLOSE

## Entry point for the authored weapon animation events (via Character2D.attack_event()).
## Events that arrive when no attack is running are ignored.
func handle_event(event: StringName) -> void:
	if not _initialized or not context.is_attacking or _active_definition == null:
		return
	match event:
		EVENT_SPAWN_EFFECT:
			_spawn_effect()
		EVENT_COMBO_WINDOW_OPEN, EVENT_COMBO_WINDOW_CLOSE:
			pass # Reserved for Phase 9.
		_:
			push_warning("AttackComponent2D: unknown attack event '%s' in attack '%s'." % [event, _active_definition.id])

## Number of effects from the current swing that are still alive.
func get_active_effect_count() -> int:
	return _active_effects.size()

func _spawn_effect() -> void:
	var active := _active_definition
	var scene: PackedScene = active.effect_scene if active.effect_scene != null else slash_scene
	var node := scene.instantiate()
	var slash := node as AttackSlash2D
	if slash == null:
		push_error("AttackComponent2D: effect scene for attack '%s' must have AttackSlash2D.gd on its root." % active.id)
		node.queue_free()
		return
	slash.configure(context.character, active.damage, context.attack_direction, active.hitbox_size, active.hitbox_offset, active.hit_layers, active.knockback, active.hit_stun)
	slash.hit_confirmed.connect(_on_slash_hit)
	# The impact effect belongs to the attack that spawned the slash, which may outlive the swing.
	slash.hit_contact.connect(_on_slash_contact.bind(active.hit_effect_scene))
	slash.tree_exited.connect(_forget_effect.bind(slash))
	var host: Node = Effects2D.get_host(context.character)
	if host == null:
		host = context.character
	host.add_child(slash)
	slash.global_position = context.character.global_position
	_active_effects.append(slash)

func _forget_effect(slash: AttackSlash2D) -> void:
	_active_effects.erase(slash)

func cancel() -> void:
	for effect in _active_effects.duplicate():
		if is_instance_valid(effect):
			effect.queue_free()
	_active_effects.clear()
	_active_definition = null
	if context == null:
		return
	context.is_attacking = false
	context.move_multiplier = 1.0
	if is_instance_valid(context.weapon_animation_player):
		context.weapon_animation_player.stop()
		if context.weapon_animation_player.has_animation(&"RESET"):
			context.weapon_animation_player.play(&"RESET")

## Called when the owner is hit. Cancels the swing in progress if its definition is
## interruptible, and starts that attack's cooldown. Returns true if a swing was cancelled.
func interrupt() -> bool:
	if not _initialized or not context.is_attacking or _active_definition == null or not _active_definition.interruptible:
		return false
	var cooldown := maxf(_active_definition.cooldown_duration, 0.0)
	cancel()
	_cooldown_remaining = cooldown
	return true

## True while a swing is running whose definition asks for the weapon to aim.
func is_aiming_weapon() -> bool:
	return _initialized and context.is_attacking and _active_definition != null and _active_definition.aim_weapon

func is_on_cooldown() -> bool:
	return _cooldown_remaining > 0.0

func _on_weapon_animation_finished(animation_name: StringName) -> void:
	if not _initialized or not context.is_attacking or _active_definition == null:
		return
	var active := _active_definition
	if animation_name == active.weapon_animation:
		if active.recovery_animation != &"":
			context.weapon_animation_player.play(active.recovery_animation)
		else:
			_finish_attack()
	elif active.recovery_animation != &"" and animation_name == active.recovery_animation:
		_finish_attack()

func _finish_attack() -> void:
	context.is_attacking = false
	context.move_multiplier = 1.0
	_cooldown_remaining = maxf(_active_definition.cooldown_duration, 0.0)
	_active_definition = null
	# Effects outlive the swing and free themselves; just stop tracking them.
	_active_effects.clear()
	attack_finished.emit()

func _on_slash_hit(target: Node, dealt_damage: int) -> void:
	attack_hit.emit(target, dealt_damage)

func _on_slash_contact(_target: Node, _dealt_damage: int, point: Vector2, hit_effect: PackedScene) -> void:
	if hit_effect != null and context != null and is_instance_valid(context.character):
		Effects2D.spawn(hit_effect, context.character, point)
