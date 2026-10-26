extends StaticBody2D
class_name Hurtbox2D
## Something that can be hit without being a character: a crate, a switch, a training dummy (P5).
##
## It is a body, so attack hitboxes find it the way they find a character, and it answers the same `apply_hit` /
## `take_damage` calls, forwarding them to a HealthComponent2D. Nothing has to join a group by hand: the hit rules
## only ask for `apply_hit`. Give the body a collision layer the attack's `hit_layers` reach, and a shape.
##
## What happens when it is hit or destroyed belongs to the scene: connect `damaged` and `died`.

signal damaged(hit: HitData)
signal died

## The health this hurtbox forwards to. Left empty, the child named HealthComponent2D is used.
@export var health_component: HealthComponent2D
## Same meaning as Character2D.team: two things on the same non-empty team do not hit each other.
@export var team: StringName = &""

func _ready() -> void:
	if health_component == null:
		health_component = get_node_or_null("HealthComponent2D") as HealthComponent2D
	if health_component == null:
		push_warning("Hurtbox2D '%s' has no HealthComponent2D; hits on it do nothing." % name)
		return
	health_component.damaged.connect(_on_damaged)
	health_component.died.connect(_on_died)

func is_alive() -> bool:
	return is_instance_valid(health_component) and health_component.is_alive()

## Applies a hit through the health component. Returns the damage actually dealt.
func apply_hit(hit: HitData) -> int:
	return health_component.apply_hit(hit) if is_instance_valid(health_component) else 0

## Shim for callers that only have a number. Prefer apply_hit().
func take_damage(amount: int) -> void:
	apply_hit(HitData.new(amount))

func _on_damaged(hit: HitData) -> void:
	damaged.emit(hit)

func _on_died() -> void:
	died.emit()
