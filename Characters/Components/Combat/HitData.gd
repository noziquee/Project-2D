extends RefCounted
class_name HitData
## Describes one hit travelling from an attack to a HealthComponent2D.
## CombatResolver2D turns the hit the attack made into the hit that is applied (crit, defense), so the
## damage in the `damaged` signal is the resolved value.

var damage: int = 0
## The attacking node. May be null or already freed; check is_instance_valid() before use.
var source: Node = null
## Direction the hit travels (attacker -> target). Zero when unknown.
var direction: Vector2 = Vector2.ZERO
var knockback: float = 0.0
var hit_stun: float = 0.0

## Chance (0 to 1) that the resolver turns this hit into a critical hit (12.3). Set by the attack.
var crit_chance: float = 0.0
## Damage multiplier of a critical hit. Values below 1 count as 1.
var crit_multiplier: float = 2.0
## Set by the resolver when the roll succeeded. `damage` is already multiplied when this is true.
var is_crit: bool = false
## StatusEffectDefinition2D resources to apply to the target when this hit deals damage (12.4).
var statuses: Array = []
## True for damage that is not an attack, such as a status tick (12.4). The resolver skips crit and defense
## for it, and the target gets no knockback, hit stun or swing interruption from it.
var is_periodic: bool = false

func _init(damage_amount: int = 0, hit_source: Node = null, hit_direction: Vector2 = Vector2.ZERO, knockback_strength: float = 0.0, stun_seconds: float = 0.0) -> void:
	damage = damage_amount
	source = hit_source
	direction = hit_direction
	knockback = knockback_strength
	hit_stun = stun_seconds

## A new hit with the same values. The resolver changes a copy, never the hit it was given.
func copy() -> HitData:
	var other := HitData.new(damage, source, direction, knockback, hit_stun)
	other.crit_chance = crit_chance
	other.crit_multiplier = crit_multiplier
	other.is_crit = is_crit
	other.statuses = statuses
	other.is_periodic = is_periodic
	return other
