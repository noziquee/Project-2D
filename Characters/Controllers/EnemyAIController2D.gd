extends Node
class_name EnemyAIController2D
## Enemy intent only; the parent Character2D performs shared movement and attacks.
##
## Targets are found through the enemy's DetectionArea (an Area2D with a CircleShape2D):
## bodies that enter it, and are characters on another team, become candidates (P4: a new faction is just a new
## team name; an empty team is neutral and is never a target). Tuning lives in an EnemyBehaviorProfile resource;
## the swing distance comes from the attack definition.

enum Behavior { IDLE, CHASE, ATTACK, RETURN }

## Swing distance used when the chosen attack definition's attack_range is 0.
const FALLBACK_ATTACK_RANGE := 30.0
## Longest an enemy backs away from a target that is inside minimum_combat_range, in seconds. After that it stops
## retreating for RETREAT_REST seconds and fights, so a wall behind it cannot leave it stuck and harmless.
const MAX_RETREAT_TIME := 1.5
const RETREAT_REST := 1.0

signal behavior_changed(previous_behavior: Behavior, current_behavior: Behavior)

@export var profile: EnemyBehaviorProfile
## Area2D whose CircleShape2D is the detection range. Left empty, the character's child
## named "DetectionArea" is used. Set its collision mask to the layers of the targets.
@export var detection_area: Area2D

var behavior: Behavior = Behavior.IDLE
var _character: Character2D
var _target: Node2D
# Untyped on purpose: a candidate can be freed while it is still in the list.
var _candidates: Array = []
var _home_position := Vector2.ZERO
var _lost_target_elapsed := 0.0
var _movement_intent := Vector2.ZERO
var _aim_direction := Vector2.RIGHT
## Id of the attack to start this frame; empty = none.
var _requested_attack_id: StringName = &""
## Random source for picking between profile.attack_choices (seed it in tests).
var rng := RandomNumberGenerator.new()
## The picked attack while profile.attack_choices is in use; empty = pick on next use.
var _chosen_attack_id: StringName = &""
## Choice ids already reported as not registered, so the warning is printed once.
var _warned_choice_ids: Dictionary = {}
## Wind-up (EnemyBehaviorProfile.attack_windup_duration): true while the warning lane is up and the swing has not started.
var _winding_up := false
var _windup_elapsed := 0.0
## Seconds left before the next swing may be requested (EnemyBehaviorProfile.attack_interval).
var _interval_remaining := 0.0
var _telegraph: EnemyAttackTelegraph2D
## Swings played in the combo in progress (counts chained swings too); 0 when no swing is running.
var _combo_count := 0
## Why the last combo check pressed again or stopped (set only while the combo window is open). Debug output.
var last_combo_decision := ""
## Charged attacks (C1): an attack with a charge_threshold is begun and released through the character's charge hooks
## instead of being requested as a plain swing. True from the request until that swing ends.
var _heavy_charging := false
## The charge was requested this frame; the next frame checks that it really started.
var _charge_begin_pending := false
var _requested_charge_id: StringName = &""
var _release_requested := false
## Direction the charge was aimed at when it began. It stays fixed so the warning lane and the swing agree and the
## player can step out of the way.
var _charge_aim := Vector2.RIGHT
## Seconds spent waiting for an opening before a chosen charged attack (EnemyBehaviorProfile.heavy_wait_for_opening).
var _heavy_wait_elapsed := 0.0
## Why the last heavy check went ahead, waited or fell back. Debug output.
var last_heavy_decision := ""
## Weapon skills (D1). One roll against skill_usage_priority is made when a skill becomes usable and kept while it stays
## usable, so the chance is not rolled again every frame.
var _skill_rolls: Dictionary = {}
## Why the last skill check used a skill, or why each skill was set aside. Debug output.
var last_skill_decision := ""
var _skill_winding_up := false
var _skill_windup_id: StringName = &""
var _skill_windup_elapsed := 0.0
var _retreating := false
# DE2 attack slots: the holders of a target's slots are kept on the target node (meta SLOT_META), so there is no global state.
const SLOT_META := &"enemy_attack_slots"
const SLOT_IDLE_RELEASE := 0.5
var _holds_slot := false
var _slot_is_heavy := false
var _slot_target: Node2D
var _slot_idle_elapsed := 0.0
## Why the last slot request was granted or refused (debug output).
var last_slot_decision := ""
var _slot_waiting := false
var _circle_sign := 0.0
const REPOSITION_FLIP_TIME := 1.5
var _reposition_sign := 0.0
var _reposition_elapsed := 0.0
var _retreat_elapsed := 0.0
var _retreat_rest_remaining := 0.0
## Debug text for the last target change or refusal (Track E). Empty until the profile uses target_switching.
var last_target_decision := ""
var _switch_cooldown := 0.0
## Debug list for the last weighted attack pick: one line per attack_choices entry, saying whether it was a candidate or why it
## was rejected (zero weight, not registered, skipped because it charges). Empty until an attack has been picked.
var last_attack_candidates: Array[String] = []

