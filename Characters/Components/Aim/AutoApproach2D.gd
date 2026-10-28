class_name AutoApproach2D
extends RefCounted
## One auto-approach, as plain data and decisions (H9.4.2): the player asked for an attack on a target that is out of
## reach, so the character walks toward it and the attack starts once it is in reach.
##
## This object only answers questions. It holds what was asked (light, heavy or skill, which attack or slot, which
## target) and how long the walk has lasted, and it says which way to walk and whether the walk should end. It moves
## nothing, reads no input and starts no attack: the player script will feed `direction()` into the one movement path
## and start the action itself (H9.4.3). The reach is passed in on every call, never stored, so a weapon swap that
## changes the attack's reach is seen at once.
##
## It ends in one of the reasons below, and stays ended: once `is_active()` is false it gives no direction.

enum Kind { LIGHT, HEAVY, SKILL }

## Why the approach ended. NONE while it is still running.
enum End {
	NONE,
	## The target is in reach: the caller starts the action now.
	ARRIVED,
	## Walked longer than `max_time`.
	TIMEOUT,
	## The distance to close has not shrunk for `stall_time` (a wall, a crowd).
	STALL,
	## The target was freed, died, or can no longer be targeted.
	TARGET_GONE,
	## The target left the camera view.
	LEFT_VIEW,
	## The action has no reach any more (the weapon changed, the attack was removed).
	NO_REACH,
	## The caller cancelled it: manual movement, dash, hit stun, death.
	CANCELLED,
}

## A walk that gains less than this many pixels in a check does not count as progress.
const PROGRESS_EPSILON := 0.5

var kind: Kind = Kind.LIGHT
## The attack id (light, heavy) the approach was asked for; empty for a skill.
var action_id: StringName = &""
## The skill slot (skill); -1 for an attack.
var slot: int = -1
var target: Node2D = null
var max_time: float = 3.0
var stall_time: float = 0.5
var elapsed: float = 0.0
var stall_elapsed: float = 0.0
var end_reason: End = End.NONE

var _best_gap := INF

## Starts an approach on `target`. `max_time` and `stall_time` come from the player's exports.
static func start(kind_: Kind, target_: Node2D, action_id_: StringName = &"", slot_: int = -1, max_time_: float = 3.0, stall_time_: float = 0.5) -> AutoApproach2D:
	var approach := AutoApproach2D.new()
	approach.kind = kind_
	approach.target = target_
	approach.action_id = action_id_
	approach.slot = slot_
	approach.max_time = max_time_
	approach.stall_time = stall_time_
	return approach

func is_active() -> bool:
	return end_reason == End.NONE

## The unit direction to walk in, or zero when the approach has ended or the target is gone.
func direction(origin: Vector2) -> Vector2:
	if not is_active() or not is_instance_valid(target):
		return Vector2.ZERO
	var to_target := target.global_position - origin
	return to_target.normalized() if to_target.length_squared() > 0.0001 else Vector2.ZERO

## True when the target is in reach right now. Same test the swing and the blue circle use (TargetingService2D).
func in_reach(origin: Vector2, reach: float, service: TargetingService2D) -> bool:
	return is_instance_valid(target) and service.is_in_reach(origin, target, reach)

## Advances the approach by `delta` seconds and returns the end reason, or End.NONE when it goes on. Call it once per
## physics frame with the character's position and the reach of the action as it is equipped right now. When it
## returns ARRIVED the caller starts the action that same frame.
## The order matters: a target that is gone or out of view ends the walk before anything else, then a missing reach,
## then arriving (so reaching the target on the very last allowed frame still counts), then the two time limits.
func update(delta: float, origin: Vector2, reach: float, service: TargetingService2D) -> End:
	if not is_active():
		return end_reason
	if not service.is_eligible(target):
		return _end(End.TARGET_GONE)
	if not service.is_in_view(target):
		return _end(End.LEFT_VIEW)
	if reach <= 0.0:
		return _end(End.NO_REACH)
	var gap := service.distance_to_reach(origin, target, reach)
	if gap <= 0.0:
		return _end(End.ARRIVED)
	elapsed += delta
	if elapsed >= max_time:
		return _end(End.TIMEOUT)
	if gap < _best_gap - PROGRESS_EPSILON:
		_best_gap = gap
		stall_elapsed = 0.0
	else:
		stall_elapsed += delta
		if stall_elapsed >= stall_time:
			return _end(End.STALL)
	return End.NONE

## Ends the approach from outside (manual movement, dash, hit stun, death). Does nothing when it already ended.
func cancel() -> void:
	if is_active():
		end_reason = End.CANCELLED

func _end(reason: End) -> End:
	end_reason = reason
	return reason
