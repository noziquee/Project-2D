extends CharacterState

func enter() -> void:
	context.play_locomotion_animation(context.idle_clip)

func physics_update(_delta: float) -> void:
	if context.is_attacking:
		state_machine.transition_to(&"Attack")
	elif context.is_dashing:
		state_machine.transition_to(&"Dash")
	elif context.movement_input.length_squared() > 0.0001:
		state_machine.transition_to(&"Move")
	else:
		# Re-assert the clip in case something else replaced it (e.g. the death clip or a swapped animation),
		# and enter() will not run again while the state stays Idle.
		context.play_locomotion_animation(context.idle_clip)