func initialize(character: Character2D) -> void:
	_character = character
	_home_position = character.global_position
	_aim_direction = character.context.facing_direction
	if profile == null:
		profile = EnemyBehaviorProfile.new()
	_setup_detection_area()
	if is_instance_valid(character.attack_component):
		character.attack_component.attack_started.connect(_on_attack_started)
		character.attack_component.swing_ended.connect(_on_swing_ended)

func physics_update(delta: float) -> void:
	if not is_instance_valid(_character) or _character.context == null or not _character.is_alive():
		_movement_intent = Vector2.ZERO
		_requested_attack_id = &""
		_requested_charge_id = &""
		_release_requested = false
		_end_heavy_charge()
		_cancel_windup()
		_cancel_skill_windup()
		_release_slot()
		return
	_requested_attack_id = &""
	_requested_charge_id = &""
	_release_requested = false
	_interval_remaining = maxf(_interval_remaining - delta, 0.0)
	_refresh_target(delta)
	_update_slot_leak(delta)
	if _heavy_charging:
		_update_heavy_charge()

	if _is_valid_target(_target):
		var to_target: Vector2 = _target.global_position - _character.global_position
		var distance: float = to_target.length()
		if distance > 0.001:
			_aim_direction = to_target / distance
		else:
			_aim_direction = _character.context.facing_direction
		if _wants_combo_continue(distance):
			_requested_attack_id = _character.get_default_attack_id() # any registered id chains while the window is open
		if _try_use_skill(distance, delta):
			_cancel_windup()
			_movement_intent = Vector2.ZERO
			return
		if _update_retreat(distance, delta):
			_cancel_windup()
			_movement_intent = -_aim_direction # backs away but keeps facing the target (the aim stays on it)
			_set_behavior(Behavior.ATTACK if distance <= get_effective_attack_range() else Behavior.CHASE)
			return
		if distance <= get_effective_attack_range():
			_movement_intent = Vector2.ZERO
			_set_behavior(Behavior.ATTACK)
			if _can_begin_attack():
				_update_windup(delta)
				if _slot_waiting and profile.circle_while_waiting:
					_movement_intent = _circle_intent(to_target, distance)
			else:
				_cancel_windup()
				if profile.preferred_combat_range > 0.0 and _is_free_to_move():
					_movement_intent = _reposition_intent(to_target, distance, delta)
		else:
			_cancel_windup()
			_movement_intent = to_target.normalized()
			_set_behavior(Behavior.CHASE)
		return

	_cancel_windup() # no valid target: the warning goes away
	_cancel_skill_windup()
	_release_slot()

	var to_home: Vector2 = _home_position - _character.global_position
	if to_home.length() > profile.home_stop_distance:
		_movement_intent = to_home.normalized()
		if to_home.length_squared() > 0.001:
			_aim_direction = to_home.normalized()
		_set_behavior(Behavior.RETURN)
	else:
		_movement_intent = Vector2.ZERO
		_set_behavior(Behavior.IDLE)

func _on_attack_started(_direction: Vector2) -> void:
	_combo_count += 1
	if _heavy_charging and is_instance_valid(_telegraph) and _telegraph.is_lane_visible():
		_telegraph.hide_lane() # the charge is released: the swing is under way

func _on_swing_ended(_cancelled: bool) -> void:
	_end_heavy_charge()
	# A combo (two or more swings) that ends leaves the enemy open for combo_recovery_pause seconds.
	if _combo_count >= 2:
		_interval_remaining = maxf(_interval_remaining, profile.combo_recovery_pause)
	_combo_count = 0
	_release_slot()

## True when the combo window is open, the profile wants a longer combo than has been played, and the target is inside
## the range of the attack that would play next (the active attack's own range when it has no next_attack link).
func _wants_combo_continue(distance: float) -> bool:
	var component: AttackComponent2D = _character.attack_component
	if _heavy_charging or not component.is_combo_window_open():
		return false
	var limit := profile.preferred_combo_length
	if _combo_count >= limit:
		last_combo_decision = "stop: length reached (%d of %d)" % [_combo_count, limit]
		return false
	if _character.is_stunned():
		last_combo_decision = "stop: stunned"
		return false
	var active := component.get_attack(component.get_active_attack_id())
	var next := component.get_next_attack(active)
	var reference := next if next != null else active
	var reach := FALLBACK_ATTACK_RANGE
	if reference != null and reference.attack_range > 0.0:
		reach = reference.attack_range
	if distance > reach:
		last_combo_decision = "stop: out of range (%.0f > %.0f)" % [distance, reach]
		return false
	last_combo_decision = "continue (swing %d of %d, %.0f <= %.0f)" % [_combo_count, limit, distance, reach]
	return true

