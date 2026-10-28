extends Node
class_name SkillComponent2D
## Runs the active skills of one character (13.2): gating, cost, cooldown, cast and interruption. Optional:
## Character2D initializes it when it has a child named SkillComponent2D, and WeaponController2D gives it the equipped
## weapon's skills. All runtime state (cooldowns, the cast in progress) lives here, never in a SkillDefinition2D.
##
## Rules (docs/phase13/13.0-notes.md):
##   - A skill starts only when the character is alive, not attacking or charging, not dashing, not stunned, not already
##     casting, the skill is off cooldown and its cost can be paid. A refused skill spends nothing and starts no cooldown.
##   - COMMIT POINT: the cost is paid and the cooldown starts the moment the cast starts (an instant skill executes at once).
##   - A cast that is cancelled before it executes (an interruptible skill hit by a damaging hit, death, cancel()) gives the
##     whole cost back and clears that skill's cooldown, so a skill that never executed costs nothing.
##   - While casting, the character cannot start an attack or a dash (context.is_casting).
##   - Cooldowns keep running when the weapon is switched.
##
## Behaviors (projectile, area, dash, buff) arrive in 13.3, one step each. PROJECTILE is built (13.3.1): executing the skill
## spawns the attack's effect scene (a ProjectileEffect2D) at the attack origin, aimed along the skill's direction. AREA is
## built (13.3.2): it spawns an AreaEffect2D at the attack origin, its circle placed by the attack's hitbox_offset along the
## direction (or centred on the caster for SELF targeting), sized by area_radius. Projectiles can also be emitted as a data-defined fan (13.4.7). Either effect belongs to the world from then on:
## cancelling a cast or killing the caster later does not remove it. DASH is built (13.3.3): the caster dashes max_range px at
## dash_speed through DashComponent2D.start_skill_dash(), and an optional attack makes an AreaEffect2D that travels with the
## caster for the length of the dash. BUFF is built (13.3.4): it puts the skill's status_effect on the caster through its
## StatusController2D; a caster with none is refused by can_use() before anything is spent.
##
## SKILL CLIP (H2.2, decision D3): a skill that names a weapon_animation plays that clip when it starts, then executes after
## its cast time; a cancelled cast stops the clip. See _play_clip().
##
## HUD signals (13.4.1): cooldown_started / cooldown_finished, skill_refused and skills_changed let a skill bar react to
## events instead of polling. The bar still reads get_cooldown_remaining(), get_cooldown_duration() and get_cast_progress()
## every frame for the wipe itself.

## The cast started: the cost is paid and the cooldown is running.
signal skill_started(skill: SkillDefinition2D)
## The skill's effect point: an instant skill emits it at once, a cast skill when its cast time is over.
signal skill_executed(skill: SkillDefinition2D, direction: Vector2)
## A cast was cancelled before it executed (the cost is back and the cooldown cleared).
signal skill_cancelled(skill: SkillDefinition2D)
## The effect of a skill's attack (projectile or area) damaged `target` by `damage` (the effect's hit_confirmed signal).
signal skill_hit(skill: SkillDefinition2D, target: Node, damage: int)
## (13.4.1) A cooldown began: `duration` seconds. Not emitted for a skill whose cooldown is 0. Emitted before skill_started.
signal cooldown_started(skill: SkillDefinition2D, duration: float)
## (13.4.1) A cooldown ended: it ran out, or a cancelled cast cleared it. It carries the id, not the skill, because a cooldown
## keeps running after a weapon switch and the skill may no longer be set. The cooldown is already gone when this arrives.
signal cooldown_finished(skill_id: StringName)
## (13.4.1) A known skill was refused by can_use(); `reason` is its message. Not emitted for an unknown id or an empty slot.
signal skill_refused(skill: SkillDefinition2D, reason: String)
## (13.4.1) The set of skills was replaced (a weapon was equipped, or set_skills() was called), even when it came out the same.
signal skills_changed

## Float sums of 1/60 s fall a hair short of whole seconds; this keeps the end of a cast or cooldown from slipping a frame.
const TIME_EPSILON := 0.0001
## The shortest flight a max_range can ask of a projectile (the same minimum ProjectileEffect2D.lifetime exports).
const MIN_PROJECTILE_LIFETIME := 0.05
## The shortest dash a skill can ask of DashComponent2D, in seconds.
const MIN_DASH_TIME := 0.05

