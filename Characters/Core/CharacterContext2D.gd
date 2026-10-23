extends RefCounted
## Per-character runtime references and intent shared by states/components.
##
## Two rig layouts are supported. Anything else warns instead of guessing:
##   Player: LayeredRig, PlayerAnim, WeaponFacingPivot/MainHand/HandAnim
##   Goblin: AnimatedSprite2D, AnimatedSprite2D/Weapon/WeaponAnimation

var character: CharacterBody2D
var visual_root: Node2D
var character_animation_player: AnimationPlayer
var animated_sprite: AnimatedSprite2D
var weapon_pivot: Node2D
var weapon_facing_root: Node2D
var weapon_animation_player: AnimationPlayer

var movement_input: Vector2 = Vector2.ZERO
## Horizontal facing chosen by locomotion; preserved while attacking.
var movement_facing_direction: Vector2 = Vector2.RIGHT
## Current visible facing. Temporarily follows attack direction during an attack.
var facing_direction: Vector2 = Vector2.RIGHT
var aim_direction: Vector2 = Vector2.RIGHT
var attack_direction: Vector2 = Vector2.RIGHT
var is_attacking: bool = false
var is_dashing: bool = false
var dash_velocity: Vector2 = Vector2.ZERO

func _init(owner: CharacterBody2D) -> void:
	character = owner
	animated_sprite = owner.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D

	var layered_rig := owner.get_node_or_null("LayeredRig") as Node2D
	if layered_rig != null:
		# Layout A: layered player rig driven by AnimationPlayer clips.
		visual_root = layered_rig
		character_animation_player = owner.get_node_or_null("PlayerAnim") as AnimationPlayer
		weapon_facing_root = owner.get_node_or_null("WeaponFacingPivot") as Node2D
		weapon_pivot = owner.get_node_or_null("WeaponFacingPivot/MainHand") as Node2D
		if weapon_pivot != null:
			weapon_animation_player = weapon_pivot.get_node_or_null("HandAnim") as AnimationPlayer
	else:
		# Layout B: AnimatedSprite2D enemy. The weapon is a child of the sprite, so
		# flipping the sprite mirrors the weapon with it.
		visual_root = animated_sprite
		weapon_pivot = owner.get_node_or_null("AnimatedSprite2D/Weapon") as Node2D
		if weapon_pivot != null:
			weapon_animation_player = weapon_pivot.get_node_or_null("WeaponAnimation") as AnimationPlayer

	if weapon_animation_player == null:
		push_warning("CharacterContext2D: '%s' has no weapon AnimationPlayer (expected WeaponFacingPivot/MainHand/HandAnim or AnimatedSprite2D/Weapon/WeaponAnimation). Attacks are disabled." % owner.name)
		return
	_validate_spawn_slash_tracks()

## The weapon clips call spawn_slash() through a method track. Warn if a track does
## not resolve to the character, instead of silently never spawning a slash.
func _validate_spawn_slash_tracks() -> void:
	var animation_root := weapon_animation_player.get_node_or_null(weapon_animation_player.root_node)
	for animation_name in weapon_animation_player.get_animation_list():
		var animation := weapon_animation_player.get_animation(animation_name)
		for track_index in animation.get_track_count():
			if animation.track_get_type(track_index) != Animation.TYPE_METHOD:
				continue
			var target: Node = null
			if animation_root != null:
				target = animation_root.get_node_or_null(animation.track_get_path(track_index))
			if target != character:
				push_warning("CharacterContext2D: '%s' animation '%s' method track %d does not resolve to the character (path '%s')." % [character.name, animation_name, track_index, animation.track_get_path(track_index)])

## Play idle/run for AnimationPlayer-based characters or fall back to AnimatedSprite2D.
## Never interrupts an authored take_damage/RESET/death sequence that is still playing.
func play_locomotion_animation(animation_name: StringName) -> void:
	if is_instance_valid(character_animation_player):
		var current := character_animation_player.current_animation
		if character_animation_player.is_playing() and (current == &"take_damage" or current == &"RESET" or current == &"death"):
			return
		if character_animation_player.has_animation(animation_name):
			if current != animation_name or not character_animation_player.is_playing():
				character_animation_player.play(animation_name)
			return

	if animated_sprite != null and animated_sprite.sprite_frames != null:
		if animated_sprite.sprite_frames.has_animation(animation_name):
			if animated_sprite.animation != animation_name or not animated_sprite.is_playing():
				animated_sprite.play(animation_name)
