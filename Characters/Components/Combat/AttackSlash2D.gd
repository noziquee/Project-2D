extends AttackEffect2D
class_name AttackSlash2D
## The melee slash effect: uses the project's sprite animation, with a separate configurable hitbox origin.
## Everything shared with other effect kinds (configure, signals, target filter, hit-once) lives in
## AttackEffect2D (10.2); this script keeps only what belongs to the slash scene.

## Default location of the effect's AnimationPlayer in AttackSlash2D.tscn.
const ANIMATION_PLAYER_PATH := "SlashEffectAnimSpritesheet/AnimationPlayer"

@export_group("Scene nodes (10.3)")
## Where this effect finds its nodes, relative to the root. The defaults match AttackSlash2D.tscn, so the shipped
## scene needs no edits; an effect scene built differently only has to point these at its own nodes.
@export var animation_player_path: NodePath = NodePath(ANIMATION_PLAYER_PATH)
## The Area2D that detects targets.
@export var hitbox_path: NodePath = ^"HitboxOrigin/HitboxMotion/Area2D"
## The CollisionShape2D whose animated `disabled` track is the hit window.
@export var collision_shape_path: NodePath = ^"HitboxOrigin/HitboxMotion/Area2D/CollisionShape2D"
## The Node2D moved by `hitbox_offset`.
@export var hitbox_origin_path: NodePath = ^"HitboxOrigin"

## True when `scene` has an effect AnimationPlayer (the one its own animation_player_path names) but not the clip
## `clip`. A scene with no such player, or one that cannot be instantiated, is not judged here (false), and neither
## is an empty clip name.
static func scene_lacks_animation(scene: PackedScene, clip: StringName) -> bool:
	if scene == null or clip == &"" or not scene.can_instantiate():
		return false
	var instance := scene.instantiate()
	var path := NodePath(ANIMATION_PLAYER_PATH)
	var custom: Variant = instance.get("animation_player_path")
	if custom is NodePath and not (custom as NodePath).is_empty():
		path = custom
	var player := instance.get_node_or_null(path) as AnimationPlayer
	var lacks := player != null and not player.has_animation(clip)
	instance.free()
	return lacks

var _slash_animation_player: AnimationPlayer
var _hitbox: Area2D
var _collision_shape: CollisionShape2D
var _hitbox_origin: Node2D

func _ready() -> void:
	if not _resolve_nodes():
		set_physics_process(false)
		queue_free()
		return
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
	if not _slash_animation_player.has_animation(effect_animation):
		push_error("AttackSlash2D requires the animation player '%s' to have the animation '%s'." % [animation_player_path, effect_animation])
		queue_free()
		return
	_slash_animation_player.play(effect_animation)

## Looks up the four nodes through the exported paths. A path that leads to nothing (or to the wrong kind of
## node) is reported by property name and the effect removes itself instead of failing later with a null error.
func _resolve_nodes() -> bool:
	_slash_animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	_hitbox = get_node_or_null(hitbox_path) as Area2D
	_collision_shape = get_node_or_null(collision_shape_path) as CollisionShape2D
	_hitbox_origin = get_node_or_null(hitbox_origin_path) as Node2D
	var ok := true
	if _slash_animation_player == null:
		push_error("AttackSlash2D: animation_player_path '%s' does not lead to an AnimationPlayer." % animation_player_path)
		ok = false
	if _hitbox == null:
		push_error("AttackSlash2D: hitbox_path '%s' does not lead to an Area2D." % hitbox_path)
		ok = false
	if _collision_shape == null:
		push_error("AttackSlash2D: collision_shape_path '%s' does not lead to a CollisionShape2D." % collision_shape_path)
		ok = false
	if _hitbox_origin == null:
		push_error("AttackSlash2D: hitbox_origin_path '%s' does not lead to a Node2D." % hitbox_origin_path)
		ok = false
	return ok

func _physics_process(_delta: float) -> void:
	if not _can_hit():
		return
	for body in _hitbox.get_overlapping_bodies():
		_try_hit(body)

func _on_body_entered(body: Node2D) -> void:
	_try_hit(body)

## The hit window: the hitbox is monitoring and the animated CollisionShape2D:disabled track has enabled it.
func _can_hit() -> bool:
	return _hitbox != null and _collision_shape != null and _hitbox.monitoring and not _collision_shape.disabled

func _get_hit_origin() -> Vector2:
	return _hitbox.global_position if _hitbox != null else global_position

func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == effect_animation:
		queue_free()
