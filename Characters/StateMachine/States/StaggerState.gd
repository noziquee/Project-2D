extends CharacterState
## Optional flinch (P6). A character that has a child state named Stagger enters it when a hit applies hit stun, and
## stays in it until the stun is over; a character without one is unchanged (the stun still blocks attacks and dashes,
## it just shows nothing). Add the node under the CharacterStateMachine only to characters that should flinch.

## The clip played while staggered, on the locomotion player (or the sprite's frames). Empty keeps the current clip.
@export var clip: StringName = &""

func enter() -> void:
	_play_clip()

func physics_update(_delta: float) -> void:
	if context.hit_stun_remaining > 0.0:
		# Re-assert the clip, as the idle state does, in case something else replaced it.
		_play_clip()
		return
	state_machine.transition_to(&"Idle")

func _play_clip() -> void:
	if clip != &"":
		context.play_locomotion_animation(clip)
