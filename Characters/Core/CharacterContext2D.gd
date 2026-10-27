extends RefCounted
class_name CharacterContext2D
## Per-character runtime references and intent shared by states/components.
##
## Two rig layouts are found by name when nothing else is said. Anything else warns instead of guessing:
##   Player: LayeredRig, PlayerAnim, and a weapon mounted under WeaponFacingPivot
##   Goblin: AnimatedSprite2D, and a weapon at AnimatedSprite2D/Weapon
## A character with another layout names its nodes with the rig paths on Character2D (P2), which arrive here as
## the optional _init arguments. A path that is set wins over the default name; one that does not resolve warns
## and leaves that reference empty (it never falls back to a default name). A rig that has a visual root (set or
## named LayeredRig) gets the player-style defaults for the rest; any other rig gets the goblin-style ones.
##
## The weapon (9.7b) is a scene: a Node2D root holding the sprite and an AnimationPlayer that has the
## weapon's clips (Weapons/Sword/scene.tscn is the shipped one). The context reads the AnimationPlayer from
## whatever weapon is mounted: the node called MainHand (player) or Weapon (goblin) first, then, on the
## player, any other Node2D child of WeaponFacingPivot that carries a weapon AnimationPlayer. Inside the
## weapon, the player is the child called HandAnim or WeaponAnimation, otherwise the first
## AnimationPlayer child (find_weapon_player). bind_weapon() points the context at a weapon that was
## mounted afterwards (equipping, 9.7c).
##
## The clips' attack_event method tracks use the path "../..", resolved from the AnimationPlayer's root
## node (the weapon root), so the weapon root must be a child of a node whose parent is the character:
## WeaponFacingPivot/<weapon> on the player.

## Names find_weapon_player() tries first, in order.
const WEAPON_PLAYER_NAMES: Array[StringName] = [&"HandAnim", &"WeaponAnimation"]

var character: CharacterBody2D
var visual_root: Node2D
var character_animation_player: AnimationPlayer
var animated_sprite: AnimatedSprite2D
## The locomotion clip names the idle, move, dash and attack states play (P3). Character2D copies its exports here.
var idle_clip: StringName = &"idle"
var run_clip: StringName = &"run"
var weapon_pivot: Node2D
var weapon_facing_root: Node2D
var weapon_animation_player: AnimationPlayer
## Optional marker where attack effects spawn (10.5); set by Character2D. Null means the character's origin.
var attack_spawn_point: Marker2D

var movement_input: Vector2 = Vector2.ZERO
## Horizontal facing chosen by locomotion; preserved while attacking.
var movement_facing_direction: Vector2 = Vector2.RIGHT
## Current visible facing. Temporarily follows attack direction during an attack.
var facing_direction: Vector2 = Vector2.RIGHT
var aim_direction: Vector2 = Vector2.RIGHT
var attack_direction: Vector2 = Vector2.RIGHT
var is_attacking: bool = false
var is_dashing: bool = false
## True while a skill with a cast time is being cast (13.2). Attacks and dashes cannot start meanwhile.
var is_casting: bool = false
var dash_velocity: Vector2 = Vector2.ZERO
## Scales normal (non-dash) movement. AttackComponent2D sets it from the active attack
## definition and restores 1.0 when the attack finishes or is cancelled.
var move_multiplier: float = 1.0
## Extra velocity from being hit. Character2D decays it every physics frame and
## MovementComponent2D adds it to normal and dash movement.
var knockback_velocity: Vector2 = Vector2.ZERO
## Forward step from the attack in progress (AttackDefinition2D.forward_impulse, P7); AttackComponent2D owns it.
var impulse_velocity: Vector2 = Vector2.ZERO
## While above zero the character cannot start an attack or a dash.
var hit_stun_remaining: float = 0.0
## True while FacingComponent2D is blending the weapon hand back to its idle pose after a swing. AttackComponent2D
## then skips its instant RESET snap on a cancel, because the blend replaces it. Set only by the facing component.
var hand_settling: bool = false

func _init(owner: CharacterBody2D, visual_root_path: NodePath = NodePath(), locomotion_player_path: NodePath = NodePath(), animated_sprite_path: NodePath = NodePath(), weapon_facing_root_path: NodePath = NodePath(), weapon_pivot_path: NodePath = NodePath()) -> void:
	character = owner
	animated_sprite = _rig_node(owner, animated_sprite_path, "AnimatedSprite2D") as AnimatedSprite2D

	# Layout A (a visual root: the layered player rig, or whatever visual_root_path names) looks for the player's
	# node names; layout B (no visual root) mirrors the AnimatedSprite2D enemy and looks only for its weapon.
	var layered_rig := _rig_node(owner, visual_root_path, "LayeredRig") as Node2D
	var layered := layered_rig != null
	visual_root = layered_rig if layered else animated_sprite
	character_animation_player = _rig_node(owner, locomotion_player_path, "PlayerAnim" if layered else "") as AnimationPlayer
	weapon_facing_root = _rig_node(owner, weapon_facing_root_path, "WeaponFacingPivot" if layered else "") as Node2D
	# The goblin's weapon is a child of the sprite, so flipping the sprite mirrors the weapon with it.
	weapon_pivot = _rig_node(owner, weapon_pivot_path, "WeaponFacingPivot/MainHand" if layered else "AnimatedSprite2D/Weapon") as Node2D
	if weapon_pivot == null and layered and weapon_pivot_path.is_empty() and weapon_facing_root != null:
		weapon_pivot = _find_mounted_weapon(weapon_facing_root)
	if weapon_pivot != null:
		weapon_animation_player = find_weapon_player(weapon_pivot)

	if weapon_animation_player == null:
		push_warning("CharacterContext2D: '%s' has no weapon AnimationPlayer (expected a weapon scene with an AnimationPlayer under WeaponFacingPivot, or at AnimatedSprite2D/Weapon). Attacks are disabled." % owner.name)
		return
	_validate_attack_event_tracks()

