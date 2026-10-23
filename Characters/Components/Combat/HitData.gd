extends RefCounted
class_name HitData
## Describes one hit travelling from an attack to a HealthComponent2D.
## knockback and hit_stun are carried now and consumed in Phase 5.

var damage: int = 0
## The attacking node. May be null or already freed; check is_instance_valid() before use.
var source: Node = null
## Direction the hit travels (attacker -> target). Zero when unknown.
var direction: Vector2 = Vector2.ZERO
var knockback: float = 0.0
var hit_stun: float = 0.0

func _init(damage_amount: int = 0, hit_source: Node = null, hit_direction: Vector2 = Vector2.ZERO, knockback_strength: float = 0.0, stun_seconds: float = 0.0) -> void:
	damage = damage_amount
	source = hit_source
	direction = hit_direction
	knockback = knockback_strength
	hit_stun = stun_seconds
