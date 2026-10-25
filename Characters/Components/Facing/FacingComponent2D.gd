extends Node
class_name FacingComponent2D
## Track P8: which way a character faces, and how the rig shows it. It replaces the facing and weapon-aim
## code that lived in `Character2D`, with the same behavior.
##
## Every physics frame, `Character2D` calls `update(idle_aim)`, and this component
##   1. remembers the last horizontal movement direction (`context.movement_facing_direction`),
##   2. picks the visible facing: that direction, or, during an attack, the side the attack points to
##      (`context.facing_direction`),
##   3. sets `context.aim_direction`: the attack direction while attacking, otherwise `idle_aim`,
##   4. mirrors the body (`context.visual_root`) and the weapon pivot (`context.weapon_facing_root`) on x,
##   5. rotates the weapon pivot toward the attack for attacks that ask for it (`aim_weapon`).
## The state stays on the context, because many components read `context.facing_direction`.
##
## Track P9 adds three things on top (all with fields below):
##   - a dead zone: an attack aimed almost straight up or down does not flip the facing, so a mouse hovering
##     above or below the character does not make the sprite flicker;
##   - sticky facing: after an attack the character keeps facing the side it attacked toward until it moves
##     horizontally (before, it flipped back to the last movement direction the moment the swing ended);
##   - a settle blend: when a swing finishes or is cancelled, the weapon pivot and the weapon's hand pose blend
##     to their rest pose over `settle_time` instead of snapping. The pivot goes to 0 by the shortest angle; the
##     hand goes to the pose in the weapon's own `idle` clip. A new swing cancels the blend, death snaps.
##
## A `Character2D` with no child named "FacingComponent2D" gets one with the defaults below, made in code,
## so a character scene written before P8 behaves as it did.

## Mirror the body rig (the player's `LayeredRig`, the goblin's `AnimatedSprite2D`) when facing left.
@export var mirror_visual := true
## Mirror the weapon pivot (the player's `WeaponFacingPivot`) when facing left.
@export var mirror_weapon := true
## Turn on for art that is drawn facing left: the rig is then mirrored when facing right instead.
@export var art_faces_left := false
## Rotate the weapon pivot toward the attack direction for attacks with `aim_weapon`. Off keeps the pivot unrotated.
@export var rotate_weapon_to_aim := true
## An attack whose aim has |x| below this (the aim is a unit vector, so 0.15 is about 9 degrees from straight up or
## down) does not change which side the character faces; it keeps the side it already shows. 0 flips on any x.
@export_range(0.0, 0.9, 0.01) var facing_dead_zone := 0.15
## After an attack, keep facing the side it was aimed toward until the character moves horizontally. Off restores
## the older behavior: the facing returns to the last movement direction when the swing ends.
@export var sticky_facing := true
## Seconds the weapon pivot and the weapon hand take to blend to their rest pose when a swing ends or is
## cancelled. 0 snaps (the pre-P9 behavior, including the instant RESET clip on a cancel).
@export_range(0.0, 1.0, 0.01) var settle_time := 0.15

var _context: CharacterContext2D
var _attack_component: AttackComponent2D
## The side the last attack was aimed toward (LEFT or RIGHT), or ZERO. Cleared by horizontal movement.
var _sticky_facing := Vector2.ZERO
## Settle blend state. `_settle_time_elapsed` runs from 0 to `settle_time`; the "from" values are the pose the
## swing ended in, the "to" values come from the weapon's `idle` clip (the pivot always goes to 0).
var _settling := false
## Length and easing of the blend in progress (settle_time and smoothstep, or a code-driven recovery's own).
var _settle_duration := 0.0
var _settle_ease: Curve
## A code-driven recovery's blend started and its swing_ended(false) has not arrived yet: that signal must not
## start a second blend.
var _recovery_blend := false
var _settle_time_elapsed := 0.0
var _pivot_blend := false
var _pivot_from := 0.0
var _hand_blend := false
var _hand_from_position := Vector2.ZERO
var _hand_from_rotation := 0.0
var _hand_to_position = null # Vector2 or null (the idle clip has no position track)
var _hand_to_rotation = null # float or null

