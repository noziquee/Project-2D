extends Node
class_name TargetingService2D
## Picks the target an aimed action points at (H8.3). It finds candidates in the `damageable` group, drops the ones that
## cannot be targeted, scores the rest with an AimShape2D and returns a target plus the direction to aim in.
##
## Rules (from the design PDF):
##   - Eligible: in the group, alive, not the caster, not on the caster's own non-empty team, inside the shape. For a
##     light tap the shape is the camera view (H9.3, ViewAimShape2D): what is on screen can be targeted, whatever the range.
##     A heavy attack or skill keeps its own aim shape.
##   - Score: how well it lines up with the aim first, distance second (AimShape2D.score).
##   - Stable: the choice is made when an action starts and kept for that action (begin_action / resolve). It is only
##     replaced when the target dies, becomes invalid or leaves range. Between actions the last target gets a small
##     bonus, so two near-equal enemies do not make the aim flip from tap to tap.
##   - No target: the direction falls back to the intended aim, then the last valid aim, then the facing, then right.
##   - Manual aim (a deliberate drag) skips the search for that action.
##
## It reads nothing from input and changes nothing in combat: the caller asks, then runs its normal attack or skill
## with the returned direction. Nobody calls it yet (H8.4 and later wire it in).

## Where a resolved direction came from.
enum Source {
	## The player aimed by hand; no search was made.
	MANUAL,
	## Toward the picked target.
	TARGET,
	## No target: the intended aim (mouse, stick, movement) was used.
	INTENDED,
	## No target and no intended aim: the last valid aim direction.
	LAST_AIM,
	## No target, no intended aim, no last aim: the last non-zero facing.
	FACING,
	## Nothing known at all: right.
	DEFAULT,
}

## Result of resolve(): who to aim at (or null) and the direction.
class AimResult extends RefCounted:
	var target: Node2D = null
	var direction: Vector2 = Vector2.RIGHT
	var source: Source = Source.DEFAULT
	func has_target() -> bool:
		return target != null

## The group characters and registered damageable objects belong to (BasicEnemy2D.tscn, player.tscn, and any
## Hurtbox2D with `targetable` on).
const GROUP := &"damageable"
## Added to the previous target's score when a new pick is made, so a near tie keeps the old target.
const STICKY_BONUS := 0.15

## The character this belongs to. Left empty, the parent node is used.
@export var caster: Node2D
## Radius of a target's body in pixels, so a big body just outside the edge still counts (AimShape2D margin).
@export_range(0.0, 64.0, 1.0) var target_margin: float = 8.0

var _action_target: Node2D = null
var _last_target: Node2D = null
## The target the on-screen marker last showed. It gets the same stay-put bonus as _last_target, so the marker does not
## flip between two enemies whose distances differ by a few pixels (H9-54).
var _marked_target: Node2D = null
var _view_override := Rect2()

func _ready() -> void:
	if caster == null:
		caster = get_parent() as Node2D

## The rectangle the camera shows, in world coordinates (H9.3). With no camera it is the viewport's own rectangle. Empty
## when the service is not in a tree.
func get_view_rect() -> Rect2:
	if _view_override.size.x > 0.0 and _view_override.size.y > 0.0:
		return _view_override
	if not is_inside_tree() or get_viewport() == null:
		return Rect2()
	var viewport := get_viewport()
	return viewport.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, viewport.get_visible_rect().size)

## Uses `rect` instead of the camera's rectangle until clear_view_override() (tests, cut scenes).
func set_view_override(rect: Rect2) -> void:
	_view_override = rect

func clear_view_override() -> void:
	_view_override = Rect2()

## True when `node` is inside the camera view (its body's margin counts).
func is_in_view(node: Node2D) -> bool:
	return is_instance_valid(node) and get_view_rect().grow(target_margin).has_point(node.global_position)

## The aim area of a light tap: the camera view as an aim shape, `angle` degrees wide round the aim.
func make_view_shape(angle: float = 360.0, weight: float = AimShape2D.ANGLE_WEIGHT) -> ViewAimShape2D:
	return ViewAimShape2D.make(get_view_rect(), angle, weight)

