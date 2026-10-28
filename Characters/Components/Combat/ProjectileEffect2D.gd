extends AttackEffect2D
class_name ProjectileEffect2D
## A projectile effect (11.1): flies in a straight line along the attack direction and hits what it touches.
## It is an AttackEffect2D, so AttackComponent2D spawns, configures, tracks and cancels it exactly like a melee
## slash (no change to the component). Damage goes through AttackEffect2D._try_hit(): HitData, apply_hit(),
## the team filter, hit-once per target, and the max_targets / pierce policy from 10.4.
##
## What a projectile adds to the shared rules:
##   - it moves: `speed` px/s along `direction` (the attack's projectile_speed when it sets one), for at most
##     `lifetime` seconds;
##   - it stops on the world layer (physics layer 3, value 4) even if the attack's hit_layers leave that bit out,
##     and then emits world_hit(point);
##   - it frees itself when it is spent (its hit policy is used up), when it hits the world, or when its
##     lifetime ends.
## The hit area is a thin box (`hitbox_size`, rotated with the flight direction, moved by `hitbox_offset`). A very
## fast projectile can step over a thin target between two physics frames: at 60 fps keep speed / 60 below the
## hitbox length.
##
## The effect_animation passed by configure() is ignored: there is no effect AnimationPlayer. The impact effect
## at a hit (the attack's hit_effect_scene) is spawned by AttackComponent2D from hit_contact, as for a slash.

## Emitted when the projectile stops on the world layer, with the world position of its hit area.
signal world_hit(point: Vector2)

## Value of physics layer 3 ("world"). It is always part of the hit area's mask.
const WORLD_LAYER := 4

@export_group("Flight")
## Speed along the attack direction, in px/s.
@export_range(0.0, 3000.0, 1.0) var speed: float = 300.0
## Seconds after which the projectile removes itself if it has hit nothing that stops it.
@export_range(0.05, 30.0, 0.05) var lifetime: float = 1.5

@export_group("Scene nodes")
## The Area2D that detects bodies, relative to the root. The defaults match ProjectileEffect2D.tscn.
@export var hitbox_path: NodePath = ^"Hitbox"
## Its CollisionShape2D. A RectangleShape2D is resized to hitbox_size.
@export var collision_shape_path: NodePath = ^"Hitbox/CollisionShape2D"

var _hitbox: Area2D
var _collision_shape: CollisionShape2D
var _age := 0.0
## True once the projectile has ended for any reason (world, lifetime, spent). It then hits nothing more.
var _ended := false

func _ready() -> void:
	if not _resolve_nodes():
		set_physics_process(false)
		queue_free()
		return
	global_rotation = direction.angle()
	# The attack's projectile_speed (11.2) wins over the scene's own default; 0 keeps the default.
	if projectile_speed > 0.0:
		speed = projectile_speed
	_hitbox.position = hitbox_offset
	# The attack's hit_layers choose the targets; the world bit is always added so a wall stops the projectile.
	var mask := hit_layers if hit_layers >= 0 else _hitbox.collision_mask
	_hitbox.collision_mask = mask | WORLD_LAYER
	_hitbox.monitoring = true
	_collision_shape.disabled = false
	if _collision_shape.shape is RectangleShape2D:
		var rectangle := (_collision_shape.shape as RectangleShape2D).duplicate() as RectangleShape2D
		rectangle.size = hitbox_size
		_collision_shape.shape = rectangle
	_hitbox.body_entered.connect(_on_body_entered)

## Looks up the two nodes through the exported paths. A path that leads to nothing (or to the wrong kind of
## node) is reported by property name and the projectile removes itself.
func _resolve_nodes() -> bool:
	_hitbox = get_node_or_null(hitbox_path) as Area2D
	_collision_shape = get_node_or_null(collision_shape_path) as CollisionShape2D
	var ok := true
	if _hitbox == null:
		push_error("ProjectileEffect2D: hitbox_path '%s' does not lead to an Area2D." % hitbox_path)
		ok = false
	if _collision_shape == null:
		push_error("ProjectileEffect2D: collision_shape_path '%s' does not lead to a CollisionShape2D." % collision_shape_path)
		ok = false
	return ok

func _physics_process(delta: float) -> void:
	if _ended:
		return
	# Bodies already inside the hit area when the projectile appears (or that the signal missed).
	for body in _hitbox.get_overlapping_bodies():
		_touch(body)
	if _ended:
		return
	_age += delta
	global_position += direction * speed * delta
	if _age >= lifetime:
		_end()

func _on_body_entered(body: Node2D) -> void:
	_touch(body)

## A body reached the hit area: ones that take hits (apply_hit, P5) go through the shared hit rules, a solid world body stops the
## projectile, anything else is ignored.
func _touch(body: Node) -> void:
	if _ended or _spent or not is_instance_valid(body) or body == source:
		return
	if body.has_method("apply_hit") or body.has_method("take_damage"):
		_try_hit(body)
	elif body is CollisionObject2D and ((body as CollisionObject2D).collision_layer & WORLD_LAYER) != 0:
		world_hit.emit(_get_hit_origin())
		_end()

func _can_hit() -> bool:
	return not _ended and _hitbox != null

func _get_hit_origin() -> Vector2:
	return _hitbox.global_position if _hitbox != null else global_position

## The hit policy is used up (max_targets reached, or pierce off after the first target).
func _on_spent() -> void:
	_end()

## Seconds the projectile has flown.
func get_age() -> float:
	return _age

func is_ended() -> bool:
	return _ended

func _end() -> void:
	if _ended:
		return
	_ended = true
	set_physics_process(false)
	if _hitbox != null:
		_hitbox.set_deferred("monitoring", false)
	queue_free()

## Scene problems (H3.2): the hit area and its shape exist.
func get_scene_problems(_effect_clip: StringName) -> Array[String]:
	return _hitbox_scene_problems(hitbox_path, collision_shape_path)

func get_scene_warnings() -> Array[String]:
	return _shape_scene_warnings(collision_shape_path, "RectangleShape2D")