## Gives the component the character's context and attack component (the attack component may be null: no
## weapon aim then). Calling it again replaces both.
func initialize(context: CharacterContext2D, attack_component: AttackComponent2D = null) -> void:
	if is_instance_valid(_attack_component) and _attack_component.swing_ended.is_connected(_on_swing_ended):
		_attack_component.swing_ended.disconnect(_on_swing_ended)
		_attack_component.recovery_started.disconnect(_on_recovery_started)
	_recovery_blend = false
	_end_settle()
	_context = context
	_attack_component = attack_component
	if is_instance_valid(_attack_component):
		_attack_component.swing_ended.connect(_on_swing_ended)
		_attack_component.recovery_started.connect(_on_recovery_started)

## One physics frame of facing. `idle_aim` is the aim direction to use when the character is not attacking.
func update(idle_aim: Vector2) -> void:
	if _context == null:
		return
	if _context.movement_input.x < -0.001:
		_context.movement_facing_direction = Vector2.LEFT
	elif _context.movement_input.x > 0.001:
		_context.movement_facing_direction = Vector2.RIGHT
	# Moving horizontally ends the sticky side; the swing itself (even while moving) keeps it.
	if not _context.is_attacking and absf(_context.movement_input.x) > 0.001:
		_sticky_facing = Vector2.ZERO
	var visible_facing: Vector2 = _context.movement_facing_direction
	if sticky_facing and _sticky_facing != Vector2.ZERO:
		visible_facing = _sticky_facing
	if _context.is_attacking:
		if absf(_context.attack_direction.x) > maxf(facing_dead_zone, 0.001):
			visible_facing = Vector2.LEFT if _context.attack_direction.x < 0.0 else Vector2.RIGHT
		else:
			visible_facing = _context.facing_direction # inside the dead zone: keep the side already shown
		_sticky_facing = visible_facing if sticky_facing else Vector2.ZERO
	_context.facing_direction = visible_facing
	_context.aim_direction = _context.attack_direction if _context.is_attacking else idle_aim

	var mirrored := _is_mirrored()
	if mirror_visual and is_instance_valid(_context.visual_root):
		var sx := absf(_context.visual_root.scale.x)
		_context.visual_root.scale.x = -sx if mirrored else sx
		if _context.animated_sprite != null:
			_context.animated_sprite.flip_h = false
	if mirror_weapon and is_instance_valid(_context.weapon_facing_root):
		var fx := absf(_context.weapon_facing_root.scale.x)
		_context.weapon_facing_root.scale.x = -fx if mirrored else fx
	if _settling:
		if _context.is_attacking and not (is_instance_valid(_attack_component) and _attack_component.is_code_recovering()):
			_end_settle() # a new swing or charge started: the animation drives the weapon again
		else:
			_settle_time_elapsed += get_physics_process_delta_time()
	update_weapon_aim()
	if _settling and _settle_time_elapsed >= _settle_duration:
		_end_settle()

## Rotates the weapon pivot toward the attack direction for attacks that set aim_weapon, and back to 0
## otherwise. The pivot is mirrored on x when the rig is mirrored, so the angle is measured from the mirrored
## forward axis: the authored arc is centred on the aim, and the mirror reflects it. `Character2D` also calls
## this on death, which puts the pivot back to 0.
func update_weapon_aim() -> void:
	if _context == null:
		return
	var weight := _settle_weight()
	if rotate_weapon_to_aim and is_instance_valid(_context.weapon_facing_root):
		var rotation_target := 0.0
		if is_instance_valid(_attack_component) and _attack_component.is_aiming_weapon():
			var aim := _context.attack_direction
			rotation_target = atan2(-aim.y, -aim.x) if _is_mirrored() else atan2(aim.y, aim.x)
		elif _settling and _pivot_blend:
			rotation_target = lerp_angle(_pivot_from, 0.0, weight)
		_context.weapon_facing_root.rotation = rotation_target
	if _settling and _hand_blend:
		_apply_hand(weight)