## True while the enemy backs away from a target closer than profile.minimum_combat_range. It only retreats when it is free
## (no swing, cast, dash, stun or wind-up under way) and for at most MAX_RETREAT_TIME at a time.
func is_retreating() -> bool:
	return _retreating

func _update_retreat(distance: float, delta: float) -> bool:
	_retreat_rest_remaining = maxf(_retreat_rest_remaining - delta, 0.0)
	var context := _character.context
	var idle := not (_winding_up or _heavy_charging or context.is_attacking or context.is_casting or context.is_dashing or _character.is_stunned())
	if profile.minimum_combat_range <= 0.0 or distance >= profile.minimum_combat_range or not idle or _retreat_rest_remaining > 0.0:
		_retreating = false
		_retreat_elapsed = 0.0
		return false
	_retreat_elapsed += delta
	if _retreat_elapsed >= MAX_RETREAT_TIME:
		_retreating = false
		_retreat_elapsed = 0.0
		_retreat_rest_remaining = RETREAT_REST
		return false
	_retreating = true
	return true

## Starts one of the equipped weapon's skills when the enemy is free and one fits the situation. The weapon owns which
## skills exist (SkillComponent2D holds the equipped weapon's active_skills); the profile only sets how readily they are
## used. A skill is set aside when SkillComponent2D says it cannot be used, or its reach or behavior does not fit the
## distance: a DASH closes a gap (the target is beyond the attack range), a PROJECTILE or AREA needs the target in reach.
## A BUFF skill (DE1) is used on the enemy itself while it has a target and the status is not already running; NONE skills are
## not used. Returns true when a skill was started.
func _try_use_skill(distance: float, delta: float = 0.0) -> bool:
	var component: SkillComponent2D = _character.skill_component
	if profile.skill_usage_priority <= 0.0 or not is_instance_valid(component) or not component.is_initialized():
		_cancel_skill_windup()
		return false
	var context := _character.context
	if context.is_attacking or context.is_dashing or context.is_casting or _character.is_stunned():
		_cancel_skill_windup()
		return false
	var usable: Dictionary = {}
	var chosen: SkillDefinition2D
	var notes: Array[String] = []
	for skill in component.get_skills():
		var problem := _skill_problem(component, skill, distance)
		if problem != "":
			notes.append("%s: %s" % [skill.id, problem])
			continue
		usable[skill.id] = true
		if not _skill_rolls.has(skill.id):
			_skill_rolls[skill.id] = rng.randf() < profile.skill_usage_priority
		if chosen == null and _skill_rolls[skill.id]:
			chosen = skill
	for skill_id in _skill_rolls.keys():
		if not usable.has(skill_id):
			_skill_rolls.erase(skill_id)
	if chosen == null:
		last_skill_decision = "none used (%s)" % "; ".join(notes) if not notes.is_empty() else "none used (rolled against)"
		_cancel_skill_windup()
		return false
	if _skill_windup_blocks(chosen, delta):
		return true
	if not component.try_use_skill(chosen.id, _aim_direction):
		last_skill_decision = "'%s' was refused when requested" % chosen.id
		return false
	_skill_rolls.erase(chosen.id)
	_cancel_skill_windup()
	last_skill_decision = "used '%s' at %.0f px" % [chosen.id, distance]
	return true

## DE3: true while the enemy is still showing the warning for `skill` (the cast waits). A skill with no drawable shape, or
## skill_windup_duration at 0, never waits.
func _skill_windup_blocks(skill: SkillDefinition2D, delta: float) -> bool:
	if profile.skill_windup_duration <= 0.0:
		return false
	var outline := get_skill_telegraph_outline(skill, _aim_direction)
	if outline.size() < 3:
		return false
	if _skill_windup_id != skill.id:
		_skill_windup_id = skill.id
		_skill_windup_elapsed = 0.0
	_skill_winding_up = true
	_skill_windup_elapsed += delta
	var telegraph := get_telegraph()
	if telegraph != null:
		telegraph.show_shape(outline)
	if _skill_windup_elapsed < profile.skill_windup_duration:
		last_skill_decision = "winding up '%s' (%.2f of %.2f s)" % [skill.id, _skill_windup_elapsed, profile.skill_windup_duration]
		return true
	return false

## The skill's warning shape as offsets from the enemy: its own aim shape drawn at the skill's real reach, so the warning is
## the area the skill can hit. Empty for a skill with no aim shape or one that is put down at a point (a ground circle).
func get_skill_telegraph_outline(skill: SkillDefinition2D, direction: Vector2) -> PackedVector2Array:
	if skill == null or skill.aim_shape == null or skill.aim_shape.is_placed():
		return PackedVector2Array()
	return skill.aim_shape.with_reach(skill.get_reach()).get_outline(direction)

## True while a skill warning is up.
func is_skill_winding_up() -> bool:
	return _skill_winding_up

