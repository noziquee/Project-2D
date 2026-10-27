extends Node
class_name PassiveController2D
## Runs the passives of the equipped weapon (14.1, 14.2). Optional: Character2D initializes it when it has a child named
## PassiveController2D, and WeaponController2D.equip() hands it the weapon's passive_skills.
##
## It listens to AttackComponent2D (attack_started, attack_hit, attack_finished), StatusController2D (status_ended) and
## HealthComponent2D (died). All runtime state lives here. The rules are in docs/phase14/14.0-notes.md:
##   - "An attack" is the span from one attack_started to the next attack_started or attack_finished. A swing that is
##     cancelled or interrupted sends no attack_finished, so it is also closed when a hit arrives after the character
##     stopped attacking.
##   - A swing counts at most once, on its first hit. Misses do not count and do not reset the counter.
##   - When the counter is reached during a swing, the reward is granted when that swing closes, so the swing that earned
##     it (all its targets) is not buffed, and the next attack is.
##   - While the reward is waiting or active, hits do not count (no overlapping rewards).
##   - A consumed reward ends when the swing that used it closes. The status multiplier is read when a hit is resolved
##     (13.3.4), so an arrow still in flight when that swing closes is resolved without the bonus.
##   - Death, an equip that changes the passives and the counter window all reset the counter.
## Event passives (14.3) skip the counter: HEAL_SELF and STATUS_ON_TARGET act on every target a basic or heavy attack hits;
## DAMAGE_BONUS_LOW_HEALTH is read by CombatResolver2D through get_damage_multiplier_against().

## The counter of a passive changed (also when it was reset to 0).
signal passive_counter_changed(id: StringName, count: int, required: int)
## A passive reached its count and its reward was granted.
signal passive_triggered(id: StringName)
## The passive list was replaced (a weapon was equipped).
signal passives_changed

var _attacks: AttackComponent2D
var _statuses: StatusController2D
var _health: HealthComponent2D
## One dictionary per passive: {definition, count, idle, last_serial, pending, granted, consuming}.
var _entries: Array = []
## Counts attack_started signals; a passive counts at most one hit per serial.
var _serial := 0
var _attack_open := false

func _ready() -> void:
	set_physics_process(false)

## Called by Character2D (or a test). Any argument may be null: without attacks nothing counts, without a status
## controller a reward cannot be granted, without health nothing resets on death.
func initialize(attacks: AttackComponent2D, statuses: StatusController2D, health: HealthComponent2D) -> void:
	_disconnect_sources()
	_attacks = attacks
	_statuses = statuses
	_health = health
	if is_instance_valid(_attacks):
		_attacks.attack_started.connect(_on_attack_started)
		_attacks.attack_hit.connect(_on_attack_hit)
		_attacks.attack_finished.connect(_on_attack_finished)
	if is_instance_valid(_statuses):
		_statuses.status_ended.connect(_on_status_ended)
	if is_instance_valid(_health):
		_health.died.connect(_on_died)

func _disconnect_sources() -> void:
	if is_instance_valid(_attacks):
		_attacks.attack_started.disconnect(_on_attack_started)
		_attacks.attack_hit.disconnect(_on_attack_hit)
		_attacks.attack_finished.disconnect(_on_attack_finished)
	if is_instance_valid(_statuses):
		_statuses.status_ended.disconnect(_on_status_ended)
	if is_instance_valid(_health):
		_health.died.disconnect(_on_died)

## Replaces the passives (an equip). Counters restart at 0 and a reward granted by the old list is taken away. An
## invalid or duplicate passive is skipped with an error naming it.
func set_passives(passives: Array) -> void:
	_clear_rewards()
	_entries.clear()
	var seen: Dictionary = {}
	for passive in passives:
		var definition := passive as PassiveDefinition2D
		if definition == null:
			continue
		var problems := definition.validate()
		if not problems.is_empty():
			push_error("PassiveController2D rejected passive: %s" % " ".join(problems))
			continue
		if seen.has(definition.id):
			push_error("PassiveController2D rejected passive '%s': its id is listed more than once." % definition.id)
			continue
		seen[definition.id] = true
		_entries.append({"definition": definition, "count": 0, "idle": 0.0, "last_serial": -1, "pending": false, "granted": false, "consuming": false})
	_attack_open = false
	_refresh_processing()
	passives_changed.emit()

func get_passive_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in _entries:
		ids.append((entry["definition"] as PassiveDefinition2D).id)
	return ids

## The qualifying swings counted so far, 0 for an unknown id.
func get_count(id: StringName) -> int:
	var entry := _find(id)
	return int(entry["count"]) if not entry.is_empty() else 0

func get_required(id: StringName) -> int:
	var entry := _find(id)
	return (entry["definition"] as PassiveDefinition2D).required_count if not entry.is_empty() else 0

## True while the reward is earned but not granted yet (the swing that earned it is still open).
func is_pending(id: StringName) -> bool:
	var entry := _find(id)
	return not entry.is_empty() and bool(entry["pending"])

## True from the moment the reward is granted until its status ends or is consumed.
func is_active(id: StringName) -> bool:
	var entry := _find(id)
	return not entry.is_empty() and bool(entry["granted"])

## Counters back to 0 and any granted reward removed.
func reset() -> void:
	_clear_rewards()
	_attack_open = false
	_refresh_processing()

func _find(id: StringName) -> Dictionary:
	for entry in _entries:
		if (entry["definition"] as PassiveDefinition2D).id == id:
			return entry
	return {}

