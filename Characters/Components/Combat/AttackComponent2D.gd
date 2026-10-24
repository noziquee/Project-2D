extends Node
class_name AttackComponent2D
## Coordinates the attack lifecycle. The AttackDefinition2D names the weapon clips and
## effect scene; the authored weapon animation fires named events through
## Character2D.attack_event(event), which arrive here in handle_event().
##
## A character owns one default attack (`attack_definition`) plus any number of extra
## attacks (`attacks`). Pick one by id with try_start_attack(); try_start(true) starts the default.
## All attacks share one cooldown, because a character performs one attack at a time.
##
## Events:
##   spawn_effect        spawns one effect scene. Put several keys in a clip for a flurry.
##   combo_window_open   opens the combo window (only during the weapon clip). Chaining into
##                       next_attack is added in 9.4c; until then the window is only tracked.
##   combo_window_close  closes the combo window.
##
## Combos: while the combo window is open, a request for an attack (try_start / try_start_attack)
## starts the active attack's next_attack instead. The current swing ends without a cooldown and
## without attack_finished; attack_started fires for each link and attack_finished once, when the
## chain ends. The attack a chain plays: the combo_sequence in progress, else next_attack, else
## (9.R2) a press at the end of a chain starts the combo again from its first attack. An attack
## that started on its own, with no link, repeats itself (it is its own first attack). A chain
## never runs on by itself: when the window closes with no press, the return clip of the attack
## that was last performed plays, and no attack can start until it has finished.

signal attack_started(direction: Vector2)
signal attack_hit(target: Node, damage: int)
signal attack_finished
## A combo link started: `previous_id` ended its swing and `next_id` took over inside the window.
signal attack_chained(previous_id: StringName, next_id: StringName)

const EVENT_SPAWN_EFFECT := &"spawn_effect"
const EVENT_COMBO_WINDOW_OPEN := &"combo_window_open"
const EVENT_COMBO_WINDOW_CLOSE := &"combo_window_close"

const DEFAULT_ATTACK = preload("res://Characters/Components/Combat/DefaultAttackDefinition.tres")
const DEFAULT_SLASH = preload("res://Characters/Components/Combat/AttackSlash2D.tscn")

## The attack this component starts with (edit it per character in the Scene dock).
## Empty falls back to DefaultAttackDefinition.tres.
@export var attack_definition: AttackDefinition2D = DEFAULT_ATTACK
## Extra attacks this character can start by id with try_start_attack() (a heavy attack, a
## lunge...). The default attack above is always selectable by its own id as well, so list
## only the additional ones. Ids must be unique and non-empty; an entry whose clips are
## missing on the weapon AnimationPlayer is rejected with an error naming the clip, and
## the other attacks keep working.
@export var attacks: Array[AttackDefinition2D] = []
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
## True between combo_window_open and combo_window_close during the weapon clip (9.4b).
var _combo_window_open := false
## True once the weapon clip has ended and the recovery clip is playing. Combo window events
## are ignored in recovery.
var _in_recovery := false
## Combo sequence of the combo in progress, and the index of its next link (9.6a). Runtime only:
## both are set when a swing starts and cleared when the combo ends.
var _combo_sequence: Array[AttackDefinition2D] = []
var _combo_step := 0
## The attack that started the combo in progress (9.R2). A press in the window of the last link
## starts it again. Runtime only; null when no combo is running.
var _combo_root: AttackDefinition2D
## Charge in progress (9.6c): the attack being charged, the seconds charged so far, and the
## direction it will swing in. Runtime only.
var _charging_definition: AttackDefinition2D
var _charge_elapsed := 0.0
var _charge_direction := Vector2.RIGHT
## Validated entries of `attacks`, keyed by id (the default attack is not in here).
var _extra_attacks: Dictionary = {}
## The weapon AnimationPlayer whose animation_finished is connected to this component (9.7c-3).
var _connected_player: AnimationPlayer

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
	_register_extra_attacks()
	_warn_combo_links()
	rebind_weapon_player()

