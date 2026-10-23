extends Node
class_name CharacterState
## Base contract for state nodes; states request presentation, not movement.
## Place one node per state (named Idle, Move, Dash, Attack, ...) under the
## CharacterStateMachine node. The node name is the state name.

var context: CharacterContext2D
var state_machine: CharacterStateMachine

func setup(machine: CharacterStateMachine, shared_context: CharacterContext2D) -> void:
	state_machine = machine
	context = shared_context

func enter() -> void:
	pass

func physics_update(_delta: float) -> void:
	pass

func exit() -> void:
	pass
