extends Node
class_name StatusController2D
## Runs the statuses on one character (12.4): applies them when a hit that deals damage carries them, ticks their
## damage, refreshes or stacks them, ends them on expiry or death. Optional: Character2D initializes it when it
## has a child named StatusController2D. All runtime state lives here, never in the StatusEffectDefinition2D.
##
## A tick is a periodic HitData through HealthComponent2D.apply_hit(): it skips crit and defense, causes no
## knockback or stun, and is ignored while the target is invulnerable, like any hit.

signal status_applied(id: StringName, stacks: int)
signal status_ended(id: StringName)

## Float sums of 1/60 s fall a hair short of whole seconds; this keeps the last tick from being lost.
const TIME_EPSILON := 0.0001

var _health: HealthComponent2D
## id -> {definition, stacks, remaining, tick_timer}
var _active: Dictionary = {}

func _ready() -> void:
	set_physics_process(false)

## Called by Character2D (or a test) with the health component this controller works on.
func initialize(health: HealthComponent2D) -> void:
	if _health == health:
		return
	if is_instance_valid(_health):
		_health.damaged.disconnect(_on_health_damaged)
		_health.died.disconnect(_on_health_died)
	_health = health
	if is_instance_valid(_health):
		_health.damaged.connect(_on_health_damaged)
		_health.died.connect(_on_health_died)

## Starts or updates a status. False when nothing changed (no definition, dead target, or the IGNORE rule).
func apply_status(definition: StatusEffectDefinition2D) -> bool:
	if definition == null or definition.duration <= 0.0 or not is_instance_valid(_health) or not _health.is_alive():
		return false
	var entry = _active.get(definition.id)
	if entry == null:
		entry = {"definition": definition, "stacks": 1, "remaining": definition.duration, "tick_timer": 0.0}
		_active[definition.id] = entry
	else:
		match definition.stack_rule:
			StatusEffectDefinition2D.StackRule.IGNORE:
				return false
			StatusEffectDefinition2D.StackRule.STACK:
				entry["stacks"] = mini(int(entry["stacks"]) + 1, maxi(definition.max_stacks, 1))
		entry["definition"] = definition
		entry["remaining"] = definition.duration
	status_applied.emit(definition.id, int(entry["stacks"]))
	set_physics_process(true)
	return true

func has_status(id: StringName) -> bool:
	return _active.has(id)

func get_stacks(id: StringName) -> int:
	return int(_active[id]["stacks"]) if _active.has(id) else 0

func get_remaining(id: StringName) -> float:
	return float(_active[id]["remaining"]) if _active.has(id) else 0.0

## The outgoing damage multiplier of this character (13.3.4): 1 plus, for each running status, (damage_multiplier - 1) per
## stack. 1 when nothing modifies it. Read by CombatResolver2D for every hit this character lands.
func get_damage_multiplier() -> float:
	var bonus := 0.0
	for entry in _active.values():
		var definition := entry["definition"] as StatusEffectDefinition2D
		bonus += (definition.damage_multiplier - 1.0) * int(entry["stacks"])
	return maxf(1.0 + bonus, 0.0)

func get_active_ids() -> Array:
	return _active.keys()

## Ends one status now. False when it was not running.
func remove_status(id: StringName) -> bool:
	if not _active.erase(id):
		return false
	status_ended.emit(id)
	if _active.is_empty():
		set_physics_process(false)
	return true

func clear() -> void:
	for id in _active.keys():
		remove_status(id)

func _physics_process(delta: float) -> void:
	for id in _active.keys():
		var entry = _active.get(id)
		if entry == null:
			continue # cleared by a death during this loop
		var definition := entry["definition"] as StatusEffectDefinition2D
		var step := minf(delta, float(entry["remaining"]))
		entry["remaining"] = float(entry["remaining"]) - delta
		if definition.tick_interval > 0.0 and definition.tick_damage > 0:
			entry["tick_timer"] = float(entry["tick_timer"]) + step
			while float(entry["tick_timer"]) >= definition.tick_interval - TIME_EPSILON:
				entry["tick_timer"] = float(entry["tick_timer"]) - definition.tick_interval
				var tick := HitData.new(definition.tick_damage * int(entry["stacks"]))
				tick.is_periodic = true
				_health.apply_hit(tick)
				if not _health.is_alive():
					return # _on_health_died has cleared everything
		if float(entry["remaining"]) <= TIME_EPSILON:
			remove_status(id)

func _on_health_damaged(hit: HitData) -> void:
	if hit.is_periodic:
		return
	for definition in hit.statuses:
		apply_status(definition as StatusEffectDefinition2D)

func _on_health_died() -> void:
	clear()