## Connects animation_finished of the context's current weapon AnimationPlayer to this component and
## drops the connection to the one used before (9.7c-3). Call it after CharacterContext2D.bind_weapon()
## when a weapon was swapped. Safe to call again with the same player.
func rebind_weapon_player() -> void:
	var player: AnimationPlayer = context.weapon_animation_player if context != null else null
	if is_instance_valid(_connected_player) and _connected_player != player and _connected_player.animation_finished.is_connected(_on_weapon_animation_finished):
		_connected_player.animation_finished.disconnect(_on_weapon_animation_finished)
	_connected_player = player
	if is_instance_valid(player) and not player.animation_finished.is_connected(_on_weapon_animation_finished):
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
	if candidate.effect_scene != null and AttackSlash2D.scene_lacks_animation(candidate.effect_scene, candidate.effect_animation):
		return "attack '%s' on '%s': effect_scene has no clip '%s' (effect_animation)." % [candidate.id, owner_name, candidate.effect_animation]
	if candidate.charge_animation != &"" and not player.has_animation(candidate.charge_animation):
		return "attack '%s' on '%s': weapon AnimationPlayer has no clip '%s' (charge_animation)." % [candidate.id, owner_name, candidate.charge_animation]
	if candidate.release_mode == AttackDefinition2D.ReleaseMode.THRESHOLD and candidate.charge_threshold <= 0.0:
		return "attack '%s': a THRESHOLD release needs charge_threshold > 0." % candidate.id
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

## Starts the default attack (`definition`) when `requested` is true.
func try_start(requested: bool, direction: Vector2 = Vector2.ZERO) -> bool:
	if not requested:
		return false
	if is_combo_window_open():
		return _try_chain(direction)
	return _begin_attack(definition, direction)

## Starts the attack with this id: the default attack's own id, or an entry of `attacks`.
## An empty id means "no attack requested" and returns false. An unknown id returns false
## with a warning. The usual gating applies (not attacking, not dashing, no hit stun, no
## cooldown).
func try_start_attack(attack_id: StringName, direction: Vector2 = Vector2.ZERO) -> bool:
	if attack_id == &"":
		return false
	if is_combo_window_open() and get_attack(attack_id) != null:
		return _try_chain(direction)
	var chosen := get_attack(attack_id)
	if chosen == null:
		var owner_name: String = context.character.name if context != null and context.character != null else "?"
		push_warning("AttackComponent2D on '%s': no attack with id '%s' (known: %s)." % [owner_name, attack_id, get_attack_ids()])
		return false
	return _begin_attack(chosen, direction)

## The attack with this id, or null. The default attack is found by its own id.
func get_attack(attack_id: StringName) -> AttackDefinition2D:
	if attack_id == &"":
		return null
	if definition != null and definition.id == attack_id:
		return definition
	return _extra_attacks.get(attack_id) as AttackDefinition2D

func has_attack(attack_id: StringName) -> bool:
	return get_attack(attack_id) != null

## Ids that try_start_attack() accepts: the default attack first, then the extra ones.
func get_attack_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	if definition != null:
		ids.append(definition.id)
	for extra_id in _extra_attacks.keys():
		ids.append(extra_id)
	return ids

## Id of the swing in progress, or an empty id when idle.
func get_active_attack_id() -> StringName:
	return _active_definition.id if _active_definition != null else &""

## Replaces the extra attacks at runtime (for example when a weapon is equipped). Invalid
## entries are skipped with an error. Returns how many were accepted. A swing already in
## progress is not affected.
func set_attacks(new_attacks: Array[AttackDefinition2D]) -> int:
	attacks = new_attacks
	var accepted := _register_extra_attacks()
	_warn_combo_links()
	return accepted

## Every attack this component can run: the default attack first, then the extra ones.
func get_all_attacks() -> Array[AttackDefinition2D]:
	var all: Array[AttackDefinition2D] = []
	if definition != null:
		all.append(definition)
	for extra in _extra_attacks.values():
		all.append(extra as AttackDefinition2D)
	return all