var context: CharacterContext2D
var mana: ManaComponent2D
var _initialized := false
## id -> SkillDefinition2D, and slot -> id, for the skills set now.
var _skills: Dictionary = {}
var _slots: Dictionary = {}
## id -> seconds left. Entries stay (and tick) for skills no longer set, so switching weapons does not reset them.
var _cooldowns: Dictionary = {}
## id -> the full length of the cooldown running now (13.4.1), for the HUD's wipe. Same keys as _cooldowns.
var _cooldown_durations: Dictionary = {}
var _casting: SkillDefinition2D
var _cast_remaining := 0.0
var _cast_direction := Vector2.RIGHT
## H2.2: the weapon AnimationPlayer this component listens to for the end of a skill clip, and the clip playing now (or &"").
var _watched_player: AnimationPlayer
var _clip_playing: StringName = &""

func _ready() -> void:
	set_physics_process(false)

## Called by Character2D (or a test). `mana_pool` may be null: skills with a mana cost are then refused.
func initialize(shared_context: CharacterContext2D, mana_pool: ManaComponent2D = null) -> void:
	context = shared_context
	mana = mana_pool
	_initialized = context != null and context.character is CharacterBody2D
	if not _initialized:
		push_error("SkillComponent2D requires a valid CharacterContext2D.")

func is_initialized() -> bool:
	return _initialized

## Replaces the skills (a weapon was equipped). A skill that is invalid, repeats an id or takes an occupied slot is skipped
## with a message and the others are kept. Returns how many were accepted. A cast in progress goes on.
func set_skills(new_skills: Array) -> int:
	_skills.clear()
	_slots.clear()
	var slot_count := WeaponDefinition2D.MAX_SKILL_SLOTS
	for entry in new_skills:
		var skill := entry as SkillDefinition2D
		if skill == null:
			push_warning("SkillComponent2D: ignoring an empty entry in the skills.")
			continue
		var problems := skill.validate(null, slot_count)
		if not problems.is_empty():
			push_error("SkillComponent2D rejected skill: %s" % problems[0])
			continue
		if _skills.has(skill.id):
			push_warning("SkillComponent2D: duplicate skill id '%s'; the first one is kept." % skill.id)
			continue
		if _slots.has(skill.slot):
			push_warning("SkillComponent2D: skill '%s' wants slot %d, which '%s' already holds; it is ignored." % [skill.id, skill.slot, _slots[skill.slot]])
			continue
		_skills[skill.id] = skill
		_slots[skill.slot] = skill.id
	var accepted := _skills.size()
	skills_changed.emit()
	return accepted

func get_skill(skill_id: StringName) -> SkillDefinition2D:
	return _skills.get(skill_id) as SkillDefinition2D

func get_skill_in_slot(slot: int) -> SkillDefinition2D:
	return get_skill(_slots.get(slot, &""))

func get_skills() -> Array[SkillDefinition2D]:
	var all: Array[SkillDefinition2D] = []
	for skill in _skills.values():
		all.append(skill as SkillDefinition2D)
	return all

func has_skill(skill_id: StringName) -> bool:
	return _skills.has(skill_id)

## Why `skill_id` cannot be used right now, as a readable message, or an empty string when it can. Changes nothing.
## The checks run in this order: unknown skill, dead, casting, attacking or charging, dashing, stunned, cooldown, what the
## behavior needs of the caster (a buff needs a StatusController2D), cost.
func can_use(skill_id: StringName) -> String:
	if not _initialized:
		return "the skill component is not initialized"
	var skill := get_skill(skill_id)
	if skill == null:
		return "no skill with id '%s'" % skill_id
	var character := context.character as Character2D
	if character != null and not character.is_alive():
		return "the character is dead"
	if _casting != null:
		return "already casting '%s'" % _casting.id
	if context.is_attacking:
		return "the character is attacking"
	if context.is_dashing:
		return "the character is dashing"
	if context.hit_stun_remaining > 0.0:
		return "the character is stunned"
	var left := get_cooldown_remaining(skill_id)
	if left > 0.0:
		return "on cooldown (%.2f s left)" % left
	var behavior_problem := _behavior_problem(skill)
	if behavior_problem != "":
		return behavior_problem
	return _cost_problem(skill)