## Puts the weapon pivot and hand at their rest pose at once and ends any blend. `Character2D` calls it on death.
func snap_to_rest() -> void:
	_end_settle()
	update_weapon_aim()
	if _context == null or not is_instance_valid(_context.weapon_pivot):
		return
	var idle := _idle_pose()
	if idle.has("position"):
		_context.weapon_pivot.position = idle["position"]
	if idle.has("rotation"):
		_context.weapon_pivot.rotation = idle["rotation"]

## True while a settle blend is running (tests and tools).
func is_settling() -> bool:
	return _settling

## A swing or charge ended (finished, cancelled or interrupted): start blending the pivot and the hand to rest.
## Emitted by AttackComponent2D before it stops the weapon clip, so the poses read here are the ones on screen.
func _on_swing_ended(cancelled: bool) -> void:
	if _context == null:
		return
	if _recovery_blend and not cancelled:
		_recovery_blend = false # a code-driven recovery already blended the weapon back; let it finish
		return
	_recovery_blend = false
	_begin_settle(settle_time, null)

## A code-driven return (AttackDefinition2D.recovery_time) began: blend over its duration with its easing.
func _on_recovery_started(duration: float, ease_curve: Curve) -> void:
	if _context == null:
		return
	_begin_settle(duration, ease_curve)
	_recovery_blend = _settling

func _begin_settle(duration: float, ease_curve: Curve) -> void:
	_end_settle()
	if duration <= 0.0:
		return
	_settle_duration = duration
	_settle_ease = ease_curve
	_pivot_blend = rotate_weapon_to_aim and is_instance_valid(_context.weapon_facing_root)
	if _pivot_blend:
		_pivot_from = _context.weapon_facing_root.rotation
	var hand := _context.weapon_pivot
	var idle := _idle_pose()
	_hand_blend = is_instance_valid(hand) and not idle.is_empty()
	if _hand_blend:
		_hand_from_position = hand.position
		_hand_from_rotation = hand.rotation
		_hand_to_position = idle.get("position")
		_hand_to_rotation = idle.get("rotation")
	_settling = _pivot_blend or _hand_blend
	_settle_time_elapsed = 0.0
	_context.hand_settling = _hand_blend

func _end_settle() -> void:
	_settling = false
	_pivot_blend = false
	_hand_blend = false
	_settle_time_elapsed = 0.0
	if _context != null:
		_context.hand_settling = false

## 0 to 1, eased, how far the blend has gone.
func _settle_weight() -> float:
	if not _settling or _settle_duration <= 0.0:
		return 1.0
	var t := clampf(_settle_time_elapsed / _settle_duration, 0.0, 1.0)
	if _settle_ease != null:
		return clampf(_settle_ease.sample(t), 0.0, 1.0)
	return smoothstep(0.0, 1.0, t)

func _apply_hand(weight: float) -> void:
	var hand := _context.weapon_pivot
	if not is_instance_valid(hand):
		return
	if _hand_to_position != null:
		hand.position = _hand_from_position.lerp(_hand_to_position as Vector2, weight)
	if _hand_to_rotation != null:
		hand.rotation = lerp_angle(_hand_from_rotation, _hand_to_rotation as float, weight)

## The weapon's rest pose: the first key of the position and rotation tracks of its `idle` clip (the clip is data
## the weapon already carries; no code plays it). Empty when the weapon has no such clip or tracks.
func _idle_pose() -> Dictionary:
	var pose := {}
	if _context == null or not is_instance_valid(_context.weapon_animation_player):
		return pose
	var player := _context.weapon_animation_player
	if not player.has_animation(&"idle"):
		return pose
	var idle := player.get_animation(&"idle")
	for property in [&"position", &"rotation"]:
		var track := idle.find_track(NodePath(".:%s" % property), Animation.TYPE_VALUE)
		if track >= 0 and idle.track_get_key_count(track) > 0:
			pose[String(property)] = idle.track_get_key_value(track, 0)
	return pose

## True when the rig is shown mirrored: facing left, or facing right for art drawn facing left.
func _is_mirrored() -> bool:
	return (_context.facing_direction.x < 0.0) != art_faces_left