## How far the target's body reaches out from its position, in pixels (H9.4.1). This is the allowance `is_in_reach()` gives
## a target for its size. It is `target_margin` at least, so a small body (the goblin's capsule is 5 px wide) keeps the same
## 8 px the aim shapes use; a body with a bigger collision shape (a crate, a large object) counts its own extent. For
## a rectangle or a capsule the smaller half-side is used, so a swing is never judged in range by a corner it cannot touch.
func get_body_allowance(target: Node2D) -> float:
	var allowance := target_margin
	if not is_instance_valid(target):
		return allowance
	for child in target.get_children():
		var collision := child as CollisionShape2D
		if collision == null or collision.disabled or collision.shape == null:
			continue
		allowance = maxf(allowance, _shape_extent(collision.shape) * _largest_scale(collision))
	return allowance

## True when `target` can be hit from `origin` by an action that reaches `reach` pixels (H9.4.1). Distance is measured
## between `origin` and the target's position, the same two points the blue circle and the swing use, minus the target's
## body allowance. A reach of 0 or less is never in reach (a self buff has no target to close in on). Visibility does not
## matter here: a target in view but too far is simply not in reach.
func is_in_reach(origin: Vector2, target: Node2D, reach: float) -> bool:
	if reach <= 0.0 or not is_instance_valid(target):
		return false
	return origin.distance_to(target.global_position) - get_body_allowance(target) <= reach

## How much farther than `reach` the target is, 0 when it is in reach (H9.4.2 reads this to see whether the walk is
## getting anywhere).
func distance_to_reach(origin: Vector2, target: Node2D, reach: float) -> float:
	if not is_instance_valid(target):
		return INF
	return maxf(origin.distance_to(target.global_position) - get_body_allowance(target) - maxf(reach, 0.0), 0.0)

static func _shape_extent(shape: Shape2D) -> float:
	var circle := shape as CircleShape2D
	if circle != null:
		return circle.radius
	var capsule := shape as CapsuleShape2D
	if capsule != null:
		return capsule.radius
	var box := shape as RectangleShape2D
	if box != null:
		return minf(box.size.x, box.size.y) * 0.5
	return 0.0

static func _largest_scale(node: Node2D) -> float:
	var scale_xy := node.global_scale.abs()
	return maxf(scale_xy.x, scale_xy.y)

## Starts a new action (a tap, a charge release, a skill cast). The next resolve() picks afresh; the previous target
## still gets the small stay-put bonus.
func begin_action() -> void:
	_action_target = null

## Forgets both the action's target and the last one (a respawn, a scene change, tests).
func clear() -> void:
	_action_target = null
	_last_target = null
	_marked_target = null

## The target kept for the current action, or null.
func get_action_target() -> Node2D:
	return _action_target if _is_valid_target(_action_target) else null

## Works out where an aimed action goes.
##   origin     where the action starts (the character or its attack origin)
##   intended   the aim the player gave: mouse, stick, movement. Zero when there is none (a plain touch tap)
##   shape      the action's AimShape2D; null means no assist (fallback only)
##   last_aim   the last valid aim direction (zero when unknown)
##   facing     the last non-zero facing (zero when unknown)
##   manual     true for a deliberate drag: the direction is used as given and no target is searched
func resolve(origin: Vector2, intended: Vector2, shape: AimShape2D, last_aim: Vector2 = Vector2.ZERO, facing: Vector2 = Vector2.ZERO, manual: bool = false) -> AimResult:
	var result := AimResult.new()
	var axis := Vector2.ZERO
	var axis_source := Source.DEFAULT
	if intended.length_squared() > 0.0001:
		axis = intended.normalized()
		axis_source = Source.MANUAL if manual else Source.INTENDED
	elif last_aim.length_squared() > 0.0001:
		axis = last_aim.normalized()
		axis_source = Source.LAST_AIM
	elif facing.length_squared() > 0.0001:
		axis = facing.normalized()
		axis_source = Source.FACING
	else:
		axis = Vector2.RIGHT
	if manual:
		result.direction = axis
		result.source = axis_source
		return result
	var target: Node2D = null
	if shape != null:
		target = _action_target if _still_good(_action_target, origin, shape) else _pick(origin, axis, shape)
	_action_target = target
	if target != null:
		_last_target = target
		var to_target := target.global_position - origin
		if to_target.length_squared() > 0.0001:
			result.target = target
			result.direction = to_target.normalized()
			result.source = Source.TARGET
			return result
	result.direction = axis
	result.source = axis_source
	return result