## Starts the skill with this id. False, with nothing spent, when can_use() gives a reason. An unknown id also warns.
## The direction defaults to the aim, then the facing, then right.
func try_use_skill(skill_id: StringName, direction: Vector2 = Vector2.ZERO) -> bool:
	if _initialized and get_skill(skill_id) == null:
		push_warning("SkillComponent2D: no skill with id '%s' (known: %s)." % [skill_id, _skills.keys()])
		return false
	var problem := can_use(skill_id)
	if problem != "":
		var refused := get_skill(skill_id)
		if refused != null:
			skill_refused.emit(refused, problem)
		return false
	var skill := get_skill(skill_id)
	_pay(skill)
	_start_cooldown(skill)
	var aim := _resolve_direction(direction, skill)
	skill_started.emit(skill)
	_play_clip(skill)
	if skill.cast_time <= 0.0:
		_execute(skill, aim)
	else:
		_casting = skill
		_cast_remaining = skill.cast_time
		_cast_direction = aim
		context.is_casting = true
	set_physics_process(true)
	return true

## try_use_skill() for the skill in a slot (0-based). False when the slot is empty.
func try_use_slot(slot: int, direction: Vector2 = Vector2.ZERO) -> bool:
	var skill := get_skill_in_slot(slot)
	return skill != null and try_use_skill(skill.id, direction)

func get_cooldown_remaining(skill_id: StringName) -> float:
	return float(_cooldowns.get(skill_id, 0.0))

## The full length in seconds of the cooldown running now (13.4.1), 0 when the skill is not cooling down. With
## get_cooldown_remaining() it gives the wipe its fraction, and it works for a skill that is no longer set.
func get_cooldown_duration(skill_id: StringName) -> float:
	return float(_cooldown_durations.get(skill_id, 0.0))

## True when the skill is set and its cooldown is over (it says nothing about cost or combat state; see can_use()).
func is_ready(skill_id: StringName) -> bool:
	return has_skill(skill_id) and get_cooldown_remaining(skill_id) <= 0.0

func is_casting() -> bool:
	return _casting != null

func get_casting_skill() -> SkillDefinition2D:
	return _casting

## Seconds of the cast left (0 when not casting).
func get_cast_remaining() -> float:
	return _cast_remaining if _casting != null else 0.0

## How much of the cast is done, 0 to 1 (13.4.1); 0 when not casting.
func get_cast_progress() -> float:
	if _casting == null or _casting.cast_time <= 0.0:
		return 0.0
	return clampf(1.0 - _cast_remaining / _casting.cast_time, 0.0, 1.0)

## A damaging hit reached the caster: cancels the cast if the skill is interruptible. True when a cast was cancelled.
func interrupt() -> bool:
	if _casting == null or not _casting.interruptible:
		return false
	_cancel_cast()
	return true

## Cancels the cast in progress whatever the skill says (death, leaving the tree). True when a cast was cancelled.
func cancel() -> bool:
	if _casting == null:
		return false
	_cancel_cast()
	return true

func _physics_process(delta: float) -> void:
	var expired: Array[StringName] = []
	for skill_id in _cooldowns.keys():
		var left := maxf(float(_cooldowns[skill_id]) - delta, 0.0)
		if left <= TIME_EPSILON:
			expired.append(skill_id)
		else:
			_cooldowns[skill_id] = left
	# Signalled after the loop, so a listener may use a skill again without touching the dictionary being walked.
	for skill_id in expired:
		_end_cooldown(skill_id)
	if _casting != null:
		_cast_remaining -= delta
		if _cast_remaining <= TIME_EPSILON:
			var skill := _casting
			_finish_cast()
			_execute(skill, _cast_direction)
	if _casting == null and _cooldowns.is_empty():
		set_physics_process(false)

## What the skill's behavior needs from the caster and the caster lacks, or an empty string (13.3.4).
func _behavior_problem(skill: SkillDefinition2D) -> String:
	if skill.behavior == SkillDefinition2D.Behavior.BUFF:
		var character := context.character as Character2D
		if character == null or not is_instance_valid(character.status_controller):
			return "the character cannot carry statuses (it has no StatusController2D)"
	return ""

