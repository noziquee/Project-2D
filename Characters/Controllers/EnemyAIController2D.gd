extends Node
class_name EnemyAIController2D
## Enemy intent only; the parent Character2D performs shared movement and attacks.
##
## Targets are found through the enemy's DetectionArea (an Area2D with a CircleShape2D):
## bodies that enter it, and are in `target_group`, become candidates. Tuning lives in an
## EnemyBehaviorProfile resource; the swing distance comes from the attack definition.

enum Behavior { IDLE, CHASE, ATTACK, RETURN }

## Swing distance used when the active attack definition's ai_attack_range is 0.
const FALLBACK_ATTACK_RANGE := 30.0

signal behavior_changed(previous_behavior: Behavior, current_behavior: Behavior)

@export var profile: EnemyBehaviorProfile
## Area2D whose CircleShape2D is the detection range. Left empty, the character's child
## named "DetectionArea" is used. Set its collision mask to the layers of the targets.
@export var detection_area: Area2D
@export var target_group: StringName = &"player"

var behavior: Behavior = Behavior.IDLE
var _character: Character2D
var _target: Node2D
# Untyped on purpose: a candidate can be freed while it is still in the list.
var _candidates: Array = []
var _home_position := Vector2.ZERO
var _lost_target_elapsed := 0.0
var _movement_intent := Vector2.ZERO
var _aim_direction := Vector2.RIGHT
var _attack_requested := false

func initialize(character: Character2D) -> void:
	_character = character
	_home_position = character.global_position
	_aim_direction = character.context.facing_direction
	if profile == null:
		profile = EnemyBehaviorProfile.new()
	_setup_detection_area()

func physics_update(delta: float) -> void:
	if not is_instance_valid(_character) or _character.context == null or not _character.is_alive():
		_movement_intent = Vector2.ZERO
		_attack_requested = false
		return
	_attack_requested = false
	_refresh_target(delta)

	if _is_valid_target(_target):
		var to_target: Vector2 = _target.global_position - _character.global_position
		var distance: float = to_target.length()
		if distance > 0.001:
			_aim_direction = to_target / distance
		else:
			_aim_direction = _character.context.facing_direction
		if distance <= get_effective_attack_range():
			_movement_intent = Vector2.ZERO
			_set_behavior(Behavior.ATTACK)
			if not _character.context.is_attacking and not _character.context.is_dashing and not _character.attack_component.is_on_cooldown():
				_attack_requested = true
		else:
			_movement_intent = to_target.normalized()
			_set_behavior(Behavior.CHASE)
		return

	var to_home: Vector2 = _home_position - _character.global_position
	if to_home.length() > profile.home_stop_distance:
		_movement_intent = to_home.normalized()
		if to_home.length_squared() > 0.001:
			_aim_direction = to_home.normalized()
		_set_behavior(Behavior.RETURN)
	else:
		_movement_intent = Vector2.ZERO
		_set_behavior(Behavior.IDLE)

## Distance at which this enemy starts a swing: the active attack definition's
## ai_attack_range when it is above zero, otherwise FALLBACK_ATTACK_RANGE.
func get_effective_attack_range() -> float:
	if is_instance_valid(_character) and is_instance_valid(_character.attack_component):
		var attack_definition: AttackDefinition2D = _character.attack_component.definition
		if attack_definition != null and attack_definition.ai_attack_range > 0.0:
			return attack_definition.ai_attack_range
	return FALLBACK_ATTACK_RANGE

## Radius of the circle currently used for detection (0 when there is no usable area).
func get_detection_radius() -> float:
	var circle := _find_detection_circle()
	return circle.radius if circle != null else 0.0

func get_behavior_name() -> String:
	return Behavior.keys()[behavior]

## Number of valid bodies currently inside the detection area.
func get_candidate_count() -> int:
	_prune_candidates()
	return _candidates.size()

func get_movement_intent() -> Vector2:
	return _movement_intent

func get_aim_direction() -> Vector2:
	return _aim_direction if _aim_direction.length_squared() > 0.001 else Vector2.RIGHT

func get_attack_direction() -> Vector2:
	return get_aim_direction()

func consume_attack_request() -> bool:
	var requested := _attack_requested
	_attack_requested = false
	return requested

func get_current_target() -> Node2D:
	return _target if _is_valid_target(_target) else null

func _setup_detection_area() -> void:
	if not is_instance_valid(detection_area):
		detection_area = _character.get_node_or_null("DetectionArea") as Area2D
	if detection_area == null:
		push_error("EnemyAIController2D on '%s' has no DetectionArea (Area2D); the enemy will never notice a target." % _character.name)
		return
	var circle := _find_detection_circle()
	if circle == null:
		push_error("EnemyAIController2D on '%s': its DetectionArea needs a CollisionShape2D with a CircleShape2D." % _character.name)
	elif profile.detection_radius > 0.0:
		# The drawn shape is a scene sub-resource shared by every instance, so override a copy.
		var override_circle := circle.duplicate() as CircleShape2D
		override_circle.radius = profile.detection_radius
		_find_detection_shape_node().shape = override_circle
	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)

func _find_detection_shape_node() -> CollisionShape2D:
	if not is_instance_valid(detection_area):
		return null
	for child in detection_area.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape is CircleShape2D:
			return child as CollisionShape2D
	return null

func _find_detection_circle() -> CircleShape2D:
	var shape_node := _find_detection_shape_node()
	return shape_node.shape as CircleShape2D if shape_node != null else null

func _on_body_entered(body: Node2D) -> void:
	if body == _character or not body.is_in_group(target_group):
		return
	if not _candidates.has(body):
		_candidates.append(body)

func _on_body_exited(body: Node2D) -> void:
	_candidates.erase(body)

func _prune_candidates() -> void:
	for i in range(_candidates.size() - 1, -1, -1):
		if not _is_valid_target(_candidates[i]):
			_candidates.remove_at(i)

func _refresh_target(delta: float) -> void:
	if _is_valid_target(_target):
		var distance: float = _character.global_position.distance_to(_target.global_position)
		if distance <= profile.disengage_radius:
			_lost_target_elapsed = 0.0
			return
		_lost_target_elapsed += delta
		if _lost_target_elapsed < profile.lost_target_grace_duration:
			return
		_target = null
		_lost_target_elapsed = 0.0
	_target = _find_nearest_candidate()

func _find_nearest_candidate() -> Node2D:
	_prune_candidates()
	var nearest: Node2D
	var nearest_distance := INF
	for candidate in _candidates:
		var node := candidate as Node2D
		var distance: float = _character.global_position.distance_to(node.global_position)
		if distance < nearest_distance:
			nearest = node
			nearest_distance = distance
	return nearest

func _is_valid_target(candidate: Node) -> bool:
	if not is_instance_valid(candidate) or not candidate is Node2D or candidate == _character:
		return false
	if not candidate.is_inside_tree() or candidate.is_queued_for_deletion():
		return false
	if candidate.has_method("is_alive") and not bool(candidate.call("is_alive")):
		return false
	return true

func _set_behavior(next_behavior: Behavior) -> void:
	if behavior == next_behavior:
		return
	var previous := behavior
	behavior = next_behavior
	behavior_changed.emit(previous, behavior)