## The attack that `candidate` chains into (its next_attack), or null when it has no link,
## the link is a self link, or the link is not registered on this component.
func get_next_attack(candidate: AttackDefinition2D) -> AttackDefinition2D:
	if candidate == null or candidate.next_attack == null or candidate.next_attack.id == candidate.id:
		return null
	return get_attack(candidate.next_attack.id)

## Problems with next_attack links on the attacks of this component, as readable messages.
## Empty when every link is valid. Links are checked, not enforced: a bad link is ignored
## at runtime, so the attack it sits on still plays.
func validate_combo_links() -> Array[String]:
	var problems: Array[String] = []
	var owner_name: String = context.character.name if context != null and context.character != null else "?"
	for attack in get_all_attacks():
		var link := attack.next_attack
		if link != null and link.id != attack.id and get_attack(link.id) == null:
			problems.append("attack '%s' on '%s': next_attack '%s' is not registered on this component (add it to 'attacks'); the link is ignored." % [attack.id, owner_name, link.id])
		if not attack.combo_sequence.is_empty():
			var first = attack.combo_sequence[0]
			if first == null or first.id != attack.id:
				problems.append("attack '%s' on '%s': combo_sequence must start with the attack itself." % [attack.id, owner_name])
			for entry in attack.combo_sequence:
				if entry == null:
					problems.append("attack '%s' on '%s': combo_sequence has an empty entry." % [attack.id, owner_name])
				elif get_attack(entry.id) == null:
					problems.append("attack '%s' on '%s': combo_sequence entry '%s' is not registered on this component (add it to 'attacks')." % [attack.id, owner_name, entry.id])
	return problems

func _warn_combo_links() -> void:
	for problem in validate_combo_links():
		push_warning("AttackComponent2D: %s" % problem)

## Starts charging the attack with this id (9.6c). While charging the character holds its place in
## the attack state (no other attack or dash can start), moves at the attack's movement_multiplier,
## and plays its charge_animation. The swing starts on release_charge(), or by itself when the
## attack's release mode is THRESHOLD and its charge_threshold is reached. False when the attack is
## unknown or a swing, charge, dash, stun or cooldown prevents it.
func begin_charge(attack_id: StringName, direction: Vector2 = Vector2.ZERO) -> bool:
	var chosen := get_attack(attack_id)
	if not _initialized or chosen == null or context.is_attacking or context.is_dashing or context.hit_stun_remaining > 0.0 or _cooldown_remaining > 0.0:
		return false
	_charging_definition = chosen
	_charge_elapsed = 0.0
	_charge_direction = _resolve_attack_direction(direction)
	context.attack_direction = _charge_direction
	context.aim_direction = _charge_direction
	context.is_attacking = true
	context.move_multiplier = chosen.movement_multiplier
	if chosen.charge_animation != &"":
		context.weapon_animation_player.play(chosen.charge_animation)
	return true

## Releases the charge in progress into its swing (9.6c). The direction defaults to the one the
## charge began with. False when nothing is charging (for example, the threshold already released it).
func release_charge(direction: Vector2 = Vector2.ZERO) -> bool:
	if _charging_definition == null:
		return false
	var charged := _charging_definition
	var aim := _resolve_attack_direction(direction if direction.length_squared() > 0.0001 else _charge_direction)
	_charging_definition = null
	_charge_elapsed = 0.0
	_begin_combo(charged)
	_start_swing(charged, aim)
	return true

## True while a charge is in progress.
func is_charging() -> bool:
	return _charging_definition != null

## Seconds the charge in progress has lasted (0 when not charging).
func get_charge_time() -> float:
	return _charge_elapsed

## How full the charge is, 0 to 1 (for a charge bar). A THRESHOLD attack fills over its
## charge_threshold; an INPUT_RELEASE attack has no end, so it reports 0 unless it sets a
## charge_threshold, which then only scales the bar (it does not release by itself).
func get_charge_ratio() -> float:
	if _charging_definition == null or _charging_definition.charge_threshold <= 0.0:
		return 0.0
	return clampf(_charge_elapsed / _charging_definition.charge_threshold, 0.0, 1.0)

