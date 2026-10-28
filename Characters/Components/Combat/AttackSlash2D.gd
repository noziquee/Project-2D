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
## The Node2D (child of the origin, parent of the Area2D) the swing moves along x (H9.2). Optional: a scene without it
## keeps whatever motion its own clips animate.
@export var hitbox_motion_path: NodePath = ^"HitboxOrigin/HitboxMotion"

@export_group("Reach (H9.2)")
## How the swing eases out to its reach over the hit window. 0.5 starts fast and slows down (the curve the old keyframes
## used); 1 is steady; above 1 starts slow. Godot's `ease()` curve.
@export_range(0.1, 4.0, 0.05) var reach_ease: float = 0.5
## Reach used when the attack names none (attack_range 0 and no aim shape): the swing's old fixed distance.
@export_range(1.0, 1000.0, 1.0) var fallback_reach: float = 70.0

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
var _hitbox_motion: Node2D
var _sprite: Node2D
## Reach driver (H9.2). Off when the scene has no motion node or its clip still animates positions itself.
var _reach_driven := false
var _motion_start_x := 0.0
var _motion_end_x := 0.0
var _window_end := 0.001

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
	_setup_reach_motion()
	_slash_animation_player.play(effect_animation)

## Looks up the four nodes through the exported paths. A path that leads to nothing (or to the wrong kind of
## node) is reported by property name and the effect removes itself instead of failing later with a null error.
func _resolve_nodes() -> bool:
	_slash_animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	_hitbox = get_node_or_null(hitbox_path) as Area2D
	_collision_shape = get_node_or_null(collision_shape_path) as CollisionShape2D
	_hitbox_origin = get_node_or_null(hitbox_origin_path) as Node2D
	_hitbox_motion = get_node_or_null(hitbox_motion_path) as Node2D
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

func _process(_delta: float) -> void:
	if _reach_driven and _slash_animation_player != null and _slash_animation_player.is_playing():
		_apply_reach_motion(_slash_animation_player.current_animation_position)

func _physics_process(_delta: float) -> void:
	if not _can_hit():
		return
	for body in _hitbox.get_overlapping_bodies():
		_try_hit(body)

func _on_body_entered(body: Node2D) -> void:
	_try_hit(body)

## H9.2: the swing's reach comes from the attack, not from keyframes. The hitbox starts where the scene puts it and
## its leading edge (centre + half the hitbox width x the clip's final shape scale + the offset) travels to
## `attack_range` over the hit window the clip authors; the sprite travels the same distance. Timing stays in the clip.
func _setup_reach_motion() -> void:
	_reach_driven = false
	if _hitbox_motion == null or _slash_animation_player == null:
		return
	var clip := _slash_animation_player.get_animation(effect_animation)
	_sprite = _slash_animation_player.get_node_or_null(_slash_animation_player.root_node) as Node2D
	if clip == null or _sprite == null or _clip_moves_positions(clip):
		return
	var reach := attack_range if attack_range > 0.0 else fallback_reach
	_motion_start_x = _hitbox_motion.position.x
	_motion_end_x = maxf(reach - hitbox_offset.x - hitbox_size.x * 0.5 * _final_shape_scale_x(clip), _motion_start_x)
	_window_end = maxf(_hit_window_end(clip), 0.001)
	_reach_driven = true
	_apply_reach_motion(0.0)

## Puts the hitbox and the sprite where the swing is `time` seconds into its clip.
func _apply_reach_motion(time: float) -> void:
	if not _reach_driven:
		return
	var progress := clampf(time / _window_end, 0.0, 1.0)
	var x := lerpf(_motion_start_x, _motion_end_x, ease(progress, reach_ease))
	_hitbox_motion.position.x = x
	_sprite.position.x = x - _motion_start_x

## True while the reach driver is moving this swing (false for a scene whose clip still animates positions).
func is_reach_driven() -> bool:
	return _reach_driven

## The hitbox's leading edge along the swing direction, in pixels from the attack origin, at this moment.
func get_leading_edge() -> float:
	if _hitbox_motion == null or _collision_shape == null:
		return 0.0
	return _hitbox_motion.position.x + hitbox_offset.x + hitbox_size.x * 0.5 * _collision_shape.scale.x

