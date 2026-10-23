extends Node
class_name EnemyAIController2D
## Enemy intent only; the parent Character2D performs shared movement and attacks.

signal behavior_changed(previous_behavior: StringName, current_behavior: StringName)

@export_group("Targeting")
@export var target_group: StringName = &"player"
@export_range(1.0, 2000.0, 1.0) var detection_radius: float = 180.0
@export_range(1.0, 2500.0, 1.0) var disengage_radius: float = 250.0
@export_range(0.0, 5.0, 0.05) var lost_target_grace_duration: float = 0.75

@export_group("Combat")
@export_range(1.0, 300.0, 1.0) var attack_range: float = 30.0

@export_group("Returning Home")
@export_range(0.0, 100.0, 1.0) var home_stop_distance: float = 5.0

var behavior: StringName = &"Idle"
var _character: Character2D
var _target: Node2D
var _home_position := Vector2.ZERO
var _lost_target_elapsed := 0.0
var _movement_intent := Vector2.ZERO
var _aim_direction := Vector2.RIGHT
var _attack_requested := false
var _target_refresh_timer := 0.0

func initialize(character: Character2D) -> void:
	_character = character
	_home_position = character.global_position
	_aim_direction = character.context.facing_direction

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
		if distance <= attack_range:
			_movement_intent = Vector2.ZERO
			_set_behavior(&"Attack")
			if not _character.context.is_attacking and not _character.context.is_dashing and not _character.attack_component.is_on_cooldown():
				_attack_requested = true
		else:
			_movement_intent = to_target.normalized()
			_set_behavior(&"Chase")
		return

	var to_home: Vector2 = _home_position - _character.global_position
	if to_home.length() > home_stop_distance:
		_movement_intent = to_home.normalized()
		if to_home.length_squared() > 0.001:
			_aim_direction = to_home.normalized()
		_set_behavior(&"Return")
	else:
		_movement_intent = Vector2.ZERO
		_set_behavior(&"Idle")

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

func _refresh_target(delta: float) -> void:
	_target_refresh_timer -= delta
	if _is_valid_target(_target):
		var distance: float = _character.global_position.distance_to(_target.global_position)
		if distance <= disengage_radius:
			_lost_target_elapsed = 0.0
			return
		_lost_target_elapsed += delta
		if _lost_target_elapsed < lost_target_grace_duration:
			return
		_target = null
		_lost_target_elapsed = 0.0
	if _target_refresh_timer > 0.0:
		return
	# A modest refresh interval avoids scanning every player node every physics frame.
	_target_refresh_timer = 0.2
	_target = _find_nearest_target()

func _find_nearest_target() -> Node2D:
	var nearest: Node2D
	var nearest_distance := detection_radius
	for candidate in get_tree().get_nodes_in_group(target_group):
		if not _is_valid_target(candidate as Node):
			continue
		var node := candidate as Node2D
		var distance: float = _character.global_position.distance_to(node.global_position)
		if distance <= nearest_distance:
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

func _set_behavior(next_behavior: StringName) -> void:
	if behavior == next_behavior:
		return
	var previous := behavior
	behavior = next_behavior
	behavior_changed.emit(previous, behavior)
