extends CharacterState
## Visual state while the dash component temporarily overrides normal movement.

func enter() -> void:
	context.play_locomotion_animation(context.run_clip)

func physics_update(_delta: float) -> void:
	if context.is_dashing:
		context.play_locomotion_animation(context.run_clip)
	else:
		var next_state: StringName = &"Move" if context.movement_input.length_squared() > 0.0001 else &"Idle"
		state_machine.transition_to(next_state)
