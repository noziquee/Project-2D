extends RefCounted
class_name CombatResolver2D
## The one place that turns a raw hit into the hit that is applied (Phase 12).
## HealthComponent2D.apply_hit() calls resolve() for every hit that can still land, so melee, projectiles and
## later skills and passives all pass through here. New damage rules are added to resolve(), never to the
## attack effects or to the health component.
##
## Order (13.3.4, 12.3, 12.2):  damage = base
##   0. buff:    if the attacker carries statuses that change its damage (an empowerment), damage = round(damage x multiplier)
##   1. crit:    if the hit rolls a crit, damage = round(damage x max(crit_multiplier, 1))
##   2. defense: if the target has defense, damage = max(damage - defense, MIN_DAMAGE)
## A periodic hit (a status tick) skips both. A hit with 0 damage is returned as it is.

## The least damage a hit that can land does once defense is subtracted.
const MIN_DAMAGE := 1

## How many times resolve() has run. Diagnostic only: the smoke test compares it before and after a hit to prove
## the damage source went through the resolver. Nothing in the game reads it.
static var resolve_calls: int = 0

## The random source of crit rolls. Seeded randomly; tests call seed_rng() to make rolls repeatable.
static var _rng := RandomNumberGenerator.new()

static func seed_rng(value: int) -> void:
	_rng.seed = value

## Returns the hit to apply to the owner of `health` (null in tests that have no health component).
## The same object comes back when nothing changed; otherwise a changed copy. Callers must use the returned hit.
static func resolve(hit: HitData, health: HealthComponent2D) -> HitData:
	resolve_calls += 1
	if hit == null or hit.is_periodic or hit.damage <= 0:
		return hit
	var crit := _rolls_crit(hit.crit_chance)
	var defense := health.defense if is_instance_valid(health) else 0
	var multiplier := _damage_multiplier(hit.source)
	var buffed := not is_equal_approx(multiplier, 1.0)
	if not crit and defense <= 0 and not buffed:
		return hit
	var resolved := hit.copy()
	if buffed:
		resolved.damage = maxi(roundi(float(hit.damage) * multiplier), 1 if multiplier > 0.0 else 0)
	if crit:
		resolved.damage = roundi(float(resolved.damage) * maxf(hit.crit_multiplier, 1.0))
		resolved.is_crit = true
	if defense > 0:
		resolved.damage = maxi(resolved.damage - defense, MIN_DAMAGE)
	return resolved

## The attacker's outgoing damage multiplier from its StatusController2D (13.3.4); 1 for a source with none, a freed one or null.
## Duck-typed (the property is read by name) so any node can be a source.
static func _damage_multiplier(source: Node) -> float:
	if not is_instance_valid(source):
		return 1.0
	var controller: Variant = source.get("status_controller")
	if is_instance_valid(controller) and controller is StatusController2D:
		return (controller as StatusController2D).get_damage_multiplier()
	return 1.0

## A chance of 0 never rolls and 1 always crits, and neither uses a random number.
static func _rolls_crit(chance: float) -> bool:
	if chance <= 0.0:
		return false
	if chance >= 1.0:
		return true
	return _rng.randf() < chance