func _begin_attack(chosen: AttackDefinition2D, direction: Vector2) -> bool:
	if not _initialized or chosen == null or context.is_attacking or context.is_dashing or context.hit_stun_remaining > 0.0 or _cooldown_remaining > 0.0:
		return false
	_begin_combo(chosen)
	_start_swing(chosen, _resolve_attack_direction(direction))
	return true

## Starts the next attack of the combo while the combo window is open (see _resolve_chain_target).
## Refused (false) only while dashing or stunned. Unlike _begin_attack, the cooldown is not checked
## and nothing is finished: the current swing is simply replaced.
func _try_chain(direction: Vector2) -> bool:
	if context.is_dashing or context.hit_stun_remaining > 0.0:
		return false
	var previous := _active_definition
	var next := _resolve_chain_target(previous)
	_start_swing(next, _resolve_attack_direction(direction))
	attack_chained.emit(previous.id, next.id)
	return true

## The attack a chain plays next (9.6a), in this order:
##   1. the combo sequence in progress: the next entry, looping, and the index advances;
##   2. the attack's explicit next_attack link (9.4);
##   3. the end of the chain: the combo's first attack again (9.R2), or the same attack again
##      when it IS the first attack, or when it links to itself on purpose.
## A link or sequence entry that is not registered falls back to repeating the attack.
func _resolve_chain_target(previous: AttackDefinition2D) -> AttackDefinition2D:
	if not _combo_sequence.is_empty():
		var entry := _combo_sequence[_combo_step % _combo_sequence.size()]
		_combo_step += 1
		var registered := get_attack(entry.id)
		return registered if registered != null else previous
	var linked := get_next_attack(previous)
	if linked != null:
		return linked
	if previous.next_attack == null and _combo_root != null:
		var root := get_attack(_combo_root.id)
		if root != null:
			return root
	return previous

## Starts a combo from `chosen` (a swing that is not a chain link): its sequence, if any, is
## kept for the combo, and the first chain plays entry 1 (entry 0 is the attack itself).
func _begin_combo(chosen: AttackDefinition2D) -> void:
	_combo_root = chosen
	_combo_sequence.clear()
	for entry in chosen.combo_sequence:
		_combo_sequence.append(entry)
	_combo_step = 1 if not _combo_sequence.is_empty() else 0

## The combo window closed with no press (a press would have chained first). The attack in
## progress ends its weapon clip here: its return clip plays at once (9.6b), cutting the rest of
## the weapon clip. An attack with no return clip ends now, and its weapon pose is reset. Ignored
## once the return has started.
func _close_window_without_press() -> void:
	if _in_recovery or _active_definition == null:
		return
	var active := _active_definition
	if active.recovery_animation != &"":
		_in_recovery = true
		context.weapon_animation_player.play(active.recovery_animation)
	else:
		if context.weapon_animation_player.has_animation(&"RESET"):
			context.weapon_animation_player.play(&"RESET")
		_finish_attack()

## Ends the combo: the next swing starts a fresh one.
func _reset_combo() -> void:
	_combo_root = null
	_combo_sequence.clear()
	_combo_step = 0

## Direction for a new swing: the requested one, else the aim, else the facing, else right.
func _resolve_attack_direction(direction: Vector2) -> Vector2:
	var attack_direction := direction.normalized()
	if attack_direction.length_squared() < 0.0001:
		attack_direction = context.aim_direction.normalized()
	if attack_direction.length_squared() < 0.0001:
		attack_direction = context.facing_direction.normalized()
	if attack_direction.length_squared() < 0.0001:
		attack_direction = Vector2.RIGHT
	return attack_direction

## Puts `chosen` into effect and starts its weapon clip. Used for normal starts and for chain links.
func _start_swing(chosen: AttackDefinition2D, attack_direction: Vector2) -> void:
	_active_definition = chosen
	_combo_window_open = false
	_in_recovery = false
	context.attack_direction = attack_direction
	context.aim_direction = attack_direction
	context.is_attacking = true
	context.move_multiplier = _active_definition.movement_multiplier
	context.weapon_animation_player.play(_active_definition.weapon_animation)
	attack_started.emit(attack_direction)

