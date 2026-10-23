extends Character2D
## Player controller: input, aim, and hit/death presentation. Health lives in the
## HealthComponent2D child (see Character2D). Groups ("player", "damageable") are set on
## the scene root in player.tscn.

## Locomotion and death clips (idle, run, death).
@onready var _rig_animation_player: AnimationPlayer = get_node_or_null("PlayerAnim") as AnimationPlayer
## Hit flash only (animates the shared flash material), so it plays in parallel with idle/run.
@onready var _reaction_animation_player: AnimationPlayer = get_node_or_null("ReactionAnim") as AnimationPlayer

func _get_movement_input() -> Vector2:
	if not is_alive():
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

func _get_dash_requested() -> bool:
	return is_alive() and Input.is_action_just_pressed("dash")

func _get_aim_direction() -> Vector2:
	if not is_alive():
		return context.facing_direction
	var direction := get_global_mouse_position() - global_position
	return direction.normalized() if direction.length_squared() > 0.0001 else context.facing_direction

func _get_attack_requested() -> bool:
	return is_alive() and Input.is_action_just_pressed("attack")

func _on_damaged(_hit: HitData) -> void:
	if not is_alive():
		return # the death clip takes over
	if is_instance_valid(_reaction_animation_player) and _reaction_animation_player.has_animation(&"take_damage"):
		_reaction_animation_player.play(&"take_damage")

func _on_death() -> void:
	if is_instance_valid(_reaction_animation_player):
		_reaction_animation_player.stop() # a flash must not outlive the character
		if _reaction_animation_player.has_animation(&"RESET"):
			_reaction_animation_player.play(&"RESET")
	if is_instance_valid(_rig_animation_player) and _rig_animation_player.has_animation(&"death"):
		_rig_animation_player.play(&"death")
	# Always stop input/movement, even if the death clip or its player is missing.
	set_physics_process(false)
