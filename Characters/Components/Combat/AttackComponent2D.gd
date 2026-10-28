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
##
## Draw (bow): an attack with a draw_animation plays it first. When it finishes the component plays the weapon clip
## (a swing) or the charge clip (a charge) by itself. A swing that starts from a combo link plays the draw again, a
## swing that starts from a charge release does not (the charge already drew). Releasing a charge while the draw is
## still playing is remembered and fires the shot the moment the draw ends; the charge time only counts after it.
##
## Input queue (bow): an attack with input_queue_time > 0 remembers a request that arrives while it runs. The request
## chains when the combo window opens, or when the weapon clip finishes, and otherwise waits for the return to end:
## Character2D then asks take_queued_attack() and starts it. So a cycle reads draw > shot > draw > shot while the
## button is pressed again in time, and draw > shot > return to idle when it is not.

signal attack_started(direction: Vector2)
signal attack_hit(target: Node, damage: int)
signal attack_finished
## A swing or charge ended: `cancelled` is false when it ran to its end and true when it was cancelled or
## interrupted. Emitted before the weapon clip is stopped, so a listener can still read the pose the weapon is in.
## Not emitted when nothing was attacking.
signal swing_ended(cancelled: bool)
## A code-driven return (AttackDefinition2D.recovery_time) began: the swing is over, no attack can start for
## `duration` seconds, and the weapon should blend to rest with `ease` (a Curve, or null for smoothstep).
signal recovery_started(duration: float, ease: Curve)
## A combo link started: `previous_id` ended its swing and `next_id` took over inside the window.
signal attack_chained(previous_id: StringName, next_id: StringName)

const EVENT_SPAWN_EFFECT := &"spawn_effect"
const EVENT_COMBO_WINDOW_OPEN := &"combo_window_open"
const EVENT_COMBO_WINDOW_CLOSE := &"combo_window_close"

## The attack this component starts with (edit it per character in the Scene dock).
## Required (10.1): with no definition the component logs an error and the character cannot attack.
@export var attack_definition: AttackDefinition2D
## Extra attacks this character can start by id with try_start_attack() (a heavy attack, a
## lunge...). The default attack above is always selectable by its own id as well, so list
## only the additional ones. Ids must be unique and non-empty; an entry whose clips are
## missing on the weapon AnimationPlayer is rejected with an error naming the clip, and
## the other attacks keep working.
@export var attacks: Array[AttackDefinition2D] = []

var context: CharacterContext2D
## The attack currently in effect at runtime (starts as attack_definition; see
## set_attack_definition()).
var definition: AttackDefinition2D
## Counts down the definition's cooldown_duration. It starts when the swing ENDS
## (recovery clip finished), so the resource value is the real gap between attacks.
var _cooldown_remaining := 0.0
var _impulse_direction := Vector2.RIGHT
var _impulse_speed := 0.0
var _impulse_total := 0.01
var _impulse_remaining := 0.0
var _initialized := false
## Effects spawned by the swing in progress. An entry removes itself when its effect
## leaves the tree; cancel() frees whatever is still alive.
var _active_effects: Array[AttackEffect2D] = []
## The definition the swing in progress started with. Swapping `definition` mid-swing
## therefore cannot strand the running attack waiting for a clip that no longer applies.
var _active_definition: AttackDefinition2D
## True between combo_window_open and combo_window_close during the weapon clip (9.4b).
var _combo_window_open := false
## True once the weapon clip has ended and the recovery clip is playing. Combo window events
## are ignored in recovery.
var _in_recovery := false
## True while the recovery in progress is code driven (recovery_time) rather than a clip, and its elapsed seconds.
var _code_recovery := false
var _code_recovery_elapsed := 0.0
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
## True while a draw_animation is playing: before a swing (_active_definition) or before a charge (_charging_definition).
var _drawing := false
## A charge was released while its draw was still playing; the shot starts when the draw ends.
var _release_pending := false
## The request remembered by an attack with input_queue_time (empty = none), the aim it was made with, and the seconds
## it stays valid. Runtime only; cancel() drops it.
var _queued_id: StringName = &""
var _queued_direction := Vector2.ZERO
var _queue_remaining := 0.0

