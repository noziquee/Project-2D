extends Node
## Small state coordinator. Transition callbacks are guarded against unknown states.

const CharacterState = preload("res://Characters/StateMachine/CharacterState.gd")
const CharacterContext2D = preload("res://Characters/Core/CharacterContext2D.gd")

signal state_changed(previous_state: StringName, current_state: StringName)

var current_state_name: StringName = &""
var _states: Dictionary = {}
var _current_state: CharacterState
var _context: CharacterContext2D

func initialize(shared_context: CharacterContext2D) -> void:
	_context = shared_context

func register_state(state_name: StringName, state: CharacterState) -> void:
	if _states.has(state_name):
		push_warning("CharacterStateMachine: duplicate state '%s'." % state_name)
		return
	state.setup(self, _context)
	_states[state_name] = state

func transition_to(state_name: StringName) -> bool:
	if not _states.has(state_name):
		push_warning("CharacterStateMachine: unknown state '%s'." % state_name)
		return false
	if current_state_name == state_name:
		return true
	var previous := current_state_name
	if _current_state != null:
		_current_state.exit()
	current_state_name = state_name
	_current_state = _states[state_name] as CharacterState
	_current_state.enter()
	state_changed.emit(previous, current_state_name)
	return true

func physics_update(delta: float) -> void:
	if _current_state != null:
		_current_state.physics_update(delta)

func has_state(state_name: StringName) -> bool:
	return _states.has(state_name)