func _cost_problem(skill: SkillDefinition2D) -> String:
	if skill.cost_resource == SkillDefinition2D.CostResource.MANA:
		if not is_instance_valid(mana):
			return "the character has no mana pool"
		if not mana.can_afford(skill.cost_amount):
			return "not enough mana (needs %s, has %s)" % [skill.cost_amount, snappedf(mana.mana, 0.01)]
	return ""

func _pay(skill: SkillDefinition2D) -> void:
	if skill.cost_resource == SkillDefinition2D.CostResource.MANA:
		mana.spend(skill.cost_amount)

func _refund(skill: SkillDefinition2D) -> void:
	if skill.cost_resource == SkillDefinition2D.CostResource.MANA and is_instance_valid(mana):
		mana.restore(skill.cost_amount)

## Starts the skill's cooldown and announces it. A skill with no cooldown stores and announces nothing (13.4.1).
func _start_cooldown(skill: SkillDefinition2D) -> void:
	if skill.cooldown <= 0.0:
		return
	_cooldowns[skill.id] = skill.cooldown
	_cooldown_durations[skill.id] = skill.cooldown
	cooldown_started.emit(skill, skill.cooldown)

## Ends a cooldown (it ran out, or a cancelled cast clears it) and announces it, only when one was running.
func _end_cooldown(skill_id: StringName) -> void:
	if _cooldowns.erase(skill_id):
		_cooldown_durations.erase(skill_id)
		cooldown_finished.emit(skill_id)

func _cancel_cast() -> void:
	var skill := _casting
	_finish_cast()
	_stop_clip()
	_refund(skill)
	_end_cooldown(skill.id)
	skill_cancelled.emit(skill)

## H2.2 (decision D3, cast then execute): a skill that names a weapon_animation plays that clip when it starts. The effect
## still executes after cast_time (at once for an instant skill), so a clip is the visible cast. A skill with no clip, or
## one the weapon lacks (validate() reports it), leaves the weapon player alone.
func _play_clip(skill: SkillDefinition2D) -> void:
	if skill.weapon_animation == &"" or context == null or not is_instance_valid(context.weapon_animation_player):
		return
	var player := context.weapon_animation_player
	if not player.has_animation(skill.weapon_animation):
		return
	_watch_player(player)
	_clip_playing = skill.weapon_animation
	player.play(skill.weapon_animation)

## Listens to the weapon player now in use; the weapon (and its player) can change when the character equips another one.
func _watch_player(player: AnimationPlayer) -> void:
	if is_instance_valid(_watched_player) and _watched_player != player and _watched_player.animation_finished.is_connected(_on_clip_finished):
		_watched_player.animation_finished.disconnect(_on_clip_finished)
	if not player.animation_finished.is_connected(_on_clip_finished):
		player.animation_finished.connect(_on_clip_finished)
	_watched_player = player

## The skill's clip ran to its end: the weapon returns to rest, unless an attack has taken the weapon over meanwhile.
func _on_clip_finished(animation_name: StringName) -> void:
	if _clip_playing == &"" or animation_name != _clip_playing:
		return
	_clip_playing = &""
	if context != null and not context.is_attacking:
		_rest_weapon_pose()

## A cancelled cast stops its clip, the way a cancelled attack does.
func _stop_clip() -> void:
	if _clip_playing == &"":
		return
	_clip_playing = &""
	if context != null and not context.is_attacking:
		_rest_weapon_pose()

## Stops the weapon clip and puts the weapon back to its RESET pose, as AttackComponent2D does when a swing is cancelled.
## A listener that settles the hand itself (FacingComponent2D sets context.hand_settling) keeps the pose it has instead.
func _rest_weapon_pose() -> void:
	var player := context.weapon_animation_player
	if not is_instance_valid(player):
		return
	player.stop(context.hand_settling)
	if not context.hand_settling and player.has_animation(&"RESET"):
		player.play(&"RESET")

func _finish_cast() -> void:
	_casting = null
	_cast_remaining = 0.0
	if context != null:
		context.is_casting = false

func _execute(skill: SkillDefinition2D, direction: Vector2) -> void:
	match skill.behavior:
		SkillDefinition2D.Behavior.PROJECTILE:
			_execute_projectile(skill, direction)
		SkillDefinition2D.Behavior.AREA:
			_execute_area(skill, direction)
		SkillDefinition2D.Behavior.DASH:
			_execute_dash(skill, direction)
		SkillDefinition2D.Behavior.BUFF:
			_execute_buff(skill)
		_:
			pass # NONE does nothing by design.
	skill_executed.emit(skill, direction)