func initialize(shared_context: CharacterContext2D) -> void:
	context = shared_context
	definition = attack_definition
	_initialized = (
		context != null
		and context.character is CharacterBody2D
		and definition != null
		and is_instance_valid(context.weapon_animation_player)
	)
	if not _initialized:
		push_error("AttackComponent2D needs a character context, an attack_definition, and a weapon AnimationPlayer.")
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
	if candidate.draw_animation != &"":
		if not player.has_animation(candidate.draw_animation):
			return "attack '%s' on '%s': weapon AnimationPlayer has no clip '%s' (draw_animation)." % [candidate.id, owner_name, candidate.draw_animation]
		if candidate.draw_animation == candidate.weapon_animation or candidate.draw_animation == candidate.charge_animation or candidate.draw_animation == candidate.recovery_animation:
			return "attack '%s' on '%s': draw_animation must differ from weapon_animation, charge_animation and recovery_animation ('%s')." % [candidate.id, owner_name, candidate.draw_animation]
	if candidate.charge_animation != &"" and not player.has_animation(candidate.charge_animation):
		return "attack '%s' on '%s': weapon AnimationPlayer has no clip '%s' (charge_animation)." % [candidate.id, owner_name, candidate.charge_animation]
	if candidate.release_mode == AttackDefinition2D.ReleaseMode.THRESHOLD and candidate.charge_threshold <= 0.0:
		return "attack '%s': a THRESHOLD release needs charge_threshold > 0." % candidate.id
	if candidate.effect_scene == null:
		return "attack '%s' on '%s': no effect_scene (every attack needs its own effect scene)." % [candidate.id, owner_name]
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

## Starts the default attack (`definition`) when `requested` is true.
func try_start(requested: bool, direction: Vector2 = Vector2.ZERO) -> bool:
	if not requested:
		return false
	if is_combo_window_open():
		return _try_chain(direction)
	if definition != null and _try_queue(definition.id, direction):
		return false
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
	if _try_queue(attack_id, direction):
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
	if not _initialized or chosen == null or context.is_attacking or context.is_dashing or context.is_casting or context.hit_stun_remaining > 0.0 or _cooldown_remaining > 0.0:
		return false
	_charging_definition = chosen
	_charge_elapsed = 0.0
	_charge_direction = _resolve_attack_direction(direction)
	context.attack_direction = _charge_direction
	context.aim_direction = _charge_direction
	context.is_attacking = true
	context.move_multiplier = chosen.movement_multiplier
	_drawing = false
	_release_pending = false
	if chosen.draw_animation != &"":
		_drawing = true
		context.weapon_animation_player.play(chosen.draw_animation)
	elif chosen.charge_animation != &"":
		context.weapon_animation_player.play(chosen.charge_animation)
	return true

## Releases the charge in progress into its swing (9.6c). The direction defaults to the one the
## charge began with. False when nothing is charging (for example, the threshold already released it).
func release_charge(direction: Vector2 = Vector2.ZERO) -> bool:
	if _charging_definition == null:
		return false
	if _drawing:
		# The draw is still playing: the shot fires the moment it ends (see _finish_draw()).
		_release_pending = true
		if direction.length_squared() > 0.0001:
			_charge_direction = direction.normalized()
		return true
	var charged := _charging_definition
	var aim := _resolve_attack_direction(direction if direction.length_squared() > 0.0001 else _charge_direction)
	_commit_release(charged, aim)
	return true

## The charge `charged` ends and its swing starts. The draw is skipped: a charge has already drawn the bow.
func _commit_release(charged: AttackDefinition2D, aim: Vector2) -> void:
	_charging_definition = null
	_charge_elapsed = 0.0
	_release_pending = false
	_begin_combo(charged)
	_start_swing(charged, aim, false)