func _cancel_skill_windup() -> void:
	if not _skill_winding_up:
		_skill_windup_id = &""
		return
	_skill_winding_up = false
	_skill_windup_id = &""
	_skill_windup_elapsed = 0.0
	if is_instance_valid(_telegraph) and _telegraph.is_lane_visible() and not _heavy_charging:
		_telegraph.hide_lane()

## Why `skill` does not fit right now, or an empty string when it does.
func _skill_problem(component: SkillComponent2D, skill: SkillDefinition2D, distance: float) -> String:
	if skill.behavior == SkillDefinition2D.Behavior.NONE:
		return "behavior not used by the AI yet"
	var refusal := component.can_use(skill.id)
	if refusal != "":
		return refusal
	if skill.behavior == SkillDefinition2D.Behavior.BUFF:
		# DE1: a self buff is worth casting while there is a target and the buff is not already running. It has no reach.
		var statuses := _character.status_controller
		if skill.status_effect == null or not is_instance_valid(statuses):
			return "buff has no status to apply"
		if statuses.has_status(skill.status_effect.id):
			return "buff already running"
		return ""
	var reach := skill.get_reach()
	if reach <= 0.0:
		return "no reach"
	if distance > reach:
		return "out of reach (%.0f > %.0f)" % [distance, reach]
	if skill.behavior == SkillDefinition2D.Behavior.DASH and distance <= get_effective_attack_range():
		return "already in attack range"
	return ""

## True when the enemy could start a swing this frame: not mid-swing, not dashing, not stunned, the attack's cooldown is
## over and the pacing interval has run out.
func _can_begin_attack() -> bool:
	if _character.context.is_attacking or _character.context.is_dashing or _character.context.is_casting:
		return false
	if _character.is_stunned() or _character.attack_component.is_on_cooldown():
		return false
	return _interval_remaining <= 0.0

## Runs the wind-up while an attack could begin. At 0 duration the swing is requested at once. Otherwise the lane shows
## until the duration has passed, then the swing is requested and the lane goes away.
func _update_windup(delta: float) -> void:
	var chosen := get_chosen_attack()
	_slot_waiting = false
	if not _holds_slot and not _try_take_slot(_is_chargeable(chosen)):
		_slot_waiting = true
		_cancel_windup() # every slot on this target is taken: wait (or circle) and ask again next frame
		return
	if _is_chargeable(chosen):
		if not _heavy_is_allowed(chosen, delta):
			return
		_begin_heavy_charge(chosen) # the charge is the warning, so the plain wind-up is skipped
		return
	var duration := profile.attack_windup_duration
	if duration > 0.0:
		if not _winding_up:
			_winding_up = true
			_windup_elapsed = 0.0
		_show_telegraph()
		_windup_elapsed += delta
		if _windup_elapsed < duration:
			return
	_cancel_windup()
	_requested_attack_id = get_chosen_attack_id()
	_chosen_attack_id = &"" # pick again for the next swing
	_interval_remaining = profile.attack_interval

## True when `attack_definition` charges (its charge_threshold is above 0). The attack definition owns this, not the AI.
func _is_chargeable(attack_definition: AttackDefinition2D) -> bool:
	return attack_definition != null and attack_definition.charge_threshold > 0.0

## True when the chosen charged attack may start now. With heavy_wait_for_opening at 0 it always may. Otherwise it waits for
## an opening in the target (see _opening_reason) and, when none comes within that time, drops the heavy for another
## attack of the profile (or the default attack).
func _heavy_is_allowed(attack_definition: AttackDefinition2D, delta: float) -> bool:
	var patience := profile.heavy_wait_for_opening
	if patience <= 0.0:
		return true
	var reason := _opening_reason(attack_definition)
	if reason != "":
		_heavy_wait_elapsed = 0.0
		last_heavy_decision = "go: " + reason
		return true
	_heavy_wait_elapsed += delta
	if _heavy_wait_elapsed < patience:
		last_heavy_decision = "wait: no opening (%.2f of %.2f s)" % [_heavy_wait_elapsed, patience]
		return false
	_heavy_wait_elapsed = 0.0
	var fallback := _pick_attack(_character.attack_component, true)
	if fallback == null:
		fallback = _character.attack_component.definition
	_chosen_attack_id = fallback.id if fallback != null else &""
	last_heavy_decision = "fallback: no opening, using '%s'" % str(_chosen_attack_id)
	return false

## Why the target is a good one for the heavy right now, or an empty string when it is not: stunned, committed to a swing,
## moving so little that it cannot leave the attack's area during the charge, or predicted to be inside the lane when it ends.
func _opening_reason(attack_definition: AttackDefinition2D) -> String:
	var target := get_current_target() as Character2D
	if target == null:
		return ""
	if target.is_stunned():
		return "target stunned"
	if target.context != null and target.context.is_attacking:
		return "target committed to a swing"
	var drift := target.velocity.length() * attack_definition.charge_threshold
	if drift <= attack_definition.hitbox_size.y * 0.5:
		return "target nearly still (drift %.0f px)" % drift
	return _predicted_hit_reason(attack_definition, target)