## Spawns the skill's projectile (13.3.1) the way AttackComponent2D spawns an attack effect: the same configure() call from
## the skill's AttackDefinition2D, the same host node, the same impact effect at each hit. Returns the projectile, or null
## (with an error) when the attack or its scene is unusable; validate() already refuses such a skill, so this only guards
## a skill whose resource was changed after it was accepted.
func _execute_projectile(skill: SkillDefinition2D, direction: Vector2) -> Array[ProjectileEffect2D]:
	var spawned: Array[ProjectileEffect2D] = []
	var attack := skill.attack
	if attack == null or attack.effect_scene == null:
		push_error("SkillComponent2D: projectile skill '%s' has no attack effect_scene." % skill.id)
		return spawned
	var count := maxi(skill.projectile_count, 1)
	for shot_index in range(count):
		var offset_degrees := 0.0
		if count > 1:
			offset_degrees = -skill.spread_degrees * 0.5 + skill.spread_degrees * float(shot_index) / float(count - 1)
		var shot_direction := direction.rotated(deg_to_rad(offset_degrees)).normalized()
		var node := attack.effect_scene.instantiate()
		var projectile := node as ProjectileEffect2D
		if projectile == null:
			push_error("SkillComponent2D: the effect scene of projectile skill '%s' must have a ProjectileEffect2D root." % skill.id)
			node.free()
			continue
		projectile.configure(context.character, attack.damage, shot_direction, attack.hitbox_size, attack.hitbox_offset, attack.hit_layers, attack.knockback, attack.hit_stun, attack.effect_animation, attack.max_targets, attack.pierce, attack.projectile_speed, attack.crit_chance, attack.crit_multiplier, attack.status_effects)
		# max_range becomes a flight time. The speed is the attack's, or the scene's own when the attack sets none.
		if skill.max_range > 0.0:
			var flight_speed := attack.projectile_speed if attack.projectile_speed > 0.0 else projectile.speed
			if flight_speed > 0.0:
				projectile.lifetime = maxf(skill.max_range / flight_speed, MIN_PROJECTILE_LIFETIME)
		_place_effect(projectile, skill)
		spawned.append(projectile)
	return spawned

## Spawns the skill's area (13.3.2) the way AttackComponent2D spawns an attack effect: the same configure() call from the
## skill's AttackDefinition2D, the same host node, the same impact effect at each hit. The circle's diameter is
## 2 * area_radius (or the attack's hitbox_size when area_radius is 0) and it sits attack.hitbox_offset in front of the
## attack origin along the direction; with SELF targeting the offset is dropped and the effect is explicitly centred on the
## character, even when an AttackSpawnPoint marker is configured. Returns the area, or null on invalid runtime data.
func _execute_area(skill: SkillDefinition2D, direction: Vector2, follow_time: float = 0.0) -> AreaEffect2D:
	var attack := skill.attack
	if attack == null or attack.effect_scene == null:
		push_error("SkillComponent2D: area skill '%s' has no attack effect_scene." % skill.id)
		return null
	var node := attack.effect_scene.instantiate()
	var area := node as AreaEffect2D
	if area == null:
		push_error("SkillComponent2D: the effect scene of area skill '%s' must have an AreaEffect2D root." % skill.id)
		node.free()
		return null
	# AreaEffect2D is circular: hitbox_size.x is its diameter. Keep the attack's
	# X dimension authoritative when area_radius is 0, regardless of the source
	# attack's Y dimension; an explicit skill radius overrides both dimensions.
	var size := Vector2(attack.hitbox_size.x, attack.hitbox_size.x)
	if skill.area_radius > 0.0:
		size = Vector2(skill.area_radius * 2.0, skill.area_radius * 2.0)
	var offset := Vector2.ZERO if skill.targeting == SkillDefinition2D.Targeting.SELF else attack.hitbox_offset
	area.configure(context.character, attack.damage, direction, size, offset, attack.hit_layers, attack.knockback, attack.hit_stun, attack.effect_animation, attack.max_targets, attack.pierce, 0.0, attack.crit_chance, attack.crit_multiplier, attack.status_effects)
	if follow_time > 0.0:
		# A dash strike (13.3.3): it lives as long as the dash and travels with the caster.
		area.follow_source = true
		area.active_time = follow_time
	_place_effect(area, skill, skill.targeting == SkillDefinition2D.Targeting.SELF)
	return area

