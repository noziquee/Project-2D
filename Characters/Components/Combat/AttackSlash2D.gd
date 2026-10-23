extends Node2D
class_name AttackSlash2D
## Uses the project's existing sprite animation, with a separate configurable hitbox origin.

signal hit_confirmed(target: Node, damage: int)

var source: Node2D
var damage: int = 1
var direction: Vector2 = Vector2.RIGHT
var hitbox_size: Vector2 = Vector2(16.0, 16.0)
var hitbox_offset: Vector2 = Vector2.ZERO

@onready var _slash_animation_player: AnimationPlayer = $SlashEffectAnimSpritesheet/AnimationPlayer
@onready var _hitbox: Area2D = $HitboxOrigin/HitboxMotion/Area2D
@onready var _collision_shape: CollisionShape2D = $HitboxOrigin/HitboxMotion/Area2D/CollisionShape2D
@onready var _hitbox_origin: Node2D = $HitboxOrigin

var _hit_targets: Dictionary = {}

func configure(attacker: Node2D, damage_amount: int, aim_direction: Vector2, shape_size: Vector2, origin_offset: Vector2) -> void:
	source = attacker
	damage = maxi(damage_amount, 0)
	direction = aim_direction.normalized() if aim_direction.length_squared() > 0.0001 else Vector2.RIGHT
	hitbox_size = Vector2(maxf(shape_size.x, 1.0), maxf(shape_size.y, 1.0))
	hitbox_offset = origin_offset

func _ready() -> void:
	global_rotation = direction.angle()
	_hitbox_origin.position = hitbox_offset
	# Collision layer/mask live on the Area2D in AttackSlash2D.tscn (mask: player + enemy).
	_hitbox.monitoring = true
	_collision_shape.disabled = true
	if _collision_shape.shape is RectangleShape2D:
		var rectangle := (_collision_shape.shape as RectangleShape2D).duplicate() as RectangleShape2D
		rectangle.size = hitbox_size
		_collision_shape.shape = rectangle
	_hitbox.body_entered.connect(_on_body_entered)
	_slash_animation_player.animation_finished.connect(_on_animation_finished)
	if not _slash_animation_player.has_animation(&"slash"):
		push_error("AttackSlash2D requires SlashEffectAnimSpritesheet/AnimationPlayer animation 'slash'.")
		queue_free()
		return
	_slash_animation_player.play(&"slash")

func _physics_process(_delta: float) -> void:
	if not _hitbox.monitoring or _collision_shape.disabled:
		return
	for body in _hitbox.get_overlapping_bodies():
		_try_hit(body)

func _on_body_entered(body: Node2D) -> void:
	_try_hit(body)

func _try_hit(target: Node) -> void:
	if (
		not is_instance_valid(target)
		or not _hitbox.monitoring
		or _collision_shape.disabled
		or target == source
		or not target.is_in_group("damageable")
		or not target.has_method("take_damage")
	):
		return
	if source != null and (
		(source.is_in_group("player") and target.is_in_group("player"))
		or (source.is_in_group("enemy") and target.is_in_group("enemy"))
	):
		return
	var target_id := target.get_instance_id()
	if _hit_targets.has(target_id):
		return
	_hit_targets[target_id] = true
	target.call("take_damage", damage)
	hit_confirmed.emit(target, damage)

func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"slash":
		queue_free()