## Phase C: where the target will be when the charge is done, if it keeps its velocity, against the lane the attack will cover
## (its full reach along the current aim, hitbox_size.y wide, plus a small margin for the target's body). A target walking along
## the lane, or toward the enemy, is hit even though it moves. Empty when the predicted spot is outside the lane.
const LANE_BODY_MARGIN := 8.0
func _predicted_hit_reason(attack_definition: AttackDefinition2D, target: Character2D) -> String:
	var predicted := target.global_position + target.velocity * attack_definition.charge_threshold
	var offset := predicted - _character.global_position
	var along := offset.dot(_aim_direction)
	var across := absf(offset.cross(_aim_direction))
	var reach := attack_definition.get_reach()
	if along < 0.0 or along > reach or across > attack_definition.hitbox_size.y * 0.5 + LANE_BODY_MARGIN:
		return ""
	return "target predicted inside the lane (%.0f of %.0f px along, %.0f px across)" % [along, reach, across]

func _begin_heavy_charge(attack_definition: AttackDefinition2D) -> void:
	_cancel_windup()
	_requested_charge_id = attack_definition.id
	_chosen_attack_id = &"" # pick again for the next attack
	_interval_remaining = profile.attack_interval
	_heavy_charging = true
	_charge_begin_pending = true
	# Read the live aim, not get_aim_direction(): _heavy_charging is already true here, so that would hand back the old _charge_aim.
	_charge_aim = _aim_direction if _aim_direction.length_squared() > 0.001 else Vector2.RIGHT
	_show_heavy_lane(attack_definition)

## Runs each frame while a charge is requested or held: confirms it started, keeps the lane up and releases at a full
## charge (an attack that releases itself at its threshold ignores the request). Once released the state is cleared by
## swing_ended.
func _update_heavy_charge() -> void:
	var component: AttackComponent2D = _character.attack_component
	if _charge_begin_pending:
		_charge_begin_pending = false
		if not component.is_charging():
			_end_heavy_charge() # the begin was refused (cooldown, stun, ...)
			_release_slot()
			return
	if component.is_charging():
		_show_heavy_lane(component.get_charging_definition())
		if component.get_charge_ratio() >= 1.0:
			_release_requested = true

func _end_heavy_charge() -> void:
	_heavy_charging = false
	_charge_begin_pending = false
	if is_instance_valid(_telegraph) and _telegraph.is_lane_visible():
		_telegraph.hide_lane()

func _show_heavy_lane(attack_definition: AttackDefinition2D) -> void:
	var telegraph := get_telegraph()
	if telegraph != null and attack_definition != null:
		telegraph.show_lane(_charge_aim, attack_definition.get_reach(), attack_definition.hitbox_size.y)

## True while the warning is up (the swing has not started yet).
func is_winding_up() -> bool:
	return _winding_up

func get_windup_elapsed() -> float:
	return _windup_elapsed if _winding_up else 0.0

## The telegraph node: the character's child named EnemyAttackTelegraph2D, made on first use when the scene has none.
func get_telegraph() -> EnemyAttackTelegraph2D:
	if not is_instance_valid(_telegraph):
		if not is_instance_valid(_character):
			return null
		_telegraph = _character.get_node_or_null("EnemyAttackTelegraph2D") as EnemyAttackTelegraph2D
		if _telegraph == null:
			_telegraph = EnemyAttackTelegraph2D.new()
			_telegraph.name = "EnemyAttackTelegraph2D"
			_character.add_child(_telegraph)
	return _telegraph

func _show_telegraph() -> void:
	var telegraph := get_telegraph()
	if telegraph == null:
		return
	var attack_definition := get_chosen_attack()
	# Only the heavy attack (and, later, an enemy skill) is warned about. A basic attack still waits out the wind-up but
	# shows no lane.
	if not profile.telegraph_all_attacks and not _is_heavy_attack(attack_definition):
		if telegraph.is_lane_visible():
			telegraph.hide_lane()
		return
	var length := get_effective_attack_range()
	var width := attack_definition.hitbox_size.y if attack_definition != null else 0.0
	telegraph.show_lane(get_aim_direction(), length, width)

## True when `attack_definition` is the heavy attack of the weapon this enemy has equipped.
func _is_heavy_attack(attack_definition: AttackDefinition2D) -> bool:
	if attack_definition == null or not is_instance_valid(_character):
		return false
	var weapons := _character.get_node_or_null("WeaponController2D") as WeaponController2D
	if weapons == null:
		return false
	var weapon := weapons.get_equipped_weapon()
	return weapon != null and weapon.heavy_attack != null and weapon.heavy_attack.id == attack_definition.id