func _clear_rewards() -> void:
	for entry in _entries:
		var definition := entry["definition"] as PassiveDefinition2D
		var was_active: bool = entry["granted"]
		entry["granted"] = false
		entry["consuming"] = false
		entry["pending"] = false
		var had_count: bool = int(entry["count"]) > 0
		entry["count"] = 0
		entry["idle"] = 0.0
		if was_active and is_instance_valid(_statuses):
			_statuses.remove_status(definition.status_effect.id)
		if had_count:
			passive_counter_changed.emit(definition.id, 0, definition.required_count)

func _on_attack_started(_direction: Vector2) -> void:
	_close_attack()
	_serial += 1
	_attack_open = true
	for entry in _entries:
		var definition := entry["definition"] as PassiveDefinition2D
		if entry["granted"] and definition.consumed_by_next_attack:
			entry["consuming"] = true

func _on_attack_finished() -> void:
	_close_attack()

func _on_attack_hit(target: Node, _damage: int) -> void:
	if _attack_open and not _is_swinging():
		_close_attack() # the swing was cancelled or interrupted: no attack_finished came
	for entry in _entries:
		var definition := entry["definition"] as PassiveDefinition2D
		match definition.effect:
			PassiveDefinition2D.Effect.HEAL_SELF:
				if is_instance_valid(_health):
					_health.heal(definition.heal_amount)
				continue
			PassiveDefinition2D.Effect.STATUS_ON_TARGET:
				_apply_status_to(target, definition.status_effect)
				continue
			PassiveDefinition2D.Effect.DAMAGE_BONUS_LOW_HEALTH:
				continue # acts in the resolver, not on the hit signal
		if entry["granted"] or entry["pending"] or int(entry["last_serial"]) == _serial:
			continue
		entry["last_serial"] = _serial
		entry["idle"] = 0.0
		entry["count"] = int(entry["count"]) + 1
		passive_counter_changed.emit(definition.id, int(entry["count"]), definition.required_count)
		if int(entry["count"]) >= definition.required_count:
			entry["count"] = 0
			passive_counter_changed.emit(definition.id, 0, definition.required_count)
			if _attack_open:
				entry["pending"] = true
			else:
				_grant(entry) # a late hit (an arrow) after the swing closed
	_refresh_processing()

## Puts `status` on `target` when it is a live node with a StatusController2D (read through Combatant2D, like the resolver does).
## A target without one, a freed one or a dead one is ignored.
func _apply_status_to(target: Node, status: StatusEffectDefinition2D) -> void:
	if not is_instance_valid(target) or status == null:
		return
	var controller := Combatant2D.status_controller_of(target)
	if controller != null:
		controller.apply_status(status)

## The product of the DAMAGE_BONUS_LOW_HEALTH multipliers that apply to a hit on the owner of `target_health`: 1 when none
## do. CombatResolver2D multiplies this into the wielder's outgoing damage before crit and defense.
func get_damage_multiplier_against(target_health: HealthComponent2D) -> float:
	if not is_instance_valid(target_health) or target_health.max_health <= 0:
		return 1.0
	var fraction := float(target_health.health) / float(target_health.max_health)
	var multiplier := 1.0
	for entry in _entries:
		var definition := entry["definition"] as PassiveDefinition2D
		if definition.effect == PassiveDefinition2D.Effect.DAMAGE_BONUS_LOW_HEALTH and fraction <= definition.health_threshold:
			multiplier *= definition.damage_multiplier
	return multiplier

## Ends the swing that is open: a consumed reward is used up, a pending one is granted.
func _close_attack() -> void:
	for entry in _entries:
		if entry["consuming"]:
			entry["consuming"] = false
			var definition := entry["definition"] as PassiveDefinition2D
			if is_instance_valid(_statuses):
				_statuses.remove_status(definition.status_effect.id)
			entry["granted"] = false
		if entry["pending"]:
			_grant(entry)
	_attack_open = false
	_refresh_processing()

func _grant(entry: Dictionary) -> void:
	entry["pending"] = false
	var definition := entry["definition"] as PassiveDefinition2D
	if is_instance_valid(_statuses) and _statuses.apply_status(definition.status_effect):
		entry["granted"] = true
		passive_triggered.emit(definition.id)

func _is_swinging() -> bool:
	if not is_instance_valid(_attacks) or _attacks.context == null:
		return _attack_open # no context (a bare component in a test): trust the signals
	return _attacks.context.is_attacking

func _on_status_ended(id: StringName) -> void:
	for entry in _entries:
		var definition := entry["definition"] as PassiveDefinition2D
		if definition.uses_counter() and definition.status_effect.id == id:
			entry["granted"] = false
			entry["consuming"] = false

func _on_died() -> void:
	reset()

func _physics_process(delta: float) -> void:
	for entry in _entries:
		var definition := entry["definition"] as PassiveDefinition2D
		if definition.counter_window <= 0.0 or int(entry["count"]) <= 0:
			continue
		entry["idle"] = float(entry["idle"]) + delta
		if float(entry["idle"]) >= definition.counter_window:
			entry["idle"] = 0.0
			entry["count"] = 0
			passive_counter_changed.emit(definition.id, 0, definition.required_count)
	_refresh_processing()

## The timer only runs while a passive with a window has something to forget.
func _refresh_processing() -> void:
	var needed := false
	for entry in _entries:
		var definition := entry["definition"] as PassiveDefinition2D
		if definition.counter_window > 0.0 and int(entry["count"]) > 0:
			needed = true
			break
	set_physics_process(needed)
