extends Node
class_name ReactionComponent2D
## Track P1: hit and death presentation as data on a component, so a character needs no
## presentation script. It listens to its Character2D's `damaged` and `died` signals and
##   - on a hit: plays `hit_clip` on `hit_player` (the clip only animates a flash, so it runs
##     in parallel with idle and run);
##   - on death: stops the hit clip and plays `reset_clip` so a flash never outlives the
##     character, plays `death_clip` on `death_player`, spawns `death_effect_scene` where the
##     character died, and frees the character when `free_on_death` is on.
## Everything is optional. An empty clip name, an unset player or a clip the player does not have
## is skipped without an error, so a character can use only the parts it needs.
##
## What stays outside this component, on purpose: stopping input and physics on death
## (`player.gd` does it, because it owns the input state) and knockback, hit stun and swing
## interruption (`Character2D._apply_hit_reaction`, which is gameplay, not presentation).
##
## Character2D finds this node by the default name "ReactionComponent2D" (or its exported
## `reaction_component`) and calls `initialize()`.

## Hit flash.
@export_group("Hit")
## Plays `hit_clip` for every hit that deals damage and leaves the character alive.
@export var hit_player: AnimationPlayer
@export var hit_clip: StringName = &"take_damage"
## Played on `hit_player` at death, after stopping the hit clip. Empty or missing: the player is only stopped.
@export var reset_clip: StringName = &"RESET"

## Death.
@export_group("Death")
## Plays `death_clip` once at death. Leave `death_player` empty for a character with no death clip.
@export var death_player: AnimationPlayer
@export var death_clip: StringName = &"death"
## Spawned in the effects container at the character's position when it dies (see Effects2D).
@export var death_effect_scene: PackedScene
## Free the character when it dies (the goblin). Leave it off for a character that stays (the player).
@export var free_on_death := false

var _character: Character2D

## Connects to the character's `damaged` and `died` signals. Calling it again, or for another
## character, moves the connections instead of doubling them.
func initialize(character: Character2D) -> void:
	_disconnect_character()
	_character = character
	if not is_instance_valid(_character):
		_character = null
		return
	_character.damaged.connect(_on_character_damaged)
	_character.died.connect(_on_character_died)

func _exit_tree() -> void:
	_disconnect_character()

func _disconnect_character() -> void:
	if is_instance_valid(_character):
		if _character.damaged.is_connected(_on_character_damaged):
			_character.damaged.disconnect(_on_character_damaged)
		if _character.died.is_connected(_on_character_died):
			_character.died.disconnect(_on_character_died)
	_character = null

## Plays the hit clip. Public so a script can trigger the same flash without a hit.
func play_hit() -> void:
	_play(hit_player, hit_clip)

func _on_character_damaged(_hit: HitData) -> void:
	# The killing hit also emits `damaged`; the death clip takes over then.
	if not is_instance_valid(_character) or not _character.is_alive():
		return
	play_hit()

func _on_character_died() -> void:
	if not is_instance_valid(_character):
		return
	if is_instance_valid(hit_player):
		hit_player.stop() # a flash must not outlive the character
		_play(hit_player, reset_clip)
	_play(death_player, death_clip)
	Effects2D.spawn(death_effect_scene, _character, _character.global_position)
	if free_on_death:
		_character.queue_free()

## Plays `clip` on `player` when all three exist. Anything missing is skipped silently. `player` is
## untyped on purpose: a player node freed after the scene loaded (a test, a removed rig) is passed in as
## a freed object, which a typed parameter would reject with a script error instead of skipping it.
func _play(player, clip: StringName) -> void:
	if clip != &"" and is_instance_valid(player) and player.has_animation(clip):
		player.play(clip)