## Puts the skill's status on the caster (13.3.4), by the status's own stack rule: a second use while it runs refreshes it,
## stacks it or is ignored. The effect of the status (for example damage_multiplier) is read by whatever it modifies.
## Returns whether the status was applied; false (with an error) when the caster has no StatusController2D, which can_use()
## already refuses, so this only guards a controller removed during a cast.
func _execute_buff(skill: SkillDefinition2D) -> bool:
	var character := context.character as Character2D
	if character == null or not is_instance_valid(character.status_controller):
		push_error("SkillComponent2D: buff skill '%s' needs a StatusController2D on the caster." % skill.id)
		return false
	return character.status_controller.apply_status(skill.status_effect)

## Dashes the caster (13.3.3): max_range px at dash_speed, started through DashComponent2D.start_skill_dash() so movement,
## the Dash state and the gating stay where they are. The dash has its own cooldown (the skill's); the character's normal
## dash cooldown is untouched. A skill with an attack also spawns its AreaEffect2D as a strike that follows the caster for
## the dash's duration and hurts what it touches once each. Returns the dash direction, or Vector2.ZERO (with a warning)
## when the character cannot dash right now (no dash component, or something started between the cast and its end).
func _execute_dash(skill: SkillDefinition2D, direction: Vector2) -> Vector2:
	var character := context.character as Character2D
	var dash: DashComponent2D = character.dash_component if character != null else null
	if not is_instance_valid(dash):
		push_error("SkillComponent2D: dash skill '%s' needs a DashComponent2D on the caster." % skill.id)
		return Vector2.ZERO
	var duration := maxf(skill.max_range / maxf(skill.dash_speed, 1.0), MIN_DASH_TIME)
	var dash_direction := dash.start_skill_dash(direction, skill.dash_speed, duration)
	if dash_direction == Vector2.ZERO:
		push_warning("SkillComponent2D: dash skill '%s' could not start a dash." % skill.id)
		return Vector2.ZERO
	if skill.attack != null:
		_execute_area(skill, dash_direction, duration)
	return dash_direction

## Connects the skill's hit signals to an effect and adds it to the host node at the attack origin. Shared by the behaviors
## that spawn an AttackEffect2D (projectile, area).
func _place_effect(effect: AttackEffect2D, skill: SkillDefinition2D, center_on_caster: bool = false) -> void:
	effect.hit_confirmed.connect(_on_effect_hit.bind(skill))
	effect.hit_contact.connect(_on_effect_contact.bind(skill.attack.hit_effect_scene))
	var host: Node = Effects2D.get_host(context.character)
	if host == null:
		host = context.character
	host.add_child(effect)
	effect.global_position = context.character.global_position if center_on_caster else context.get_attack_origin()

func _on_effect_hit(target: Node, dealt_damage: int, skill: SkillDefinition2D) -> void:
	skill_hit.emit(skill, target, dealt_damage)

func _on_effect_contact(_target: Node, _dealt_damage: int, point: Vector2, hit_effect: PackedScene) -> void:
	if hit_effect != null and context != null and is_instance_valid(context.character):
		Effects2D.spawn(hit_effect, context.character, point)

func _resolve_direction(direction: Vector2, skill: SkillDefinition2D) -> Vector2:
	if skill.targeting == SkillDefinition2D.Targeting.SELF:
		return Vector2.ZERO
	var aim := direction.normalized()
	if aim.length_squared() < 0.0001:
		aim = context.aim_direction.normalized()
	if aim.length_squared() < 0.0001:
		aim = context.facing_direction.normalized()
	if aim.length_squared() < 0.0001:
		aim = Vector2.RIGHT
	return aim

func _exit_tree() -> void:
	if is_instance_valid(_watched_player) and _watched_player.animation_finished.is_connected(_on_clip_finished):
		_watched_player.animation_finished.disconnect(_on_clip_finished)
	if _casting != null:
		_finish_cast()
