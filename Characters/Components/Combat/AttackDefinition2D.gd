extends Resource
class_name AttackDefinition2D
## Tunable attack data kept separate from the authored slash animation.

@export_range(0, 10000, 1) var damage: int = 1
@export_range(0.0, 5.0, 0.01) var cooldown_duration: float = 0.4
@export var hitbox_size: Vector2 = Vector2(16.0, 16.0)
## Offset of the hitbox's animated sweep origin from the attacking character.
@export var hitbox_offset: Vector2 = Vector2.ZERO
