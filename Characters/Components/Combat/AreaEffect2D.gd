extends AttackEffect2D
class_name AreaEffect2D
## An area effect (13.3.2): a circle that appears where it is spawned, damages every valid target inside it for a short
## time and then removes itself. It is an AttackEffect2D, so it is configured with the same configure(...) call as a slash
## or an arrow and goes through the shared rules: HitData, apply_hit(), the team filter, hit-once per target and the
## max_targets / pierce policy (10.4). Nothing about it is skill-specific; an attack could spawn it too.
##
## What an area adds:
##   - the hit shape is a circle. Its DIAMETER is hitbox_size.x (the radius is half of it);
##   - the circle is centred `hitbox_offset` from the spawn point, in the effect's own frame: the effect is rotated toward
##     `direction`, so an offset of (32, 0) is 32 px in front of the caster. An offset of (0, 0) is centred on the caster;
##   - it hits for `active_time` seconds (each target once, so a target that walks in later is still hit), then frees itself;
##     it also frees itself as soon as its hit policy is used up;
##   - with follow_source it travels with its source (a dash skill's strike);
##   - it never stops on walls (a blast is not a projectile): only the attack's hit_layers decide what it looks at.
## The effect_animation passed by configure() is ignored: the area has no AnimationPlayer. The flash it draws is a
## fading disc, so a new area skill needs no art; a scene with its own visuals just hides or replaces `Visual`.

@export_group("Area")
## Seconds the area can hit after it appears. Short on purpose: it is a burst, not a zone that stays.
@export_range(0.05, 10.0, 0.05) var active_time: float = 0.25
## Colour of the flash that fades out over active_time. Alpha 0 draws nothing.
@export var flash_color: Color = Color(1.0, 0.85, 0.4, 0.35)

@export_group("Scene nodes")
## The Area2D that detects bodies, relative to the root. The defaults match AreaEffect2D.tscn.
@export var hitbox_path: NodePath = ^"Hitbox"
## Its CollisionShape2D. A CircleShape2D is resized to hitbox_size.x / 2.
@export var collision_shape_path: NodePath = ^"Hitbox/CollisionShape2D"

## When true the area moves with `source` instead of staying where it appeared (set by a dash skill, 13.3.3, so the
## strike travels with the dash). It keeps the offset it had from the source on its first physics frame.
var follow_source := false

var _follow_delta := Vector2.ZERO
var _follow_ready := false
var _hitbox: Area2D
var _collision_shape: CollisionShape2D
var _age := 0.0
## True once the area has ended for any reason (time, hit policy used up). It then hits nothing more.
var _ended := false

func _ready() -> void:
	if not _resolve_nodes():
		set_physics_process(false)
		queue_free()
		return
	global_rotation = direction.angle()
	_hitbox.position = hitbox_offset
	# The attack's hit_layers choose the targets (the scene's mask, player + enemy + world, is only a fallback).
	if hit_layers >= 0:
		_hitbox.collision_mask = hit_layers
	_hitbox.monitoring = true
	_collision_shape.disabled = false
	if _collision_shape.shape is CircleShape2D:
		var circle := (_collision_shape.shape as CircleShape2D).duplicate() as CircleShape2D
		circle.radius = get_radius()
		_collision_shape.shape = circle
	_hitbox.body_entered.connect(_on_body_entered)
	queue_redraw()

## Looks up the two nodes through the exported paths. A path that leads to nothing (or to the wrong kind of node) is
## reported by property name and the area removes itself.
func _resolve_nodes() -> bool:
	_hitbox = get_node_or_null(hitbox_path) as Area2D
	_collision_shape = get_node_or_null(collision_shape_path) as CollisionShape2D
	var ok := true
	if _hitbox == null:
		push_error("AreaEffect2D: hitbox_path '%s' does not lead to an Area2D." % hitbox_path)
		ok = false
	if _collision_shape == null:
		push_error("AreaEffect2D: collision_shape_path '%s' does not lead to a CollisionShape2D." % collision_shape_path)
		ok = false
	return ok

## Radius of the hit circle in px (half of hitbox_size.x).
func get_radius() -> float:
	return maxf(hitbox_size.x * 0.5, 0.5)

## Seconds the area has existed.
func get_age() -> float:
	return _age

func is_ended() -> bool:
	return _ended

func _physics_process(delta: float) -> void:
	if _ended:
		return
	if follow_source and is_instance_valid(source):
		if _follow_ready:
			global_position = source.global_position + _follow_delta
		else:
			_follow_delta = global_position - source.global_position
			_follow_ready = true
	# Bodies already inside when the area appears, or that the signal missed.
	for body in _hitbox.get_overlapping_bodies():
		_try_hit(body)
	if _ended:
		return
	_age += delta
	queue_redraw()
	if _age >= active_time:
		_end()

func _on_body_entered(body: Node2D) -> void:
	_try_hit(body)

func _can_hit() -> bool:
	return not _ended and _hitbox != null

func _get_hit_origin() -> Vector2:
	return _hitbox.global_position if _hitbox != null else global_position

## The hit policy is used up (max_targets reached, or pierce off after the first target).
func _on_spent() -> void:
	_end()

func _end() -> void:
	if _ended:
		return
	_ended = true
	set_physics_process(false)
	if _hitbox != null:
		_hitbox.set_deferred("monitoring", false)
	queue_free()

func _draw() -> void:
	if flash_color.a <= 0.0:
		return
	var fade := 1.0 - clampf(_age / maxf(active_time, 0.05), 0.0, 1.0)
	var fill := flash_color
	fill.a *= fade
	var rim := Color(flash_color.r, flash_color.g, flash_color.b, minf(flash_color.a * 3.0, 1.0) * fade)
	draw_circle(hitbox_offset, get_radius(), fill)
	draw_arc(hitbox_offset, get_radius(), 0.0, TAU, 40, rim, 1.5)

## Scene problems (H3.2): the hit area and its shape exist.
func get_scene_problems(_effect_clip: StringName) -> Array[String]:
	return _hitbox_scene_problems(hitbox_path, collision_shape_path)

func get_scene_warnings() -> Array[String]:
	return _shape_scene_warnings(collision_shape_path, "CircleShape2D")
