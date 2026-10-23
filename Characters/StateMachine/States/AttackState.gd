extends "res://Characters/StateMachine/CharacterState.gd"

func physics_update(_delta: float) -> void:
	var desired: StringName = &"run" if context.movement_input.length_squared() > 0.0001 else &"idle"
	context.play_locomotion_animation(desired)
	if not context.is_attacking:
		var next_state: StringName = &"Dash" if context.is_dashing else (&"Move" if context.movement_input.length_squared() > 0.0001 else &"Idle")
		state_machine.call("transition_to", next_state)