## Jumps the swing to `time` seconds into its clip and applies the reach motion (for tests and previews).
func seek_swing(time: float) -> void:
	if _slash_animation_player != null:
		_slash_animation_player.seek(time, true)
	_apply_reach_motion(time)

## True when `clip` animates any position itself (the old sprite and hitbox tracks): the driver then stays off.
static func _clip_moves_positions(clip: Animation) -> bool:
	for i in clip.get_track_count():
		if str(clip.track_get_path(i)).ends_with(":position"):
			return true
	return false

## The x scale the hit shape ends with: the last key of the clip's CollisionShape2D scale track, else 1.
static func _final_shape_scale_x(clip: Animation) -> float:
	for i in clip.get_track_count():
		var path := str(clip.track_get_path(i))
		if path.ends_with("CollisionShape2D:scale") and clip.track_get_key_count(i) > 0:
			var last: Variant = clip.track_get_key_value(i, clip.track_get_key_count(i) - 1)
			if last is Vector2:
				return (last as Vector2).x
	return 1.0

## When the hit window closes: the time of the `disabled` key that turns true after it was false; the clip's length
## when there is none.
static func _hit_window_end(clip: Animation) -> float:
	for i in clip.get_track_count():
		if not str(clip.track_get_path(i)).ends_with(":disabled"):
			continue
		var opened := false
		for k in clip.track_get_key_count(i):
			var disabled: Variant = clip.track_get_key_value(i, k)
			if disabled == false:
				opened = true
			elif opened:
				return clip.track_get_key_time(i, k)
		break
	return clip.length

## The hit window: the hitbox is monitoring and the animated CollisionShape2D:disabled track has enabled it.
func _can_hit() -> bool:
	return _hitbox != null and _collision_shape != null and _hitbox.monitoring and not _collision_shape.disabled

func _get_hit_origin() -> Vector2:
	return _hitbox.global_position if _hitbox != null else global_position

func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == effect_animation:
		queue_free()

## Scene problems of a slash (H3.2): all four node paths lead somewhere, the hit shape exists, and the effect clip (when
## given and present) has a track on a CollisionShape2D's `disabled` property. Without that track the hit window never
## opens (the shape starts disabled), so the slash plays but can never hit anything.
func get_scene_problems(effect_clip: StringName) -> Array[String]:
	var found := _hitbox_scene_problems(hitbox_path, collision_shape_path)
	var player := get_node_or_null(animation_player_path) as AnimationPlayer
	if player == null:
		found.append("AttackSlash2D: animation_player_path '%s' does not lead to an AnimationPlayer." % animation_player_path)
	var origin := get_node_or_null(hitbox_origin_path) as Node2D
	if origin == null:
		found.append("AttackSlash2D: hitbox_origin_path '%s' does not lead to a Node2D." % hitbox_origin_path)
	if player != null and effect_clip != &"" and player.has_animation(effect_clip) and not _clip_opens_hit_window(player.get_animation(effect_clip)):
		found.append("AttackSlash2D: clip '%s' has no track on a CollisionShape2D 'disabled' property, so its hit window never opens and it can never hit." % effect_clip)
	return found

func get_scene_warnings() -> Array[String]:
	var found := _shape_scene_warnings(collision_shape_path, "RectangleShape2D")
	var player := get_node_or_null(animation_player_path) as AnimationPlayer
	if player != null and get_node_or_null(hitbox_motion_path) != null:
		for clip_name in player.get_animation_list():
			if clip_name != &"RESET" and _clip_moves_positions(player.get_animation(clip_name)):
				found.append("AttackSlash2D: clip '%s' still animates a position track, so the swing's reach (H9.2) is not applied to it. Remove the sprite and HitboxMotion position tracks and the attack's range drives the swing." % clip_name)
	return found

static func _clip_opens_hit_window(clip: Animation) -> bool:
	for i in clip.get_track_count():
		if str(clip.track_get_path(i)).ends_with(":disabled"):
			return true
	return false