## Points the charge in progress at `direction` (the live aim while the button is held). The direction the
## swing takes is still decided at release; this only keeps `attack_direction` and `aim_direction` current so the
## facing and the weapon pivot follow the aim during the charge. Does nothing when not charging or for a zero vector.
## Once the button has been released (`_release_pending`: the draw is still playing and the shot fires when it ends)
## the direction is fixed, so an assisted aim chosen at release is not replaced by the live aim (H8.7).
func update_charge_direction(direction: Vector2) -> void:
	if _charging_definition == null or _release_pending or direction.length_squared() < 0.0001:
		return
	_charge_direction = direction.normalized()
	context.attack_direction = _charge_direction
	context.aim_direction = _charge_direction

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
	if not _initialized or chosen == null or context.is_attacking or context.is_dashing or context.is_casting or context.hit_stun_remaining > 0.0 or _cooldown_remaining > 0.0:
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
	elif active.recovery_time > 0.0:
		_begin_code_recovery(active)
	else:
		# Finish first: swing_ended lets FacingComponent2D take over the hand pose (context.hand_settling).
		_finish_attack()
		if context.hand_settling:
			context.weapon_animation_player.stop(true) # keep the pose; the blend takes it from here
		elif context.weapon_animation_player.has_animation(&"RESET"):
			context.weapon_animation_player.play(&"RESET")

## Starts the code-driven return (P10): the weapon clip is stopped where it is (the pose is kept), the attack
## stays in recovery for recovery_time, and listeners blend the weapon to rest. _finish_attack() ends it.
func _begin_code_recovery(active: AttackDefinition2D) -> void:
	_combo_window_open = false
	_in_recovery = true
	_code_recovery = true
	_code_recovery_elapsed = 0.0
	recovery_started.emit(active.recovery_time, active.recovery_ease) # listeners read the pose before the clip stops
	context.weapon_animation_player.stop(true)

## True while a code-driven return is running.
func is_code_recovering() -> bool:
	return _code_recovery

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
func _start_swing(chosen: AttackDefinition2D, attack_direction: Vector2, with_draw: bool = true) -> void:
	_active_definition = chosen
	_combo_window_open = false
	_in_recovery = false
	_code_recovery = false
	_drawing = false
	_release_pending = false
	context.attack_direction = attack_direction
	context.aim_direction = attack_direction
	context.is_attacking = true
	context.move_multiplier = _active_definition.movement_multiplier
	if with_draw and chosen.draw_animation != &"":
		_drawing = true
		context.weapon_animation_player.play(chosen.draw_animation)
	else:
		context.weapon_animation_player.play(chosen.weapon_animation)
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
		_update_impulse(delta)
		if _queued_id != &"":
			_queue_remaining -= delta
			if _queue_remaining <= 0.0:
				_clear_queue()
		if _code_recovery and _active_definition != null:
			_code_recovery_elapsed += delta
			if _code_recovery_elapsed >= _active_definition.recovery_time:
				_finish_attack()
		if _charging_definition != null:
			if not _drawing:
				_charge_elapsed += delta # the charge starts counting once the draw is over
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
			if _combo_window_open and _queued_id != &"":
				# A request made before the window opened (during the draw or the shot) chains now.
				var queued_direction := _queued_direction
				_clear_queue()
				_try_chain(queued_direction)
		EVENT_COMBO_WINDOW_CLOSE:
			_combo_window_open = false
			_close_window_without_press()
		_:
			push_warning("AttackComponent2D: unknown attack event '%s' in attack '%s'." % [event, _active_definition.id])

## Number of effects from the current swing that are still alive.
func get_active_effect_count() -> int:
	return _active_effects.size()

## P7: the forward step of an attack that has one starts when its effect spawns, then fades out linearly.
func _start_impulse(active: AttackDefinition2D) -> void:
	if active.forward_impulse <= 0.0:
		return
	_impulse_direction = context.attack_direction.normalized()
	_impulse_speed = active.forward_impulse
	_impulse_total = maxf(active.impulse_duration, 0.01)
	_impulse_remaining = _impulse_total

func _update_impulse(delta: float) -> void:
	if _impulse_remaining <= 0.0:
		return
	_impulse_remaining = maxf(_impulse_remaining - delta, 0.0)
	context.impulse_velocity = _impulse_direction * _impulse_speed * (_impulse_remaining / _impulse_total)

