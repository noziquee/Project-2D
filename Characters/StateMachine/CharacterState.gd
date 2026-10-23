extends RefCounted
## Base contract for state objects; states request presentation, not movement.

const CharacterContext2D = preload("res://Characters/Core/CharacterContext2D.gd")

var context: CharacterContext2D
var state_machine: Node

func setup(machine: Node, shared_context: CharacterContext2D) -> void:
	state_machine = machine
	context = shared_context

func enter() -> void:
	pass

func physics_update(_delta: float) -> void:
	pass

func exit() -> void:
	pass