## Drops the wind-up and hides the lane. Safe to call every frame.
func _cancel_windup() -> void:
	_heavy_wait_elapsed = 0.0
	_winding_up = false
	_windup_elapsed = 0.0
	if is_instance_valid(_telegraph) and _telegraph.is_lane_visible() and not _heavy_charging and not _skill_winding_up:
		_telegraph.hide_lane()

## True when nothing the enemy is doing (a swing, cast, dash, charge, stun) forbids walking.
func _is_free_to_move() -> bool:
	var context := _character.context
	return not (context.is_attacking or context.is_casting or context.is_dashing or _heavy_charging or _winding_up or _character.is_stunned())

## Phase E repositioning: sideways around the target, switching side every REPOSITION_FLIP_TIME seconds, with a pull toward
## preferred_combat_range (at most 95% of the attack's range). Used while the enemy is in range but cannot attack yet.
func _reposition_intent(to_target: Vector2, distance: float, delta: float) -> Vector2:
	if _reposition_sign == 0.0:
		_reposition_sign = 1.0 if rng.randf() < 0.5 else -1.0
	_reposition_elapsed += delta
	if _reposition_elapsed >= REPOSITION_FLIP_TIME:
		_reposition_elapsed = 0.0
		_reposition_sign = -_reposition_sign
	var toward := to_target / maxf(distance, 0.001)
	var wanted := minf(profile.preferred_combat_range, get_effective_attack_range() * 0.95)
	var radial := clampf((distance - wanted) / maxf(wanted, 1.0), -1.0, 1.0)
	return (toward.orthogonal() * _reposition_sign * 0.8 + toward * radial).normalized()

## True while the enemy is in range but waiting for an attack slot.
func is_waiting_for_slot() -> bool:
	return _slot_waiting

## Movement for circle_while_waiting: sideways around the target (the side is picked once, at random from the seeded rng), with a
## pull toward 90% of the attack range so the circle stays inside the distance it will attack from.
func _circle_intent(to_target: Vector2, distance: float) -> Vector2:
	if _circle_sign == 0.0:
		_circle_sign = 1.0 if rng.randf() < 0.5 else -1.0
	var toward := to_target / maxf(distance, 0.001)
	var tangent := toward.orthogonal() * _circle_sign
	var wanted := get_effective_attack_range() * 0.9
	var radial := clampf((distance - wanted) / maxf(wanted, 1.0), -1.0, 1.0)
	return (tangent + toward * radial).normalized()

## True while this enemy holds one of its target's attack slots (DE2).
func holds_attack_slot() -> bool:
	return _holds_slot

## Takes an attack slot on the current target. With max_simultaneous_attackers at 0 there is no limit and nothing is tracked.
## A heavy also needs room under max_simultaneous_heavies. False (and last_slot_decision says why) when the group is full.
func _try_take_slot(heavy: bool) -> bool:
	var limit := profile.max_simultaneous_attackers
	if limit <= 0 or not is_instance_valid(_target):
		return true
	var holders := _slot_holders(_target)
	if holders.size() >= limit:
		last_slot_decision = "wait: %d of %d attack slots taken" % [holders.size(), limit]
		return false
	if heavy and profile.max_simultaneous_heavies > 0:
		var heavies := 0
		for holder in holders:
			if (holder as EnemyAIController2D)._slot_is_heavy:
				heavies += 1
		if heavies >= profile.max_simultaneous_heavies:
			last_slot_decision = "wait: %d of %d heavy slots taken" % [heavies, profile.max_simultaneous_heavies]
			return false
	holders.append(self)
	_target.set_meta(SLOT_META, holders)
	_holds_slot = true
	_slot_is_heavy = heavy
	_slot_target = _target
	_slot_idle_elapsed = 0.0
	last_slot_decision = "took slot %d of %d%s" % [holders.size(), limit, " (heavy)" if heavy else ""]
	return true

## The controllers holding a slot on `target`, with anything freed or no longer holding removed.
func _slot_holders(target: Node) -> Array:
	var holders: Array = []
	if is_instance_valid(target) and target.has_meta(SLOT_META):
		for holder in target.get_meta(SLOT_META):
			if is_instance_valid(holder) and (holder as EnemyAIController2D)._holds_slot and (holder as EnemyAIController2D)._slot_target == target:
				holders.append(holder)
	return holders

func _release_slot() -> void:
	if not _holds_slot:
		return
	if is_instance_valid(_slot_target) and _slot_target.has_meta(SLOT_META):
		var holders: Array = _slot_target.get_meta(SLOT_META)
		holders.erase(self)
		_slot_target.set_meta(SLOT_META, holders)
	_holds_slot = false
	_slot_is_heavy = false
	_slot_target = null
	_slot_idle_elapsed = 0.0

