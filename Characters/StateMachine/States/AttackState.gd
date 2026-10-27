extends CharacterState

func physics_update(_delta: float) -> void:
	var desired: StringName = context.run_clip if context.movement_input.length_squared() > 0.0001 else context.idle_clip
	context.play_locomotion_animation(desired)
	if not context.is_attacking:
		var next_state: StringName = &"Dash" if context.is_dashing else (&"Move" if context.movement_input.length_squared() > 0.0001 else &"Idle")
		state_machine.transition_to(next_state)
