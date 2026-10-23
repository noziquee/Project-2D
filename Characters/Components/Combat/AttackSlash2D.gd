extends Node2D
class_name AttackSlash2D
## Uses the project's existing sprite animation, with a separate configurable hitbox origin.

signal hit_confirmed(target: Node, damage: int)
## Emitted just before hit_confirmed with the world position where the hit landed
## (halfway between the hitbox and the target), for impact effects.
signal hit_contact(target: Node, damage: int, point: Vector2)

var source: Node2D
var damage: int = 1
var direction: Vector2 = Vector2.RIGHT
var hitbox_size: Vector2 = Vector2(16.0, 16.0)
var hitbox_offset: Vector2 = Vector2.ZERO
## Physics layers the hitbox looks at. -1 keeps the mask set in the scene.
var hit_layers: int = -1
var knockback: float = 0.0
var hit_stun: float = 0.0

@onready var _slash_animation_player: AnimationPlayer = $SlashEffectAnimSpritesheet/AnimationPlayer
@onready var _hitbox: Area2D = $HitboxOrigin/HitboxMotion/Area2D
@onready var _collision_shape: CollisionShape2D = $HitboxOrigin/HitboxMotion/Area2D/CollisionShape2D
@onready var _hitbox_origin: Node2D = $HitboxOrigin

var _hit_targets: Dictionary = {}

func configure(attacker: Node2D, damage_amount: int, aim_direction: Vector2, shape_size: Vector2, origin_offset: Vector2, layers: int = -1, knockback_strength: float = 0.0, stun_seconds: float = 0.0) -> void:
	source = attacker
	damage = maxi(damage_amount, 0)
	direction = aim_direction.normalized() if aim_direction.length_squared() > 0.0001 else Vector2.RIGHT
	hitbox_size = Vector2(maxf(shape_size.x, 1.0), maxf(shape_size.y, 1.0))
	hitbox_offset = origin_offset
	hit_layers = layers
	knockback = maxf(knockback_strength, 0.0)
	hit_stun = maxf(stun_seconds, 0.0)

func _ready() -> void:
	global_rotation = direction.angle()
	_hitbox_origin.position = hitbox_offset
	# Collision layer lives on the Area2D in AttackSlash2D.tscn; the mask comes from the
	# attack definition's hit_layers (the scene's mask, player + enemy, is only a fallback).
	if hit_layers >= 0:
		_hitbox.collision_mask = hit_layers
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
		or not (target.has_method("apply_hit") or target.has_method("take_damage"))
	):
		return
	if _is_same_team(target):
		return
	var target_id := target.get_instance_id()
	if _hit_targets.has(target_id):
		return
	_hit_targets[target_id] = true
	# Read the contact point first: the hit may kill and free the target.
	var point := _contact_point(target)
	if target.has_method("apply_hit"):
		var dealt := int(target.call("apply_hit", HitData.new(damage, source, direction, knockback, hit_stun)))
		if dealt > 0:
			hit_contact.emit(target, dealt, point)
			hit_confirmed.emit(target, dealt)
	else:
		target.call("take_damage", damage)
		hit_contact.emit(target, damage, point)
		hit_confirmed.emit(target, damage)

func _contact_point(target: Node) -> Vector2:
	if target is Node2D:
		return _hitbox.global_position.lerp((target as Node2D).global_position, 0.5)
	return _hitbox.global_position

## Teams come from the `team` property on the attacker and the target. An empty team is
## neutral and can always be hit; two characters on the same non-empty team cannot hit
## each other. A new faction is just a new team name.
func _is_same_team(target: Node) -> bool:
	if not is_instance_valid(source):
		return false
	var source_team := StringName(source.get("team")) if source.get("team") != null else &""
	var target_team := StringName(target.get("team")) if target.get("team") != null else &""
	return source_team != &"" and source_team == target_team

func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"slash":
		queue_free()