## A rig node: the one at `path` when it is set (a warning when it does not resolve), otherwise the child at
## `default_name`. An empty default name means there is no default, so an unset path gives null.
func _rig_node(owner: Node, path: NodePath, default_name: String) -> Node:
	if path.is_empty():
		return owner.get_node_or_null(default_name) if default_name != "" else null
	var found := owner.get_node_or_null(path)
	if found == null:
		push_warning("CharacterContext2D: '%s' rig path '%s' does not resolve to a node." % [owner.name, path])
	return found

## Where an attack effect appears: the spawn marker when there is a live one in the tree, otherwise the
## character's origin.
func get_attack_origin() -> Vector2:
	if is_instance_valid(attack_spawn_point) and attack_spawn_point.is_inside_tree():
		return attack_spawn_point.global_position
	return character.global_position

## The AnimationPlayer that holds a weapon's clips: the child called HandAnim or WeaponAnimation, otherwise
## the first AnimationPlayer child of `weapon_root`. Null when there is none (or no weapon).
static func find_weapon_player(weapon_root: Node) -> AnimationPlayer:
	if weapon_root == null:
		return null
	for player_name in WEAPON_PLAYER_NAMES:
		var named := weapon_root.get_node_or_null(NodePath(player_name)) as AnimationPlayer
		if named != null:
			return named
	for child in weapon_root.get_children():
		if child is AnimationPlayer:
			return child
	return null

## Points the context at a weapon that is already mounted in the character's tree (as a descendant, so the
## attack_event paths can resolve). Returns false, with a warning and the old weapon kept, when the weapon
## has no AnimationPlayer. Rebinding does not reconnect AttackComponent2D's animation_finished signal:
## that is part of equipping (9.7c).
func bind_weapon(weapon_root: Node2D) -> bool:
	var player := find_weapon_player(weapon_root)
	if player == null:
		var weapon_name := str(weapon_root.name) if weapon_root != null else "<null>"
		push_warning("CharacterContext2D: weapon '%s' has no AnimationPlayer; keeping the current weapon." % weapon_name)
		return false
	weapon_pivot = weapon_root
	weapon_animation_player = player
	_validate_attack_event_tracks()
	return true

## A weapon scene mounted under `mount` with a name other than MainHand: the first Node2D child that
## carries a weapon AnimationPlayer.
func _find_mounted_weapon(mount: Node) -> Node2D:
	for child in mount.get_children():
		if child is Node2D and find_weapon_player(child) != null:
			return child as Node2D
	return null

## The weapon clips fire attack_event(<name>) through method tracks. Warn if a track does
## not resolve to the character, calls a method the character lacks, or passes an
## unknown event name, instead of silently never spawning an effect.
func _validate_attack_event_tracks() -> void:
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
				continue
			for key_index in animation.track_get_key_count(track_index):
				var method := animation.method_track_get_name(track_index, key_index)
				var params := animation.method_track_get_params(track_index, key_index)
				if not character.has_method(method):
					push_warning("CharacterContext2D: '%s' animation '%s' track %d key %d calls '%s', which the character does not have." % [character.name, animation_name, track_index, key_index, method])
				elif method == &"attack_event":
					var valid_arg: bool = params.size() == 1 and (typeof(params[0]) == TYPE_STRING_NAME or typeof(params[0]) == TYPE_STRING)
					if not valid_arg:
						push_warning("CharacterContext2D: '%s' animation '%s' track %d key %d: attack_event needs exactly one event-name argument." % [character.name, animation_name, track_index, key_index])
					elif not AttackComponent2D.is_known_event(StringName(params[0])):
						push_warning("CharacterContext2D: '%s' animation '%s' track %d key %d fires unknown attack event '%s'." % [character.name, animation_name, track_index, key_index, params[0]])

## Play idle/run for AnimationPlayer-based characters or fall back to AnimatedSprite2D.
## Never interrupts the authored death sequence while it is playing. (Hit flashes live on a
## separate reaction AnimationPlayer, so they never compete with idle/run.)
func play_locomotion_animation(animation_name: StringName) -> void:
	if is_instance_valid(character_animation_player):
		var current := character_animation_player.current_animation
		if character_animation_player.is_playing() and current == &"death":
			return
		if character_animation_player.has_animation(animation_name):
			if current != animation_name or not character_animation_player.is_playing():
				character_animation_player.play(animation_name)
			return

	if animated_sprite != null and animated_sprite.sprite_frames != null:
		if animated_sprite.sprite_frames.has_animation(animation_name):
			if animated_sprite.animation != animation_name or not animated_sprite.is_playing():
				animated_sprite.play(animation_name)
