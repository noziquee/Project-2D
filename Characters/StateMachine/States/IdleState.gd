extends "res://Characters/StateMachine/CharacterState.gd"

func enter() -> void:
	context.play_locomotion_animation(&"idle")

func physics_update(_delta: float) -> void:
	if context.is_attacking:
		state_machine.call("transition_to", &"Attack")
	elif context.is_dashing:
		state_machine.call("transition_to", &"Dash")
	elif context.movement_input.length_squared() > 0.0001:
		state_machine.call("transition_to", &"Move")
	else:
		# Re-assert the clip: a hit reaction (take_damage -> RESET) may have replaced it,
		# and enter() will not run again while the state stays Idle.
		context.play_locomotion_animation(&"idle")