func _clear_impulse() -> void:
	_impulse_remaining = 0.0
	if context != null:
		context.impulse_velocity = Vector2.ZERO

func _spawn_effect() -> void:
	var active := _active_definition
	_start_impulse(active)
	var scene: PackedScene = active.effect_scene
	if scene == null:
		push_error("AttackComponent2D: attack '%s' has no effect_scene." % active.id)
		return
	var node := scene.instantiate()
	var slash := node as AttackEffect2D
	if slash == null:
		push_error("AttackComponent2D: effect scene for attack '%s' must have an AttackEffect2D script (such as AttackSlash2D.gd) on its root." % active.id)
		node.queue_free()
		return
	slash.configure(context.character, active.damage, context.attack_direction, active.hitbox_size, active.hitbox_offset, active.hit_layers, active.knockback, active.hit_stun, active.effect_animation, active.max_targets, active.pierce, active.projectile_speed, active.crit_chance, active.crit_multiplier, active.status_effects, active.get_reach())
	slash.hit_confirmed.connect(_on_slash_hit)
	# The impact effect belongs to the attack that spawned the slash, which may outlive the swing.
	slash.hit_contact.connect(_on_slash_contact.bind(active.hit_effect_scene))
	slash.tree_exited.connect(_forget_effect.bind(slash))
	var host: Node = Effects2D.get_host(context.character)
	if host == null:
		host = context.character
	host.add_child(slash)
	slash.global_position = context.get_attack_origin()
	_active_effects.append(slash)

func _forget_effect(slash: AttackEffect2D) -> void:
	_active_effects.erase(slash)

func cancel() -> void:
	if context != null and context.is_attacking:
		swing_ended.emit(true)
	for effect in _active_effects.duplicate():
		if is_instance_valid(effect):
			effect.queue_free()
	_active_effects.clear()
	_active_definition = null
	_combo_window_open = false
	_in_recovery = false
	_code_recovery = false
	_reset_combo()
	_charging_definition = null
	_charge_elapsed = 0.0
	_drawing = false
	_release_pending = false
	_clear_queue()
	_clear_impulse()
	if context == null:
		return
	context.is_attacking = false
	context.move_multiplier = 1.0
	if is_instance_valid(context.weapon_animation_player):
		# A listener that settles the hand pose itself (FacingComponent2D) sets context.hand_settling; the pose is
		# then kept as it is (stop(true)) and no RESET snap is played.
		context.weapon_animation_player.stop(context.hand_settling)
		if not context.hand_settling and context.weapon_animation_player.has_animation(&"RESET"):
			context.weapon_animation_player.play(&"RESET")
	# A weapon that carries props (the bow's nocked arrow) puts them away, even when the pose is kept above.
	if is_instance_valid(context.weapon_pivot) and context.weapon_pivot.has_method(&"on_attack_cancelled"):
		context.weapon_pivot.call(&"on_attack_cancelled")

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
	if _code_recovery:
		return false # the pivot is blending back to rest
	var aiming := _active_definition if _active_definition != null else _charging_definition
	return _initialized and context.is_attacking and aiming != null and aiming.aim_weapon

## True while a combo window is open: the weapon clip has fired combo_window_open and has not
## yet fired combo_window_close, the swing is still running, and it is not in recovery.
func is_combo_window_open() -> bool:
	return _initialized and context.is_attacking and _combo_window_open and _active_definition != null

func is_on_cooldown() -> bool:
	return _cooldown_remaining > 0.0

func _on_weapon_animation_finished(animation_name: StringName) -> void:
	if not _initialized or not context.is_attacking:
		return
	if _drawing:
		_finish_draw(animation_name)
		return
	if _active_definition == null:
		return
	var active := _active_definition
	if animation_name == active.weapon_animation:
		if _queued_id != &"" and _chain_from_queue(active):
			return # a request is waiting: draw again instead of returning
		if active.recovery_animation != &"":
			_combo_window_open = false
			_in_recovery = true
			context.weapon_animation_player.play(active.recovery_animation)
		elif active.recovery_time > 0.0:
			_begin_code_recovery(active)
		else:
			_finish_attack()
	elif active.recovery_animation != &"" and animation_name == active.recovery_animation:
		_finish_attack()