## A slot is freed when its holder switches target, or when it has been doing nothing for SLOT_IDLE_RELEASE seconds (a swing
## that was refused, for example), so a slot can never stay taken for good.
func _update_slot_leak(delta: float) -> void:
	if not _holds_slot:
		return
	if _slot_target != _target:
		_release_slot()
		return
	var busy := _winding_up or _heavy_charging or _character.context.is_attacking
	if busy:
		_slot_idle_elapsed = 0.0
		return
	_slot_idle_elapsed += delta
	if _slot_idle_elapsed >= SLOT_IDLE_RELEASE:
		_release_slot()

func _exit_tree() -> void:
	_release_slot()

## Distance at which this enemy starts a swing: the chosen attack's attack_range when it
## is above zero, otherwise FALLBACK_ATTACK_RANGE.
func get_effective_attack_range() -> float:
	var attack_definition := get_chosen_attack()
	if attack_definition != null and attack_definition.attack_range > 0.0:
		return attack_definition.attack_range
	return FALLBACK_ATTACK_RANGE

## The attack the AI will use for its next swing. With no usable entry in
## profile.attack_choices this is always the character's default attack (read live, so
## swapping it takes effect at once). Otherwise a weighted pick that is kept until the swing
## is requested (or reset_attack_choice() is called).
func get_chosen_attack() -> AttackDefinition2D:
	if not is_instance_valid(_character) or not is_instance_valid(_character.attack_component):
		return null
	var component: AttackComponent2D = _character.attack_component
	if _chosen_attack_id != &"":
		var current := component.get_attack(_chosen_attack_id)
		if current != null:
			return current
		_chosen_attack_id = &""
	var picked := _pick_attack(component)
	if picked == null:
		return component.definition
	_chosen_attack_id = picked.id
	return picked

func get_chosen_attack_id() -> StringName:
	var chosen := get_chosen_attack()
	return chosen.id if chosen != null else &""

## Forgets the picked attack, so the next call picks again (use after editing the choices).
func reset_attack_choice() -> void:
	_chosen_attack_id = &""

## Weighted random pick from profile.attack_choices, or null when no entry is usable (empty
## list, zero weights, or entries that are not registered on the attack component).
func _pick_attack(component: AttackComponent2D, skip_chargeable: bool = false) -> AttackDefinition2D:
	if profile == null:
		return null
	var usable: Array[AttackDefinition2D] = []
	var weights: Array[float] = []
	var total := 0.0
	var report: Array[String] = []
	for choice in profile.attack_choices:
		if choice == null or choice.attack == null:
			report.append("(empty entry): rejected, no attack set")
			continue
		var label := str(choice.attack.id)
		if choice.weight <= 0.0:
			report.append("%s: rejected, weight 0" % label)
			continue
		if skip_chargeable and _is_chargeable(choice.attack):
			report.append("%s: rejected, charges (heavy skipped)" % label)
			continue
		var registered := component.get_attack(choice.attack.id)
		if registered == null:
			report.append("%s: rejected, not registered on the AttackComponent2D" % label)
			if not _warned_choice_ids.has(choice.attack.id):
				_warned_choice_ids[choice.attack.id] = true
				push_warning("EnemyAIController2D on '%s': attack choice '%s' is not registered on its AttackComponent2D (add it to 'attacks'); ignored." % [_character.name, choice.attack.id])
			continue
		usable.append(registered)
		weights.append(choice.weight)
		total += choice.weight
		report.append("%s: candidate, weight %.1f" % [label, choice.weight])
	if usable.is_empty():
		last_attack_candidates = report
		return null
	var roll := rng.randf() * total
	var picked: AttackDefinition2D = usable[usable.size() - 1]
	for i in usable.size():
		roll -= weights[i]
		if roll < 0.0:
			picked = usable[i]
			break
	report.append("picked: %s" % str(picked.id))
	last_attack_candidates = report
	return picked

## Radius of the circle currently used for detection (0 when there is no usable area).
func get_detection_radius() -> float:
	var circle := _find_detection_circle()
	return circle.radius if circle != null else 0.0

func get_behavior_name() -> String:
	return Behavior.keys()[behavior]

## Number of valid bodies currently inside the detection area.
func get_candidate_count() -> int:
	_prune_candidates()
	return _candidates.size()

func get_movement_intent() -> Vector2:
	return _movement_intent

func get_aim_direction() -> Vector2:
	if _heavy_charging:
		return _charge_aim
	return _aim_direction if _aim_direction.length_squared() > 0.001 else Vector2.RIGHT

func get_attack_direction() -> Vector2:
	return get_aim_direction()

## Returns the id of the attack the AI wants to start (empty = none) and clears the request.
func consume_attack_request() -> StringName:
	var requested := _requested_attack_id
	_requested_attack_id = &""
	return requested

## The id of the charged attack to begin this frame (empty = none); clears the request.
func consume_charge_request() -> StringName:
	var requested := _requested_charge_id
	_requested_charge_id = &""
	return requested