## The best target for `axis` right now, with no action state (null when there is none).
func pick_target(origin: Vector2, axis: Vector2, shape: AimShape2D) -> Node2D:
	return _pick(origin, axis, shape)

## The target the marker shows: the same rule as pick_target(), but the previously marked target keeps the stay-put
## bonus while it stays valid, so the marker is stable. Changes only the marker's memory, never the action's target.
func pick_marked_target(origin: Vector2, axis: Vector2, shape: AimShape2D) -> Node2D:
	var remembered: Node2D = _marked_target if is_instance_valid(_marked_target) else null
	var picked := _pick(origin, axis, shape, remembered)
	_marked_target = picked
	return picked

## Every eligible target inside `shape` right now, best first (H8.9: the indicator rings them). No action state, so asking
## never changes which target an action keeps.
func candidates_in_shape(origin: Vector2, axis: Vector2, shape: AimShape2D) -> Array[Node2D]:
	var found: Array[Node2D] = []
	if shape == null or not is_inside_tree():
		return found
	var scored: Array = []
	for node in get_tree().get_nodes_in_group(GROUP):
		if not is_eligible(node):
			continue
		var candidate: Node2D = node
		var score := shape.score(origin, axis, candidate.global_position, target_margin)
		if score >= 0.0:
			scored.append([score, candidate])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for entry in scored:
		found.append(entry[1])
	return found

## Every eligible target whose body touches the circle at `center` of `radius`, nearest the centre first (H8.8: what a
## placed ground circle covers). No action state.
func candidates_in_circle(center: Vector2, radius: float) -> Array[Node2D]:
	var found: Array[Node2D] = []
	if radius <= 0.0 or not is_inside_tree():
		return found
	var scored: Array = []
	for node in get_tree().get_nodes_in_group(GROUP):
		if not is_eligible(node):
			continue
		var candidate: Node2D = node
		var distance := center.distance_to(candidate.global_position)
		if distance <= radius + target_margin:
			scored.append([distance, candidate])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry in scored:
		found.append(entry[1])
	return found

## True when `node` could be a target at all, whatever the shape: valid, in the tree, in the group, not the caster,
## not on the caster's own team, alive.
func is_eligible(node: Variant) -> bool:
	if not _is_valid_target(node):
		return false
	if not node.is_in_group(GROUP):
		return false
	return true

func _pick(origin: Vector2, axis: Vector2, shape: AimShape2D, sticky: Node2D = null) -> Node2D:
	if shape == null or not is_inside_tree():
		return null
	var best: Node2D = null
	var best_score := -1.0
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(GROUP):
		if not is_eligible(node):
			continue
		var candidate: Node2D = node
		var score := shape.score(origin, axis, candidate.global_position, target_margin)
		if score < 0.0:
			continue
		if candidate == _last_target or (sticky != null and candidate == sticky):
			score += STICKY_BONUS
		var distance := origin.distance_to(candidate.global_position)
		if score > best_score or (is_equal_approx(score, best_score) and distance < best_distance):
			best = candidate
			best_score = score
			best_distance = distance
	return best

## The action's target is kept while it is valid and still inside the shape (its reach, or for the camera view the
## screen; not necessarily in the same direction: the stability rule is about range and validity, not about re-aiming).
func _still_good(node: Variant, origin: Vector2, shape: AimShape2D) -> bool:
	if not _is_valid_target(node):
		return false
	return shape.keeps_target(origin, node.global_position, target_margin)

## Takes a Variant on purpose: a target that was freed since it was stored must read as "not valid", not raise an error.
func _is_valid_target(node: Variant) -> bool:
	if not is_instance_valid(node) or not (node is Node2D):
		return false
	if not node.is_inside_tree() or node == caster:
		return false
	if node.has_method("is_alive") and not node.is_alive():
		return false
	if caster != null and is_instance_valid(caster):
		var own_team: Variant = caster.get("team")
		var their_team: Variant = node.get("team")
		if own_team != null and their_team != null and own_team != &"" and own_team == their_team:
			return false
	return true