## The draw clip of the swing or charge in progress ended. A swing goes on to its weapon clip. A charge goes on to its
## charge clip, or straight to the shot when the button was already released.
func _finish_draw(animation_name: StringName) -> void:
	var swinging := _active_definition != null
	var drawing := _active_definition if swinging else _charging_definition
	if drawing == null or animation_name != drawing.draw_animation:
		return
	_drawing = false
	if swinging:
		context.weapon_animation_player.play(drawing.weapon_animation)
		return
	if _release_pending:
		_commit_release(drawing, _resolve_attack_direction(_charge_direction))
	elif drawing.charge_animation != &"":
		context.weapon_animation_player.play(drawing.charge_animation)

## True while a draw clip is playing (a swing's or a charge's).
func is_drawing() -> bool:
	return _drawing

## Remembers a request for `attack_id` made while an attack with input_queue_time is running (a swing or its return, not
## a charge). True when it was remembered, so the caller reports the request as not started. The newest request wins.
func _try_queue(attack_id: StringName, direction: Vector2) -> bool:
	if not _initialized or attack_id == &"" or not context.is_attacking or _charging_definition != null or _active_definition == null:
		return false
	if _active_definition.input_queue_time <= 0.0 or context.is_dashing or context.hit_stun_remaining > 0.0:
		return false
	_queued_id = attack_id
	_queued_direction = direction
	_queue_remaining = _active_definition.input_queue_time
	return true

func _clear_queue() -> void:
	_queued_id = &""
	_queued_direction = Vector2.ZERO
	_queue_remaining = 0.0

## The attack id remembered by _try_queue(), or empty.
func get_queued_attack_id() -> StringName:
	return _queued_id

## Hands out the remembered request once the character can start an attack again (nothing running, no dash, cast, stun
## or cooldown), and forgets it. Empty when there is none or it cannot start yet; it stays until it expires. Character2D
## asks for it each frame when the player pressed nothing new, so a click made during the return still plays.
func take_queued_attack() -> StringName:
	if _queued_id == &"" or not _initialized:
		return &""
	if context.is_attacking or context.is_dashing or context.is_casting or context.hit_stun_remaining > 0.0 or _cooldown_remaining > 0.0:
		return &""
	var queued := _queued_id
	_clear_queue()
	return queued

## The weapon clip ended with a request waiting: the next attack starts at once (its draw plays first), as a chain link
## from `previous`. The request's own attack is used, so a heavy shot followed by a light click plays the light attack.
func _chain_from_queue(previous: AttackDefinition2D) -> bool:
	if context.is_dashing or context.hit_stun_remaining > 0.0:
		return false
	var next := get_attack(_queued_id)
	var direction := _queued_direction
	_clear_queue()
	if next == null:
		return false
	_begin_combo(next)
	_start_swing(next, _resolve_attack_direction(direction))
	attack_chained.emit(previous.id, next.id)
	return true

func _finish_attack() -> void:
	_clear_impulse()
	swing_ended.emit(false)
	context.is_attacking = false
	context.move_multiplier = 1.0
	_cooldown_remaining = maxf(_active_definition.cooldown_duration, 0.0)
	_active_definition = null
	_combo_window_open = false
	_in_recovery = false
	_code_recovery = false
	_drawing = false
	_reset_combo()
	# Effects outlive the swing and free themselves; just stop tracking them.
	_active_effects.clear()
	attack_finished.emit()

func _on_slash_hit(target: Node, dealt_damage: int) -> void:
	attack_hit.emit(target, dealt_damage)

func _on_slash_contact(_target: Node, _dealt_damage: int, point: Vector2, hit_effect: PackedScene) -> void:
	if hit_effect != null and context != null and is_instance_valid(context.character):
		Effects2D.spawn(hit_effect, context.character, point)