## Rebuilds the id lookup from `attacks`. A bad entry (empty, no id, duplicate id, missing
## clip) is skipped with a message so it never disables the default attack or the others.
func _register_extra_attacks() -> int:
	_extra_attacks.clear()
	for entry in attacks:
		if entry == null:
			push_warning("AttackComponent2D: ignoring an empty entry in 'attacks'.")
			continue
		if entry.id == &"":
			push_warning("AttackComponent2D: ignoring an attack with an empty id (an empty id means 'no attack').")
			continue
		if definition != null and entry.id == definition.id:
			push_warning("AttackComponent2D: attack '%s' in 'attacks' has the same id as the default attack and is ignored." % entry.id)
			continue
		if _extra_attacks.has(entry.id):
			push_warning("AttackComponent2D: duplicate attack id '%s' in 'attacks'; the first one is kept." % entry.id)
			continue
		if context != null:
			var problem := validate_definition(entry)
			if problem != "":
				push_error("AttackComponent2D rejected attack: %s" % problem)
				continue
		_extra_attacks[entry.id] = entry
	return _extra_attacks.size()

func physics_update(delta: float) -> void:
	if _initialized:
		_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)
		if _charging_definition != null:
			_charge_elapsed += delta
			if _charging_definition.release_mode == AttackDefinition2D.ReleaseMode.THRESHOLD and _charge_elapsed >= _charging_definition.charge_threshold:
				release_charge()

## True for event names this component understands (including the combo window events).
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
		EVENT_COMBO_WINDOW_OPEN:
			_combo_window_open = not _in_recovery
		EVENT_COMBO_WINDOW_CLOSE:
			_combo_window_open = false
			_close_window_without_press()
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
	slash.configure(context.character, active.damage, context.attack_direction, active.hitbox_size, active.hitbox_offset, active.hit_layers, active.knockback, active.hit_stun, active.effect_animation)
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
	_combo_window_open = false
	_in_recovery = false
	_reset_combo()
	_charging_definition = null
	_charge_elapsed = 0.0
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
	if not _initialized or not context.is_attacking:
		return false
	# A charge is interrupted only if the attack being charged is interruptible (9.6c).
	var current := _active_definition if _active_definition != null else _charging_definition
	if current == null or not current.interruptible:
		return false
	var cooldown := maxf(current.cooldown_duration, 0.0)
	cancel()
	_cooldown_remaining = cooldown
	return true

## True while a swing is running whose definition asks for the weapon to aim.
func is_aiming_weapon() -> bool:
	var aiming := _active_definition if _active_definition != null else _charging_definition
	return _initialized and context.is_attacking and aiming != null and aiming.aim_weapon

## True while a combo window is open: the weapon clip has fired combo_window_open and has not
## yet fired combo_window_close, the swing is still running, and it is not in recovery.
func is_combo_window_open() -> bool:
	return _initialized and context.is_attacking and _combo_window_open and _active_definition != null

func is_on_cooldown() -> bool:
	return _cooldown_remaining > 0.0

func _on_weapon_animation_finished(animation_name: StringName) -> void:
	if not _initialized or not context.is_attacking or _active_definition == null:
		return
	var active := _active_definition
	if animation_name == active.weapon_animation:
		if active.recovery_animation != &"":
			_combo_window_open = false
			_in_recovery = true
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
	_combo_window_open = false
	_in_recovery = false
	_reset_combo()
	# Effects outlive the swing and free themselves; just stop tracking them.
	_active_effects.clear()
	attack_finished.emit()

func _on_slash_hit(target: Node, dealt_damage: int) -> void:
	attack_hit.emit(target, dealt_damage)

func _on_slash_contact(_target: Node, _dealt_damage: int, point: Vector2, hit_effect: PackedScene) -> void:
	if hit_effect != null and context != null and is_instance_valid(context.character):
		Effects2D.spawn(hit_effect, context.character, point)
