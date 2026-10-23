extends "res://Characters/StateMachine/CharacterState.gd"

func enter() -> void:
	context.play_locomotion_animation(&"run")

func physics_update(_delta: float) -> void:
	if context.is_attacking:
		state_machine.call("transition_to", &"Attack")
	elif context.is_dashing:
		state_machine.call("transition_to", &"Dash")
	elif context.movement_input.length_squared() < 0.0001:
		state_machine.call("transition_to", &"Idle")
	else:
		# Resume "run" after a hit reaction interrupted it (see IdleState).
		context.play_locomotion_animation(&"run")
