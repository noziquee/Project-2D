extends Node
class_name CharacterStateMachine
## Small state coordinator. Its CharacterState child nodes are registered by node name in
## _ready(); initialize() (called by Character2D) hands them the shared context and enters
## initial_state. Transition callbacks are guarded against unknown states.

signal state_changed(previous_state: StringName, current_state: StringName)

## State entered by initialize().
@export var initial_state: StringName = &"Idle"

var current_state_name: StringName = &""
var _states: Dictionary = {}
var _current_state: CharacterState
var _context: CharacterContext2D

func _ready() -> void:
	# Children are ready before their parent, so this runs before Character2D._ready().
	# Only collect here; the context does not exist yet.
	for child in get_children():
		if child is CharacterState:
			register_state(child.name, child as CharacterState)

func initialize(shared_context: CharacterContext2D) -> void:
	_context = shared_context
	for state in _states.values():
		(state as CharacterState).setup(self, _context)
	if not transition_to(initial_state):
		push_error("CharacterStateMachine: initial_state '%s' is not a child state node." % initial_state)

func register_state(state_name: StringName, state: CharacterState) -> void:
	if _states.has(state_name):
		push_warning("CharacterStateMachine: duplicate state '%s'." % state_name)
		return
	_states[state_name] = state
	if _context != null:
		state.setup(self, _context) # registered after initialize()

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
