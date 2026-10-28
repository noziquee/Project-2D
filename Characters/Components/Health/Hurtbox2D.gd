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
## Whether an aim assist may pick this as a target (H8.3). Off by default: a crate or a switch only draws the assist when
## it is switched on here, so scenery and decoration are never auto-targeted. It joins the `damageable` group while on.
@export var targetable: bool = false:
	set(value):
		targetable = value
		if is_inside_tree():
			_apply_targetable()

func _ready() -> void:
	_apply_targetable()
	if health_component == null:
		health_component = get_node_or_null("HealthComponent2D") as HealthComponent2D
	if health_component == null:
		push_warning("Hurtbox2D '%s' has no HealthComponent2D; hits on it do nothing." % name)
		return
	health_component.damaged.connect(_on_damaged)
	health_component.died.connect(_on_died)

func _apply_targetable() -> void:
	if targetable:
		add_to_group(&"damageable")
	elif is_in_group(&"damageable"):
		remove_from_group(&"damageable")

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