## True when the charge in progress should be released this frame; clears the request.
func consume_release_request() -> bool:
	var requested := _release_requested
	_release_requested = false
	return requested

func get_current_target() -> Node2D:
	return _target if _is_valid_target(_target) else null

func _setup_detection_area() -> void:
	if not is_instance_valid(detection_area):
		detection_area = _character.get_node_or_null("DetectionArea") as Area2D
	if detection_area == null:
		push_error("EnemyAIController2D on '%s' has no DetectionArea (Area2D); the enemy will never notice a target." % _character.name)
		return
	var circle := _find_detection_circle()
	if circle == null:
		push_error("EnemyAIController2D on '%s': its DetectionArea needs a CollisionShape2D with a CircleShape2D." % _character.name)
	elif profile.detection_radius > 0.0:
		# The drawn shape is a scene sub-resource shared by every instance, so override a copy.
		var override_circle := circle.duplicate() as CircleShape2D
		override_circle.radius = profile.detection_radius
		_find_detection_shape_node().shape = override_circle
	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)

func _find_detection_shape_node() -> CollisionShape2D:
	if not is_instance_valid(detection_area):
		return null
	for child in detection_area.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape is CircleShape2D:
			return child as CollisionShape2D
	return null

func _find_detection_circle() -> CircleShape2D:
	var shape_node := _find_detection_shape_node()
	return shape_node.shape as CircleShape2D if shape_node != null else null

func _on_body_entered(body: Node2D) -> void:
	if not _is_hostile(body):
		return
	if not _candidates.has(body):
		_candidates.append(body)

## A character with a team of its own that is not this enemy's team. Neutral (empty team) characters, bodies that
## are not characters, and the enemy itself are not hostile.
func _is_hostile(body: Node) -> bool:
	if body == _character or not body is Character2D:
		return false
	var other_team := (body as Character2D).team
	return other_team != &"" and other_team != _character.team

func _on_body_exited(body: Node2D) -> void:
	_candidates.erase(body)

func _prune_candidates() -> void:
	for i in range(_candidates.size() - 1, -1, -1):
		if not _is_valid_target(_candidates[i]):
			_candidates.remove_at(i)

func _refresh_target(delta: float) -> void:
	_switch_cooldown = maxf(_switch_cooldown - delta, 0.0)
	if _is_valid_target(_target):
		var distance: float = _character.global_position.distance_to(_target.global_position)
		if distance <= profile.disengage_radius:
			_lost_target_elapsed = 0.0
			_maybe_switch_target(distance)
			return
		_lost_target_elapsed += delta
		if _lost_target_elapsed < profile.lost_target_grace_duration:
			return
		_target = null
		_lost_target_elapsed = 0.0
	_target = _find_nearest_candidate()

## Track E target switching: with profile.target_switching = NEAREST, change to a hostile that is at least target_switch_margin
## closer than the current target, at most once per target_switch_min_interval, and only while the enemy is free to move and
## holds no attack slot (so a swing, a combo or a slot is never dropped for a new target). Does nothing at KEEP_CURRENT.
func _maybe_switch_target(current_distance: float) -> void:
	if profile.target_switching != EnemyBehaviorProfile.TargetSwitching.NEAREST:
		return
	if _switch_cooldown > 0.0:
		return
	if not _is_free_to_move() or _holds_slot:
		return
	var nearest := _find_nearest_candidate()
	if nearest == null or nearest == _target:
		return
	var nearest_distance: float = _character.global_position.distance_to(nearest.global_position)
	if nearest_distance + profile.target_switch_margin > current_distance:
		last_target_decision = "keep '%s': '%s' is only %.0f px closer (needs %.0f)" % [_target.name, nearest.name, current_distance - nearest_distance, profile.target_switch_margin]
		return
	last_target_decision = "switch '%s' -> '%s': %.0f px closer" % [_target.name, nearest.name, current_distance - nearest_distance]
	_target = nearest
	_switch_cooldown = profile.target_switch_min_interval
	_combo_count = 0

func _find_nearest_candidate() -> Node2D:
	_prune_candidates()
	var nearest: Node2D
	var nearest_distance := INF
	for candidate in _candidates:
		var node := candidate as Node2D
		var distance: float = _character.global_position.distance_to(node.global_position)
		if distance < nearest_distance:
			nearest = node
			nearest_distance = distance
	return nearest

func _is_valid_target(candidate: Node) -> bool:
	if not is_instance_valid(candidate) or not candidate is Node2D or candidate == _character:
		return false
	if not candidate.is_inside_tree() or candidate.is_queued_for_deletion():
		return false
	if candidate.has_method("is_alive") and not bool(candidate.call("is_alive")):
		return false
	return true

func _set_behavior(next_behavior: Behavior) -> void:
	if behavior == next_behavior:
		return
	var previous := behavior
	behavior = next_behavior
	behavior_changed.emit(previous, behavior)
