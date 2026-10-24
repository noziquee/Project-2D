extends SceneTree

var failures := 0
var passes := 0

## Loaded by path (not by class name) so the section II checks do not depend on the global class cache.
const WEAPON_SCRIPT := preload("res://Characters/Components/Weapons/WeaponDefinition2D.gd")
const SWORD_WEAPON_PATH := "res://Data/Weapons/SwordWeaponDefinition.tres"
const WEAPON_CONTROLLER_SCRIPT := preload("res://Characters/Components/Weapons/WeaponController2D.gd")

## A controller whose attack step always fails, to reach the rollback that follows a mount swap (9.7c-3).
class FailingApplyController extends "res://Characters/Components/Weapons/WeaponController2D.gd":
	func _set_attacks_from(_weapon: WeaponDefinition2D) -> bool:
		return false

func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
	else:
		failures += 1
	print(("CHECK PASS  " if cond else "CHECK FAIL  ") + msg)

func phys(n: int) -> void:
	for i in n:
		await physics_frame

## A new Main instance for a test. Main.tscn is the playable arena with nine goblins; the checks are written
## for one ("BasicEnemy2D"), and the other eight (spread around the arena, inside the 200 px detection range
## of some) would chase and hit the player at random times. They are freed here, before the scene enters the
## tree, so every check sees the same single-goblin arena (V2b).
func load_main() -> Node:
	var main: Node = load("res://Main.tscn").instantiate()
	for child in main.get_children():
		if child is BasicEnemy2D and child.name != &"BasicEnemy2D":
			child.free()
	return main

func fresh() -> Node:
	var main: Node = load_main()
	root.add_child(main)
	quiet_goblin_choices(main)
	await phys(3)
	return main

## Like fresh(), but with the shipped goblin profile (slash and lunge choices), for checks of the choice logic.
func fresh_shipped() -> Node:
	var main: Node = load_main()
	root.add_child(main)
	await phys(3)
	return main

## Like fresh(), but the goblin starts 400 px away, outside its detection area.
func fresh_far() -> Node:
	var main: Node = load_main()
	(main.get_node("BasicEnemy2D") as Node2D).position = Vector2(400, 0)
	root.add_child(main)
	quiet_goblin_choices(main)
	await phys(3)
	return main

## Gives `enemy` a private copy of its detection circle with the given radius. Tests that
## rely on the goblin noticing the player at a set distance use this, so they keep passing
## when the drawn circle in BasicEnemy2D.tscn is retuned. The shared scene shape is untouched.
func set_detection_radius(enemy: Node, radius: float) -> void:
	var shape_node := enemy.get_node("DetectionArea/CollisionShape2D") as CollisionShape2D
	var circle := (shape_node.shape as CircleShape2D).duplicate() as CircleShape2D
	circle.radius = radius
	shape_node.shape = circle

## Sets a player's max and current health together. Used by checks that need a small health
## pool (the shipped player has more hp so it is not easily killed). Sets max first so the
## current value is not clamped to the old maximum.
func set_player_health(player: Node, hp: int) -> void:
	player.health_component.max_health = hp
	player.health_component.health = hp

## Gives the goblin a private copy of its profile with no weighted choices, so checks written before
## the goblin had a second attack keep testing its default attack. The shipped profile is untouched.
func quiet_goblin_choices(main: Node) -> void:
	var goblin := main.get_node_or_null("BasicEnemy2D")
	if goblin == null:
		return
	# Found by node name, not through goblin._ai_controller: that is an @onready variable and is still
	# null when this runs before the goblin's own _ready() (the very first fresh() call, made from _initialize()).
	var ai := goblin.get_node_or_null("EnemyAIController2D") as EnemyAIController2D
	if ai == null or ai.profile == null:
		return
	ai.profile = ai.profile.duplicate()
	var none: Array[AttackChoice2D] = []
	ai.profile.attack_choices = none

func cleanup(main: Node) -> void:
	main.queue_free()
	await phys(2)

## Time of the combo_window_close key in a clip, or -1 when it has none.
func window_close_time(anim: Animation) -> float:
	for track in anim.get_track_count():
		if anim.track_get_type(track) != Animation.TYPE_METHOD:
			continue
		for key in anim.track_get_key_count(track):
			if anim.method_track_get_params(track, key)[0] == &"combo_window_close":
				return anim.track_get_key_time(track, key)
	return -1.0

## Weapon swing length in seconds (the default attack's weapon clip + its recovery clip, scaled by the player's speed).
func weapon_cycle_seconds(ch: Character2D) -> float:
	var ap: AnimationPlayer = ch.context.weapon_animation_player
	var swing_def: AttackDefinition2D = ch.attack_component.definition
	var slash_len: float = ap.get_animation(swing_def.weapon_animation).length
	# A combo window that closes with no press ends the slash at its close key (9.6b).
	var close_at := window_close_time(ap.get_animation(swing_def.weapon_animation))
	if close_at >= 0.0:
		slash_len = minf(slash_len, close_at)
	var total: float = slash_len + ap.get_animation(swing_def.recovery_animation).length
	return total / maxf(absf(ap.speed_scale), 0.001)

## Swing once, then request another attack every physics frame. Reports, in physics
## frames, when the first swing started, when it finished, and when the next one began.
func measure_attack_rate(ch: Character2D) -> Dictionary:
	var comp: AttackComponent2D = ch.attack_component
	var started: bool = comp.try_start(true, Vector2.RIGHT)
	var f_start: int = Engine.get_physics_frames()
	var f_finish := -1
	var cooldown_at_finish := false
	var f_second := -1
	for i in 600:
		await physics_frame
		var now: int = Engine.get_physics_frames()
		if f_finish < 0 and not ch.context.is_attacking:
			f_finish = now
			cooldown_at_finish = comp.is_on_cooldown()
		# Requests inside a combo window would chain (that is the combo, not the attack rate), so skip them.
		if not comp.is_combo_window_open() and comp.try_start(true, Vector2.RIGHT):
			f_second = now
			break
	return {
		"started": started,
		"cooldown_at_finish": cooldown_at_finish,
		"swing_frames": f_finish - f_start,
		"gap_frames": f_second - f_finish,
		"period_frames": f_second - f_start,
	}

## Runs the attack-rate checks for one character with its shipped cooldown and again
## with an overridden cooldown, so a regression to "cooldown hidden by the animation"
## (finding A) fails here.
func check_attack_rate(label: String, ch: Character2D) -> void:
	var cycle: float = weapon_cycle_seconds(ch)
	var shipped_cd: float = ch.attack_definition.cooldown_duration
	var fps := float(Engine.physics_ticks_per_second)
	# The gap and delta checks are one-frame precise. The swing itself runs a little longer
	# than slash.length + sword_return.length: each clip only reports "finished" on the first
	# frame at or past its length, and sword_return starts a frame after slash ends.
	var tol := 1.5 # frames: quantisation of the cooldown countdown vs. the test's sampling
	var handoff := 3.0 # frames: allowance for the two clip-end/hand-off latencies above

	var a: Dictionary = await measure_attack_rate(ch)
	var cycle_frames: float = cycle * fps
	check(a.started, "%s1 first swing starts" % label)
	check(a.cooldown_at_finish, "%s2 cooldown is active the moment the swing ends" % label)
	check(a.swing_frames >= cycle_frames - 0.5 and a.swing_frames <= cycle_frames + handoff, "%s3 swing lasts one animation cycle (%d frames, expected %.1f..%.1f)" % [label, a.swing_frames, cycle_frames, cycle_frames + handoff])
	check(absf(a.gap_frames - shipped_cd * fps) <= tol, "%s4 gap after the swing equals cooldown_duration (%d frames, expected %.1f)" % [label, a.gap_frames, shipped_cd * fps])
	var period_min: float = cycle_frames + shipped_cd * fps - 0.5
	check(a.period_frames >= period_min and a.period_frames <= period_min + 0.5 + handoff + tol, "%s5 swing-to-swing period = cycle + cooldown (%d frames, expected %.1f..%.1f)" % [label, a.period_frames, period_min + 0.5, period_min + 0.5 + handoff + tol])

	# Let the shipped cooldown run out, then raise it and measure again.
	await phys(60)
	var longer: AttackDefinition2D = ch.attack_definition.duplicate()
	longer.cooldown_duration = 0.5
	ch.attack_definition = longer
	await phys(80) # let any previous swing + cooldown finish
	var b: Dictionary = await measure_attack_rate(ch)
	check(absf(b.gap_frames - 0.5 * fps) <= tol, "%s6 raising cooldown_duration to 0.5 widens the gap (%d frames, expected %.1f; first swing started=%s and lasted %d frames, definition cooldown %.2f s)" % [label, b.gap_frames, 0.5 * fps, str(b.started), b.swing_frames, ch.attack_component.definition.cooldown_duration])
	check(absf((b.period_frames - a.period_frames) - (0.5 - shipped_cd) * fps) <= tol, "%s7 attack rate changes by exactly the cooldown delta (%d frames)" % [label, b.period_frames - a.period_frames])

## Children of the effects container (slashes, impact and death effects), or of `main`
## itself when it has no Effects node.
func effect_children(main: Node) -> Array:
	var host: Node = main.get_node_or_null("Effects")
	return (host if host != null else main).get_children()

## Live effects in the container that were instantiated from `scene_path`.
func effects_from(main: Node, scene_path: String) -> Array:
	return effect_children(main).filter(func(n): return n.scene_file_path == scene_path and not n.is_queued_for_deletion())

func count_slashes(main: Node, meta_name: StringName = &"") -> int:
	var n := 0
	for c in effect_children(main):
		if c is AttackSlash2D and (meta_name == &"" or c.has_meta(meta_name)):
			n += 1
	return n

## Adds copies of existing weapon clips under new names (default library) and returns the
## library. It is a scene sub-resource shared between instances, so always pair this with
## remove_clips() AFTER the character is freed: removing a clip an AnimationPlayer still
## references (even as its last-played clip) crashes the engine on stop().
func add_clip_aliases(ap: AnimationPlayer, aliases: Dictionary) -> AnimationLibrary:
	var lib: AnimationLibrary = ap.get_animation_library(&"")
	for new_name in aliases:
		lib.add_animation(new_name, lib.get_animation(aliases[new_name]).duplicate())
	return lib

func remove_clips(lib: AnimationLibrary, names: Array) -> void:
	for n in names:
		if lib.has_animation(n):
			lib.remove_animation(n)

func definition_variant(source: AttackDefinition2D, attack_id: StringName) -> AttackDefinition2D:
	var d: AttackDefinition2D = source.duplicate()
	d.id = attack_id
	# A variant starts with no combo links, so shipped links (player_light -> player_light2) never leak into a test.
	d.next_attack = null
	d.combo_sequence = []
	return d

## A WeaponDefinition2D built in code (the script is loaded by path). `combo` may contain nulls on purpose.
func make_weapon(weapon_id: StringName, combo: Array, heavy: AttackDefinition2D = null) -> Resource:
	var w: Resource = WEAPON_SCRIPT.new()
	w.weapon_id = weapon_id
	w.display_name = String(weapon_id).capitalize()
	var typed: Array[AttackDefinition2D] = []
	for entry in combo:
		typed.append(entry)
	w.basic_combo = typed
	w.heavy_attack = heavy
	return w

## Element-by-element comparison, so a typed Array[StringName] can be compared with a plain literal.
func ids_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true

## True when any message in `problems` contains `needle`.
func has_problem(problems: Array, needle: String) -> bool:
	for message in problems:
		if str(message).contains(needle):
			return true
	return false

func attack_choice(attack: AttackDefinition2D, weight: float = 1.0) -> AttackChoice2D:
	var c := AttackChoice2D.new()
	c.attack = attack
	c.weight = weight
	return c

## Inserts an attack_event(<event>) key into the first method track of `anim`.
func add_event_key(anim: Animation, time: float, event: StringName) -> void:
	for t in anim.get_track_count():
		if anim.track_get_type(t) == Animation.TYPE_METHOD:
			anim.track_insert_key(t, time, {"method": &"attack_event", "args": [event]})
			return

## Event names fired by the method tracks of one clip, in key order per track.
func clip_events(anim: Animation) -> Array:
	var out: Array = []
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_METHOD:
			continue
		for k in anim.track_get_key_count(t):
			out.append([anim.method_track_get_name(t, k), anim.method_track_get_params(t, k)])
	return out

## Node paths (relative to the root) stored in a scene file, i.e. what the Scene dock shows,
## not what _ready() creates at runtime.
func scene_node_paths(path: String) -> Array:
	var state := (load(path) as PackedScene).get_state()
	var out: Array = []
	for i in state.get_node_count():
		var node_path := str(state.get_node_path(i))
		out.append(node_path.substr(2) if node_path.begins_with("./") else node_path)
	return out

## Like fresh_far(), but `prepare` (a Callable taking the Main instance) runs before Main enters the tree, so a test
## can add or assign a spawn marker that Character2D._ready() will resolve (10.5).
func fresh_far_prepared(prepare: Callable) -> Node:
	var main: Node = load_main()
	(main.get_node("BasicEnemy2D") as Node2D).position = Vector2(400, 0)
	prepare.call(main)
	root.add_child(main)
	quiet_goblin_choices(main)
	await phys(3)
	return main

## Adds `marker` as a child of `character` and points the character's exported attack_spawn_point at it (10.5).
func mount_exported_marker(character: Character2D, marker: Marker2D) -> void:
	character.add_child(marker)
	character.attack_spawn_point = marker

## Live AttackSlash2D effects in the effects container.
func live_slashes(main: Node) -> Array:
	return effect_children(main).filter(func(n): return n is AttackSlash2D and not n.is_queued_for_deletion())

## A ProjectileEffect2D fired by `shooter` from `origin` along `dir` (11.1). It is added to the Effects container
## and positioned after it is in the tree, the way AttackComponent2D spawns effects. `opts` may hold speed,
## lifetime, damage, size, layers, max_targets and pierce.
func fire_projectile(main: Node, shooter: Node2D, origin: Vector2, dir: Vector2, opts: Dictionary = {}) -> ProjectileEffect2D:
	var arrow := (load("res://Characters/Components/Combat/ProjectileEffect2D.tscn") as PackedScene).instantiate() as ProjectileEffect2D
	arrow.speed = opts.get("speed", 300.0)
	arrow.lifetime = opts.get("lifetime", 1.5)
	arrow.configure(shooter, opts.get("damage", 3), dir, opts.get("size", Vector2(12, 12)), Vector2.ZERO, opts.get("layers", -1), 0.0, 0.0, &"", opts.get("max_targets", 0), opts.get("pierce", true))
	main.get_node("Effects").add_child(arrow)
	arrow.global_position = origin
	return arrow

## A goblin parked far from the arena with its AI off, to be hit by a projectile (11.1).
func parked_goblin(main: Node, at: Vector2) -> Character2D:
	var goblin := (load("res://Characters/Enemies/BasicEnemy2D.tscn") as PackedScene).instantiate() as Character2D
	main.add_child(goblin)
	goblin.global_position = at
	goblin.set_physics_process(false)
	return goblin

## True while `node` still exists and is not about to be freed.
func is_alive_node(node) -> bool:
	# Untyped on purpose: a typed Object parameter would reject an instance that was already freed.
	return is_instance_valid(node) and not (node as Node).is_queued_for_deletion()

const ARROW_LIGHT_PATH := "res://Characters/Components/Combat/ArrowAttackDefinition.tres"
const ARROW_HEAVY_PATH := "res://Characters/Components/Combat/ArrowHeavyAttackDefinition.tres"
const ARROW_SCENE_PATH := "res://Characters/Components/Combat/Arrow.tscn"
const BOW_WEAPON_PATH := "res://Data/Weapons/BowWeaponDefinition.tres"
const BOW_SCENE_PATH := "res://Weapons/Bow.tscn"

## An arrow scene configured the way AttackComponent2D configures it from `def` (11.2), added to the Effects
## container and positioned after it is in the tree.
func fire_arrow(main: Node, shooter: Node2D, origin: Vector2, def: AttackDefinition2D, dir: Vector2 = Vector2.RIGHT) -> ProjectileEffect2D:
	var arrow := (def.effect_scene as PackedScene).instantiate() as ProjectileEffect2D
	arrow.configure(shooter, def.damage, dir, def.hitbox_size, def.hitbox_offset, def.hit_layers, def.knockback, def.hit_stun, def.effect_animation, def.max_targets, def.pierce, def.projectile_speed)
	main.get_node("Effects").add_child(arrow)
	arrow.global_position = origin
	return arrow

## A goblin and its health, as a pair of numbers, to compare before and after a shot.
func hp_of(character: Character2D) -> int:
	return character.health_component.health

func _initialize() -> void:
	await _run()
	print("SUMMARY passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)

func _run() -> void:
	# ---------- A. structure ----------
	var main := await fresh()
	var p = main.get_node("Player")
	var e = main.get_node("BasicEnemy2D")
	check(p.has_node("WeaponFacingPivot/MainHand/weapon"), "A1 player weapon sprite is under WeaponFacingPivot/MainHand")
	check(p.has_node("WeaponFacingPivot/MainHand/HandAnim"), "A2 player HandAnim is under WeaponFacingPivot/MainHand")
	var stray := p.get_children().filter(func(n): return str(n.name).contains("#"))
	check(stray.is_empty(), "A3 no orphaned re-parented nodes on the player root (found %d)" % stray.size())
	check(p.context.weapon_animation_player != null and p.context.weapon_animation_player.has_animation(p.attack_definition.weapon_animation), "A4 player weapon player has its default attack's weapon clip")
	check(e.context.weapon_animation_player != null and e.context.weapon_animation_player.has_animation(&"slash"), "A5 enemy weapon player has 'slash'")
	check(p.is_in_group("player") and p.is_in_group("damageable"), "A6 player groups")
	check(e.is_in_group("enemy") and e.is_in_group("damageable"), "A7 enemy groups")
	check(main.has_node("HUD/PlayerHealthBar"), "A8 player HUD present")

	# ---------- B. player attack ----------
	e.set_physics_process(false)
	e.global_position = p.global_position + Vector2(28, 0)
	var start_pos: Vector2 = p.global_position
	var started: bool = p.attack_component.try_start(true, Vector2.RIGHT)
	check(started, "B1 attack_component.try_start succeeds")
	await phys(30)
	var slash_count := 0
	for c in effect_children(main):
		if c is AttackSlash2D:
			slash_count += 1
	check(slash_count >= 1 or e.health_component.health < e.health_component.max_health, "B2 a slash was spawned by the animation event")
	await phys(40)
	check(e.health_component.health == e.health_component.max_health - p.attack_definition.damage, "B3 enemy took exactly one swing's damage (%d; health=%d)" % [p.attack_definition.damage, e.health_component.health])
	check(p.global_position.is_equal_approx(start_pos), "B4 swing animation did not move the player body (pos=%s)" % str(p.global_position))
	await phys(60)
	check(not p.context.is_attacking, "B5 attack lifecycle finished")
	await cleanup(main)

	# ---------- C. hit reaction resumes locomotion ----------
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	var anim: AnimationPlayer = p.get_node("PlayerAnim")
	var react: AnimationPlayer = p.get_node("ReactionAnim")
	await phys(5)
	check(anim.current_animation == "idle", "C1 idle plays at start (got '%s')" % anim.current_animation)
	p.take_damage(1)
	await phys(5)
	check(react.current_animation == "take_damage" and react.is_playing(), "C2 the hit flash plays on ReactionAnim (got '%s')" % react.current_animation)
	check(anim.current_animation == "idle" and anim.is_playing(), "C2b idle keeps playing underneath the flash (got '%s')" % anim.current_animation)
	await phys(40)
	check(not react.is_playing() and anim.current_animation == "idle" and anim.is_playing(), "C3 flash ends and idle is still playing (got '%s', playing=%s)" % [anim.current_animation, str(anim.is_playing())])
	Input.action_press("move_right")
	await phys(8)
	check(anim.current_animation == "run", "C4 run plays while moving (got '%s')" % anim.current_animation)
	p.take_damage(1)
	await phys(5)
	check(anim.current_animation == "run" and anim.is_playing() and react.is_playing(), "C5 run is not interrupted by a hit while moving (got '%s')" % anim.current_animation)
	await phys(40)
	check(anim.current_animation == "run" and anim.is_playing(), "C5b run still playing after the flash (got '%s')" % anim.current_animation)
	Input.action_release("move_right")
	await cleanup(main)

	# ---------- D. facing flip ----------
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	Input.action_press("move_left")
	await phys(6)
	check(p.context.visual_root.scale.x < 0.0 and p.context.weapon_facing_root.scale.x < 0.0, "D1 moving left mirrors body and weapon")
	Input.action_release("move_left")
	Input.action_press("move_right")
	await phys(6)
	check(p.context.visual_root.scale.x > 0.0 and p.context.weapon_facing_root.scale.x > 0.0, "D2 moving right restores facing")
	Input.action_release("move_right")
	await cleanup(main)

	# ---------- E. dash ----------
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	var x0: float = p.global_position.x
	var did: bool = p.dash_component.try_start(true, Vector2.RIGHT)
	await phys(3)
	check(did and p.context.is_dashing, "E1 dash starts")
	await phys(20)
	check(not p.context.is_dashing and p.global_position.x - x0 > 40.0, "E2 dash ends and moved (dx=%.1f)" % (p.global_position.x - x0))
	await cleanup(main)

	# ---------- F. enemy AI chases, attacks, player dies ----------
	main = await fresh()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	set_detection_radius(e, 180.0)
	e.global_position = p.global_position + Vector2(150, 0)
	# The shipped player has more hp than F can wear down in 20 s, so F uses a 5 hp player.
	set_player_health(p, 5)
	var d0: float = e.global_position.distance_to(p.global_position)
	await phys(30)
	var d1: float = e.global_position.distance_to(p.global_position)
	check(d1 < d0 - 5.0, "F1 enemy chases (%.1f -> %.1f)" % [d0, d1])
	await phys(60 * 3)
	check(p.health_component.health < p.health_component.max_health, "F2 enemy damages the player (health=%d/%d)" % [p.health_component.health, p.health_component.max_health])
	var hp_seen: Array[int] = []
	await phys(60 * 20)
	check(p.health_component.health <= 0 and not p.is_alive(), "F3 repeated hits kill the player (health=%d)" % p.health_component.health)
	check(not p.is_physics_processing(), "F4 dead player stops processing input/physics")
	check(p.get_node("PlayerAnim").current_animation == "death" or not p.get_node("PlayerAnim").is_playing(), "F5 death clip played")
	await cleanup(main)

	# ---------- G. dead player stays stopped even without PlayerAnim ----------
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	p.get_node("PlayerAnim").free()
	p.take_damage(999)
	await phys(2)
	check(not p.is_physics_processing(), "G1 physics disabled on death even if the AnimationPlayer is missing")
	await cleanup(main)

	# ---------- H. attack timing: cooldown starts when the swing ends ----------
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	await check_attack_rate("H-player ", p)
	await cleanup(main)

	main = await fresh()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.global_position = p.global_position + Vector2(400, 0) # outside detection_radius, so the AI stays idle
	await phys(5)
	await check_attack_rate("H-goblin ", e)
	await cleanup(main)

	# ---------- I. one resource per attack (Phase 2) ----------
	# I1-I3: shipped definitions are complete.
	main = await fresh()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	var ai: EnemyAIController2D = e.get_node("EnemyAIController2D")
	check(p.attack_definition.weapon_animation == &"sword_slash_1" and p.attack_definition.recovery_animation == &"sword_slash_return_1", "I1 player definition names its weapon and recovery clips")
	check(p.attack_definition.effect_scene != null and e.attack_definition.effect_scene != null, "I2 both shipped definitions carry their own effect scene")
	check(e.attack_definition.ai_attack_range > 0.0 and is_equal_approx(ai.get_effective_attack_range(), e.attack_definition.ai_attack_range), "I3 goblin AI takes its range from the definition (%.0f)" % ai.get_effective_attack_range())
	await cleanup(main)

	# I4-I6: a definition with different clip names plays correctly.
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	var ap: AnimationPlayer = p.context.weapon_animation_player
	var heavy_lib := add_clip_aliases(ap, {&"heavy_swing": p.attack_definition.weapon_animation, &"heavy_recover": p.attack_definition.recovery_animation})
	var heavy := definition_variant(p.attack_definition, &"test_heavy")
	heavy.weapon_animation = &"heavy_swing"
	heavy.recovery_animation = &"heavy_recover"
	p.attack_definition = heavy
	check(p.attack_component.definition == heavy, "I4 definition with custom clip names is accepted")
	check(p.attack_component.try_start(true, Vector2.RIGHT), "I5 swing starts with custom clips")
	await phys(8)
	check(ap.current_animation == "heavy_swing" and count_slashes(main) >= 1, "I6 custom weapon clip plays and its spawn event creates the effect (clip='%s', slashes=%d)" % [ap.current_animation, count_slashes(main)])
	await phys(30)
	check(ap.current_animation == "heavy_recover", "I7 custom recovery clip follows (got '%s')" % ap.current_animation)
	await phys(60)
	check(not p.context.is_attacking, "I8 attack finishes after the custom recovery clip")
	await cleanup(main)
	remove_clips(heavy_lib, [&"heavy_swing", &"heavy_recover"])

	# I9-I10: empty recovery_animation ends the attack with the weapon clip.
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	ap = p.context.weapon_animation_player
	var quick_lib := add_clip_aliases(ap, {&"quick_swing": p.attack_definition.weapon_animation})
	var quick := definition_variant(p.attack_definition, &"test_quick")
	quick.weapon_animation = &"quick_swing"
	quick.recovery_animation = &""
	p.attack_definition = quick
	p.attack_component.try_start(true, Vector2.RIGHT)
	await phys(26) # slash clip is ~17.5 frames; the full two-clip cycle is ~58
	check(not p.context.is_attacking, "I9 attack with no recovery clip ends when the weapon clip ends")
	check(ap.current_animation != "sword_return", "I10 sword_return was not played (got '%s')" % ap.current_animation)
	await cleanup(main)
	remove_clips(quick_lib, [&"quick_swing"])

	# I11-I15: a definition with a missing clip is rejected with an error naming the clip.
	# (Two push_error lines naming 'no_such_*' are expected in the log for this section.)
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	var comp: AttackComponent2D = p.attack_component
	var good: AttackDefinition2D = comp.definition
	var bad_weapon := definition_variant(good, &"test_bad_weapon")
	bad_weapon.weapon_animation = &"no_such_weapon_clip"
	var bad_recovery := definition_variant(good, &"test_bad_recovery")
	bad_recovery.recovery_animation = &"no_such_recovery_clip"
	var same_clip := definition_variant(good, &"test_same_clip")
	same_clip.recovery_animation = same_clip.weapon_animation
	check(comp.validate_definition(bad_weapon).contains("no_such_weapon_clip"), "I11 validation names the missing weapon clip")
	check(comp.validate_definition(bad_recovery).contains("no_such_recovery_clip"), "I12 validation names the missing recovery clip")
	check(comp.validate_definition(same_clip) != "", "I13 recovery clip equal to the weapon clip is rejected")
	check(comp.validate_definition(good) == "", "I14 the shipped definition validates cleanly")
	check(not comp.set_attack_definition(bad_weapon) and comp.definition == good, "I15 component rejects a bad definition and keeps the old one")
	p.attack_definition = bad_recovery
	check(p.attack_definition == good and comp.definition == good, "I16 Character2D export mirrors the rejection")
	check(comp.try_start(true, Vector2.RIGHT), "I17 the character can still attack after a rejected swap")
	await cleanup(main)

	# I18-I20: the AI takes its swing distance from the definition.
	main = await fresh()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	ai = e.get_node("EnemyAIController2D")
	p.set_physics_process(false)
	set_detection_radius(e, 180.0)
	var wide := definition_variant(e.attack_definition, &"test_wide")
	wide.ai_attack_range = 100.0
	e.attack_definition = wide
	e.global_position = p.global_position + Vector2(90, 0) # inside detection, far beyond the controller's own 30
	await phys(10)
	check(is_equal_approx(ai.get_effective_attack_range(), 100.0) and ai.behavior == EnemyAIController2D.Behavior.ATTACK, "I18 range 100 from the definition: goblin attacks at 90 px (behavior=%s)" % ai.get_behavior_name())
	await cleanup(main)

	main = await fresh()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	ai = e.get_node("EnemyAIController2D")
	p.set_physics_process(false)
	set_detection_radius(e, 180.0)
	var fallback := definition_variant(e.attack_definition, &"test_fallback")
	fallback.ai_attack_range = 0.0
	e.attack_definition = fallback
	e.global_position = p.global_position + Vector2(90, 0)
	await phys(10)
	check(is_equal_approx(ai.get_effective_attack_range(), EnemyAIController2D.FALLBACK_ATTACK_RANGE) and ai.behavior == EnemyAIController2D.Behavior.CHASE, "I19 range 0 falls back to FALLBACK_ATTACK_RANGE (%.0f, behavior=%s)" % [ai.get_effective_attack_range(), ai.get_behavior_name()])
	await cleanup(main)

	# I20: the goblin's configured AI range is inside the swing's real reach.
	main = await fresh()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	var reach: float = e.attack_definition.ai_attack_range
	e.global_position = Vector2.ZERO
	p.global_position = Vector2(reach, 0)
	p.set_physics_process(false)
	e.set_physics_process(false)
	e.attack_component.try_start(true, Vector2.RIGHT)
	await phys(70)
	check(p.health_component.health < p.health_component.max_health, "I20 a goblin swing connects with a target at its ai_attack_range (%.0f px)" % reach)
	await cleanup(main)

	# I21-I25: movement_multiplier scales walking during the swing and always resets.
	main = await fresh()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.global_position = Vector2(0, 250)
	e.set_physics_process(false)
	var rooted := definition_variant(p.attack_definition, &"test_slow")
	rooted.movement_multiplier = 0.25
	p.attack_definition = rooted
	Input.action_press("move_right")
	await phys(5)
	check(absf(p.velocity.x - p.movement_component.move_speed) < 0.01 and p.context.move_multiplier == 1.0, "I21 full speed before the attack (vx=%.1f)" % p.velocity.x)
	p.attack_component.try_start(true, Vector2.RIGHT)
	await phys(3)
	check(is_equal_approx(p.context.move_multiplier, 0.25) and absf(p.velocity.x - p.movement_component.move_speed * 0.25) < 0.01, "I22 movement is scaled during the swing (mult=%.2f, vx=%.1f)" % [p.context.move_multiplier, p.velocity.x])
	await phys(80)
	check(not p.context.is_attacking and p.context.move_multiplier == 1.0 and absf(p.velocity.x - p.movement_component.move_speed) < 0.01, "I23 multiplier returns to 1.0 when the attack finishes (mult=%.2f, vx=%.1f)" % [p.context.move_multiplier, p.velocity.x])
	await phys(10)
	p.attack_component.try_start(true, Vector2.RIGHT)
	await phys(3)
	check(is_equal_approx(p.context.move_multiplier, 0.25), "I24 second swing scales movement again")
	p.attack_component.cancel()
	check(p.context.move_multiplier == 1.0 and not p.context.is_attacking, "I25 multiplier returns to 1.0 when the attack is cancelled")
	Input.action_release("move_right")
	await cleanup(main)

	# I26-I27: the definition's effect_scene is the scene that spawns; a definition with none is refused (10.1).
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	var marked: Node = load("res://Characters/Components/Combat/AttackSlash2D.tscn").instantiate()
	marked.set_meta(&"from_definition", true)
	var marked_scene := PackedScene.new()
	check(marked_scene.pack(marked) == OK, "I26a marked effect scene packs")
	marked.free()
	var with_effect := definition_variant(p.attack_definition, &"test_effect")
	with_effect.effect_scene = marked_scene
	p.attack_definition = with_effect
	p.attack_component.try_start(true, Vector2.RIGHT)
	await phys(8)
	check(count_slashes(main, &"from_definition") >= 1, "I26 definition.effect_scene is the scene that spawns")
	await phys(80)
	# I27 (rewritten on purpose in 10.1): there is no legacy slash scene any more, so a definition without an
	# effect_scene is refused and the previous attack stays.
	var no_effect := definition_variant(p.attack_definition, &"test_no_effect")
	no_effect.effect_scene = null
	var no_effect_before: StringName = p.attack_definition.id
	p.attack_definition = no_effect
	check(p.attack_definition.id == no_effect_before and p.attack_definition.id != &"test_no_effect", "I27 a definition with no effect_scene is refused and the previous attack stays")
	await cleanup(main)

	# ---------- J. Phase 3: generic animation events and multi-hit ----------
	main = await fresh()
	p = main.get_node("Player")
	var ge: Character2D = main.get_node("BasicEnemy2D")
	ge.set_physics_process(false)
	check(p.has_method("attack_event") and not p.has_method("spawn_slash"), "J1 attack_event exists and the spawn_slash alias is gone")
	for pair in [["player", p], ["goblin", ge]]:
		var ch: Character2D = pair[1]
		var evs: Array = clip_events(ch.context.weapon_animation_player.get_animation(ch.attack_definition.weapon_animation)).filter(func(ev: Array) -> bool: return ev[1] == [&"spawn_effect"])
		check(evs.size() == 1 and evs[0][0] == &"attack_event" and evs[0][1] == [&"spawn_effect"], "J2 %s slash clip fires attack_event(spawn_effect) (%s)" % [pair[0], str(evs)])
	check(AttackComponent2D.is_known_event(&"spawn_effect") and AttackComponent2D.is_known_event(&"combo_window_open") and AttackComponent2D.is_known_event(&"combo_window_close") and not AttackComponent2D.is_known_event(&"nope"), "J3 spawn_effect and the reserved combo events are the known events")

	# Events outside an attack are ignored.
	p.attack_event(&"spawn_effect")
	await phys(2)
	check(count_slashes(main) == 0 and p.attack_component.get_active_effect_count() == 0, "J4 attack_event(spawn_effect) with no attack running spawns nothing")

	# J5-J9: a clip with two spawn_effect events creates two slashes (flurry).
	var ap2: AnimationPlayer = p.context.weapon_animation_player
	var flurry_lib := add_clip_aliases(ap2, {&"flurry_swing": p.attack_definition.weapon_animation})
	var flurry_anim: Animation = flurry_lib.get_animation(&"flurry_swing")
	add_event_key(flurry_anim, 0.12, &"spawn_effect")
	var flurry := definition_variant(p.attack_definition, &"test_flurry")
	flurry.weapon_animation = &"flurry_swing"
	p.attack_definition = flurry
	check(p.attack_component.try_start(true, Vector2.RIGHT), "J5 flurry swing starts")
	await phys(5) # t ~ 0.083 s: first key (0.05) has fired, second (0.12) has not
	check(count_slashes(main) == 1 and p.attack_component.get_active_effect_count() == 1, "J6 first event spawns one slash (%d)" % count_slashes(main))
	await phys(7) # t ~ 0.2 s; each slash lives 0.375 s
	check(count_slashes(main) == 2 and p.attack_component.get_active_effect_count() == 2, "J7 second event spawns another without freeing the first (%d)" % count_slashes(main))

	# J8: reserved combo events are accepted and spawn nothing.
	p.attack_event(&"combo_window_open")
	p.attack_event(&"combo_window_close")
	await phys(1)
	check(count_slashes(main) == 2, "J8 reserved combo events do not spawn effects")

	# J9: an effect that leaves the tree drops out of the active list.
	var first_slash: Node = null
	for c in effect_children(main):
		if c is AttackSlash2D:
			first_slash = c
			break
	first_slash.queue_free()
	await phys(2)
	check(p.attack_component.get_active_effect_count() == 1, "J9 a freed effect is removed from the active list (%d)" % p.attack_component.get_active_effect_count())

	# J10: cancel() frees every live effect.
	p.attack_component.cancel()
	await phys(2)
	check(count_slashes(main) == 0 and p.attack_component.get_active_effect_count() == 0 and not p.context.is_attacking, "J10 cancel() frees all active effects (%d left)" % count_slashes(main))
	await cleanup(main)
	remove_clips(flurry_lib, [&"flurry_swing"])

	# J11: a finished swing stops tracking its effects but leaves them to finish.
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	p.attack_component.try_start(true, Vector2.RIGHT)
	await phys(8)
	check(p.attack_component.get_active_effect_count() == 1, "J11a single-effect attack tracks its slash")
	await phys(70)
	check(not p.context.is_attacking and p.attack_component.get_active_effect_count() == 0, "J11b finished attack tracks no effects (%d)" % p.attack_component.get_active_effect_count())
	await cleanup(main)

	# ---------- K. Phase 4: HealthComponent2D and HitData ----------
	main = await fresh()
	p = main.get_node("Player")
	var ke: Character2D = main.get_node("BasicEnemy2D")
	ke.set_physics_process(false)
	set_player_health(p, 5)
	check(p.health_component is HealthComponent2D and p.health_component.max_health == 5 and p.health_component.health == 5, "K1 player has a HealthComponent2D (max 5, full health)")
	check(ke.health_component is HealthComponent2D and ke.health_component.max_health >= 1 and ke.health_component.health == ke.health_component.max_health, "K2 goblin has a HealthComponent2D at full health (%d/%d)" % [ke.health_component.health, ke.health_component.max_health])

	var seen := {"changed": [], "damaged": [], "died": 0}
	p.health_changed.connect(func(cur: int, mx: int): seen["changed"].append([cur, mx]))
	p.damaged.connect(func(h: HitData): seen["damaged"].append(h))
	p.died.connect(func(): seen["died"] += 1)
	p.take_damage(2)
	check(p.health_component.health == 3 and seen["changed"] == [[3, 5]] and seen["damaged"].size() == 1 and seen["damaged"][0].damage == 2 and seen["died"] == 0, "K3 take_damage shim wraps a HitData and re-emits health_changed/damaged (%s)" % str(seen["changed"]))
	check(p.apply_hit(null) == 0 and p.health_component.health == 3, "K4 a null hit is ignored")
	p.take_damage(0)
	p.take_damage(-4)
	check(p.health_component.health == 3 and seen["damaged"].size() == 1, "K5 zero or negative damage is ignored")

	# Healing clamps to max and reports what it restored.
	check(p.heal(10) == 2 and p.health_component.health == 5 and seen["changed"].back() == [5, 5], "K6 heal() is clamped to max_health and returns the amount restored (health=%d)" % p.health_component.health)
	check(p.heal(3) == 0 and p.heal(-1) == 0, "K7 healing at full health or by a non-positive amount does nothing")

	# Overkill: dealt damage is capped at the health left, death fires once.
	p.take_damage(2)
	var dealt: int = p.apply_hit(HitData.new(999))
	check(dealt == 3 and p.health_component.health == 0 and not p.is_alive() and seen["died"] == 1, "K8 overkill deals only the remaining health (dealt=%d) and emits died once" % dealt)
	check(p.apply_hit(HitData.new(5)) == 0 and seen["died"] == 1 and p.heal(5) == 0 and p.health_component.health == 0, "K9 a dead character cannot be hit again or healed")
	check(not p.is_physics_processing(), "K10 death still stops the player's physics processing")
	await cleanup(main)

	# K11-K12: invulnerability window.
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	set_player_health(p, 5)
	check(p.health_component.invulnerability_duration == 0.0 and not p.health_component.is_invulnerable(), "K11 invulnerability is off by default")
	p.health_component.invulnerability_duration = 0.5
	check(p.apply_hit(HitData.new(1)) == 1 and p.health_component.health == 4 and p.health_component.is_invulnerable(), "K12 first hit lands and opens the window")
	check(p.apply_hit(HitData.new(1)) == 0 and p.health_component.health == 4, "K13 a second hit inside the window is ignored")
	await phys(40) # 0.67 s > 0.5 s
	check(not p.health_component.is_invulnerable() and p.apply_hit(HitData.new(1)) == 1 and p.health_component.health == 3, "K14 hits land again once the window has expired (health=%d)" % p.health_component.health)
	await cleanup(main)

	# K16-K17: slash builds a HitData with its source and direction.
	main = await fresh()
	p = main.get_node("Player")
	ke = main.get_node("BasicEnemy2D")
	ke.set_physics_process(false)
	ke.global_position = p.global_position + Vector2(28, 0)
	var got: Array = []
	ke.damaged.connect(func(h: HitData): got.append(h))
	p.attack_component.try_start(true, Vector2.RIGHT)
	await phys(40)
	check(got.size() == 1 and got[0].damage == p.attack_definition.damage and got[0].source == p, "K16 slash hit carries damage and source (%d hits)" % got.size())
	check(got.size() == 1 and got[0].direction.is_equal_approx(Vector2.RIGHT), "K17 slash hit carries the slash direction (%s)" % (str(got[0].direction) if got.size() > 0 else "none"))
	await cleanup(main)

	# K18-K19: shared death handling cancels the attack; goblin death frees the node.
	main = await fresh()
	p = main.get_node("Player")
	ke = main.get_node("BasicEnemy2D")
	ke.set_physics_process(false)
	p.attack_component.try_start(true, Vector2.RIGHT)
	await phys(3)
	check(p.context.is_attacking and is_equal_approx(p.context.move_multiplier, p.attack_definition.movement_multiplier), "K18a player is mid-swing")
	p.take_damage(999)
	check(not p.context.is_attacking and p.context.move_multiplier == 1.0 and p.velocity == Vector2.ZERO, "K18 death cancels the swing through the shared handler")
	var goblin_died := [0]
	ke.died.connect(func(): goblin_died[0] += 1)
	ke.take_damage(999)
	await phys(2)
	check(goblin_died[0] == 1 and not is_instance_valid(ke), "K19 goblin death emits died once and frees the node")
	await cleanup(main)

	# K20: changing the component's max_health re-announces health.
	main = await fresh()
	ke = main.get_node("BasicEnemy2D")
	ke.set_physics_process(false)
	var announced: Array = []
	ke.health_changed.connect(func(cur: int, mx: int): announced.append([cur, mx]))
	var health_before: int = ke.health_component.health
	ke.health_component.max_health = 6
	check(ke.health_component.max_health == 6 and announced.back() == [mini(health_before, 6), 6], "K20 setting the component's max_health emits health_changed (%s)" % str(announced))
	ke.health_component.max_health = 2
	check(ke.health_component.health == 2 and announced.back() == [2, 2], "K21 lowering max_health below current health clamps it (%s)" % str(announced.back()))
	await cleanup(main)

	# ---------- L. Phase 5: teams, hit layers, knockback, interrupts ----------
	main = await fresh()
	p = main.get_node("Player")
	ke = main.get_node("BasicEnemy2D")
	ke.set_physics_process(false)
	check(p.team == &"player" and ke.team == &"enemy", "L1 player and goblin are on the player/enemy teams")
	check(p.attack_definition.knockback > 0.0 and p.attack_definition.hit_stun > 0.0 and ke.attack_definition.interruptible and not p.attack_definition.interruptible, "L2 shipped definitions carry knockback/hit stun; only the goblin's swing is interruptible")

	# L3: same-team hit does nothing. L4: a third team is damaged. L5: a neutral (empty) team is damaged.
	var swing_results := {}
	for team_name in [&"player", &"third_faction", &""]:
		ke.team = team_name
		ke.global_position = p.global_position + Vector2(28, 0)
		var before: int = ke.health_component.health
		p.attack_component.try_start(true, Vector2.RIGHT)
		await phys(40)
		swing_results[team_name] = before - ke.health_component.health
		await phys(60) # let the swing finish before the next one
	check(swing_results[&"player"] == 0, "L3 a same-team target takes no damage (took %d)" % swing_results[&"player"])
	check(swing_results[&"third_faction"] == p.attack_definition.damage, "L4 a third team is damaged without any script change (took %d)" % swing_results[&"third_faction"])
	check(swing_results[&""] == p.attack_definition.damage, "L5 a neutral (empty-team) target can be hit (took %d)" % swing_results[&""])
	await cleanup(main)

	# L6-L8: hit_layers sets the hitbox mask and decides what can be hit.
	main = await fresh()
	p = main.get_node("Player")
	ke = main.get_node("BasicEnemy2D")
	ke.set_physics_process(false)
	var layer_results := {}
	var masks := {}
	for layers in [1, 2, 4]:
		var d := definition_variant(p.attack_definition, StringName("test_layers_%d" % layers))
		d.hit_layers = layers
		p.attack_definition = d
		ke.global_position = p.global_position + Vector2(28, 0)
		var hp_before: int = ke.health_component.health
		p.attack_component.try_start(true, Vector2.RIGHT)
		await phys(8)
		for c in effect_children(main):
			if c is AttackSlash2D:
				masks[layers] = (c.get_node("HitboxOrigin/HitboxMotion/Area2D") as Area2D).collision_mask
		await phys(32)
		layer_results[layers] = hp_before - ke.health_component.health
		await phys(60)
	check(masks.get(1, -1) == 1 and masks.get(2, -1) == 2 and masks.get(4, -1) == 4, "L6 the hitbox mask comes from definition.hit_layers (%s)" % str(masks))
	check(layer_results[1] == 0 and layer_results[4] == 0, "L7 layers that exclude the target's layer miss it (player-only=%d, world-only=%d)" % [layer_results[1], layer_results[4]])
	check(layer_results[2] == p.attack_definition.damage, "L8 the enemy layer hits the goblin (took %d)" % layer_results[2])
	await cleanup(main)

	# L9-L10: knockback pushes along the hit direction, then decays to zero.
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	var kx0: float = p.global_position.x
	var ky0: float = p.global_position.y
	p.apply_hit(HitData.new(1, null, Vector2.LEFT, 300.0, 0.0))
	await phys(5)
	check(p.global_position.x < kx0 - 8.0 and absf(p.global_position.y - ky0) < 0.5, "L9 knockback moves the target along the hit direction (dx=%.1f, dy=%.1f)" % [p.global_position.x - kx0, p.global_position.y - ky0])
	await phys(40)
	var kx1: float = p.global_position.x
	check(p.context.knockback_velocity == Vector2.ZERO and kx0 - kx1 > 20.0 and kx0 - kx1 < 60.0, "L10 knockback decays to zero after about v^2/(2*friction) px (moved %.1f)" % (kx0 - kx1))
	await phys(10)
	check(is_equal_approx(p.global_position.x, kx1), "L10b the target stays put once knockback ends")
	# A killing hit applies no knockback.
	p.apply_hit(HitData.new(999, null, Vector2.LEFT, 500.0, 0.5))
	check(p.context.knockback_velocity == Vector2.ZERO and p.context.hit_stun_remaining == 0.0 and not p.is_alive(), "L11 a killing hit leaves no knockback or stun behind")
	await cleanup(main)

	# L12-L14: hit stun blocks attacks and dashes, then expires.
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	p.apply_hit(HitData.new(1, null, Vector2.ZERO, 0.0, 0.3))
	check(p.is_stunned(), "L12 a hit with hit_stun stuns the target")
	check(not p.attack_component.try_start(true, Vector2.RIGHT) and not p.dash_component.try_start(true, Vector2.RIGHT), "L13 a stunned character can neither attack nor dash")
	await phys(25) # 0.42 s > 0.3 s
	check(not p.is_stunned() and p.attack_component.try_start(true, Vector2.RIGHT), "L14 the stun expires and attacks work again")
	await cleanup(main)

	# L15-L17: interrupts.
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	p.attack_component.try_start(true, Vector2.RIGHT)
	await phys(3)
	p.apply_hit(HitData.new(1))
	check(p.context.is_attacking, "L15 a non-interruptible swing survives being hit")
	await phys(80)
	var interruptible := definition_variant(p.attack_definition, &"test_interruptible")
	interruptible.interruptible = true
	interruptible.cooldown_duration = 0.5
	p.attack_definition = interruptible
	p.attack_component.try_start(true, Vector2.RIGHT)
	await phys(8) # the first slash has spawned
	check(p.attack_component.get_active_effect_count() == 1, "L16a interruptible swing has spawned its effect")
	p.apply_hit(HitData.new(1))
	await phys(2)
	check(not p.context.is_attacking and p.context.move_multiplier == 1.0 and count_slashes(main) == 0, "L16 an interruptible swing is cancelled by a hit (effects freed: %d left)" % count_slashes(main))
	check(p.attack_component.is_on_cooldown() and not p.attack_component.try_start(true, Vector2.RIGHT), "L17 an interrupted attack starts its cooldown")
	await cleanup(main)

	# ---------- M. Phase 6a: components are scene nodes ----------
	for scene_path in ["res://player.tscn", "res://Characters/Enemies/BasicEnemy2D.tscn"]:
		var paths := scene_node_paths(scene_path)
		for node_name in ["MovementComponent2D", "DashComponent2D", "AttackComponent2D", "HealthComponent2D"]:
			check(paths.has(node_name), "M1 %s stores a %s node in the scene file" % [scene_path.get_file(), node_name])
	main = await fresh()
	p = main.get_node("Player")
	ke = main.get_node("BasicEnemy2D")
	ke.set_physics_process(false)
	check(p.movement_component == p.get_node("MovementComponent2D") and p.dash_component == p.get_node("DashComponent2D") and p.attack_component == p.get_node("AttackComponent2D"), "M2 the character uses the scene's component nodes")
	check(p.movement_component.move_speed == 100.0 and p.dash_component.dash_speed == 600.0 and p.dash_component.dash_duration == 0.16 and p.dash_component.dash_cooldown == 0.45, "M3 player keeps its tuned move speed (100, set in player.tscn) and the default dash values")
	check(ke.movement_component.move_speed == 50.0 and ke.dash_component.dash_speed == 150.0, "M4 the goblin's move_speed 50 and dash_speed 150 now live on its components")
	check(p.attack_definition.id == &"player_light" and ke.attack_definition.id == &"goblin_slash", "M5 each character's AttackComponent2D carries its own definition")
	check(not ("move_speed" in p) and not ("dash_speed" in p) and not ("attack_slash_scene" in p), "M6 Character2D no longer forwards move/dash/slash-scene values")
	p.movement_component.move_speed = 100.0
	Input.action_press("move_right")
	await phys(5)
	check(absf(p.velocity.x - 100.0) < 0.01, "M7 editing move_speed on the component changes movement (vx=%.1f)" % p.velocity.x)
	Input.action_release("move_right")
	await cleanup(main)

	# M8: a character missing a required component logs an error and disables itself.
	# (One push_error naming MovementComponent2D is expected in the log for this check.)
	main = await fresh()
	var broken: Node = load("res://Characters/Enemies/BasicEnemy2D.tscn").instantiate()
	broken.get_node("MovementComponent2D").free()
	main.add_child(broken)
	await phys(3)
	check(not broken.is_physics_processing() and broken.movement_component == null, "M8 missing MovementComponent2D disables the character instead of crashing")
	await cleanup(main)

	# ---------- N. Phase 6b: states are scene nodes ----------
	for scene_path in ["res://player.tscn", "res://Characters/Enemies/BasicEnemy2D.tscn"]:
		var paths := scene_node_paths(scene_path)
		for node_path in ["CharacterStateMachine", "CharacterStateMachine/Idle", "CharacterStateMachine/Move", "CharacterStateMachine/Dash", "CharacterStateMachine/Attack"]:
			check(paths.has(node_path), "N1 %s stores a %s node in the scene file" % [scene_path.get_file(), node_path])
	main = await fresh()
	p = main.get_node("Player")
	ke = main.get_node("BasicEnemy2D")
	ke.set_physics_process(false)
	check(p.state_machine == p.get_node("CharacterStateMachine") and p.get_node("CharacterStateMachine/Idle") is CharacterState, "N2 the character uses the scene's state machine and state nodes")
	check(p.state_machine.has_state(&"Idle") and p.state_machine.has_state(&"Move") and p.state_machine.has_state(&"Dash") and p.state_machine.has_state(&"Attack"), "N3 the machine registered all four child states by node name")
	check(p.state_machine.initial_state == &"Idle" and p.state_machine.current_state_name == &"Idle", "N4 the machine enters initial_state (%s)" % p.state_machine.current_state_name)
	Input.action_press("move_right")
	await phys(5)
	check(p.state_machine.current_state_name == &"Move", "N5 moving enters Move (%s)" % p.state_machine.current_state_name)
	Input.action_release("move_right")
	await phys(5)
	check(p.state_machine.current_state_name == &"Idle", "N6 stopping returns to Idle (%s)" % p.state_machine.current_state_name)
	p.dash_component.try_start(true, Vector2.RIGHT)
	await phys(3)
	check(p.state_machine.current_state_name == &"Dash", "N7 dashing enters Dash (%s)" % p.state_machine.current_state_name)
	await phys(25)
	p.attack_component.try_start(true, Vector2.RIGHT)
	await phys(3)
	check(p.state_machine.current_state_name == &"Attack", "N8 attacking enters Attack (%s)" % p.state_machine.current_state_name)
	await phys(80)
	check(p.state_machine.current_state_name == &"Idle", "N9 the machine returns to Idle after the swing (%s)" % p.state_machine.current_state_name)
	await cleanup(main)

	# N10: initial_state is an editable export.
	main = await fresh()
	var custom: Node = load("res://Characters/Enemies/BasicEnemy2D.tscn").instantiate()
	custom.get_node("CharacterStateMachine").initial_state = &"Move"
	custom.set_physics_process(false)
	main.add_child(custom)
	check(custom.state_machine.current_state_name == &"Move", "N10 initial_state decides the first state (%s)" % custom.state_machine.current_state_name)

	# N11: a character without a CharacterStateMachine node logs an error and disables itself.
	# (One push_error naming CharacterStateMachine is expected in the log for this check.)
	var no_machine: Node = load("res://Characters/Enemies/BasicEnemy2D.tscn").instantiate()
	no_machine.get_node("CharacterStateMachine").free()
	main.add_child(no_machine)
	await phys(3)
	check(not no_machine.is_physics_processing() and no_machine.state_machine == null, "N11 missing CharacterStateMachine disables the character instead of crashing")
	await cleanup(main)

	# ---------- O. Phase 7: scene-driven feedback and VFX ----------
	var hit_effect_path := "res://Characters/Effects/HitEffect.tscn"
	var death_effect_path := "res://Characters/Effects/DeathEffect.tscn"

	# O1: structure lives in the scene files.
	var player_paths := scene_node_paths("res://player.tscn")
	var enemy_paths := scene_node_paths("res://Characters/Enemies/BasicEnemy2D.tscn")
	check(player_paths.has("ReactionAnim") and enemy_paths.has("AnimatedSprite2D/AnimationPlayer"), "O1 the reaction players are nodes in the scene files")
	check(scene_node_paths("res://Main.tscn").has("Effects"), "O1b Main.tscn has an Effects node")
	for scene_path in [hit_effect_path, death_effect_path]:
		var effect_state := (load(scene_path) as PackedScene).get_state()
		var has_player := false
		for i in effect_state.get_node_count():
			if effect_state.get_node_type(i) == &"AnimationPlayer":
				has_player = true
		check(has_player, "O1c %s is built from a scene with its own AnimationPlayer" % scene_path.get_file())

	# O2: the enemy flash clip no longer fights the idle/run frame animation.
	var enemy_scene_state := load("res://Characters/Enemies/BasicEnemy2D.tscn") as PackedScene
	var probe: Node = enemy_scene_state.instantiate()
	var hit_lib: AnimationPlayer = probe.get_node("AnimatedSprite2D/AnimationPlayer")
	for clip_name in [&"take_damage", &"RESET"]:
		var clip: Animation = hit_lib.get_animation(clip_name)
		var frame_tracks := 0
		for t in clip.get_track_count():
			if str(clip.track_get_path(t)).ends_with(":frame"):
				frame_tracks += 1
		check(frame_tracks == 0, "O2 enemy '%s' clip has no :frame track (%d)" % [clip_name, frame_tracks])
	var flash_clip: Animation = hit_lib.get_animation(&"take_damage")
	var flash_position_end := Vector2(99, 99)
	for t in flash_clip.get_track_count():
		if str(flash_clip.track_get_path(t)) == ".:position":
			flash_position_end = flash_clip.track_get_key_value(t, flash_clip.track_get_key_count(t) - 1)
	check(flash_position_end == Vector2.ZERO, "O2b the flash shake ends back at the rest position (%s)" % str(flash_position_end))
	probe.free()

	# O3: enemy plays the authored clip; frame animation keeps running; pose is restored.
	main = await fresh()
	p = main.get_node("Player")
	ke = main.get_node("BasicEnemy2D")
	ke.set_physics_process(false)
	var enemy_sprite: AnimatedSprite2D = ke.get_node("AnimatedSprite2D")
	var enemy_hit_player: AnimationPlayer = ke.get_node("AnimatedSprite2D/AnimationPlayer")
	check(not ke.has_method("_play_hit_feedback") and ke.get("_hit_tween") == null, "O3 the tween-based hit feedback is gone")
	ke.take_damage(1)
	await phys(3)
	check(enemy_hit_player.current_animation == "take_damage" and enemy_hit_player.is_playing(), "O3b a hit plays the take_damage clip (got '%s')" % enemy_hit_player.current_animation)
	var frames_seen := {}
	for i in 12:
		frames_seen[enemy_sprite.frame] = true
		await physics_frame
	check(enemy_sprite.is_playing() and frames_seen.size() > 1, "O3c idle/run frames keep animating during the flash (%d distinct frames)" % frames_seen.size())
	await phys(30)
	check(enemy_sprite.position == Vector2.ZERO and enemy_sprite.modulate == Color.WHITE and enemy_sprite.self_modulate == Color.WHITE, "O3d the sprite is back at rest after the flash (pos=%s)" % str(enemy_sprite.position))
	await cleanup(main)

	# O4: player flash is its own player, driven by one shared material.
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	var rig_sprites: Array = ["Legs", "Head", "Hair", "Torso"].map(func(n): return p.get_node("LayeredRig/" + n))
	var same_material := true
	for sprite in rig_sprites:
		same_material = same_material and sprite.material == rig_sprites[0].material and sprite.material != null
	check(same_material, "O4 the four rig sprites share one flash material")
	check(not p.get_node("PlayerAnim").has_animation(&"take_damage"), "O4b PlayerAnim has no take_damage clip any more")
	var flash_on := false
	p.take_damage(1)
	for i in 20:
		await physics_frame
		for sprite in rig_sprites:
			flash_on = flash_on or sprite.material.get_shader_parameter("enabled") == true
	check(flash_on, "O4c the flash turns the shader on during take_damage")
	await phys(20)
	check(rig_sprites[0].material.get_shader_parameter("enabled") == false, "O4d the flash ends switched off")
	await cleanup(main)

	# O5: effects go to the container.
	main = await fresh()
	p = main.get_node("Player")
	ke = main.get_node("BasicEnemy2D")
	ke.set_physics_process(false)
	var effects_root: Node = main.get_node("Effects")
	check(effects_root.is_in_group("effects_root") and Effects2D.get_host(p) == effects_root, "O5 Effects2D finds the effects_root node")
	ke.global_position = p.global_position + Vector2(28, 0)
	p.attack_component.try_start(true, Vector2.RIGHT)
	await phys(8)
	var direct_slashes := main.get_children().filter(func(n): return n is AttackSlash2D)
	check(effects_root.get_children().any(func(n): return n is AttackSlash2D) and direct_slashes.is_empty(), "O5b the slash is parented under Effects, not Main")

	# O6: a hit spawns the impact effect near the contact point, and it frees itself.
	var impact_seen: Array = []
	var impact_pos := Vector2.ZERO
	for i in 90:
		await physics_frame
		var found := effects_from(main, hit_effect_path)
		if not found.is_empty():
			impact_seen.append(found[0])
			impact_pos = found[0].global_position
	check(ke.health_component.health < ke.health_component.max_health and not impact_seen.is_empty(), "O6 a landed hit spawns HitEffect in the Effects container")
	check(not impact_seen.is_empty() and impact_pos.distance_to(ke.global_position) < 40.0, "O6b the impact appears near the target (dist=%.1f)" % impact_pos.distance_to(ke.global_position))
	await phys(40)
	check(effects_from(main, hit_effect_path).is_empty(), "O6c the impact frees itself when its clip ends")
	await phys(60)

	# O7: with no hit_effect_scene on the definition nothing is spawned.
	var silent: AttackDefinition2D = p.attack_definition.duplicate()
	silent.hit_effect_scene = null
	p.attack_definition = silent
	ke.health_component.heal(99)
	var silent_seen := 0
	p.attack_component.try_start(true, Vector2.RIGHT)
	for i in 50:
		await physics_frame
		silent_seen += effects_from(main, hit_effect_path).size()
	check(silent_seen == 0, "O7 an attack with no hit_effect_scene spawns no impact (%d)" % silent_seen)
	await cleanup(main)

	# O8: the goblin's death effect appears in the container where it died.
	main = await fresh()
	p = main.get_node("Player")
	ke = main.get_node("BasicEnemy2D")
	ke.set_physics_process(false)
	ke.global_position = Vector2(60, 40)
	ke.take_damage(999)
	await phys(2)
	var burst := effects_from(main, death_effect_path)
	check(not is_instance_valid(ke) or ke.is_queued_for_deletion(), "O8 the goblin is removed on death")
	check(burst.size() == 1 and burst[0].global_position.is_equal_approx(Vector2(60, 40)), "O8b one DeathEffect spawned at the death position (%d)" % burst.size())
	await phys(50)
	check(effects_from(main, death_effect_path).is_empty(), "O8c the death effect frees itself")
	await cleanup(main)

	# O9: static properties are authored in the scenes, not set by code.
	for script_path in ["res://player.gd", "res://Characters/Enemies/BasicEnemy2D.gd", "res://Characters/Core/Character2D.gd"]:
		var source := FileAccess.get_file_as_string(script_path)
		check(not source.contains("add_to_group") and not source.contains(".z_index"), "O9 %s sets no groups or z_index in code" % script_path.get_file())
	check("player" in (load("res://player.tscn") as PackedScene).get_state().get_node_groups(0) and "damageable" in (load("res://player.tscn") as PackedScene).get_state().get_node_groups(0), "O9b player.tscn root carries the player/damageable groups")
	check("enemy" in enemy_scene_state.get_state().get_node_groups(0) and "damageable" in enemy_scene_state.get_state().get_node_groups(0), "O9c BasicEnemy2D.tscn root carries the enemy/damageable groups")
	main = await fresh()
	p = main.get_node("Player")
	ke = main.get_node("BasicEnemy2D")
	check(p.context.weapon_pivot.z_index == 1 and ke.context.weapon_pivot.z_index == 1, "O9d both weapon pivots have z_index 1 from the scene")
	await cleanup(main)

	# ---------- P. Phase 7 (optional step): aimed swing ----------
	main = await fresh()
	p = main.get_node("Player")
	ke = main.get_node("BasicEnemy2D")
	ke.set_physics_process(false)
	ke.global_position = Vector2(400, 300)
	check(p.attack_definition.aim_weapon and not ke.attack_definition.aim_weapon, "P1 the player's attack aims its weapon, the goblin's does not")
	var pivot: Node2D = p.context.weapon_facing_root
	var aim_ok := true
	var aim_report := ""
	for aim in [Vector2.RIGHT, Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2(-1, -1).normalized(), Vector2(-1, 1).normalized(), Vector2(1, -1).normalized(), Vector2(1, 1).normalized()]:
		p.attack_component.try_start(true, aim)
		await phys(3)
		var forward: Vector2 = pivot.global_transform.x.normalized()
		var aim_good := forward.is_equal_approx(aim) or (absf(aim.x) < 0.001 and forward.is_equal_approx(aim))
		aim_ok = aim_ok and aim_good
		aim_report += " %s->%s" % [str(aim), str(forward)]
		p.attack_component.cancel()
		await phys(3)
	check(aim_ok, "P2 the pivot's forward axis points along the attack direction:%s" % aim_report)
	check(is_zero_approx(pivot.rotation), "P3 cancelling the swing restores the pivot rotation (%.3f)" % pivot.rotation)
	p.attack_component.try_start(true, Vector2.DOWN)
	await phys(3)
	check(absf(pivot.rotation) > 0.1, "P4 the pivot is rotated while the swing runs (%.3f)" % pivot.rotation)
	await phys(70)
	check(not p.context.is_attacking and is_zero_approx(pivot.rotation), "P5 the pivot returns to 0 when the swing finishes (%.3f)" % pivot.rotation)
	var flat: AttackDefinition2D = p.attack_definition.duplicate()
	flat.aim_weapon = false
	p.attack_definition = flat
	p.attack_component.try_start(true, Vector2.DOWN)
	await phys(3)
	check(is_zero_approx(pivot.rotation), "P6 aim_weapon = false keeps the original unrotated arc (%.3f)" % pivot.rotation)
	p.attack_component.cancel()
	var aimed: AttackDefinition2D = flat.duplicate()
	aimed.aim_weapon = true
	p.attack_definition = aimed
	await phys(70)
	p.attack_component.try_start(true, Vector2.UP)
	await phys(3)
	p.take_damage(999)
	await phys(2)
	check(is_zero_approx(pivot.rotation), "P7 dying mid-swing leaves the pivot unrotated (%.3f)" % pivot.rotation)
	await cleanup(main)

	# P8: a goblin whose definition asks to aim still swings (it has no pivot to rotate).
	main = await fresh()
	ke = main.get_node("BasicEnemy2D")
	ke.set_physics_process(false)
	var goblin_aim: AttackDefinition2D = ke.attack_definition.duplicate()
	goblin_aim.aim_weapon = true
	ke.attack_definition = goblin_aim
	check(ke.context.weapon_facing_root == null and ke.attack_component.try_start(true, Vector2.DOWN), "P8 aim_weapon is ignored on a rig without WeaponFacingPivot")
	await cleanup(main)

	# ---------- Q. Phase 8a: detection area and behavior profile ----------
	const GOBLIN_SCENE := "res://Characters/Enemies/BasicEnemy2D.tscn"
	main = await fresh()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	ai = e.get_node("EnemyAIController2D")
	var det: Area2D = e.get_node_or_null("DetectionArea")
	var det_shape: CollisionShape2D = det.get_node_or_null("CollisionShape2D") if det != null else null
	# The radius drawn in BasicEnemy2D.tscn (tuned in the editor); tests compare against it.
	var drawn_radius: float = (det_shape.shape as CircleShape2D).radius if det_shape != null and det_shape.shape is CircleShape2D else 0.0
	check(det != null and det.collision_layer == 0 and det.collision_mask == 1 and not det.monitorable, "Q1 the goblin has a DetectionArea that watches the player layer only")
	check(det_shape != null and det_shape.shape is CircleShape2D and drawn_radius > 0.0, "Q2 DetectionArea has a drawn CircleShape2D (radius %.0f)" % drawn_radius)
	check(ai.detection_area == det and ai.profile is EnemyBehaviorProfile, "Q3 the AI controller points at the area and a profile resource")
	check(is_equal_approx(ai.profile.disengage_radius, 250.0) and is_equal_approx(ai.profile.lost_target_grace_duration, 0.75) and is_equal_approx(ai.profile.home_stop_distance, 5.0) and is_zero_approx(ai.profile.detection_radius), "Q4 the goblin profile carries the old controller values (detection 0 = use the drawn shape)")
	check(is_equal_approx(ai.get_detection_radius(), drawn_radius), "Q5 detection radius is read from the drawn shape (%.0f)" % ai.get_detection_radius())
	var ai_source := FileAccess.get_file_as_string("res://Characters/Controllers/EnemyAIController2D.gd")
	check(not ai_source.contains("get_nodes_in_group") and not ai_source.contains("&\"Idle\"") and not ai_source.contains("&\"Chase\""), "Q6 the AI no longer scans groups or compares behavior strings")
	check(ai.get_behavior_name() in ["IDLE", "CHASE", "ATTACK", "RETURN"], "Q7 behavior is an enum value (%s)" % ai.get_behavior_name())
	await cleanup(main)

	# Q8-Q12: outside the area the player is ignored; inside it is chased; far away it is dropped.
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	ai = e.get_node("EnemyAIController2D")
	p.set_physics_process(false)
	set_detection_radius(e, 180.0)
	e.global_position = p.global_position + Vector2(400, 0)
	await phys(10)
	check(ai.get_current_target() == null and ai.behavior == EnemyAIController2D.Behavior.IDLE and ai.get_candidate_count() == 0, "Q8 a player outside the detection area is ignored (behavior=%s)" % ai.get_behavior_name())
	var seen_behaviors: Array = []
	ai.behavior_changed.connect(func(_prev, cur): seen_behaviors.append(cur))
	e.global_position = p.global_position + Vector2(150, 0)
	await phys(10)
	check(ai.get_current_target() == p and ai.get_candidate_count() == 1 and ai.behavior == EnemyAIController2D.Behavior.CHASE, "Q9 once inside the area the goblin targets and chases (behavior=%s)" % ai.get_behavior_name())
	# After the teleport the area reports the player one physics step later, so a short RETURN can
	# precede CHASE; only the values and the CHASE transition matter here.
	var behaviors_valid := true
	for seen_value in seen_behaviors:
		behaviors_valid = behaviors_valid and typeof(seen_value) == TYPE_INT and int(seen_value) in EnemyAIController2D.Behavior.values()
	check(behaviors_valid and seen_behaviors.has(EnemyAIController2D.Behavior.CHASE), "Q10 behavior_changed reports enum values and includes CHASE (%s)" % str(seen_behaviors))
	e.set_physics_process(false)
	e.global_position = p.global_position + Vector2(220, 0)
	await phys(5)
	check(ai.get_candidate_count() == 0 and ai.get_current_target() == p, "Q11 leaving the area (220 px) removes the candidate but the target is kept inside the disengage radius")
	e.set_physics_process(true)
	e.global_position = p.global_position + Vector2(600, 0)
	await phys(60)
	check(ai.get_current_target() == null, "Q12 beyond the disengage radius for the grace time the target is dropped")
	await cleanup(main)

	# Q13: dragging the circle (changing its radius) changes who is noticed, on a private copy.
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	ai = e.get_node("EnemyAIController2D")
	p.set_physics_process(false)
	e.set_physics_process(false)
	var small: CircleShape2D = (e.get_node("DetectionArea/CollisionShape2D") as CollisionShape2D).shape.duplicate()
	small.radius = 60.0
	(e.get_node("DetectionArea/CollisionShape2D") as CollisionShape2D).shape = small
	e.global_position = p.global_position + Vector2(100, 0)
	await phys(10)
	check(ai.get_candidate_count() == 0 and is_equal_approx(ai.get_detection_radius(), 60.0), "Q13 a smaller drawn circle (60) leaves a player at 100 px unnoticed")
	e.global_position = p.global_position + Vector2(40, 0)
	await phys(10)
	check(ai.get_candidate_count() == 1, "Q14 the same smaller circle notices a player at 40 px")
	await cleanup(main)

	# Q15-Q16: a profile with detection_radius > 0 overrides the drawn shape for that enemy only.
	main = await fresh()
	p = main.get_node("Player")
	p.set_physics_process(false)
	main.get_node("BasicEnemy2D").queue_free()
	await phys(2)
	var custom_profile := EnemyBehaviorProfile.new()
	custom_profile.detection_radius = drawn_radius * 0.5
	var tuned: Character2D = (load(GOBLIN_SCENE) as PackedScene).instantiate()
	tuned.get_node("EnemyAIController2D").profile = custom_profile
	main.add_child(tuned)
	tuned.global_position = p.global_position + Vector2(drawn_radius * 0.8, 0) # inside the drawn circle, outside the override
	await phys(10)
	var tuned_ai: EnemyAIController2D = tuned.get_node("EnemyAIController2D")
	check(is_equal_approx(tuned_ai.get_detection_radius(), drawn_radius * 0.5) and tuned_ai.get_current_target() == null, "Q15 profile.detection_radius (%.0f) overrides the drawn %.0f (player at %.0f px ignored)" % [drawn_radius * 0.5, drawn_radius, drawn_radius * 0.8])
	var other: Character2D = (load(GOBLIN_SCENE) as PackedScene).instantiate()
	main.add_child(other)
	await phys(2)
	check(is_equal_approx(other.get_node("EnemyAIController2D").get_detection_radius(), drawn_radius), "Q16 the override did not change the shared scene shape (another goblin still has %.0f)" % drawn_radius)
	await cleanup(main)

	# ---------- R. Phase 8b: HealthBar scene, styling data, binding ----------
	main = await fresh()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	var bar: HealthBar = main.get_node("HUD/PlayerHealthBar")
	check(bar != null and bar.scene_file_path == "res://UI/HUD/HealthBar.tscn", "R1 the HUD uses the shared HealthBar scene")
	check(bar.get_node(bar.health_source) == p.health_component, "R2 health_source (a NodePath) points at the player's HealthComponent2D")
	for gone in ["HealthBarStyle.gd", "PlayerHealthBar.gd", "PlayerHealthBar.tscn", "EnemyHealthBar2D.gd", "EnemyHealthBar2D.tscn"]:
		check(not FileAccess.file_exists("res://UI/HUD/" + gone), "R3 %s was deleted" % gone)
	var bar_clips: AnimationPlayer = bar.get_node("AnimationPlayer")
	check(bar_clips.has_animation(&"intro") and bar_clips.has_animation(&"hit") and bar_clips.has_animation(&"heal") and bar_clips.has_animation(&"critical"), "R4 the bar has intro, hit, heal and critical clips")
	check(bar_clips.get_animation(&"critical").loop_mode == Animation.LOOP_LINEAR, "R5 the critical clip loops")
	check(bar.color_gradient is Gradient and bar.color_gradient.resource_path == "res://UI/HUD/Styles/health_gradient.tres", "R6 colours come from a Gradient resource")
	check(not ("health" in p) and not ("max_health" in p), "R7 the Phase 4 health / max_health shims are gone from Character2D")
	var r_max: int = p.health_component.max_health
	var r_60 := roundi(r_max * 0.6)
	var r_40 := roundi(r_max * 0.4)
	var r_20 := roundi(r_max * 0.2)
	check(is_equal_approx(bar.get_shown_health(), float(r_max)) and bar.get_counter_text() == "%d / %d" % [r_max, r_max], "R8 the bar starts full (%s)" % bar.get_counter_text())
	var full_color: Color = bar.progress_bar.modulate
	check(full_color.is_equal_approx(bar.color_gradient.sample(1.0)), "R9 a full bar uses the high colour")

	await phys(25) # let the intro clip finish
	p.take_damage(r_max - r_60)
	await phys(2)
	check(bar_clips.current_animation == "hit" and bar_clips.is_playing(), "R10 a hit plays the hit clip (got '%s')" % bar_clips.current_animation)
	await phys(20)
	check(is_equal_approx(bar.get_shown_health(), float(r_60)) and bar.get_counter_text() == "%d / %d" % [r_60, r_max], "R11 the bar value and counter follow health_changed (%s)" % bar.get_counter_text())
	check(bar.get_trail_health() > float(r_60), "R12 the damage trail lags behind the bar (%.2f)" % bar.get_trail_health())
	await phys(90)
	check(is_equal_approx(bar.get_trail_health(), float(r_60)), "R13 the damage trail catches up (%.2f)" % bar.get_trail_health())
	p.take_damage(r_60 - r_40)
	await phys(40)
	check(bar.progress_bar.modulate.is_equal_approx(bar.color_gradient.sample(0.4)) and not bar.progress_bar.modulate.is_equal_approx(full_color), "R14 40 percent health switches to the mid colour")
	check(not bar.is_critical(), "R15 40 percent is not critical")
	p.take_damage(r_40 - r_20)
	await phys(40)
	check(bar.is_critical() and bar_clips.current_animation == "critical" and bar_clips.is_playing(), "R16 20 percent health runs the critical clip (got '%s')" % bar_clips.current_animation)
	check(bar.progress_bar.modulate.is_equal_approx(bar.color_gradient.sample(0.2)), "R17 20 percent uses the low colour")
	p.heal(r_60 - r_20)
	await phys(2)
	check(bar_clips.current_animation == "heal", "R18 healing plays the heal clip (got '%s')" % bar_clips.current_animation)
	await phys(40)
	check(is_equal_approx(bar.get_shown_health(), float(r_60)) and not bar.is_critical() and bar_clips.current_animation != "critical", "R19 healing out of the critical range stops the pulse (clip '%s', playing %s, shown %.1f of %d, critical %s)" % [bar_clips.current_animation, str(bar_clips.is_playing()), bar.get_shown_health(), r_60, str(bar.is_critical())])
	p.take_damage(999)
	await phys(5)
	check(bar.is_dead_state() and bar.get_counter_text() == "DEAD" and not bar_clips.is_playing(), "R20 death shows DEAD and stops the clips")
	await cleanup(main)

	# R21-R26: enemy variant (inherited scene).
	main = await fresh()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	p.set_physics_process(false)
	e.set_physics_process(false)
	var base_state := (load("res://UI/HUD/EnemyHealthBar.tscn") as PackedScene).get_state()
	check(base_state.get_node_instance(0) != null and base_state.get_node_instance(0).resource_path == "res://UI/HUD/HealthBar.tscn", "R21 EnemyHealthBar.tscn inherits HealthBar.tscn")
	var ebar: HealthBar = e.get_node("EnemyHealthBar2D")
	check(ebar != null and ebar.hide_until_damaged and ebar.hide_on_death and ebar.get_node(ebar.health_source) == e.health_component, "R22 the enemy bar is bound to the goblin's HealthComponent2D by NodePath")
	check(not ebar.visible, "R23 the enemy bar stays hidden until damaged")
	check(not ebar.get_node("Card/Padding/Content/Header").visible and ebar.get_node("Card/Padding/Content/BarStack/BarLabel").visible, "R24 the compact variant shows the on-bar label instead of the header")
	e.take_damage(1)
	await phys(40)
	var expected_counter := "%d / %d" % [e.health_component.health, e.health_component.max_health]
	check(ebar.visible and ebar.get_counter_text() == expected_counter and is_equal_approx(ebar.get_shown_health(), float(e.health_component.health)), "R25 the first hit reveals the bar and it follows health (%s)" % ebar.get_counter_text())
	check(ebar.get_node("Card/Padding/Content/BarStack/BarLabel").text == expected_counter, "R26 the on-bar label shows the same counter")
	await cleanup(main)

	# ---------- S. Phase 9.1: attacks array and try_start_attack ----------
	main = await fresh()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	e.global_position = p.global_position + Vector2(28, 0)
	var s_ac: AttackComponent2D = p.attack_component
	var s_default_id: StringName = s_ac.definition.id
	check(s_ac.attacks.size() == 2 and e.attack_component.attacks.size() == 1 and e.attack_component.has_attack(&"goblin_lunge"), "S1 the player lists two extra attacks (the combo follow-up and the heavy); the goblin lists one (the lunge)")
	check(s_ac.get_attack_ids().size() == 3 and s_ac.get_attack_ids()[0] == s_default_id and s_ac.get_attack_ids()[1] == &"player_light2" and s_ac.get_attack_ids()[2] == &"player_heavy", "S2 the player's selectable ids are the default attack and its combo follow-up and heavy attack (%s)" % str(s_ac.get_attack_ids()))
	check(s_ac.get_attack(s_default_id) == s_ac.definition and s_ac.has_attack(s_default_id) and s_ac.get_attack(&"") == null and not s_ac.has_attack(&"no_such_attack"), "S3 get_attack finds the default by its id; empty and unknown ids give null")
	check(not s_ac.try_start_attack(&"", Vector2.RIGHT) and not p.context.is_attacking, "S4 an empty id means no attack and starts nothing")
	check(not s_ac.try_start_attack(&"no_such_attack", Vector2.RIGHT) and not p.context.is_attacking, "S5 an unknown id starts nothing")
	check(s_ac.try_start_attack(s_default_id, Vector2.RIGHT) and p.context.is_attacking and s_ac.get_active_attack_id() == s_default_id, "S6 try_start_attack with the default id runs the default attack")
	await phys(70)
	check(not p.context.is_attacking and s_ac.get_active_attack_id() == &"", "S7 the default attack finishes and clears the active id")

	# S8-S10: an extra attack runs through the same lifecycle with its own numbers.
	var s_heavy := definition_variant(s_ac.definition, &"test_heavy")
	s_heavy.damage = 3
	s_heavy.movement_multiplier = 0.3
	s_heavy.cooldown_duration = 1.0
	var s_heavy_list: Array[AttackDefinition2D] = [s_heavy]
	check(s_ac.set_attacks(s_heavy_list) == 1 and s_ac.has_attack(&"test_heavy") and s_ac.get_attack_ids().size() == 2, "S8 set_attacks registers one extra attack (%s)" % str(s_ac.get_attack_ids()))
	await phys(70)
	var s_hp_before: int = e.health_component.health
	check(s_ac.try_start_attack(&"test_heavy", Vector2.RIGHT) and s_ac.get_active_attack_id() == &"test_heavy", "S9 try_start_attack starts the extra attack by id")
	await phys(3)
	check(is_equal_approx(p.context.move_multiplier, 0.3), "S10 the extra attack's movement_multiplier applies while it runs (%.2f)" % p.context.move_multiplier)
	check(not s_ac.try_start_attack(s_default_id, Vector2.RIGHT) and s_ac.get_active_attack_id() == &"test_heavy", "S11 another attack cannot start while one is running")
	var s_waited := 0
	while p.context.is_attacking and s_waited < 200:
		await phys(1)
		s_waited += 1
	check(e.health_component.health == s_hp_before - 3, "S12 the extra attack dealt its own damage (%d -> %d)" % [s_hp_before, e.health_component.health])
	check(is_equal_approx(p.context.move_multiplier, 1.0) and s_ac.get_active_attack_id() == &"", "S13 movement and active id are restored when the extra attack ends")
	check(s_ac.is_on_cooldown() and not s_ac.try_start_attack(s_default_id, Vector2.RIGHT), "S14 the finished attack's cooldown (1 s) blocks every other attack")
	await phys(65)
	check(s_ac.try_start_attack(s_default_id, Vector2.RIGHT), "S15 once the cooldown has passed the default attack starts again")
	p.attack_component.cancel()

	# S16: bad entries are skipped with an error; good ones and the default keep working.
	var s_good_extra := definition_variant(s_ac.definition, &"test_good")
	var s_bad_clip := definition_variant(s_ac.definition, &"test_bad_clip")
	s_bad_clip.weapon_animation = &"no_such_clip"
	var s_duplicate := definition_variant(s_ac.definition, &"test_good")
	var s_no_id := definition_variant(s_ac.definition, &"")
	var s_same_as_default := definition_variant(s_ac.definition, s_default_id)
	var s_mixed: Array[AttackDefinition2D] = [s_good_extra, s_bad_clip, s_duplicate, s_no_id, s_same_as_default, null]
	check(s_ac.set_attacks(s_mixed) == 1 and s_ac.has_attack(&"test_good") and not s_ac.has_attack(&"test_bad_clip") and s_ac.get_attack_ids().size() == 2, "S16 only the valid, unique, named entry is registered (%s)" % str(s_ac.get_attack_ids()))
	check(s_ac.get_attack(&"test_good") == s_good_extra, "S17 the first of two attacks with the same id is kept")

	# S18: swapping the default attack keeps the extras; clearing the list leaves only the default.
	var s_swapped := definition_variant(s_ac.definition, &"test_swapped_default")
	p.attack_definition = s_swapped
	check(s_ac.has_attack(&"test_swapped_default") and s_ac.has_attack(&"test_good") and not s_ac.has_attack(s_default_id), "S18 replacing the default attack keeps the extra attacks (%s)" % str(s_ac.get_attack_ids()))
	var s_none_list: Array[AttackDefinition2D] = []
	check(s_ac.set_attacks(s_none_list) == 0 and s_ac.get_attack_ids().size() == 1, "S19 an empty list leaves only the default attack")
	await cleanup(main)

	# S20: the `attacks` export set on the scene instance is registered when the character starts.
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").queue_free()
	p.queue_free()
	await phys(2)
	var s_scene_player: Character2D = (load("res://player.tscn") as PackedScene).instantiate()
	var s_scene_heavy := definition_variant(load("res://Characters/Components/Combat/DefaultAttackDefinition.tres"), &"scene_heavy")
	var s_scene_list: Array[AttackDefinition2D] = [s_scene_heavy]
	s_scene_player.get_node("AttackComponent2D").attacks = s_scene_list
	# Since 9.7c-4 the player's WeaponController2D equips the sword at startup, which replaces `attacks`;
	# this check is about the component's own list, so the instance gets no starting weapon.
	s_scene_player.get_node("WeaponController2D").starting_weapon = null
	main.add_child(s_scene_player)
	await phys(3)
	check(s_scene_player.attack_component.has_attack(&"scene_heavy") and s_scene_player.attack_component.try_start_attack(&"scene_heavy", Vector2.RIGHT), "S20 an `attacks` list set on the component is registered at startup and selectable")
	await cleanup(main)

	# ---------- T. Phase 9.2a: _get_attack_requested() returns an attack id ----------
	main = await fresh()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	e.global_position = p.global_position + Vector2(200, 0)
	var t_none: Array[AttackDefinition2D] = []
	p.attack_component.set_attacks(t_none) # these checks predate the heavy attack
	var t_id: StringName = p.get_default_attack_id()
	check(t_id != &"" and t_id == p.attack_component.definition.id, "T1 get_default_attack_id() is the attack component's default id (%s)" % str(t_id))
	check(typeof(p._get_attack_requested()) == TYPE_STRING_NAME and p._get_attack_requested() == &"", "T2 with no input the player requests no attack (empty id)")
	await phys(5)
	check(not p.context.is_attacking, "T3 no input starts no swing")
	Input.action_press("attack_light")
	await phys(2)
	Input.action_release("attack_light")
	check(p.context.is_attacking and p.attack_component.get_active_attack_id() == t_id, "T4 pressing attack starts the default attack by its id (active: %s)" % str(p.attack_component.get_active_attack_id()))
	await phys(70)
	check(not p.context.is_attacking and is_equal_approx(p.context.move_multiplier, 1.0), "T5 the swing finishes and movement is restored")
	# T6: the id follows a swapped default attack.
	p.attack_component._cooldown_remaining = 0.0
	var t_swapped := definition_variant(load("res://Characters/Components/Combat/DefaultAttackDefinition.tres"), &"t_swapped")
	check(p.attack_component.set_attack_definition(t_swapped) and p.get_default_attack_id() == &"t_swapped", "T6 the default id follows a swapped definition")
	Input.action_press("attack_light")
	await phys(2)
	Input.action_release("attack_light")
	check(p.attack_component.get_active_attack_id() == &"t_swapped", "T7 pressing attack starts the swapped default attack")
	await phys(70)
	# T8: a dead player requests nothing even while the button is held.
	p.attack_component._cooldown_remaining = 0.0
	p.health_component.apply_hit(HitData.new(100000))
	Input.action_press("attack_light")
	await physics_frame
	check(not p.is_alive() and p._get_attack_requested() == &"", "T8 a dead player requests no attack")
	Input.action_release("attack_light")
	await cleanup(main)
	# T9: the goblin's AI requests its own default attack id and the swing starts through it.
	main = await fresh()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	p.set_physics_process(false)
	set_detection_radius(e, 180.0)
	var t_enemy_id: StringName = e.get_default_attack_id()
	var t_started_ids: Array[StringName] = []
	e.attack_component.attack_started.connect(func(_direction: Vector2) -> void: t_started_ids.append(e.attack_component.get_active_attack_id()))
	e.global_position = p.global_position + Vector2(40, 0)
	await phys(15)
	check(t_enemy_id != &"" and not t_started_ids.is_empty() and t_started_ids[0] == t_enemy_id, "T9 the goblin AI starts its default attack by id (%s)" % str(t_started_ids))
	check(e._ai_controller.consume_attack_request() == &"" and typeof(e._ai_controller.consume_attack_request()) == TYPE_STRING_NAME, "T10 consume_attack_request() returns an empty id once the request has been used")
	await cleanup(main)

	# ---------- U. Phase 9.2b: attack_light / attack_heavy input ----------
	main = await fresh()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	e.global_position = p.global_position + Vector2(200, 0)
	var u_none: Array[AttackDefinition2D] = []
	p.attack_component.set_attacks(u_none) # U4-U5 test the no-heavy path
	var u_light_id: StringName = p.get_default_attack_id()
	var u_has_mouse := false
	for ev in InputMap.action_get_events(&"attack_light"):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			u_has_mouse = true
	check(u_has_mouse and not InputMap.has_action(&"attack"), "U1 attack_light is the left mouse button and the old 'attack' action is gone")
	check(InputMap.has_action(&"attack_heavy") and InputMap.action_get_events(&"attack_heavy").is_empty(), "U2 attack_heavy exists with no default binding")
	check(p.heavy_attack_id == &"" and p.get_heavy_attack_id() == &"player_heavy" and is_equal_approx(p.charge_start_time, 0.1) and p.light_attack_id == &"", "U3 default exports (changed in 9.7d-1): both id overrides empty, the heavy id comes from the equipped sword (player_heavy), charge starts after 0.1 s")
	# U4: no heavy attack registered yet -> light fires on press, attack_heavy is dropped.
	Input.action_press("attack_heavy")
	await phys(3)
	Input.action_release("attack_heavy")
	check(not p.context.is_attacking, "U4 attack_heavy does nothing while the character has no heavy attack")
	Input.action_press("attack_light")
	await phys(2)
	check(p.context.is_attacking and p.attack_component.get_active_attack_id() == u_light_id, "U5 without a heavy attack, attack_light starts the light attack on press, still held")
	Input.action_release("attack_light")
	await phys(70)
	# From here on the player has a heavy attack.
	var u_heavy := definition_variant(load("res://Characters/Components/Combat/DefaultAttackDefinition.tres"), &"player_heavy")
	var u_list: Array[AttackDefinition2D] = [u_heavy]
	check(p.attack_component.set_attacks(u_list) == 1, "U6 the heavy attack registers")
	# U7: a hold shorter than heavy_hold_time starts nothing until release, then the light attack.
	Input.action_press("attack_light")
	await phys(5)
	check(not p.context.is_attacking, "U7 while a press may still become a hold, nothing starts")
	Input.action_release("attack_light")
	await phys(2)
	check(p.context.is_attacking and p.attack_component.get_active_attack_id() == u_light_id, "U8 releasing before heavy_hold_time starts the light attack")
	await phys(70)
	# U9-U11: a hold past charge_start_time begins a charge of the heavy attack; its release lets it go.
	Input.action_press("attack_light")
	await phys(22)
	check(p.attack_component.is_charging() and p.attack_component.get_active_attack_id() == &"", "U9 holding attack_light past charge_start_time begins a charge of the heavy attack, with no swing yet")
	Input.action_release("attack_light")
	await phys(2)
	check(p.context.is_attacking and p.attack_component.get_active_attack_id() == &"player_heavy" and not p.attack_component.is_charging(), "U10 releasing the button releases the charge into the heavy attack (active: %s)" % str(p.attack_component.get_active_attack_id()))
	await phys(110)
	check(not p.context.is_attacking, "U11 after the heavy swing nothing else starts: one hold gives one heavy attack")
	# U12: a shorter charge_start_time begins the charge sooner.
	p.charge_start_time = 0.05
	Input.action_press("attack_light")
	await phys(5)
	check(p.attack_component.is_charging(), "U12 a shorter charge_start_time begins the charge sooner")
	Input.action_release("attack_light")
	await phys(110)
	p.charge_start_time = 0.1
	# U13: attack_heavy charges the heavy directly; its release starts the swing.
	Input.action_press("attack_heavy")
	await phys(2)
	Input.action_release("attack_heavy")
	await phys(2)
	check(p.attack_component.get_active_attack_id() == &"player_heavy", "U13 attack_heavy charges the heavy attack, and its release starts the swing")
	await phys(110)
	# U14: light_attack_id overrides the default attack for the tap.
	p.light_attack_id = &"player_heavy"
	Input.action_press("attack_light")
	await phys(3)
	Input.action_release("attack_light")
	await phys(2)
	check(p.attack_component.get_active_attack_id() == &"player_heavy", "U14 light_attack_id overrides which attack a tap starts (active '%s', light id '%s', cooldown %s, stunned %s, charging %s)" % [str(p.attack_component.get_active_attack_id()), str(p.get_light_attack_id()), str(p.attack_component.is_on_cooldown()), str(p.is_stunned()), str(p.attack_component.is_charging())])
	p.light_attack_id = &""
	await phys(110)
	# U15: a dead player requests nothing, and a hold in progress is dropped.
	Input.action_press("attack_light")
	await phys(3)
	p.health_component.apply_hit(HitData.new(100000))
	await phys(1)
	check(not p.is_alive() and p._get_attack_requested() == &"" and not p._light_held, "U15 a dead player requests nothing and drops the hold in progress")
	Input.action_release("attack_light")
	await cleanup(main)

	# ---------- V. Phase 9.3: the AI chooses between weighted attacks ----------
	main = await fresh()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	p.set_physics_process(false)
	e.set_physics_process(false)
	var v_ai: EnemyAIController2D = e._ai_controller
	var v_default_id: StringName = e.get_default_attack_id()
	var v_default_range: float = e.attack_definition.ai_attack_range
	check(load("res://Characters/Controllers/GoblinBehaviorProfile.tres").attack_choices.size() == 2 and AttackChoice2D.new().weight == 1.0, "V1 the shipped goblin profile offers two weighted choices; a new choice defaults to weight 1")
	check(v_ai.get_chosen_attack_id() == v_default_id and is_equal_approx(v_ai.get_effective_attack_range(), v_default_range), "V2 with no choices the AI uses the default attack and its range (%s, %.0f)" % [str(v_default_id), v_default_range])
	v_ai.profile = v_ai.profile.duplicate() # the shipped profile is a shared resource
	var v_base: AttackDefinition2D = load("res://Characters/Components/Combat/GoblinAttackDefinition.tres")
	var v_short := definition_variant(v_base, &"v_short")
	v_short.ai_attack_range = 20.0
	var v_long := definition_variant(v_base, &"v_long")
	v_long.ai_attack_range = 80.0
	var v_extra: Array[AttackDefinition2D] = [v_short, v_long]
	check(e.attack_component.set_attacks(v_extra) == 2, "V3 the two test attacks register on the goblin")
	var v_choices: Array[AttackChoice2D] = [attack_choice(v_short)]
	v_ai.profile.attack_choices = v_choices
	v_ai.reset_attack_choice()
	check(v_ai.get_chosen_attack_id() == &"v_short" and is_equal_approx(v_ai.get_effective_attack_range(), 20.0), "V4 a single choice is used, and its ai_attack_range becomes the swing distance")
	var v_picks: Array[StringName] = []
	v_choices = [attack_choice(v_short, 0.0), attack_choice(v_long, 1.0)]
	v_ai.profile.attack_choices = v_choices
	for i in 30:
		v_ai.reset_attack_choice()
		v_picks.append(v_ai.get_chosen_attack_id())
	check(v_picks.all(func(id): return id == &"v_long"), "V5 an entry with weight 0 is never picked")
	v_choices = [attack_choice(v_short, 1.0), attack_choice(v_long, 3.0)]
	v_ai.profile.attack_choices = v_choices
	v_ai.rng.seed = 12345
	var v_long_count := 0
	for i in 400:
		v_ai.reset_attack_choice()
		if v_ai.get_chosen_attack_id() == &"v_long":
			v_long_count += 1
	check(v_long_count > 260 and v_long_count < 340, "V6 weights 1 : 3 pick the heavier entry about 75 percent of the time (%d / 400)" % v_long_count)
	v_ai.reset_attack_choice()
	var v_first: StringName = v_ai.get_chosen_attack_id()
	var v_stable := true
	for i in 20:
		v_stable = v_stable and v_ai.get_chosen_attack_id() == v_first
	check(v_stable, "V7 the picked attack is kept until the swing is requested")
	var v_missing := definition_variant(v_base, &"v_missing")
	v_choices = [attack_choice(v_missing, 1.0)]
	v_ai.profile.attack_choices = v_choices
	v_ai.reset_attack_choice()
	check(v_ai.get_chosen_attack_id() == v_default_id, "V8 a choice that is not registered on the attack component falls back to the default attack")
	v_choices = [attack_choice(v_missing, 5.0), attack_choice(v_long, 1.0)]
	v_ai.profile.attack_choices = v_choices
	v_ai.reset_attack_choice()
	check(v_ai.get_chosen_attack_id() == &"v_long", "V9 an unregistered entry is skipped, the usable ones are still picked")
	var v_null_list: Array[AttackChoice2D] = [null, AttackChoice2D.new()]
	v_ai.profile.attack_choices = v_null_list
	v_ai.reset_attack_choice()
	check(v_ai.get_chosen_attack_id() == v_default_id, "V10 null entries and entries without an attack are ignored")
	v_choices = [attack_choice(v_short, 0.0), attack_choice(v_long, 0.0)]
	v_ai.profile.attack_choices = v_choices
	v_ai.reset_attack_choice()
	check(v_ai.get_chosen_attack_id() == v_default_id, "V11 when every weight is 0 the default attack is used")
	await cleanup(main)
	# V12/V13: end to end. The goblin walks until it is inside the CHOSEN attack's range, swings with it, and picks again.
	main = await fresh()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	p.set_physics_process(false)
	set_detection_radius(e, 180.0)
	v_ai = e._ai_controller
	v_ai.profile = v_ai.profile.duplicate()
	v_base = load("res://Characters/Components/Combat/GoblinAttackDefinition.tres")
	v_short = definition_variant(v_base, &"v_short")
	v_short.ai_attack_range = 20.0
	v_long = definition_variant(v_base, &"v_long")
	v_long.ai_attack_range = 80.0
	v_extra = [v_short, v_long]
	e.attack_component.set_attacks(v_extra)
	v_choices = [attack_choice(v_long, 1.0)]
	v_ai.profile.attack_choices = v_choices
	v_ai.reset_attack_choice()
	var v_started: Array[StringName] = []
	e.attack_component.attack_started.connect(func(_direction: Vector2) -> void: v_started.append(e.attack_component.get_active_attack_id()))
	e.global_position = p.global_position + Vector2(70, 0)
	await phys(15)
	check(not v_started.is_empty() and v_started[0] == &"v_long" and e.global_position.distance_to(p.global_position) > v_default_range, "V12 the goblin swings with the chosen attack from beyond the default range (%s, %.0f px)" % [str(v_started), e.global_position.distance_to(p.global_position)])
	v_choices = [attack_choice(v_short, 1.0)]
	v_ai.profile.attack_choices = v_choices
	v_ai.reset_attack_choice()
	e.global_position = p.global_position + Vector2(15, 0)
	await phys(160)
	check(v_started.has(&"v_short") and v_started[v_started.size() - 1] == &"v_short", "V13 after the choices change, the next swings use the new pick (%s)" % str(v_started))
	await cleanup(main)

	# ---------- W. Phase 9.4a: next_attack links (validation only, no chaining yet) ----------
	main = await fresh()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	var w_ac: AttackComponent2D = p.attack_component
	var w_base: AttackDefinition2D = w_ac.definition
	var w_first := definition_variant(w_base, &"w_first")
	var w_second := definition_variant(w_base, &"w_second")
	var w_orphan := definition_variant(w_base, &"w_orphan")
	var w_extras: Array[AttackDefinition2D] = [w_second]
	check(AttackDefinition2D.new().next_attack == null and w_first.next_attack == null, "W1 a new attack has no next_attack unless one is set")
	w_first.next_attack = w_second
	check(w_ac.set_attack_definition(w_first) and w_ac.set_attacks(w_extras) == 1, "W2a the default attack and a registered extra attack are set up")
	check(w_ac.validate_combo_links().is_empty() and w_ac.get_next_attack(w_first) == w_second, "W2b a link to a registered attack is valid and resolves to that attack")
	w_second.next_attack = w_orphan
	var w_problems := w_ac.validate_combo_links()
	check(w_problems.size() == 1 and w_problems[0].contains("not registered") and w_ac.get_next_attack(w_second) == null, "W3 a link to an unregistered attack is reported and never followed (%s)" % str(w_problems))
	w_second.next_attack = w_second
	w_problems = w_ac.validate_combo_links()
	check(w_problems.is_empty() and w_ac.get_next_attack(w_second) == null, "W4 a link to itself is valid: it means repeat, and is never followed as an explicit link (9.6a)")
	w_second.next_attack = w_orphan
	check(w_ac.try_start_attack(&"w_second", Vector2.RIGHT) and p.context.is_attacking, "W5a an attack with a bad link still starts normally")
	w_ac.cancel()
	check(not p.context.is_attacking and w_ac.get_active_attack_id() == &"", "W5b cancel() ends the swing")
	w_second.next_attack = w_first
	check(w_ac.validate_combo_links().is_empty() and w_ac.get_next_attack(w_second) == w_first, "W6 a link back to the default attack is valid (cycles are allowed)")
	var w_shipped: AttackDefinition2D = load("res://Characters/Components/Combat/DefaultAttackDefinition.tres")
	var w_goblin: AttackDefinition2D = load("res://Characters/Components/Combat/GoblinAttackDefinition.tres")
	check(w_shipped.next_attack != null and w_shipped.next_attack.id == &"player_light2" and w_goblin.next_attack == null and e.attack_component.validate_combo_links().is_empty(), "W7 the shipped player attack links to player_light2 and the goblin has no link")
	await cleanup(main)

	# ---------- X. Phase 9.4b: combo window state (tracked only, no chaining yet) ----------
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	var x_ac: AttackComponent2D = p.attack_component
	check(not x_ac.is_combo_window_open(), "X1 the window is closed when nothing is running")
	p.attack_event(&"combo_window_open")
	check(not x_ac.is_combo_window_open(), "X2 a window event with no swing running does nothing")
	x_ac.try_start_attack(x_ac.definition.id, Vector2.RIGHT)
	check(p.context.is_attacking and not x_ac.is_combo_window_open(), "X3 a new swing starts with the window closed")
	p.attack_event(&"combo_window_open")
	check(x_ac.is_combo_window_open(), "X4 combo_window_open opens the window during the swing")
	p.attack_event(&"combo_window_close")
	check(p.context.is_attacking and not x_ac.is_combo_window_open(), "X5 combo_window_close closes it and the swing goes on")
	p.attack_event(&"combo_window_open")
	x_ac.cancel()
	check(not x_ac.is_combo_window_open(), "X6 cancel() closes the window")
	x_ac.try_start_attack(x_ac.definition.id, Vector2.RIGHT)
	p.attack_event(&"combo_window_open")
	var x_weapon: StringName = x_ac.definition.weapon_animation
	var x_guard := 0
	while p.context.weapon_animation_player.current_animation == x_weapon and x_guard < 200:
		await physics_frame
		x_guard += 1
	check(p.context.is_attacking and p.context.weapon_animation_player.current_animation != x_weapon and not x_ac.is_combo_window_open(), "X7 the window closes when the weapon clip ends and recovery starts")
	p.attack_event(&"combo_window_open")
	check(not x_ac.is_combo_window_open(), "X8 window events during the recovery clip are ignored")
	x_guard = 0
	while p.context.is_attacking and x_guard < 200:
		await physics_frame
		x_guard += 1
	check(not p.context.is_attacking and not x_ac.is_combo_window_open(), "X9 the window is closed when the swing finishes")
	var x_goblin_ac: AttackComponent2D = e.attack_component
	x_goblin_ac.try_start(true, Vector2.RIGHT)
	e.attack_event(&"combo_window_open")
	check(x_goblin_ac.is_combo_window_open(), "X10 the goblin's window opens too")
	e.take_damage(1)
	check(not e.context.is_attacking and not x_goblin_ac.is_combo_window_open(), "X11 an interrupted swing closes the window")
	await cleanup(main)

	# ---------- Y. Phase 9.4c: chaining inside the combo window ----------
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	var y_ac: AttackComponent2D = p.attack_component
	var y_base: AttackDefinition2D = y_ac.definition
	var y_first := definition_variant(y_base, &"y_first")
	var y_second := definition_variant(y_base, &"y_second")
	y_second.damage = 3
	y_second.interruptible = true
	y_first.next_attack = y_second
	var y_extras: Array[AttackDefinition2D] = [y_second]
	y_ac.set_attack_definition(y_first)
	y_ac.set_attacks(y_extras)
	var y_started: Array[StringName] = []
	var y_finished := [0]
	var y_chained: Array = []
	y_ac.attack_started.connect(func(_d: Vector2) -> void: y_started.append(y_ac.get_active_attack_id()))
	y_ac.attack_finished.connect(func() -> void: y_finished[0] += 1)
	y_ac.attack_chained.connect(func(a: StringName, b: StringName) -> void: y_chained.append([a, b]))
	check(y_ac.try_start_attack(&"y_first", Vector2.RIGHT) and p.context.is_attacking, "Y1 the first attack starts")
	check(not y_ac.try_start_attack(&"y_second", Vector2.RIGHT) and y_ac.get_active_attack_id() == &"y_first" and y_started.size() == 1, "Y2 outside the window a request does not chain (normal gating applies)")
	p.attack_event(&"combo_window_open")
	check(y_ac.try_start_attack(&"y_first", Vector2.LEFT), "Y3a a request inside the window is accepted")
	check(y_ac.get_active_attack_id() == &"y_second" and p.context.is_attacking and not y_ac.is_combo_window_open(), "Y3b the request chains into next_attack and the window closes")
	check(y_started.size() == 2 and y_started[0] == &"y_first" and y_started[1] == &"y_second" and y_chained.size() == 1 and y_chained[0] == [&"y_first", &"y_second"], "Y4 attack_started fires per link, attack_chained once (started %s, chained %s)" % [str(y_started), str(y_chained)])
	check(y_finished[0] == 0 and not y_ac.is_on_cooldown(), "Y5 the chain does not finish or start a cooldown mid-chain (finished %d)" % y_finished[0])
	check(p.context.attack_direction.is_equal_approx(Vector2.LEFT), "Y6 the chained link uses the direction of the request (%s)" % str(p.context.attack_direction))
	p.attack_event(&"combo_window_open")
	check(y_ac.try_start_attack(&"y_first", Vector2.RIGHT) and y_ac.get_active_attack_id() == &"y_first" and y_started.size() == 3, "Y7 a press in the window of the last link starts the combo again from its first attack (9.R2; was: repeat the last link)")
	var y_guard := 0
	while p.context.is_attacking and y_guard < 200:
		await physics_frame
		y_guard += 1
	check(not p.context.is_attacking and y_finished[0] == 1, "Y8 the whole chain finishes once (attack_finished count %d)" % y_finished[0])
	await phys(15)
	check(y_ac.try_start_attack(&"y_first", Vector2.RIGHT) and y_ac.get_active_attack_id() == &"y_first", "Y9a a new chain can start after the previous one has ended and the cooldown has passed")
	p.attack_event(&"combo_window_open")
	check(y_ac.try_start_attack(&"y_first", Vector2.RIGHT) and y_ac.get_active_attack_id() == &"y_second", "Y9b the second chain works the same way")
	p.take_damage(1)
	check(not p.context.is_attacking and y_ac.get_active_attack_id() == &"", "Y10 a hit on the chained link interrupts it (it is interruptible)")
	await cleanup(main)

	# ---------- Z. Phase 9.4d: the player's own requests chain (no controller change needed) ----------
	# Headless tests cannot press a key, so these checks use the ids the controller sends and the
	# per-frame empty request that Character2D makes with no input.
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	var z_ac: AttackComponent2D = p.attack_component
	var z_base: AttackDefinition2D = z_ac.definition
	var z_first := definition_variant(z_base, &"z_first")
	var z_second := definition_variant(z_base, &"z_second")
	var z_heavy := definition_variant(z_base, &"player_heavy")
	z_heavy.damage = 4
	z_first.next_attack = z_second
	var z_extras: Array[AttackDefinition2D] = [z_second, z_heavy]
	z_ac.set_attack_definition(z_first)
	z_ac.set_attacks(z_extras)
	check(p.get_default_attack_id() == &"z_first" and p.light_attack_id == &"" and p.get_heavy_attack_id() == &"player_heavy", "Z1 the controller sends the default attack id for a light press and the equipped weapon's heavy (player_heavy) for a heavy one")
	check(z_ac.try_start_attack(p.get_default_attack_id(), Vector2.RIGHT) and z_ac.get_active_attack_id() == &"z_first", "Z2 the light request starts the first attack")
	p.attack_event(&"combo_window_open")
	await phys(3)
	check(z_ac.get_active_attack_id() == &"z_first" and z_ac.is_combo_window_open(), "Z3 the per-frame empty request with no input does not chain")
	check(z_ac.try_start_attack(p.get_default_attack_id(), Vector2.RIGHT) and z_ac.get_active_attack_id() == &"z_second", "Z4 the light request chains into next_attack inside the window")
	var z_guard := 0
	while p.context.is_attacking and z_guard < 200:
		await physics_frame
		z_guard += 1
	await phys(15)
	check(z_ac.try_start_attack(&"z_first", Vector2.RIGHT) and z_ac.get_active_attack_id() == &"z_first", "Z5a a new first attack starts after the chain ended")
	p.attack_event(&"combo_window_open")
	check(z_ac.try_start_attack(p.get_heavy_attack_id(), Vector2.RIGHT) and z_ac.get_active_attack_id() == &"z_second", "Z5b the heavy request inside the window chains too (any attack request does)")
	await cleanup(main)

	# ---------- AA. Phase 9.4e: the shipped player scene chains for real ----------
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	var aa_ac: AttackComponent2D = p.attack_component
	var aa_ap: AnimationPlayer = p.context.weapon_animation_player
	var aa_slash: Animation = aa_ap.get_animation(&"sword_slash_1")
	var aa_open_at := -1.0
	var aa_close_at := -1.0
	for aa_t in aa_slash.get_track_count():
		if aa_slash.track_get_type(aa_t) != Animation.TYPE_METHOD:
			continue
		for aa_k in aa_slash.track_get_key_count(aa_t):
			var aa_params: Array = aa_slash.method_track_get_params(aa_t, aa_k)
			if aa_params[0] == &"combo_window_open":
				aa_open_at = aa_slash.track_get_key_time(aa_t, aa_k)
			if aa_params[0] == &"combo_window_close":
				aa_close_at = aa_slash.track_get_key_time(aa_t, aa_k)
	check(aa_ap.has_animation(&"sword_slash_2") and aa_open_at > 0.0 and aa_close_at > aa_open_at and aa_close_at <= aa_slash.length, "AA1 the slash clip opens and closes the combo window inside its length (open %.2f, close %.2f, length %.2f)" % [aa_open_at, aa_close_at, aa_slash.length])
	var aa_next := aa_ac.get_next_attack(aa_ac.definition)
	check(aa_ac.validate_combo_links().is_empty() and aa_next != null and aa_next.id == &"player_light2", "AA2 the shipped player links player_light to player_light2 and the links validate")
	check(aa_ac.try_start_attack(p.get_default_attack_id(), Vector2.RIGHT), "AA3a the shipped light attack starts")
	var aa_guard := 0
	while aa_ap.current_animation_position < aa_open_at + 0.03 and aa_guard < 120:
		await physics_frame
		aa_guard += 1
	check(aa_ac.is_combo_window_open(), "AA3b the window opens from the clip's own key (now at %.2fs, opens at %.2fs)" % [aa_ap.current_animation_position, aa_open_at])
	check(aa_ac.try_start_attack(p.get_default_attack_id(), Vector2.RIGHT) and aa_ac.get_active_attack_id() == &"player_light2", "AA3c a press inside the window chains into player_light2 (active: %s)" % str(aa_ac.get_active_attack_id()))
	await cleanup(main)

	# ---------- BB. Phase 9.5a: the player's heavy attack, driven by the real input ----------
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	var bb_ac: AttackComponent2D = p.attack_component
	var bb_light: AttackDefinition2D = bb_ac.definition
	var bb_heavy: AttackDefinition2D = bb_ac.get_attack(&"player_heavy")
	var bb_ap: AnimationPlayer = p.context.weapon_animation_player
	check(bb_heavy != null and bb_ac.validate_combo_links().is_empty() and bb_ap.has_animation(&"sword_heavy_slash") and bb_heavy.weapon_animation == &"sword_heavy_slash" and bb_heavy.charge_animation == &"sword_charge_heavy_slash" and bb_heavy.recovery_animation == &"sword_slash_return_1", "BB1 the heavy attack is registered and its clip exists on the weapon player")
	check(bb_heavy.damage > bb_light.damage and bb_heavy.movement_multiplier <= bb_light.movement_multiplier and bb_heavy.knockback > bb_light.knockback and bb_heavy.charge_animation != &"", "BB2 the heavy hits harder, pushes further, never moves faster than the light attack, and has a charge clip the light attack does not")
	Input.action_press("attack_light")
	await phys(22)
	check(bb_ac.is_charging() and bb_ac.get_active_attack_id() == &"", "BB3a holding attack_light past charge_start_time begins the heavy charge, with no swing yet")
	check(is_equal_approx(p.context.move_multiplier, bb_heavy.movement_multiplier), "BB3b the heavy attack slows movement to its movement_multiplier (%.2f)" % p.context.move_multiplier)
	Input.action_release("attack_light")
	var bb_guard := 0
	while p.context.is_attacking and bb_guard < 200:
		await physics_frame
		bb_guard += 1
	check(not p.context.is_attacking and is_equal_approx(p.context.move_multiplier, 1.0), "BB4 the heavy swing finishes and movement is restored")
	await phys(20)
	Input.action_press("attack_light")
	await phys(2)
	Input.action_release("attack_light")
	await phys(2)
	check(p.context.is_attacking and bb_ac.get_active_attack_id() == &"player_light", "BB5 a quick tap still starts the light attack, on release (active: %s)" % str(bb_ac.get_active_attack_id()))
	await cleanup(main)

	# BB6: the heavy hits a goblin in reach for its own damage.
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	e.global_position = p.global_position + Vector2(28, 0)
	bb_ac = p.attack_component
	bb_heavy = bb_ac.get_attack(&"player_heavy")
	var bb_hp: int = e.health_component.health
	check(bb_ac.try_start_attack(&"player_heavy", Vector2.RIGHT), "BB6a the heavy attack starts by its id")
	await phys(90)
	check(e.health_component.health == bb_hp - bb_heavy.damage, "BB6b the heavy hits the goblin for its own damage (took %d, expected %d)" % [bb_hp - e.health_component.health, bb_heavy.damage])
	await cleanup(main)

	# ---------- CC. Phase 9.5b: the goblin lunge and the weighted AI choice (shipped data) ----------
	main = await fresh_shipped()
	e = main.get_node("BasicEnemy2D")
	p = main.get_node("Player")
	p.set_physics_process(false)
	e.set_physics_process(false)
	var cc_ai: EnemyAIController2D = e._ai_controller
	var cc_ac: AttackComponent2D = e.attack_component
	var cc_slash: AttackDefinition2D = e.attack_definition
	var cc_lunge: AttackDefinition2D = cc_ac.get_attack(&"goblin_lunge")
	var cc_ap: AnimationPlayer = e.context.weapon_animation_player
	check(cc_lunge != null and cc_ac.validate_combo_links().is_empty() and cc_ap.has_animation(&"lunge") and cc_lunge.weapon_animation == &"lunge" and cc_ai.profile.attack_choices.size() == 2, "CC1 the goblin has a registered lunge with its clip, and its profile offers two weighted choices")
	check(cc_lunge.movement_multiplier < 1.0 and cc_lunge.ai_attack_range > cc_slash.ai_attack_range and cc_lunge.damage > cc_slash.damage and cc_lunge.interruptible, "CC2 the lunge slows the goblin, reaches further, hits harder and can be interrupted like its slash")
	cc_ai.rng.seed = 7
	var cc_lunges := 0
	for i in 400:
		cc_ai.reset_attack_choice()
		if cc_ai.get_chosen_attack_id() == &"goblin_lunge":
			cc_lunges += 1
	check(cc_lunges > 60 and cc_lunges < 140, "CC3 weights 3 : 1 pick the lunge about a quarter of the time (%d / 400)" % cc_lunges)
	await cleanup(main)

	# CC4-CC5: a goblin that may only lunge, 72 px away: beyond the slash's range, inside the lunge's.
	main = await fresh_shipped()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	p.set_physics_process(false)
	set_detection_radius(e, 180.0)
	cc_ai = e._ai_controller
	cc_ai.profile = cc_ai.profile.duplicate()
	var cc_only_lunge: Array[AttackChoice2D] = [attack_choice(e.attack_component.get_attack(&"goblin_lunge"), 1.0)]
	cc_ai.profile.attack_choices = cc_only_lunge
	cc_ai.reset_attack_choice()
	var cc_started: Array[StringName] = []
	e.attack_component.attack_started.connect(func(_d: Vector2) -> void: cc_started.append(e.attack_component.get_active_attack_id()))
	e.global_position = p.global_position + Vector2(72, 0)
	await phys(15)
	check(not cc_started.is_empty() and cc_started[0] == &"goblin_lunge", "CC4 at 72 px, beyond the slash's range but inside the lunge's, the goblin lunges (%s)" % str(cc_started))
	check(e.context.is_attacking and is_equal_approx(e.context.move_multiplier, cc_lunge.movement_multiplier), "CC5 during the lunge the goblin moves at the lunge's movement_multiplier (%.2f)" % e.context.move_multiplier)
	await cleanup(main)

	# ---------- DD. Phase 9.6a: looping combo sequences, repeat, and resets ----------
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	var dd_ac: AttackComponent2D = p.attack_component
	var dd_base: AttackDefinition2D = dd_ac.definition
	var dd_1 := definition_variant(dd_base, &"dd_1")
	var dd_2 := definition_variant(dd_base, &"dd_2")
	var dd_3 := definition_variant(dd_base, &"dd_3")
	for dd_a in [dd_1, dd_2, dd_3]:
		dd_a.interruptible = true
	var dd_rest: Array[AttackDefinition2D] = [dd_2, dd_3]
	var dd_loop: Array[AttackDefinition2D] = [dd_1, dd_2, dd_3]
	dd_1.combo_sequence = dd_loop
	dd_ac.set_attack_definition(dd_1)
	dd_ac.set_attacks(dd_rest)
	check(dd_ac.validate_combo_links().is_empty(), "DD1a a looping sequence whose entries are registered validates")
	var dd_orphan := definition_variant(dd_base, &"dd_orphan")
	var dd_bad: Array[AttackDefinition2D] = [dd_1, dd_orphan]
	dd_1.combo_sequence = dd_bad
	var dd_problems := dd_ac.validate_combo_links()
	check(dd_problems.size() == 1 and dd_problems[0].contains("not registered"), "DD1b an unregistered sequence entry is reported (%s)" % str(dd_problems))
	var dd_wrong_start: Array[AttackDefinition2D] = [dd_2, dd_3]
	dd_1.combo_sequence = dd_wrong_start
	dd_problems = dd_ac.validate_combo_links()
	check(dd_problems.size() == 1 and dd_problems[0].contains("must start with"), "DD1c a sequence must start with the attack itself (%s)" % str(dd_problems))
	dd_1.combo_sequence = dd_loop

	# DD2: the loop 1 -> 2 -> 3 -> 1, one press per link.
	var dd_seen: Array[StringName] = []
	dd_ac.try_start_attack(&"dd_1", Vector2.RIGHT)
	dd_seen.append(dd_ac.get_active_attack_id())
	for dd_i in 3:
		p.attack_event(&"combo_window_open")
		dd_ac.try_start_attack(&"dd_1", Vector2.RIGHT)
		dd_seen.append(dd_ac.get_active_attack_id())
	check(str(dd_seen) == str([&"dd_1", &"dd_2", &"dd_3", &"dd_1"]), "DD2 the sequence loops 1 -> 2 -> 3 -> 1 (%s)" % str(dd_seen))
	var dd_guard := 0
	while p.context.is_attacking and dd_guard < 200:
		await physics_frame
		dd_guard += 1
	await phys(15)

	# DD3: an attack with no sequence and no link repeats itself.
	var dd_solo := definition_variant(dd_base, &"dd_solo")
	dd_ac.set_attack_definition(dd_solo)
	dd_ac.try_start_attack(&"dd_solo", Vector2.RIGHT)
	p.attack_event(&"combo_window_open")
	check(dd_ac.try_start_attack(&"dd_solo", Vector2.RIGHT) and dd_ac.get_active_attack_id() == &"dd_solo", "DD3 an attack with no sequence or link repeats itself inside its window")
	dd_guard = 0
	while p.context.is_attacking and dd_guard < 200:
		await physics_frame
		dd_guard += 1
	await phys(15)

	# DD4: a finished combo restarts at the beginning of its sequence.
	dd_ac.set_attack_definition(dd_1)
	dd_ac.try_start_attack(&"dd_1", Vector2.RIGHT)
	p.attack_event(&"combo_window_open")
	dd_ac.try_start_attack(&"dd_1", Vector2.RIGHT)
	dd_guard = 0
	while p.context.is_attacking and dd_guard < 200:
		await physics_frame
		dd_guard += 1
	await phys(15)
	dd_ac.try_start_attack(&"dd_1", Vector2.RIGHT)
	p.attack_event(&"combo_window_open")
	dd_ac.try_start_attack(&"dd_1", Vector2.RIGHT)
	check(dd_ac.get_active_attack_id() == &"dd_2", "DD4 a new combo after a finished one starts at the beginning of the sequence (active: %s)" % str(dd_ac.get_active_attack_id()))
	dd_guard = 0
	while p.context.is_attacking and dd_guard < 200:
		await physics_frame
		dd_guard += 1
	await phys(15)

	# DD5: a hit that interrupts the combo ends it; the next combo starts at the beginning.
	dd_ac.try_start_attack(&"dd_1", Vector2.RIGHT)
	p.attack_event(&"combo_window_open")
	dd_ac.try_start_attack(&"dd_1", Vector2.RIGHT)
	p.take_damage(1)
	check(not p.context.is_attacking, "DD5a a hit interrupts the chained attack and ends the combo")
	await phys(15)
	dd_ac.try_start_attack(&"dd_1", Vector2.RIGHT)
	p.attack_event(&"combo_window_open")
	dd_ac.try_start_attack(&"dd_1", Vector2.RIGHT)
	check(dd_ac.get_active_attack_id() == &"dd_2", "DD5b the next combo after an interrupt starts at the beginning of the sequence (active: %s)" % str(dd_ac.get_active_attack_id()))
	await cleanup(main)

	# ---------- EE. Phase 9.6b: the return starts when the combo window closes with no press ----------
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	var ee_ac: AttackComponent2D = p.attack_component
	var ee_ap: AnimationPlayer = p.context.weapon_animation_player
	ee_ac.try_start_attack(ee_ac.definition.id, Vector2.RIGHT)
	p.attack_event(&"combo_window_open")
	p.attack_event(&"combo_window_close")
	check(p.context.is_attacking and ee_ap.current_animation == &"sword_slash_return_1", "EE1 closing the window with no press starts the return at once (now: %s)" % ee_ap.current_animation)
	check(not ee_ac.try_start_attack(ee_ac.definition.id, Vector2.RIGHT) and ee_ac.get_active_attack_id() == ee_ac.definition.id, "EE2 a press after the window has closed does not chain")
	await cleanup(main)

	# EE3: with the real clip, the return starts at the clip's own combo_window_close key, not at the end of the clip.
	# (V2a: the old expectation 0.2 to 0.28 s was written for an earlier slash clip; sword_slash_1 closes at 0.4167 s of 0.5 s.)
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	ee_ac = p.attack_component
	ee_ap = p.context.weapon_animation_player
	ee_ac.try_start_attack(ee_ac.definition.id, Vector2.RIGHT)
	var ee_last := 0.0
	var ee_guard := 0
	while ee_ap.current_animation == &"sword_slash_1" and ee_guard < 200:
		ee_last = ee_ap.current_animation_position
		await physics_frame
		ee_guard += 1
	var ee_clip: Animation = ee_ap.get_animation(&"sword_slash_1")
	var ee_close := window_close_time(ee_clip)
	check(ee_close > 0.0 and ee_clip.length - ee_close > 0.02 and ee_ap.current_animation == &"sword_slash_return_1" and ee_last >= ee_close - 0.05 and ee_last <= ee_close + 0.03, "EE3 the return starts at the clip's own close key, not at the end of the clip (cut at %.2fs, close key %.2fs, clip length %.2fs)" % [ee_last, ee_close, ee_clip.length])
	await cleanup(main)

	# EE4: an attack with no return clip ends at once when its window closes.
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	ee_ac = p.attack_component
	var ee_noret := definition_variant(ee_ac.definition, &"ee_noret")
	ee_noret.recovery_animation = &""
	ee_ac.set_attack_definition(ee_noret)
	ee_ac.try_start_attack(&"ee_noret", Vector2.RIGHT)
	p.attack_event(&"combo_window_open")
	p.attack_event(&"combo_window_close")
	check(not p.context.is_attacking, "EE4 an attack with no return clip ends at once when its window closes")
	await cleanup(main)

	# ---------- FF. Phase 9.6c: heavy charge and release modes (component API; player wiring is 9.6d) ----------
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	var ff_ac: AttackComponent2D = p.attack_component
	var ff_base: AttackDefinition2D = ff_ac.definition
	var ff_input := definition_variant(ff_base, &"ff_input")
	ff_input.charge_animation = &"idle"
	ff_input.release_mode = AttackDefinition2D.ReleaseMode.INPUT_RELEASE
	var ff_thresh := definition_variant(ff_base, &"ff_thresh")
	ff_thresh.charge_animation = &"idle"
	ff_thresh.release_mode = AttackDefinition2D.ReleaseMode.THRESHOLD
	ff_thresh.charge_threshold = 0.5
	var ff_extras: Array[AttackDefinition2D] = [ff_input, ff_thresh]
	ff_ac.set_attacks(ff_extras)
	var ff_nothr := definition_variant(ff_base, &"ff_nothr")
	ff_nothr.release_mode = AttackDefinition2D.ReleaseMode.THRESHOLD
	ff_nothr.charge_threshold = 0.0
	var ff_noclip := definition_variant(ff_base, &"ff_noclip")
	ff_noclip.charge_animation = &"no_such_clip"
	check(ff_ac.validate_definition(ff_thresh) == "", "FF1a a THRESHOLD attack with a threshold and a known charge clip validates")
	check(ff_ac.validate_definition(ff_nothr).contains("charge_threshold"), "FF1b a THRESHOLD attack needs a charge_threshold above 0")
	check(ff_ac.validate_definition(ff_noclip).contains("charge_animation"), "FF1c a missing charge clip is reported by name")
	var ff_started := [0]
	ff_ac.attack_started.connect(func(_d: Vector2) -> void: ff_started[0] += 1)
	check(ff_ac.begin_charge(&"ff_input", Vector2.RIGHT) and ff_ac.is_charging() and p.context.is_attacking and p.context.weapon_animation_player.current_animation == &"idle" and ff_started[0] == 0, "FF2 begin_charge holds the character in the charge, plays the charge clip, and starts no swing yet")
	await phys(60)
	check(ff_ac.is_charging() and ff_ac.get_charge_time() > 0.9, "FF3 an INPUT_RELEASE charge is held, with no automatic release (charged %.2fs)" % ff_ac.get_charge_time())
	check(ff_ac.release_charge() and ff_ac.get_active_attack_id() == &"ff_input" and ff_started[0] == 1 and not ff_ac.is_charging(), "FF4 release_charge() turns the charge into its swing (started %d)" % ff_started[0])
	var ff_guard := 0
	while p.context.is_attacking and ff_guard < 200:
		await physics_frame
		ff_guard += 1
	await phys(15)
	check(ff_ac.begin_charge(&"ff_thresh", Vector2.RIGHT), "FF5a a THRESHOLD charge starts")
	var ff_last := 0.0
	ff_guard = 0
	while ff_ac.is_charging() and ff_guard < 120:
		ff_last = ff_ac.get_charge_time()
		await physics_frame
		ff_guard += 1
	check(not ff_ac.is_charging() and ff_ac.get_active_attack_id() == &"ff_thresh" and ff_last >= 0.44 and ff_last <= 0.52, "FF5b a THRESHOLD charge releases by itself at its threshold, with no input (charged %.2fs)" % ff_last)
	check(not ff_ac.release_charge() and ff_ac.get_active_attack_id() == &"ff_thresh", "FF6 releasing after a threshold release does nothing")
	ff_guard = 0
	while p.context.is_attacking and ff_guard < 200:
		await physics_frame
		ff_guard += 1
	await phys(15)
	ff_ac.begin_charge(&"ff_input", Vector2.RIGHT)
	p.take_damage(1)
	check(ff_ac.is_charging(), "FF7 a hit does not cancel a charge of an attack that is not interruptible")
	ff_ac.cancel()
	check(not ff_ac.is_charging() and not p.context.is_attacking and not ff_ac.release_charge(), "FF8 cancel() ends a charge, and a release after it does nothing")
	ff_ac.try_start_attack(&"ff_input", Vector2.RIGHT)
	check(not ff_ac.begin_charge(&"ff_thresh", Vector2.RIGHT) and not ff_ac.is_charging(), "FF9 a charge cannot start while a swing is running")
	await cleanup(main)

	# ---------- GG. Phase 9.6d: the player wires press, hold and release to the charge ----------
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	check(is_equal_approx(p.charge_start_time, 0.1) and p.get_heavy_attack_id() == &"player_heavy", "GG1 the controller exports a 0.1 s charge start and takes the heavy attack id from the equipped weapon")
	Input.action_press("attack_light")
	await phys(10)
	check(p.attack_component.is_charging() and p.attack_component.get_active_attack_id() == &"", "GG2 holding attack_light begins a charge of the heavy attack")
	Input.action_release("attack_light")
	await phys(2)
	check(p.attack_component.get_active_attack_id() == &"player_heavy" and not p.attack_component.is_charging(), "GG3 releasing the held button releases the heavy charge into its swing")
	var gg_guard := 0
	while p.context.is_attacking and gg_guard < 200:
		await physics_frame
		gg_guard += 1
	await phys(20)
	Input.action_press("attack_light")
	await phys(3)
	Input.action_release("attack_light")
	await phys(2)
	check(p.attack_component.get_active_attack_id() == p.get_default_attack_id() and not p.attack_component.is_charging(), "GG4 a tap under 0.1 s is the light attack, sent on release")
	gg_guard = 0
	while p.context.is_attacking and gg_guard < 200:
		await physics_frame
		gg_guard += 1
	await phys(20)
	var gg_thresh := definition_variant(p.attack_component.get_attack(&"player_heavy"), &"player_heavy")
	gg_thresh.release_mode = AttackDefinition2D.ReleaseMode.THRESHOLD
	gg_thresh.charge_threshold = 0.4
	gg_thresh.charge_animation = &"idle"
	var gg_list: Array[AttackDefinition2D] = [gg_thresh]
	p.attack_component.set_attacks(gg_list)
	Input.action_press("attack_light")
	await phys(40)
	check(not p.attack_component.is_charging() and p.attack_component.get_active_attack_id() == &"player_heavy", "GG5a a THRESHOLD heavy releases by itself while the button is still held")
	Input.action_release("attack_light")
	await phys(2)
	check(p.attack_component.get_active_attack_id() == &"player_heavy" and not p.attack_component.is_charging(), "GG5b releasing afterwards adds nothing: the heavy swing carries on")
	gg_guard = 0
	while p.context.is_attacking and gg_guard < 200:
		await physics_frame
		gg_guard += 1
	await cleanup(main)

	# GG6: a press held into the combo window is too long to be a tap, but its charge is refused
	# (a swing is running), so its release is a light attack, which chains.
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	p.attack_component.try_start_attack(p.get_default_attack_id(), Vector2.RIGHT)
	Input.action_press("attack_light")
	# V2a: the press is released one frame after the combo window opens (sword_slash_1 opens it at 0.25 s,
	# 15 frames in; the old fixed 12-frame hold released before the window existed).
	var gg6_guard := 0
	while not p.attack_component.is_combo_window_open() and gg6_guard < 120:
		await physics_frame
		gg6_guard += 1
	await phys(1)
	Input.action_release("attack_light")
	await phys(2)
	check(p.attack_component.get_active_attack_id() == &"player_light2" and not p.attack_component.is_charging(), "GG6 a press held into the combo window chains as the light attack, not as a charge (active: %s)" % str(p.attack_component.get_active_attack_id()))
	await cleanup(main)

	# ---------- HH. Phase 9.R2: light combo flow with the real clips, return rules, heavy release ----------
	# HH1-HH5: light -> light2 -> (restart) light, driven only by presses inside the real windows.
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	var hh_ac: AttackComponent2D = p.attack_component
	var hh_ap: AnimationPlayer = p.context.weapon_animation_player
	var hh_light: StringName = p.get_default_attack_id()
	var hh_started: Array[StringName] = []
	var hh_finished := [0]
	hh_ac.attack_started.connect(func(_d: Vector2) -> void: hh_started.append(hh_ac.get_active_attack_id()))
	hh_ac.attack_finished.connect(func() -> void: hh_finished[0] += 1)
	var hh_guard := 0
	check(hh_ac.try_start_attack(hh_light, Vector2.RIGHT) and hh_ap.current_animation == &"sword_slash_1", "HH1a the light attack starts with sword_slash_1")
	check(not hh_ac.try_start_attack(hh_light, Vector2.RIGHT) and hh_ac.get_active_attack_id() == &"player_light", "HH1b a press before the window opens does not chain")
	while not hh_ac.is_combo_window_open() and hh_guard < 120:
		await physics_frame
		hh_guard += 1
	check(hh_ac.try_start_attack(hh_light, Vector2.RIGHT) and hh_ac.get_active_attack_id() == &"player_light2" and hh_ap.current_animation == &"sword_slash_2", "HH2 a press in the first window plays sword_slash_2")
	hh_guard = 0
	while not hh_ac.is_combo_window_open() and hh_guard < 120:
		await physics_frame
		hh_guard += 1
	check(hh_ac.try_start_attack(hh_light, Vector2.RIGHT) and hh_ac.get_active_attack_id() == &"player_light" and hh_ap.current_animation == &"sword_slash_1", "HH3 a press in the SECOND window starts a new combo with attack 1, not a repeat of attack 2 (active: %s)" % str(hh_ac.get_active_attack_id()))
	hh_guard = 0
	while not hh_ac.is_combo_window_open() and hh_guard < 120:
		await physics_frame
		hh_guard += 1
	check(hh_ac.try_start_attack(hh_light, Vector2.RIGHT) and hh_ac.get_active_attack_id() == &"player_light2", "HH4 the restarted combo goes on to attack 2 again")
	check(str(hh_started) == str([&"player_light", &"player_light2", &"player_light", &"player_light2"]) and hh_finished[0] == 0, "HH5 four swings in a row, no attack_finished until the chain ends (%s)" % str(hh_started))

	# HH6-HH9: no press in the second window -> return_2, and nothing can start until it has finished.
	hh_guard = 0
	while hh_ap.current_animation != &"sword_slash_return_2" and hh_guard < 120:
		await physics_frame
		hh_guard += 1
	check(hh_ap.current_animation == &"sword_slash_return_2" and p.context.is_attacking and not hh_ac.is_combo_window_open(), "HH6 the window closing with no press plays the return of the LAST attack (sword_slash_return_2)")
	await phys(5)
	check(not hh_ac.try_start_attack(hh_light, Vector2.RIGHT) and hh_ap.current_animation == &"sword_slash_return_2" and hh_started.size() == 4, "HH7 a press during the return is refused: the return keeps playing")
	Input.action_press("attack_light")
	await phys(2)
	Input.action_release("attack_light")
	await phys(2)
	check(hh_ap.current_animation == &"sword_slash_return_2" and hh_started.size() == 4, "HH8 a real tap during the return starts nothing")
	hh_guard = 0
	while p.context.is_attacking and hh_guard < 200:
		await physics_frame
		hh_guard += 1
	check(not p.context.is_attacking and hh_finished[0] == 1 and is_equal_approx(p.context.move_multiplier, 1.0), "HH9 the return finishes the combo once and restores movement")
	await phys(10)
	var hh10_blockers := "attacking=%s cooldown=%s stunned=%s dashing=%s" % [str(p.context.is_attacking), str(hh_ac.is_on_cooldown()), str(p.is_stunned()), str(p.context.is_dashing)]
	check(hh_ac.try_start_attack(hh_light, Vector2.RIGHT) and hh_ac.get_active_attack_id() == &"player_light", "HH10 after the return a new combo starts at attack 1 (%s)" % hh10_blockers)

	# HH11: a single attack 1 with no press returns with return_1 (not return_2).
	hh_guard = 0
	while hh_ap.current_animation != &"sword_slash_return_1" and hh_guard < 120:
		await physics_frame
		hh_guard += 1
	check(hh_ap.current_animation == &"sword_slash_return_1", "HH11 attack 1 alone ends with sword_slash_return_1 (now %s)" % hh_ap.current_animation)
	hh_guard = 0
	while p.context.is_attacking and hh_guard < 200:
		await physics_frame
		hh_guard += 1
	await phys(10)

	# HH12-HH14: interrupted combos start again at attack 1.
	hh_ac.try_start_attack(hh_light, Vector2.RIGHT)
	hh_guard = 0
	while not hh_ac.is_combo_window_open() and hh_guard < 120:
		await physics_frame
		hh_guard += 1
	hh_ac.try_start_attack(hh_light, Vector2.RIGHT)
	check(hh_ac.get_active_attack_id() == &"player_light2", "HH12a the combo is on attack 2")
	var hh_light2: AttackDefinition2D = hh_ac.get_attack(&"player_light2")
	var hh_was := hh_light2.interruptible
	hh_light2.interruptible = true
	p.take_damage(1)
	hh_light2.interruptible = hh_was
	check(not p.context.is_attacking and hh_ac.get_active_attack_id() == &"" and is_equal_approx(p.context.move_multiplier, 1.0), "HH12b a hit that interrupts attack 2 ends the combo and restores movement")
	await phys(30)
	check(hh_ac.try_start_attack(hh_light, Vector2.RIGHT) and hh_ac.get_active_attack_id() == &"player_light", "HH13 after the interrupt the next press is attack 1")
	hh_guard = 0
	while not hh_ac.is_combo_window_open() and hh_guard < 120:
		await physics_frame
		hh_guard += 1
	hh_ac.cancel()
	await phys(2)
	check(hh_ac.try_start_attack(hh_light, Vector2.RIGHT) and hh_ac.get_active_attack_id() == &"player_light", "HH14 cancel() in a window also resets the combo: the next press is attack 1, not attack 2")
	await cleanup(main)

	# HH15-HH17: the real heavy flow. INPUT_RELEASE: held for a long time, nothing releases it; release swings.
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	hh_ac = p.attack_component
	hh_ap = p.context.weapon_animation_player
	Input.action_press("attack_light")
	await phys(150)
	check(hh_ac.is_charging() and hh_ac.get_active_attack_id() == &"" and hh_ap.assigned_animation == &"sword_charge_heavy_slash", "HH15 the shipped heavy (INPUT_RELEASE) is still charging after 2.5 s of hold; the charge clip is playing")
	check(hh_ac.get_charge_ratio() == 0.0, "HH15b an INPUT_RELEASE heavy with no threshold reports no charge ratio")
	Input.action_release("attack_light")
	await phys(3)
	check(not hh_ac.is_charging() and hh_ac.get_active_attack_id() == &"player_heavy" and hh_ap.current_animation == &"sword_heavy_slash", "HH16 releasing the input swings sword_heavy_slash")
	hh_guard = 0
	while hh_ap.current_animation != &"sword_slash_return_1" and hh_guard < 120:
		await physics_frame
		hh_guard += 1
	check(hh_ap.current_animation == &"sword_slash_return_1", "HH17 the heavy ends with its return clip")
	hh_guard = 0
	while p.context.is_attacking and hh_guard < 200:
		await physics_frame
		hh_guard += 1
	check(not p.context.is_attacking and is_equal_approx(p.context.move_multiplier, 1.0), "HH17b the character is free again after the heavy return")
	await cleanup(main)

	# HH18-HH20: THRESHOLD heavy: releases by itself while held; the held button does not charge again.
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	hh_ac = p.attack_component
	var hh_thresh := definition_variant(hh_ac.get_attack(&"player_heavy"), &"player_heavy")
	hh_thresh.release_mode = AttackDefinition2D.ReleaseMode.THRESHOLD
	hh_thresh.charge_threshold = 0.8
	var hh_list: Array[AttackDefinition2D] = [hh_thresh]
	hh_ac.set_attacks(hh_list)
	hh_started = []
	hh_ac.attack_started.connect(func(_d: Vector2) -> void: hh_started.append(hh_ac.get_active_attack_id()))
	Input.action_press("attack_light")
	await phys(36)
	var hh_mid := hh_ac.get_charge_ratio()
	check(hh_ac.is_charging() and hh_mid > 0.3 and hh_mid < 0.9, "HH18 a threshold charge fills over time and has not released yet (ratio %.2f)" % hh_mid)
	await phys(30)
	check(not hh_ac.is_charging() and hh_started.size() == 1 and hh_started[0] == &"player_heavy", "HH19 the heavy releases by itself at the threshold with the button still held")
	hh_guard = 0
	while p.context.is_attacking and hh_guard < 300:
		await physics_frame
		hh_guard += 1
	await phys(30)
	check(not hh_ac.is_charging() and hh_started.size() == 1, "HH20 still holding after the swing and return: no second charge starts (swings: %d)" % hh_started.size())
	Input.action_release("attack_light")
	await phys(5)
	Input.action_press("attack_light")
	await phys(12)
	check(hh_ac.is_charging(), "HH20b the next press starts a new charge")
	Input.action_release("attack_light")
	await phys(3)
	await cleanup(main)

	# HH21: a button held through a light swing and its return starts the charge once the character is free.
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	hh_ac = p.attack_component
	hh_ac.try_start_attack(p.get_default_attack_id(), Vector2.RIGHT)
	Input.action_press("attack_light")
	await phys(30)
	check(hh_ac.get_active_attack_id() != &"" and not hh_ac.is_charging(), "HH21a while a swing runs, the held button cannot charge yet")
	hh_guard = 0
	while not hh_ac.is_charging() and hh_guard < 240:
		await physics_frame
		hh_guard += 1
	check(hh_ac.is_charging() and hh_guard < 240, "HH21b once the return has finished the held button begins the heavy charge")
	Input.action_release("attack_light")
	await phys(3)
	await cleanup(main)

	# ---------- II. Phase 9.7a: WeaponDefinition2D (data and validation only, nothing equips it yet) ----------
	main = await fresh()
	p = main.get_node("Player")
	var ii_player: AnimationPlayer = p.context.weapon_animation_player
	var ii_ids_before: Array = p.attack_component.get_attack_ids()
	var ii_sword: Resource = load(SWORD_WEAPON_PATH)
	check(ii_sword != null and ii_sword.get_script() == WEAPON_SCRIPT, "II1a the shipped sword weapon loads as a WeaponDefinition2D")
	check(ii_sword.weapon_id == &"sword" and ii_sword.display_name == "Sword", "II1b sword id and display name")
	check(ii_sword.basic_combo.size() == 2 and ii_sword.basic_combo[0].id == &"player_light" and ii_sword.basic_combo[1].id == &"player_light2", "II1c the sword's basic combo is light then light2")
	check(ii_sword.heavy_attack != null and ii_sword.heavy_attack.id == &"player_heavy", "II1d the sword's heavy attack is player_heavy")
	check(ii_sword.weapon_scene != null and ii_sword.weapon_scene.resource_path == "res://Weapons/Sword.tscn", "II1e the sword's weapon_scene is Weapons/Sword.tscn (9.7b; it was empty in 9.7a)")

	var ii_data_problems: Array = ii_sword.validate()
	check(ii_data_problems.is_empty(), "II2 the sword's data validates (problems: %s)" % str(ii_data_problems))
	var ii_clip_problems: Array = ii_sword.validate(ii_player)
	check(ii_clip_problems.is_empty(), "II3 every clip the sword's attacks name exists on the player's weapon AnimationPlayer (problems: %s)" % str(ii_clip_problems))

	check(ii_sword.get_default_attack().id == &"player_light", "II4a the default attack is the first combo entry")
	var ii_extra_ids: Array = ii_sword.get_extra_attacks().map(func(a): return a.id)
	check(ids_equal(ii_extra_ids, [&"player_light2", &"player_heavy"]), "II4b the extra attacks are the rest of the combo, then the heavy (%s)" % str(ii_extra_ids))
	check(ids_equal(ii_sword.get_attack_ids(), [&"player_light", &"player_light2", &"player_heavy"]), "II4c all attack ids in order")
	check(ii_sword.get_attack(&"player_heavy") == ii_sword.heavy_attack and ii_sword.get_attack(&"nope") == null and ii_sword.get_attack(&"") == null, "II5 lookup by id: found, unknown is null, empty is null")

	# The sword describes exactly what the shipped player has registered today, so equipping it in 9.7c changes nothing.
	var ii_registered: Array = ii_ids_before.duplicate()
	ii_registered.sort()
	var ii_weapon_ids: Array = ii_sword.get_attack_ids().duplicate()
	ii_weapon_ids.sort()
	check(ii_registered == ii_weapon_ids, "II6a the sword lists the same attacks the player's AttackComponent2D has registered (%s)" % str(ii_registered))
	check(p.attack_component.get_attack_ids() == ii_ids_before and p.attack_definition.id == &"player_light", "II6b nothing was equipped or changed on the player by loading the weapon")

	var ii_light: AttackDefinition2D = ii_sword.basic_combo[0]
	var ii_light2: AttackDefinition2D = ii_sword.basic_combo[1]
	var ii_heavy: AttackDefinition2D = ii_sword.heavy_attack

	# Data problems (each message must name the weapon and what is wrong).
	var ii_w: Resource = make_weapon(&"", [ii_light])
	ii_w.display_name = "Nameless"
	check(has_problem(ii_w.validate(), "weapon_id is empty") and has_problem(ii_w.validate(), "Nameless"), "II7 an empty weapon_id is reported, naming the weapon by its display name")
	ii_w = make_weapon(&"empty", [])
	check(has_problem(ii_w.validate(), "weapon 'empty'") and has_problem(ii_w.validate(), "basic_combo has no attack"), "II8 a weapon with no basic_combo attack is reported")
	ii_w = make_weapon(&"holes", [null, definition_variant(ii_light, &"a")])
	check(has_problem(ii_w.validate(), "basic_combo[0] is empty") and ii_w.get_default_attack().id == &"a", "II9 an empty entry is reported, and the default attack skips it")
	ii_w = make_weapon(&"dups", [definition_variant(ii_light, &"a"), definition_variant(ii_light2, &"a")])
	check(has_problem(ii_w.validate(), "attack id 'a' is listed more than once"), "II10a a duplicate id inside basic_combo is reported")
	ii_w = make_weapon(&"dups2", [definition_variant(ii_light, &"a")], definition_variant(ii_heavy, &"a"))
	check(has_problem(ii_w.validate(), "attack id 'a' is listed more than once"), "II10b a heavy attack with the same id as a combo attack is reported")
	ii_w = make_weapon(&"noid", [definition_variant(ii_light, &"")])
	check(has_problem(ii_w.validate(), "empty id"), "II10c an attack with an empty id is reported")

	# Link problems.
	var ii_a: AttackDefinition2D = definition_variant(ii_light, &"a")
	var ii_b: AttackDefinition2D = definition_variant(ii_light2, &"b")
	ii_w = make_weapon(&"unlinked", [ii_a, ii_b])
	check(has_problem(ii_w.validate(), "'b' cannot be reached from 'a'"), "II11a a combo entry no link leads to is reported as unreachable")
	ii_a.next_attack = ii_b
	check(ii_w.validate().is_empty(), "II11b once 'a' links to 'b' the weapon validates (problems: %s)" % str(ii_w.validate()))
	var ii_seq_a: AttackDefinition2D = definition_variant(ii_light, &"sa")
	var ii_seq_b: AttackDefinition2D = definition_variant(ii_light2, &"sb")
	var ii_seq: Array[AttackDefinition2D] = [ii_seq_a, ii_seq_b]
	ii_seq_a.combo_sequence = ii_seq
	ii_w = make_weapon(&"looped", [ii_seq_a, ii_seq_b])
	check(ii_w.validate().is_empty(), "II11c an entry reached through combo_sequence counts as reachable (problems: %s)" % str(ii_w.validate()))
	var ii_outside: AttackDefinition2D = definition_variant(ii_light2, &"outside")
	ii_a.next_attack = ii_outside
	ii_w = make_weapon(&"leaky", [ii_a])
	check(has_problem(ii_w.validate(), "next_attack 'outside', which is not part of this weapon"), "II12a a next_attack to an attack outside the weapon is reported")
	ii_a.next_attack = null
	var ii_leaky_seq: Array[AttackDefinition2D] = [ii_a, ii_outside]
	ii_a.combo_sequence = ii_leaky_seq
	check(has_problem(ii_w.validate(), "combo_sequence entry 'outside', which is not part of this weapon"), "II12b a combo_sequence entry outside the weapon is reported")
	var ii_self: AttackDefinition2D = definition_variant(ii_light, &"self")
	ii_self.next_attack = ii_self
	ii_w = make_weapon(&"repeat", [ii_self])
	check(ii_w.validate().is_empty(), "II12c a deliberate self link (repeat) is valid")

	# Clip problems need the weapon's AnimationPlayer.
	var ii_bad_weapon_clip: AttackDefinition2D = definition_variant(ii_light, &"bad_weapon")
	ii_bad_weapon_clip.weapon_animation = &"no_such_clip"
	ii_w = make_weapon(&"clips", [ii_bad_weapon_clip])
	check(ii_w.validate().is_empty(), "II13a without an AnimationPlayer only the data is checked")
	check(has_problem(ii_w.validate(ii_player), "weapon 'clips'") and has_problem(ii_w.validate(ii_player), "attack 'bad_weapon'") and has_problem(ii_w.validate(ii_player), "'no_such_clip' (weapon_animation)"), "II13b a missing weapon clip names the weapon, the attack and the clip")
	var ii_bad_recovery: AttackDefinition2D = definition_variant(ii_light, &"bad_return")
	ii_bad_recovery.recovery_animation = &"no_such_return"
	ii_w = make_weapon(&"clips2", [ii_bad_recovery])
	check(has_problem(ii_w.validate(ii_player), "'no_such_return' (recovery_animation)"), "II13c a missing recovery clip is reported")
	var ii_bad_charge: AttackDefinition2D = definition_variant(ii_heavy, &"bad_charge")
	ii_bad_charge.charge_animation = &"no_such_charge"
	ii_w = make_weapon(&"clips3", [ii_light], ii_bad_charge)
	check(has_problem(ii_w.validate(ii_player), "'no_such_charge' (charge_animation)"), "II13d a missing charge clip on the heavy attack is reported")
	var ii_same_clip: AttackDefinition2D = definition_variant(ii_light, &"same")
	ii_same_clip.recovery_animation = ii_same_clip.weapon_animation
	ii_w = make_weapon(&"clips4", [ii_same_clip])
	check(has_problem(ii_w.validate(ii_player), "recovery_animation must differ"), "II13e a recovery clip equal to the weapon clip is reported")
	var ii_no_recovery: AttackDefinition2D = definition_variant(ii_light, &"no_return")
	ii_no_recovery.recovery_animation = &""
	ii_w = make_weapon(&"clips5", [ii_no_recovery])
	check(ii_w.validate(ii_player).is_empty(), "II13f an attack with no recovery clip is valid")

	# Shared data stays untouched by validation and by the variants above.
	check(ii_sword.basic_combo.size() == 2 and ii_sword.basic_combo[0].next_attack != null and ii_sword.basic_combo[0].next_attack.id == &"player_light2" and ii_light.id == &"player_light", "II14 validating and building variants left the shipped sword and its attacks unchanged")
	await cleanup(main)

	# ---------- JJ. Phase 9.7b: the sword is a weapon scene ----------
	# (One push_warning naming a weapon with no AnimationPlayer is expected in the log for JJ4c.)
	var jj_scene_path := "res://Weapons/Sword.tscn"
	var jj_scene := load(jj_scene_path) as PackedScene
	check(jj_scene != null and jj_scene.can_instantiate(), "JJ1a Weapons/Sword.tscn loads and can be instantiated")
	var jj_root := jj_scene.instantiate() as Node2D
	check(jj_root != null and jj_root.name == &"MainHand", "JJ1b the weapon root is a Node2D called MainHand (it takes over the node the player rig used to hold)")
	var jj_sprite := jj_root.get_node_or_null("weapon") as Sprite2D
	check(jj_sprite != null and jj_sprite.texture != null and jj_sprite.texture.resource_path.ends_with("Weapon/Sword.png") and jj_sprite.offset == Vector2(8, -8), "JJ1c the weapon sprite keeps the sword texture and its (8, -8) offset")
	var jj_ap := jj_root.get_node_or_null("HandAnim") as AnimationPlayer
	check(jj_ap != null, "JJ1d the weapon scene has a HandAnim AnimationPlayer")
	check(jj_root.z_index == 1 and jj_root.position == Vector2(-4, 5) and absf(jj_root.rotation - 0.87266463) < 0.0001, "JJ1e the weapon root keeps the pose the player's MainHand had (z_index 1, position (-4, 5), rotation 0.8727)")
	var jj_missing: Array = []
	for clip_name in [&"RESET", &"idle", &"sword_slash_1", &"sword_slash_2", &"sword_slash_return_1", &"sword_slash_return_2", &"sword_heavy_slash", &"sword_charge_heavy_slash"]:
		if jj_ap == null or not jj_ap.has_animation(clip_name):
			jj_missing.append(clip_name)
	check(jj_missing.is_empty(), "JJ1f the weapon player has every clip that moved out of player.tscn (missing: %s)" % str(jj_missing))

	# find_weapon_player: by name first, then by type.
	check(CharacterContext2D.find_weapon_player(jj_root) == jj_ap, "JJ2a find_weapon_player finds HandAnim in the sword scene")
	var jj_odd := Node2D.new()
	var jj_odd_ap := AnimationPlayer.new()
	jj_odd_ap.name = "Whatever"
	jj_odd.add_child(jj_odd_ap)
	check(CharacterContext2D.find_weapon_player(jj_odd) == jj_odd_ap, "JJ2b with no HandAnim or WeaponAnimation the first AnimationPlayer child is used")
	var jj_none := Node2D.new()
	check(CharacterContext2D.find_weapon_player(jj_none) == null and CharacterContext2D.find_weapon_player(null) == null, "JJ2c a weapon with no AnimationPlayer, or no weapon, gives null")
	var jj_both := Node2D.new()
	var jj_other_ap := AnimationPlayer.new()
	jj_other_ap.name = "Other"
	jj_both.add_child(jj_other_ap)
	var jj_hand_ap := AnimationPlayer.new()
	jj_hand_ap.name = "HandAnim"
	jj_both.add_child(jj_hand_ap)
	check(CharacterContext2D.find_weapon_player(jj_both) == jj_hand_ap, "JJ2d a player called HandAnim wins over an earlier AnimationPlayer child")
	jj_odd.free()
	jj_none.free()
	jj_both.free()
	jj_root.free()

	# The clips' attack_event tracks must resolve to the character once the weapon is mounted under WeaponFacingPivot.
	var jj_char := Character2D.new()
	var jj_pivot := Node2D.new()
	jj_pivot.name = "WeaponFacingPivot"
	jj_char.add_child(jj_pivot)
	var jj_mounted: Node2D = jj_scene.instantiate()
	jj_pivot.add_child(jj_mounted)
	var jj_mounted_ap := jj_mounted.get_node("HandAnim") as AnimationPlayer
	var jj_anim_root := jj_mounted_ap.get_node_or_null(jj_mounted_ap.root_node)
	var jj_method_tracks := 0
	var jj_unresolved := 0
	var jj_bad_events := 0
	for clip_name in jj_mounted_ap.get_animation_list():
		var jj_clip := jj_mounted_ap.get_animation(clip_name)
		for track in jj_clip.get_track_count():
			if jj_clip.track_get_type(track) != Animation.TYPE_METHOD:
				continue
			jj_method_tracks += 1
			if jj_anim_root == null or jj_anim_root.get_node_or_null(jj_clip.track_get_path(track)) != jj_char:
				jj_unresolved += 1
			for key in jj_clip.track_get_key_count(track):
				var jj_args: Array = jj_clip.method_track_get_params(track, key)
				if jj_clip.method_track_get_name(track, key) != &"attack_event" or jj_args.size() != 1 or not AttackComponent2D.is_known_event(StringName(jj_args[0])):
					jj_bad_events += 1
	check(jj_method_tracks > 0 and jj_unresolved == 0, "JJ3a every method track of the sword clips (%d) resolves to the character when mounted under WeaponFacingPivot (%d did not)" % [jj_method_tracks, jj_unresolved])
	check(jj_bad_events == 0, "JJ3b every method key calls attack_event with one known event name (%d did not)" % jj_bad_events)
	var jj_no_spawn: Array = []
	for attack in ii_sword.get_all_attacks():
		var jj_spawns := 0
		for entry in clip_events(jj_mounted_ap.get_animation(attack.weapon_animation)):
			if entry[1].size() == 1 and StringName(entry[1][0]) == AttackComponent2D.EVENT_SPAWN_EFFECT:
				jj_spawns += 1
		if jj_spawns == 0:
			jj_no_spawn.append(attack.id)
	check(jj_no_spawn.is_empty(), "JJ3c every sword attack's weapon clip spawns an effect (without one: %s)" % str(jj_no_spawn))
	jj_char.free()

	# CharacterContext2D reads the weapon from whatever is mounted; the old names are only the first choice.
	var jj_body := Character2D.new()
	var jj_rig := Node2D.new()
	jj_rig.name = "LayeredRig"
	jj_body.add_child(jj_rig)
	var jj_body_pivot := Node2D.new()
	jj_body_pivot.name = "WeaponFacingPivot"
	jj_body.add_child(jj_body_pivot)
	var jj_blade: Node2D = jj_scene.instantiate()
	jj_blade.name = "Blade"
	jj_body_pivot.add_child(jj_blade)
	var jj_ctx := CharacterContext2D.new(jj_body)
	check(jj_ctx.weapon_pivot == jj_blade and jj_ctx.weapon_animation_player == jj_blade.get_node("HandAnim") and jj_ctx.weapon_facing_root == jj_body_pivot, "JJ4a a weapon scene mounted under another name than MainHand is found")
	var jj_spare: Node2D = jj_scene.instantiate()
	jj_spare.name = "Spare"
	jj_body_pivot.add_child(jj_spare)
	check(jj_ctx.bind_weapon(jj_spare) and jj_ctx.weapon_pivot == jj_spare and jj_ctx.weapon_animation_player == jj_spare.get_node("HandAnim"), "JJ4b bind_weapon points the context at a weapon mounted later")
	var jj_bare := Node2D.new()
	jj_bare.name = "Bare"
	jj_body_pivot.add_child(jj_bare)
	check(not jj_ctx.bind_weapon(jj_bare) and jj_ctx.weapon_pivot == jj_spare and jj_ctx.weapon_animation_player == jj_spare.get_node("HandAnim"), "JJ4c bind_weapon refuses a weapon with no AnimationPlayer and keeps the old one")
	jj_body.free()
	var jj_body2 := Character2D.new()
	var jj_rig2 := Node2D.new()
	jj_rig2.name = "LayeredRig"
	jj_body2.add_child(jj_rig2)
	var jj_pivot2 := Node2D.new()
	jj_pivot2.name = "WeaponFacingPivot"
	jj_body2.add_child(jj_pivot2)
	var jj_first: Node2D = jj_scene.instantiate()
	jj_first.name = "Blade"
	jj_pivot2.add_child(jj_first)
	var jj_main_hand: Node2D = jj_scene.instantiate()
	jj_pivot2.add_child(jj_main_hand)
	check(jj_main_hand.name == &"MainHand" and CharacterContext2D.new(jj_body2).weapon_pivot == jj_main_hand, "JJ4d a node called MainHand is preferred over another mounted weapon")
	jj_body2.free()

	# The shipped player mounts the sword scene and plays exactly as before.
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	var jj_mount: Node2D = p.get_node_or_null("WeaponFacingPivot/MainHand")
	check(jj_mount != null and jj_mount.scene_file_path == jj_scene_path, "JJ5a the player's MainHand is an instance of Weapons/Sword.tscn")
	check(jj_mount != null and p.context.weapon_pivot == jj_mount and p.context.weapon_animation_player == jj_mount.get_node("HandAnim"), "JJ5b the player's context reads the weapon player from the mounted weapon scene")
	var jj_player_paths := scene_node_paths("res://player.tscn")
	check(jj_player_paths.has("WeaponFacingPivot/MainHand") and not jj_player_paths.has("WeaponFacingPivot/MainHand/HandAnim") and not jj_player_paths.has("WeaponFacingPivot/MainHand/weapon"), "JJ5c player.tscn stores only the MainHand instance; the sprite and the clips live in the weapon scene")
	check(p.attack_component.get_attack_ids() == ii_ids_before and p.attack_definition.id == &"player_light" and jj_mount != null and jj_mount.z_index == 1, "JJ5d the player's attacks and the weapon's z_index are unchanged")
	check(ii_sword.validate_scene().is_empty(), "JJ5e the shipped sword's own scene validates (problems: %s)" % str(ii_sword.validate_scene()))
	var jj_instance: Node2D = ii_sword.instantiate_weapon()
	check(jj_instance != null and jj_instance.name == &"MainHand" and jj_instance.scene_file_path == jj_scene_path, "JJ5f instantiate_weapon() gives a new MainHand from the weapon's scene")
	if jj_instance != null:
		jj_instance.free()
	check(p.attack_component.try_start(true, Vector2.RIGHT), "JJ6a the player can start a swing with the weapon from the scene")
	var jj_guard := 0
	while count_slashes(main) == 0 and jj_guard < 60:
		await phys(1)
		jj_guard += 1
	check(count_slashes(main) >= 1, "JJ6b the clip's attack_event reaches the character and spawns the effect (after %d frames)" % jj_guard)
	jj_guard = 0
	while p.context.is_attacking and jj_guard < 240:
		await phys(1)
		jj_guard += 1
	check(not p.context.is_attacking and p.context.move_multiplier == 1.0, "JJ6c the swing finishes through the weapon scene's clips and movement is restored (%d frames)" % jj_guard)
	var jj_goblin: Character2D = main.get_node("BasicEnemy2D")
	check(jj_goblin.context.weapon_pivot == jj_goblin.get_node("AnimatedSprite2D/Weapon") and jj_goblin.context.weapon_animation_player == jj_goblin.get_node("AnimatedSprite2D/Weapon/WeaponAnimation"), "JJ7a the goblin's own rig layout is still found")
	check(jj_goblin.context.weapon_animation_player.has_animation(&"slash") and jj_goblin.context.weapon_animation_player.has_animation(&"lunge"), "JJ7b the goblin still has its slash and lunge clips")
	await cleanup(main)

	# validate_scene() and instantiate_weapon() on weapons built in code.
	var jj_w: Resource = make_weapon(&"scenic", [ii_light])
	check(jj_w.validate_scene().is_empty() and jj_w.instantiate_weapon() == null, "JJ8a a weapon with no scene has nothing to validate and instantiates nothing")
	var jj_plain := Node.new()
	var jj_plain_scene := PackedScene.new()
	jj_plain_scene.pack(jj_plain)
	jj_plain.free()
	jj_w.weapon_scene = jj_plain_scene
	check(has_problem(jj_w.validate_scene(), "weapon 'scenic'") and has_problem(jj_w.validate_scene(), "root must be a Node2D") and jj_w.instantiate_weapon() == null, "JJ8b a scene whose root is not a Node2D is reported, naming the weapon")
	var jj_empty := Node2D.new()
	var jj_empty_scene := PackedScene.new()
	jj_empty_scene.pack(jj_empty)
	jj_empty.free()
	jj_w.weapon_scene = jj_empty_scene
	check(has_problem(jj_w.validate_scene(), "no AnimationPlayer"), "JJ8c a weapon scene without an AnimationPlayer is reported")
	var jj_bare_root := Node2D.new()
	var jj_bare_ap := AnimationPlayer.new()
	jj_bare_ap.name = "HandAnim"
	jj_bare_root.add_child(jj_bare_ap)
	jj_bare_ap.owner = jj_bare_root
	var jj_bare_scene := PackedScene.new()
	jj_bare_scene.pack(jj_bare_root)
	jj_bare_root.free()
	jj_w.weapon_scene = jj_bare_scene
	var jj_clip_problems: Array = jj_w.validate_scene()
	check(has_problem(jj_clip_problems, "weapon 'scenic'") and has_problem(jj_clip_problems, "attack '%s'" % ii_light.id) and has_problem(jj_clip_problems, "'%s' (weapon_animation)" % ii_light.weapon_animation), "JJ8d a weapon scene missing a clip names the weapon, the attack and the clip")

	# ---------- KK. WeaponController2D dry run (9.7c-1) ----------
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	var kk_sword: Resource = load(SWORD_WEAPON_PATH)
	var kk_light: AttackDefinition2D = kk_sword.basic_combo[0]
	var kk_ctrl = WEAPON_CONTROLLER_SCRIPT.new()
	check(not kk_ctrl.is_initialized() and has_problem(kk_ctrl.validate_equip(kk_sword), "not initialized"), "KK1a a controller that was never initialized refuses every weapon and says so")
	p.add_child(kk_ctrl)
	kk_ctrl.initialize(p.context, p.attack_component)
	check(kk_ctrl.is_initialized(), "KK1b the controller initializes with the player's context and attack component")
	var kk_sword_problems: Array = kk_ctrl.validate_equip(kk_sword)
	check(kk_sword_problems.is_empty(), "KK1c the shipped sword can be equipped by the player (problems: %s)" % str(kk_sword_problems))
	check(kk_ctrl.can_equip(kk_sword), "KK1d can_equip() agrees with validate_equip()")
	check(has_problem(kk_ctrl.validate_equip(null), "no weapon"), "KK2a a null weapon is reported")

	# Busy characters: a swing or a charge blocks equipping, and it works again afterwards.
	check(p.attack_component.try_start(true, Vector2.RIGHT), "KK3a the player starts a swing")
	check(has_problem(kk_ctrl.validate_equip(kk_sword), "swing or charge") and not kk_ctrl.can_equip(kk_sword), "KK3b equipping during a swing is refused")
	p.attack_component.cancel()
	check(kk_ctrl.can_equip(kk_sword), "KK3c after the swing is cancelled the sword can be equipped again")
	check(p.attack_component.begin_charge(&"player_heavy", Vector2.RIGHT), "KK3d the player starts a heavy charge")
	check(has_problem(kk_ctrl.validate_equip(kk_sword), "swing or charge"), "KK3e equipping during a charge is refused")
	p.attack_component.cancel()
	check(kk_ctrl.can_equip(kk_sword), "KK3f after the charge is cancelled the sword can be equipped again")

	# Problems in the weapon itself, each naming the weapon (and the attack or clip).
	var kk_hollow_problems: Array = kk_ctrl.validate_equip(make_weapon(&"hollow", []))
	check(has_problem(kk_hollow_problems, "weapon 'hollow'") and has_problem(kk_hollow_problems, "basic_combo"), "KK4a a weapon with no combo attack is reported by name")
	var kk_ghost := AttackDefinition2D.new()
	kk_ghost.id = &"ghost"
	kk_ghost.weapon_animation = &"no_such_clip"
	kk_ghost.recovery_animation = &""
	var kk_ghost_problems: Array = kk_ctrl.validate_equip(make_weapon(&"ghostly", [kk_ghost]))
	check(has_problem(kk_ghost_problems, "weapon 'ghostly'") and has_problem(kk_ghost_problems, "attack 'ghost'") and has_problem(kk_ghost_problems, "'no_such_clip' (weapon_animation)"), "KK4b a weapon without a scene is checked against the player's current weapon clips (%s)" % str(kk_ghost_problems))
	var kk_bare_root := Node2D.new()
	var kk_bare_ap := AnimationPlayer.new()
	kk_bare_ap.name = &"HandAnim"
	kk_bare_root.add_child(kk_bare_ap)
	kk_bare_ap.owner = kk_bare_root
	var kk_bare_scene := PackedScene.new()
	kk_bare_scene.pack(kk_bare_root)
	kk_bare_root.free()
	var kk_scenic: Resource = make_weapon(&"scenic", [kk_light])
	kk_scenic.weapon_scene = kk_bare_scene
	var kk_scenic_problems: Array = kk_ctrl.validate_equip(kk_scenic)
	check(has_problem(kk_scenic_problems, "weapon 'scenic'") and has_problem(kk_scenic_problems, "(weapon_animation)"), "KK4c a weapon with a scene is checked against its own scene, not the player's current clips (%s)" % str(kk_scenic_problems))
	check(kk_ctrl.validate_equip(make_weapon(&"plain", [definition_variant(kk_light, &"kk_plain")])).is_empty(), "KK4d a valid weapon without a scene is accepted (its one attack has no link that leaves the weapon)")
	var kk_bad_fx := AttackDefinition2D.new()
	kk_bad_fx.id = &"badfx"
	kk_bad_fx.weapon_animation = kk_light.weapon_animation
	kk_bad_fx.recovery_animation = kk_light.recovery_animation
	kk_bad_fx.effect_scene = PackedScene.new()
	var kk_bad_fx_problems: Array = kk_ctrl.validate_equip(make_weapon(&"fx", [kk_bad_fx]))
	check(has_problem(kk_bad_fx_problems, "weapon 'fx'") and has_problem(kk_bad_fx_problems, "attack 'badfx'") and has_problem(kk_bad_fx_problems, "effect_scene"), "KK4e an effect scene that cannot be instantiated is reported")
	var kk_bad_charge := AttackDefinition2D.new()
	kk_bad_charge.id = &"badcharge"
	kk_bad_charge.weapon_animation = kk_light.weapon_animation
	kk_bad_charge.recovery_animation = kk_light.recovery_animation
	kk_bad_charge.release_mode = AttackDefinition2D.ReleaseMode.THRESHOLD
	kk_bad_charge.charge_threshold = 0.0
	var kk_bad_charge_problems: Array = kk_ctrl.validate_equip(make_weapon(&"charger", [kk_bad_charge]))
	check(has_problem(kk_bad_charge_problems, "weapon 'charger'") and has_problem(kk_bad_charge_problems, "attack 'badcharge'") and has_problem(kk_bad_charge_problems, "charge_threshold"), "KK4f a THRESHOLD release with no charge_threshold is reported")

	# The dry run changes nothing.
	var kk_pivot: Node = p.get_node("WeaponFacingPivot")
	var kk_ids_before: Array = p.attack_component.get_attack_ids().duplicate()
	var kk_children_before: int = kk_pivot.get_child_count()
	var kk_mount_before: Node2D = p.context.weapon_pivot
	var kk_player_before: AnimationPlayer = p.context.weapon_animation_player
	kk_ctrl.validate_equip(kk_sword)
	kk_ctrl.validate_equip(kk_scenic)
	kk_ctrl.validate_equip(make_weapon(&"hollow", []))
	check(ids_equal(p.attack_component.get_attack_ids(), kk_ids_before) and p.attack_definition.id == &"player_light" and kk_pivot.get_child_count() == kk_children_before and p.context.weapon_pivot == kk_mount_before and p.context.weapon_animation_player == kk_player_before and not p.context.is_attacking and not p.attack_component.is_on_cooldown(), "KK5 validate_equip() leaves the attacks, the mounted weapon, the weapon player and the attack state untouched")

	# A character without a WeaponFacingPivot (the goblin) cannot swap weapons.
	var kk_goblin: Character2D = main.get_node("BasicEnemy2D")
	var kk_goblin_ctrl = WEAPON_CONTROLLER_SCRIPT.new()
	kk_goblin.add_child(kk_goblin_ctrl)
	kk_goblin_ctrl.initialize(kk_goblin.context, kk_goblin.attack_component)
	check(kk_goblin_ctrl.is_initialized() and has_problem(kk_goblin_ctrl.validate_equip(kk_sword), "WeaponFacingPivot"), "KK6 the goblin rig has no WeaponFacingPivot, so equipping is refused with that reason")
	await cleanup(main)

	# ---------- LL. WeaponController2D.equip() for the mounted weapon (9.7c-2) ----------
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	var ll_sword: Resource = load(SWORD_WEAPON_PATH)
	var ll_light: AttackDefinition2D = ll_sword.basic_combo[0]
	var ll_heavy: AttackDefinition2D = ll_sword.heavy_attack
	var ll_ctrl = WEAPON_CONTROLLER_SCRIPT.new()
	p.add_child(ll_ctrl)
	ll_ctrl.initialize(p.context, p.attack_component)
	var ll_events: Array = []
	var ll_failures: Array = []
	ll_ctrl.weapon_equipped.connect(func(_w): ll_events.append(&"equipped"))
	ll_ctrl.equip_failed.connect(func(_w, _problems): ll_events.append(&"failed"))
	ll_ctrl.equip_failed.connect(func(_w, problems): ll_failures.append_array(problems))
	check(ll_ctrl.get_equipped_weapon() == null, "LL1a nothing is equipped until equip() succeeds")
	check(ll_ctrl.equip(ll_sword) and ll_ctrl.get_equipped_weapon() == ll_sword and ll_events == [&"equipped"], "LL1b equipping the shipped sword (the mounted weapon) succeeds and emits weapon_equipped")
	check(ids_equal(p.attack_component.get_attack_ids(), [&"player_light", &"player_light2", &"player_heavy"]) and p.attack_definition.id == &"player_light", "LL1c the sword's attacks are exactly what the player already had")

	# A weapon with no scene of its own: its attacks replace the character's.
	var ll_duel_a := definition_variant(ll_light, &"duel_a")
	var ll_duel_h := definition_variant(ll_heavy, &"duel_h")
	var ll_duelist: Resource = make_weapon(&"duelist", [ll_duel_a], ll_duel_h)
	check(ll_ctrl.equip(ll_duelist) and ll_ctrl.get_equipped_weapon() == ll_duelist, "LL2a a valid weapon with no scene can be equipped")
	check(ids_equal(p.attack_component.get_attack_ids(), [&"duel_a", &"duel_h"]) and p.attack_definition.id == &"duel_a", "LL2b the default attack is the weapon's first combo attack and the heavy is registered")
	check(not p.attack_component.has_attack(&"player_light") and not p.attack_component.has_attack(&"player_light2") and not p.attack_component.has_attack(&"player_heavy") and p.get_default_attack_id() == &"duel_a", "LL2c the previous weapon's attacks are gone")
	check(p.attack_component.try_start_attack(&"duel_a", Vector2.RIGHT), "LL2d the new default attack can be started by its id")
	var ll_guard := 0
	while count_slashes(main) == 0 and ll_guard < 60:
		await phys(1)
		ll_guard += 1
	check(count_slashes(main) >= 1, "LL2e the new attack spawns its effect (after %d frames)" % ll_guard)
	ll_guard = 0
	while p.context.is_attacking and ll_guard < 240:
		await phys(1)
		ll_guard += 1
	await phys(10)
	check(not p.context.is_attacking and p.context.move_multiplier == 1.0 and p.attack_component.begin_charge(&"duel_h", Vector2.RIGHT), "LL2f the swing finishes, movement is restored, and the new heavy can be charged (%d frames)" % ll_guard)
	p.attack_component.cancel()

	# Back to the sword: the mounted scene is accepted again and the old attacks return.
	check(ll_ctrl.equip(ll_sword) and ids_equal(p.attack_component.get_attack_ids(), [&"player_light", &"player_light2", &"player_heavy"]) and p.attack_definition.id == &"player_light" and not p.attack_component.has_attack(&"duel_a"), "LL3a equipping the sword again restores its attacks and drops the duelist's")
	check(ll_events == [&"equipped", &"equipped", &"equipped"] and ll_failures.is_empty(), "LL3b three successful equips emitted three weapon_equipped and no equip_failed")
	await cleanup(main)

	# Refused during a swing: nothing changes.
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	ll_ctrl = WEAPON_CONTROLLER_SCRIPT.new()
	p.add_child(ll_ctrl)
	ll_ctrl.initialize(p.context, p.attack_component)
	ll_events.clear()
	ll_failures.clear()
	ll_ctrl.weapon_equipped.connect(func(_w): ll_events.append(&"equipped"))
	ll_ctrl.equip_failed.connect(func(_w, _problems): ll_events.append(&"failed"))
	ll_ctrl.equip_failed.connect(func(_w, problems): ll_failures.append_array(problems))
	var ll_ids_before: Array = p.attack_component.get_attack_ids().duplicate()
	check(p.attack_component.try_start(true, Vector2.RIGHT), "LL4a the player starts a swing")
	check(not ll_ctrl.equip(ll_duelist) and ll_events == [&"failed"] and has_problem(ll_failures, "swing or charge"), "LL4b equipping during a swing is refused, emits equip_failed and names the reason")
	check(ids_equal(p.attack_component.get_attack_ids(), ll_ids_before) and p.attack_definition.id == &"player_light" and ll_ctrl.get_equipped_weapon() == null, "LL4c the attacks and the equipped weapon are unchanged")
	p.attack_component.cancel()

	# A weapon the attack component rejects: the old attacks are restored. _apply_attacks() is called
	# directly because validate_equip() would stop this weapon first.
	var ll_alt := definition_variant(ll_light, &"alt_light")
	var ll_ghost := AttackDefinition2D.new()
	ll_ghost.id = &"ghost"
	ll_ghost.weapon_animation = &"no_such_clip"
	ll_ghost.recovery_animation = &""
	var ll_broken: Resource = make_weapon(&"brokenish", [ll_alt], ll_ghost)
	check(not ll_ctrl._apply_attacks(ll_broken), "LL5a the attack component rejecting an attack makes the apply step fail")
	check(ids_equal(p.attack_component.get_attack_ids(), ll_ids_before) and p.attack_definition.id == &"player_light" and p.attack_component.attacks.size() == 2, "LL5b the previous default attack and attacks list are restored")
	ll_events.clear()
	check(not ll_ctrl.equip(ll_broken) and ll_events == [&"failed"] and ids_equal(p.attack_component.get_attack_ids(), ll_ids_before), "LL5c equip() refuses the same weapon up front, emits equip_failed and changes nothing")

	await cleanup(main)

	# ---------- MM. Swapping to another weapon scene (9.7c-3) ----------
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	var mm_sword: Resource = load(SWORD_WEAPON_PATH)
	var mm_probe: Node2D = mm_sword.instantiate_weapon()
	var mm_scene := PackedScene.new()
	mm_scene.pack(mm_probe)
	mm_probe.free()
	var mm_copy: Resource = mm_sword.duplicate()
	mm_copy.weapon_scene = mm_scene
	mm_copy.weapon_id = &"sword_copy"
	check(mm_copy.validate_scene().is_empty(), "MM1a precondition: the packed copy of the sword scene validates (problems: %s)" % str(mm_copy.validate_scene()))
	var mm_ctrl = WEAPON_CONTROLLER_SCRIPT.new()
	p.add_child(mm_ctrl)
	mm_ctrl.initialize(p.context, p.attack_component)
	var mm_events: Array = []
	var mm_failures: Array = []
	mm_ctrl.weapon_equipped.connect(func(_w): mm_events.append(&"equipped"))
	mm_ctrl.equip_failed.connect(func(_w, _problems): mm_events.append(&"failed"))
	mm_ctrl.equip_failed.connect(func(_w, problems): mm_failures.append_array(problems))
	var mm_pivot: Node = p.get_node("WeaponFacingPivot")
	var mm_old: Node2D = p.context.weapon_pivot
	var mm_old_player: AnimationPlayer = p.context.weapon_animation_player
	var mm_old_index: int = mm_old.get_index()
	var mm_kids_before: int = mm_pivot.get_child_count()
	var mm_ids_before: Array = p.attack_component.get_attack_ids().duplicate()
	check(mm_ctrl.equip(mm_copy) and mm_ctrl.get_equipped_weapon() == mm_copy and mm_events == [&"equipped"], "MM1b a weapon with a different scene is equipped and emits weapon_equipped")
	var mm_new: Node2D = p.context.weapon_pivot
	check(mm_new != mm_old and not is_instance_valid(mm_old) and not is_instance_valid(mm_old_player), "MM2a the old weapon is freed and the context points at the new one")
	check(mm_new.name == &"MainHand" and mm_new.get_parent() == mm_pivot and mm_new.get_index() == mm_old_index and mm_pivot.get_child_count() == mm_kids_before and p.has_node("WeaponFacingPivot/MainHand/HandAnim"), "MM2b the new weapon takes the old one's name, place and path")
	check(p.context.weapon_animation_player == mm_new.get_node("HandAnim"), "MM2c the context reads the weapon player from the new weapon")
	check(ids_equal(p.attack_component.get_attack_ids(), mm_ids_before) and p.attack_definition.id == &"player_light", "MM3a the weapon's attacks are registered (here the same ids as the sword)")

	# A swing on the new weapon spawns its effect and finishes: attack_event reaches the character and the
	# attack component listens to the new player.
	check(p.attack_component.try_start(true, Vector2.RIGHT), "MM4a the player swings the new weapon")
	var mm_guard := 0
	while count_slashes(main) == 0 and mm_guard < 60:
		await phys(1)
		mm_guard += 1
	check(count_slashes(main) >= 1, "MM4b the new weapon's clip spawns the effect (after %d frames)" % mm_guard)
	mm_guard = 0
	while p.context.is_attacking and mm_guard < 240:
		await phys(1)
		mm_guard += 1
	check(not p.context.is_attacking and p.context.move_multiplier == 1.0, "MM4c the swing finishes, so animation_finished is connected to the new player (%d frames)" % mm_guard)
	await phys(10)

	# Swap back to the shipped sword.
	check(mm_ctrl.equip(mm_sword) and mm_ctrl.get_equipped_weapon() == mm_sword and p.context.weapon_animation_player == p.get_node("WeaponFacingPivot/MainHand/HandAnim") and mm_pivot.get_child_count() == mm_kids_before, "MM5a equipping the shipped sword again works and leaves one weapon mounted")
	check(p.attack_component.try_start(true, Vector2.RIGHT), "MM5b the player swings the sword again")
	mm_guard = 0
	while p.context.is_attacking and mm_guard < 240:
		await phys(1)
		mm_guard += 1
	check(not p.context.is_attacking and mm_guard < 240, "MM5c that swing finishes too (%d frames)" % mm_guard)
	await phys(10)

	# Refused during a swing: the mounted weapon stays.
	var mm_mount_now: Node2D = p.context.weapon_pivot
	check(p.attack_component.try_start(true, Vector2.RIGHT), "MM6a the player starts a swing")
	mm_events.clear()
	check(not mm_ctrl.equip(mm_copy) and mm_events == [&"failed"] and p.context.weapon_pivot == mm_mount_now and is_instance_valid(mm_mount_now) and mm_pivot.get_child_count() == mm_kids_before, "MM6b swapping during a swing is refused and the mounted weapon is untouched")
	p.attack_component.cancel()
	await phys(1)

	# The attack step fails after the swap: the old weapon is put back, the new one is freed.
	var mm_stub = FailingApplyController.new()
	p.add_child(mm_stub)
	mm_stub.initialize(p.context, p.attack_component)
	var mm_stub_events: Array = []
	mm_stub.equip_failed.connect(func(_w, _problems): mm_stub_events.append(&"failed"))
	var mm_ids_now: Array = p.attack_component.get_attack_ids().duplicate()
	var mm_index_now: int = mm_mount_now.get_index()
	check(not mm_stub.equip(mm_copy) and mm_stub_events == [&"failed"], "MM7a a failing attack step makes equip() return false and emit equip_failed")
	check(p.context.weapon_pivot == mm_mount_now and is_instance_valid(mm_mount_now) and mm_mount_now.is_inside_tree() and mm_mount_now.get_index() == mm_index_now and mm_pivot.get_child_count() == mm_kids_before and mm_mount_now.name == &"MainHand", "MM7b the previous weapon is back in its place and the failed one is gone")
	check(p.context.weapon_animation_player == mm_mount_now.get_node("HandAnim") and ids_equal(p.attack_component.get_attack_ids(), mm_ids_now) and p.attack_definition.id == &"player_light", "MM7c the context and the attacks are as before")
	check(p.attack_component.try_start(true, Vector2.RIGHT), "MM7d the player can swing the restored weapon")
	mm_guard = 0
	while p.context.is_attacking and mm_guard < 240:
		await phys(1)
		mm_guard += 1
	check(not p.context.is_attacking and mm_guard < 240, "MM7e that swing finishes, so the attack component listens to the restored weapon's player (%d frames)" % mm_guard)
	await cleanup(main)

	# ---------- NN. The player owns a WeaponController2D with the sword as its starting weapon (9.7c-4) ----------
	# These checks need the node added to player.tscn in the editor (see docs/phase9/9.7c-4-notes.md).
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	check(p.weapon_controller != null and p.weapon_controller.is_initialized(), "NN1a the player has a WeaponController2D and Character2D initialized it (add the node in player.tscn if this fails)")
	check(p.weapon_controller != null and p.weapon_controller.get_equipped_weapon() != null and p.weapon_controller.get_equipped_weapon().weapon_id == &"sword", "NN1b the controller's starting weapon, the sword, is equipped")
	check(ids_equal(p.attack_component.get_attack_ids(), [&"player_light", &"player_light2", &"player_heavy"]) and p.attack_definition.id == &"player_light" and p.context.weapon_pivot == p.get_node("WeaponFacingPivot/MainHand"), "NN1c equipping the starting weapon leaves the player's attacks and mounted sword exactly as the scene had them")
	var nn_goblin: Character2D = main.get_node("BasicEnemy2D")
	check(nn_goblin.weapon_controller == null and nn_goblin.attack_component.get_attack_ids().size() >= 1, "NN2a the goblin has no weapon controller and keeps its attacks")
	var nn_light: AttackDefinition2D = p.attack_definition
	var nn_blade: Resource = make_weapon(&"nn_blade", [definition_variant(nn_light, &"nn_blade_hit")])
	check(p.weapon_controller != null and p.weapon_controller.equip(nn_blade) and p.get_default_attack_id() == &"nn_blade_hit", "NN3a the player's own controller equips another weapon")
	check(p.attack_component.try_start(true, Vector2.RIGHT), "NN3b the player swings it")
	var nn_guard := 0
	while p.context.is_attacking and nn_guard < 240:
		await phys(1)
		nn_guard += 1
	await phys(10)
	check(not p.context.is_attacking and nn_guard < 240, "NN3c the swing finishes (%d frames)" % nn_guard)
	check(p.weapon_controller != null and p.weapon_controller.equip(p.weapon_controller.starting_weapon) and ids_equal(p.attack_component.get_attack_ids(), [&"player_light", &"player_light2", &"player_heavy"]) and p.attack_definition.id == &"player_light", "NN3d the starting weapon can be equipped again and restores the sword's attacks")
	await cleanup(main)

	# ---------- OO. The player takes its attack ids from the equipped weapon (9.7d-1) ----------
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	check(p.light_attack_id == &"" and p.heavy_attack_id == &"", "OO1a both id overrides are empty on the shipped player")
	check(p.get_light_attack_id() == &"player_light" and p.get_heavy_attack_id() == &"player_heavy", "OO1b the ids come from the equipped sword: light player_light, heavy player_heavy")
	p.heavy_attack_id = &"oo_override"
	check(p.get_heavy_attack_id() == &"oo_override", "OO2a a non-empty heavy_attack_id overrides the weapon")
	p.heavy_attack_id = &""
	p.light_attack_id = &"oo_light_override"
	check(p.get_light_attack_id() == &"oo_light_override", "OO2b a non-empty light_attack_id overrides the default attack")
	p.light_attack_id = &""

	# OO3: a weapon with its own heavy attack: the hold charges that attack, the release swings it.
	var oo_light := definition_variant(p.attack_definition, &"oo_light")
	var oo_heavy := definition_variant(p.attack_component.get_attack(&"player_heavy"), &"oo_heavy")
	var oo_axe: Resource = make_weapon(&"oo_axe", [oo_light], oo_heavy)
	check(p.weapon_controller != null and p.weapon_controller.equip(oo_axe), "OO3a the player equips a weapon with its own light and heavy attack")
	check(p.get_light_attack_id() == &"oo_light" and p.get_heavy_attack_id() == &"oo_heavy", "OO3b the controller now sends that weapon's ids")
	Input.action_press("attack_light")
	await phys(10)
	check(p.attack_component.is_charging() and p.attack_component.get_active_attack_id() == &"", "OO3c holding attack_light begins a charge of the new weapon's heavy attack")
	Input.action_release("attack_light")
	await phys(2)
	check(p.attack_component.get_active_attack_id() == &"oo_heavy" and not p.attack_component.is_charging(), "OO3d releasing swings the new weapon's heavy attack")
	var oo_guard := 0
	while p.context.is_attacking and oo_guard < 240:
		await physics_frame
		oo_guard += 1
	await phys(20)

	# OO4: a weapon with no heavy attack: nothing to charge, so attack_light is the light attack on press.
	var oo_staff: Resource = make_weapon(&"oo_staff", [definition_variant(p.attack_definition, &"oo_staff_hit")])
	check(p.weapon_controller.equip(oo_staff) and p.get_heavy_attack_id() == &"", "OO4a a weapon with no heavy attack leaves the heavy id empty")
	Input.action_press("attack_light")
	await phys(2)
	check(p.attack_component.get_active_attack_id() == &"oo_staff_hit" and not p.attack_component.is_charging(), "OO4b attack_light starts the light attack on press when the weapon has no heavy")
	Input.action_release("attack_light")
	oo_guard = 0
	while p.context.is_attacking and oo_guard < 240:
		await physics_frame
		oo_guard += 1
	await phys(20)

	# OO5: the starting weapon brings its ids back.
	check(p.weapon_controller.equip(p.weapon_controller.starting_weapon) and p.get_light_attack_id() == &"player_light" and p.get_heavy_attack_id() == &"player_heavy", "OO5a equipping the sword again restores player_light and player_heavy")
	# OO6: no weapon controller and no override: no heavy attack (the light attack still works).
	var oo_controller: WeaponController2D = p.weapon_controller
	p.weapon_controller = null
	check(p.get_heavy_attack_id() == &"" and p.get_light_attack_id() == &"player_light", "OO6a without a weapon controller the heavy id is empty and the light id is still the default attack")
	p.weapon_controller = oo_controller
	await cleanup(main)

	# ---------- PP. Effect clips: an attack names the clip of its effect scene (9.8a) ----------
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	var pp_light: AttackDefinition2D = p.attack_component.get_attack(&"player_light")
	var pp_heavy: AttackDefinition2D = p.attack_component.get_attack(&"player_heavy")
	check(AttackDefinition2D.new().effect_animation == &"slash" and pp_light.effect_animation == &"slash" and pp_heavy.effect_animation == &"heavy_slash", "PP1a effect_animation defaults to slash; the shipped light attack keeps it and the heavy attack uses heavy_slash")
	var pp_scene := load("res://Characters/Components/Combat/AttackSlash2D.tscn") as PackedScene
	check(not AttackSlash2D.scene_lacks_animation(pp_scene, &"slash") and not AttackSlash2D.scene_lacks_animation(pp_scene, &"heavy_slash") and AttackSlash2D.scene_lacks_animation(pp_scene, &"no_such_effect_clip") and not AttackSlash2D.scene_lacks_animation(null, &"x") and not AttackSlash2D.scene_lacks_animation(pp_scene, &""), "PP1b the effect scene has slash and heavy_slash; a missing clip is detected; no scene or an empty name is not judged")

	# PP2: real swings spawn effects that play the attack's clip, and free themselves when it ends.
	check(p.attack_component.try_start_attack(&"player_light", Vector2.RIGHT), "PP2a the light attack starts")
	await phys(6)
	var pp_live := effect_children(main).filter(func(n): return n is AttackSlash2D and not n.is_queued_for_deletion())
	check(pp_live.size() == 1 and pp_live[0].effect_animation == &"slash" and pp_live[0].get_node(AttackSlash2D.ANIMATION_PLAYER_PATH).current_animation == &"slash", "PP2b the light attack's effect plays slash")
	var pp_guard := 0
	while p.context.is_attacking and pp_guard < 240:
		await physics_frame
		pp_guard += 1
	await phys(40)
	check(p.attack_component.try_start_attack(&"player_heavy", Vector2.RIGHT), "PP2c the heavy attack starts")
	await phys(6)
	pp_live = effect_children(main).filter(func(n): return n is AttackSlash2D and not n.is_queued_for_deletion())
	check(pp_live.size() == 1 and pp_live[0].effect_animation == &"heavy_slash" and pp_live[0].get_node(AttackSlash2D.ANIMATION_PLAYER_PATH).current_animation == &"heavy_slash", "PP2d the heavy attack's effect plays heavy_slash")
	pp_guard = 0
	while p.context.is_attacking and pp_guard < 240:
		await physics_frame
		pp_guard += 1
	await phys(40)
	var pp_left: Array = effect_children(main).filter(func(n): return n is AttackSlash2D).map(func(n): return "%s (%s)" % [n.name, n.get_node(AttackSlash2D.ANIMATION_PLAYER_PATH).current_animation])
	check(count_slashes(main) == 0, "PP2e the heavy effect frees itself when heavy_slash ends (left over: %s)" % str(pp_left))

	# PP3 to PP4: an attack naming a clip its effect scene lacks is refused, naming the clip.
	var pp_bad := definition_variant(pp_light, &"pp_bad")
	pp_bad.effect_animation = &"no_such_effect_clip"
	var pp_message: String = p.attack_component.validate_definition(pp_bad)
	check(pp_message.contains("no_such_effect_clip") and pp_message.contains("effect_animation"), "PP3a validate_definition names the missing effect clip (%s)" % pp_message)
	check(not p.attack_component.set_attack_definition(pp_bad) and p.attack_definition.id == &"player_light", "PP3b the attack component refuses it and keeps the previous attack")
	var pp_bad_weapon: Resource = make_weapon(&"pp_bad_fx", [pp_bad])
	check(has_problem(p.weapon_controller.validate_equip(pp_bad_weapon), "no_such_effect_clip") and not p.weapon_controller.can_equip(pp_bad_weapon), "PP4 validate_equip reports the missing effect clip and the weapon cannot be equipped")

	# PP5 to PP6: the effect itself.
	var pp_fx := pp_scene.instantiate() as AttackSlash2D
	pp_fx.configure(p, 1, Vector2.RIGHT, Vector2(16, 16), Vector2.ZERO, -1, 0.0, 0.0, &"")
	check(pp_fx.effect_animation == &"slash", "PP5 an empty effect animation falls back to slash")
	pp_fx.free()
	var pp_missing := pp_scene.instantiate() as AttackSlash2D
	pp_missing.configure(p, 1, Vector2.RIGHT, Vector2(16, 16), Vector2.ZERO, -1, 0.0, 0.0, &"no_such_effect_clip")
	main.add_child(pp_missing)
	await phys(3)
	check(not is_instance_valid(pp_missing) or pp_missing.is_queued_for_deletion(), "PP6 an effect told to play a clip it lacks logs an error and removes itself")
	await cleanup(main)

	# ---------- QQ. No legacy slash scene: every attack carries its own effect_scene (10.1) ----------
	# Expected in the Output log (not failures): "rejected definition" errors naming qq_no_fx, and the
	# "needs a character context, an attack_definition" error from the bare component (QQ6).
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	await phys(3)
	var qq_ac: AttackComponent2D = p.attack_component
	var qq_consts: Dictionary = qq_ac.get_script().get_script_constant_map()
	check(not ("attack_slash_scene" in qq_ac) and not ("slash_scene" in qq_ac) and not qq_ac.has_method("set_slash_scene") and not qq_consts.has("DEFAULT_SLASH") and not qq_consts.has("DEFAULT_ATTACK"), "QQ1a the legacy slash scene, its setter and the two default constants are gone from AttackComponent2D")
	check(qq_ac.attack_definition != null and qq_ac.attack_definition.id == &"player_light" and e.attack_component.attack_definition != null, "QQ1b the player scene sets its own attack_definition (it no longer relies on a script default) and so does the goblin")
	var qq_light: AttackDefinition2D = qq_ac.get_attack(&"player_light")
	var qq_none := definition_variant(qq_light, &"qq_no_fx")
	qq_none.effect_scene = null
	var qq_message: String = qq_ac.validate_definition(qq_none)
	check(qq_message.contains("qq_no_fx") and qq_message.contains("effect_scene"), "QQ2 validate_definition names an attack that has no effect_scene (%s)" % qq_message)
	check(not qq_ac.set_attack_definition(qq_none) and qq_ac.definition.id == &"player_light", "QQ3 set_attack_definition refuses it and keeps the previous attack")
	var qq_weapon: Resource = make_weapon(&"qq_fxless", [qq_none])
	check(has_problem(p.weapon_controller.validate_equip(qq_weapon), "effect_scene") and not p.weapon_controller.can_equip(qq_weapon), "QQ4 a weapon holding such an attack is refused by the dry run")
	p.attack_definition = null
	check(p.attack_definition != null and p.attack_definition.id == &"player_light", "QQ5 assigning a null attack_definition is refused and the previous attack stays")
	var qq_bare := AttackComponent2D.new()
	qq_bare.initialize(p.context)
	check(not qq_bare._initialized and qq_bare.definition == null, "QQ6 a component with no attack_definition does not initialize, so that character cannot attack")
	qq_bare.free()
	await cleanup(main)

	# ---------- RR. AttackEffect2D: the shared base class of every effect scene (10.2) ----------
	# Expected in the Output log (not failures): one "must have an AttackEffect2D script" error from RR5.
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	await phys(3)
	var rr_scene := load("res://Characters/Components/Combat/AttackSlash2D.tscn") as PackedScene
	var rr_slash := rr_scene.instantiate()
	check(rr_slash is AttackEffect2D and rr_slash is AttackSlash2D and rr_slash.get_script().get_base_script() == load("res://Characters/Components/Combat/AttackEffect2D.gd"), "RR1 AttackSlash2D is an AttackEffect2D (its script extends the base class)")
	rr_slash.free()

	# RR2: configure() lives on the base class and clamps its inputs the way the slash always did.
	var rr_fx := AttackEffect2D.new()
	rr_fx.configure(p, -5, Vector2(0, 10), Vector2(0, -3), Vector2(2, 3), 5, -1.0, -2.0, &"")
	check(rr_fx.damage == 0 and rr_fx.direction == Vector2.DOWN and rr_fx.hitbox_size == Vector2(1, 1) and rr_fx.hitbox_offset == Vector2(2, 3) and rr_fx.hit_layers == 5 and rr_fx.knockback == 0.0 and rr_fx.hit_stun == 0.0 and rr_fx.effect_animation == &"slash", "RR2a configure() clamps damage, size, knockback and stun, normalizes the direction and defaults the clip to slash")
	rr_fx.configure(p, 1, Vector2.ZERO, Vector2(8, 8), Vector2.ZERO)
	check(rr_fx.direction == Vector2.RIGHT, "RR2b a zero aim direction falls back to right")
	rr_fx.free()

	# RR3: the shared hit rules, exercised on a bare base-class effect (no scene, no hitbox).
	var rr_team_before: StringName = p.team
	p.team = &"rr_team"
	var rr_enemy_team_before: StringName = e.team
	e.team = &"rr_team"
	var rr_hp: int = e.health_component.health
	var rr_friendly := AttackEffect2D.new()
	main.add_child(rr_friendly)
	rr_friendly.configure(p, 3, Vector2.RIGHT, Vector2(8, 8), Vector2.ZERO)
	rr_friendly._try_hit(e)
	check(e.health_component.health == rr_hp, "RR3a an effect never hits a character on the attacker's own team")
	p.team = rr_team_before
	e.team = rr_enemy_team_before
	var rr_hit := AttackEffect2D.new()
	main.add_child(rr_hit)
	rr_hit.global_position = e.global_position
	rr_hit.configure(p, 3, Vector2.RIGHT, Vector2(8, 8), Vector2.ZERO)
	var rr_seen: Array = []
	rr_hit.hit_confirmed.connect(func(_target, dealt): rr_seen.append(dealt))
	rr_hit._try_hit(e)
	rr_hit._try_hit(e)
	check(e.health_component.health == rr_hp - 3 and rr_seen == [3], "RR3b an enemy is hit once per effect, through apply_hit, and hit_confirmed fires once")
	var rr_self := AttackEffect2D.new()
	main.add_child(rr_self)
	rr_self.configure(e, 3, Vector2.RIGHT, Vector2(8, 8), Vector2.ZERO)
	rr_self._try_hit(e)
	check(e.health_component.health == rr_hp - 3, "RR3c an effect never hits its own attacker")
	rr_friendly.queue_free()
	rr_hit.queue_free()
	rr_self.queue_free()

	# RR4: the attack component spawns, tracks and cancels any AttackEffect2D, not only slashes.
	var rr_proto := AttackEffect2D.new()
	var rr_bare_scene := PackedScene.new()
	check(rr_bare_scene.pack(rr_proto) == OK, "RR4a a scene whose root is a bare AttackEffect2D packs")
	rr_proto.free()
	var rr_def := definition_variant(p.attack_component.get_attack(&"player_light"), &"rr_bare")
	rr_def.effect_scene = rr_bare_scene
	check(p.attack_component.set_attack_definition(rr_def) and p.attack_component.definition.id == &"rr_bare", "RR4b the component accepts an attack whose effect scene is not a slash")
	p.attack_component.try_start(true, Vector2.RIGHT)
	await phys(8)
	var rr_live := effect_children(main).filter(func(n): return n is AttackEffect2D and not (n is AttackSlash2D) and not n.is_queued_for_deletion())
	check(rr_live.size() == 1 and p.attack_component.get_active_effect_count() == 1, "RR4c the swing spawns that effect and the component tracks it")
	var rr_node: Node = rr_live[0] if not rr_live.is_empty() else null
	p.attack_component.cancel()
	await phys(2)
	check(p.attack_component.get_active_effect_count() == 0 and (rr_node == null or not is_instance_valid(rr_node) or rr_node.is_queued_for_deletion()), "RR4d cancel() removes it")
	await cleanup(main)

	# RR5: an effect scene whose root is not an AttackEffect2D is still refused with an error and spawns nothing.
	main = await fresh_far()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	await phys(3)
	var rr_plain := Node2D.new()
	rr_plain.name = &"rr_plain"
	var rr_plain_scene := PackedScene.new()
	rr_plain_scene.pack(rr_plain)
	rr_plain.free()
	var rr_plain_def := definition_variant(p.attack_component.get_attack(&"player_light"), &"rr_plain")
	rr_plain_def.effect_scene = rr_plain_scene
	p.attack_component.set_attack_definition(rr_plain_def)
	p.attack_component.try_start(true, Vector2.RIGHT)
	await phys(8)
	check(p.attack_component.get_active_effect_count() == 0 and not effect_children(main).any(func(n): return n.name == &"rr_plain" and not n.is_queued_for_deletion()), "RR5 a scene whose root is not an AttackEffect2D spawns nothing")
	await cleanup(main)

	# ---------- SS. AttackSlash2D finds its nodes through exported paths (10.3) ----------
	# Expected in the Output log (not failures): one "hitbox_path 'Nowhere' does not lead to an Area2D" error from SS3.
	main = await fresh_far()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	await phys(3)
	var ss_scene := load("res://Characters/Components/Combat/AttackSlash2D.tscn") as PackedScene
	var ss_shipped := ss_scene.instantiate() as AttackSlash2D
	check(ss_shipped.animation_player_path == NodePath(AttackSlash2D.ANIMATION_PLAYER_PATH) and ss_shipped.hitbox_path == ^"HitboxOrigin/HitboxMotion/Area2D" and ss_shipped.collision_shape_path == ^"HitboxOrigin/HitboxMotion/Area2D/CollisionShape2D" and ss_shipped.hitbox_origin_path == ^"HitboxOrigin", "SS1a the shipped scene keeps the default paths (no scene edit was needed)")
	check(ss_shipped.get_node_or_null(ss_shipped.animation_player_path) is AnimationPlayer and ss_shipped.get_node_or_null(ss_shipped.hitbox_path) is Area2D and ss_shipped.get_node_or_null(ss_shipped.collision_shape_path) is CollisionShape2D and ss_shipped.get_node_or_null(ss_shipped.hitbox_origin_path) is Node2D, "SS1b every default path leads to the right kind of node")
	ss_shipped.free()

	# SS2: an effect scene whose animation player lives somewhere else works by pointing the path at it.
	var ss_alt_root := ss_scene.instantiate() as AttackSlash2D
	var ss_alt_player := AnimationPlayer.new()
	ss_alt_player.name = &"AltPlayer"
	ss_alt_root.add_child(ss_alt_player)
	ss_alt_player.owner = ss_alt_root
	var ss_anim := Animation.new()
	ss_anim.length = 0.2
	var ss_lib := AnimationLibrary.new()
	ss_lib.add_animation(&"alt_clip", ss_anim)
	ss_alt_player.add_animation_library(&"", ss_lib)
	ss_alt_root.animation_player_path = ^"AltPlayer"
	var ss_alt_scene := PackedScene.new()
	check(ss_alt_scene.pack(ss_alt_root) == OK, "SS2a an effect scene with its own animation player and path packs")
	ss_alt_root.free()
	check(not AttackSlash2D.scene_lacks_animation(ss_alt_scene, &"alt_clip") and AttackSlash2D.scene_lacks_animation(ss_alt_scene, &"slash"), "SS2b the clip check looks at the player the scene's own path names, not the standard one")
	var ss_def := definition_variant(p.attack_component.get_attack(&"player_light"), &"ss_alt")
	ss_def.effect_scene = ss_alt_scene
	ss_def.effect_animation = &"alt_clip"
	p.attack_component.set_attack_definition(ss_def)
	p.attack_component.try_start(true, Vector2.RIGHT)
	await phys(8)
	var ss_live := effect_children(main).filter(func(n): return n is AttackSlash2D and not n.is_queued_for_deletion())
	var ss_playing: bool = ss_live.size() == 1 and (ss_live[0].get_node_or_null("AltPlayer") as AnimationPlayer) != null and (ss_live[0].get_node("AltPlayer") as AnimationPlayer).current_animation == &"alt_clip"
	await phys(40)
	check(ss_playing and count_slashes(main) == 0, "SS2c the swing plays alt_clip on that player and the effect frees itself when it ends")

	# SS3: a path that leads nowhere is reported by name and the effect removes itself.
	var ss_broken := ss_scene.instantiate() as AttackSlash2D
	ss_broken.hitbox_path = ^"Nowhere"
	var ss_broken_scene := PackedScene.new()
	ss_broken_scene.pack(ss_broken)
	ss_broken.free()
	var ss_node := ss_broken_scene.instantiate() as AttackSlash2D
	ss_node.configure(p, 1, Vector2.RIGHT, Vector2(8, 8), Vector2.ZERO)
	main.add_child(ss_node)
	await phys(3)
	check(not is_instance_valid(ss_node) or ss_node.is_queued_for_deletion(), "SS3 an effect with a broken node path logs an error and removes itself")
	await cleanup(main)

	# ---------- TT. Hit policy: max_targets and pierce on the attack and on the effect (10.4) ----------
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	await phys(3)
	var tt_ok := true
	for tt_id in [&"player_light", &"player_light2", &"player_heavy"]:
		var tt_attack: AttackDefinition2D = p.attack_component.get_attack(tt_id)
		tt_ok = tt_ok and tt_attack != null and tt_attack.max_targets == 0 and tt_attack.pierce
	tt_ok = tt_ok and e.attack_definition.max_targets == 0 and e.attack_definition.pierce
	check(AttackDefinition2D.new().max_targets == 0 and AttackDefinition2D.new().pierce and tt_ok, "TT1 a new attack and every shipped attack keep the old behavior (no target limit, pierce on)")

	# TT2: three goblins far from the fight, hit in a fixed order by a bare effect with different policies.
	var tt_scene := load("res://Characters/Enemies/BasicEnemy2D.tscn") as PackedScene
	var tt_targets: Array = []
	for tt_i in 3:
		var tt_g := tt_scene.instantiate() as Character2D
		main.add_child(tt_g)
		tt_g.global_position = Vector2(3000 + tt_i * 200, 3000)
		tt_g.set_physics_process(false)
		tt_targets.append(tt_g)
	await phys(2)
	var tt_hp := func() -> Array: return tt_targets.map(func(g): return g.health_component.health)

	var tt_before: Array = tt_hp.call()
	var tt_a := AttackEffect2D.new()
	main.add_child(tt_a)
	tt_a.configure(p, 1, Vector2.RIGHT, Vector2(8, 8), Vector2.ZERO, -1, 0.0, 0.0, &"", 0, true)
	for tt_g in tt_targets:
		tt_a._try_hit(tt_g)
	check(tt_hp.call() == [tt_before[0] - 1, tt_before[1] - 1, tt_before[2] - 1] and not tt_a.is_spent(), "TT2a no limit and pierce on: the effect hits all three and is never spent")

	tt_before = tt_hp.call()
	var tt_b := AttackEffect2D.new()
	main.add_child(tt_b)
	tt_b.configure(p, 1, Vector2.RIGHT, Vector2(8, 8), Vector2.ZERO, -1, 0.0, 0.0, &"", 1, true)
	for tt_g in tt_targets:
		tt_b._try_hit(tt_g)
	check(tt_hp.call() == [tt_before[0] - 1, tt_before[1], tt_before[2]] and tt_b.is_spent(), "TT2b max_targets 1: only the first target is hit and the effect is spent")

	tt_before = tt_hp.call()
	var tt_c := AttackEffect2D.new()
	main.add_child(tt_c)
	tt_c.configure(p, 1, Vector2.RIGHT, Vector2(8, 8), Vector2.ZERO, -1, 0.0, 0.0, &"", 0, false)
	for tt_g in tt_targets:
		tt_c._try_hit(tt_g)
	check(tt_hp.call() == [tt_before[0] - 1, tt_before[1], tt_before[2]] and tt_c.is_spent(), "TT2c pierce off: the first target ends the effect")

	tt_before = tt_hp.call()
	var tt_d := AttackEffect2D.new()
	main.add_child(tt_d)
	tt_d.configure(p, 1, Vector2.RIGHT, Vector2(8, 8), Vector2.ZERO, -1, 0.0, 0.0, &"", 2, true)
	for tt_g in tt_targets:
		tt_d._try_hit(tt_g)
	check(tt_hp.call() == [tt_before[0] - 1, tt_before[1] - 1, tt_before[2]] and tt_d.is_spent(), "TT2d max_targets 2 with pierce on: two targets are hit, then the effect is spent")

	tt_before = tt_hp.call()
	var tt_e := AttackEffect2D.new()
	main.add_child(tt_e)
	tt_e.configure(p, 1, Vector2.RIGHT, Vector2(8, 8), Vector2.ZERO, -1, 0.0, 0.0, &"", 3, true)
	for tt_g in tt_targets:
		tt_e._try_hit(tt_g)
	check(tt_hp.call() == [tt_before[0] - 1, tt_before[1] - 1, tt_before[2] - 1] and tt_e.is_spent(), "TT2e a limit equal to the number of targets hits them all and then the effect is spent")
	for tt_fx in [tt_a, tt_b, tt_c, tt_d, tt_e]:
		tt_fx.queue_free()
	await cleanup(main)

	# TT3: the attack component hands the attack's policy to the effect it spawns.
	main = await fresh_far()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	await phys(3)
	var tt_def := definition_variant(p.attack_component.get_attack(&"player_light"), &"tt_policy")
	tt_def.max_targets = 2
	tt_def.pierce = false
	p.attack_component.set_attack_definition(tt_def)
	p.attack_component.try_start(true, Vector2.RIGHT)
	await phys(8)
	var tt_live := effect_children(main).filter(func(n): return n is AttackSlash2D and not n.is_queued_for_deletion())
	check(tt_live.size() == 1 and tt_live[0].max_targets == 2 and not tt_live[0].pierce, "TT3 the spawned effect carries the attack's max_targets and pierce")
	await cleanup(main)

	# ---------- UU. 10.5 AttackSpawnPoint ----------
	# UU1: the shipped scenes have no marker, so effects still start at the character's origin.
	main = await fresh_far()
	p = main.get_node("Player")
	var uu_goblin: Character2D = main.get_node("BasicEnemy2D")
	check(p.attack_spawn_point == null and p.context.get_attack_origin() == p.global_position, "UU1a the shipped player has no spawn marker and its attack origin is its own position")
	check(uu_goblin.attack_spawn_point == null and uu_goblin.context.get_attack_origin() == uu_goblin.global_position, "UU1b the shipped goblin has no spawn marker and its attack origin is its own position")
	await cleanup(main)

	# UU2: a child named AttackSpawnPoint is found by name and the effect spawns there.
	var uu_marker := Marker2D.new()
	uu_marker.name = "AttackSpawnPoint"
	uu_marker.position = Vector2(40, -12)
	main = await fresh_far_prepared(func(m): m.get_node("Player").add_child(uu_marker))
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	check(p.attack_spawn_point == uu_marker and p.context.attack_spawn_point == uu_marker, "UU2a a child named AttackSpawnPoint is resolved on the character and its context")
	p.attack_component.try_start(true, Vector2.RIGHT)
	await phys(8)
	var uu_live := live_slashes(main)
	check(uu_live.size() >= 1 and uu_live[0].global_position.distance_to(uu_marker.global_position) < 0.01 and uu_marker.global_position.distance_to(p.global_position) > 1.0, "UU2b the spawned effect appears at the marker, not at the character's origin")

	# UU4: the origin follows the marker when it moves.
	uu_marker.position = Vector2(-30, 5)
	check(p.context.get_attack_origin().distance_to(uu_marker.global_position) < 0.01, "UU4 the attack origin follows the marker when it moves")

	# UU5: a marker that was freed falls back to the character's origin.
	uu_marker.free()
	check(p.context.get_attack_origin() == p.global_position, "UU5 after the marker is freed the attack origin is the character's position again")
	await cleanup(main)

	# UU3: the exported reference works with any node name.
	var uu_named := Marker2D.new()
	uu_named.name = "Muzzle"
	uu_named.position = Vector2(0, -20)
	main = await fresh_far_prepared(func(m): mount_exported_marker(m.get_node("Player"), uu_named))
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	p.attack_component.try_start(true, Vector2.RIGHT)
	await phys(8)
	uu_live = live_slashes(main)
	check(p.attack_spawn_point == uu_named and uu_live.size() >= 1 and uu_live[0].global_position.distance_to(uu_named.global_position) < 0.01, "UU3 an exported marker with another name is used for the spawn position")
	await cleanup(main)

	# UU6: a node called AttackSpawnPoint that is not a Marker2D is ignored (one warning is expected in the log).
	var uu_wrong := Node2D.new()
	uu_wrong.name = "AttackSpawnPoint"
	main = await fresh_far_prepared(func(m): m.get_node("Player").add_child(uu_wrong))
	p = main.get_node("Player")
	check(p.attack_spawn_point == null and p.context.get_attack_origin() == p.global_position, "UU6 an AttackSpawnPoint node that is not a Marker2D is ignored")
	await cleanup(main)

	# UU7: the goblin layout supports a marker too.
	var uu_goblin_marker := Marker2D.new()
	uu_goblin_marker.name = "AttackSpawnPoint"
	uu_goblin_marker.position = Vector2(10, 4)
	main = await fresh_far_prepared(func(m): m.get_node("BasicEnemy2D").add_child(uu_goblin_marker))
	uu_goblin = main.get_node("BasicEnemy2D")
	check(uu_goblin.attack_spawn_point == uu_goblin_marker and uu_goblin.context.get_attack_origin().distance_to(uu_goblin_marker.global_position) < 0.01, "UU7 the goblin resolves a marker and uses it as its attack origin")
	await cleanup(main)

	# ---------- VV. 11.1 ProjectileEffect2D ----------
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	await phys(3)
	var vv_scene := load("res://Characters/Components/Combat/ProjectileEffect2D.tscn") as PackedScene
	var vv_probe := vv_scene.instantiate()
	check(vv_probe is ProjectileEffect2D and vv_probe is AttackEffect2D and vv_probe.has_node("Hitbox/CollisionShape2D") and (vv_probe as ProjectileEffect2D).speed > 0.0 and (vv_probe as ProjectileEffect2D).lifetime > 0.0, "VV1 the projectile scene is an AttackEffect2D with a hit area, a speed and a lifetime")
	vv_probe.free()

	# VV2: it travels along its direction at its speed (30 frames at 300 px/s = about 150 px).
	var vv_fly := fire_projectile(main, p, Vector2(5000, 0), Vector2.RIGHT, {"speed": 300.0, "lifetime": 3.0})
	await phys(30)
	var vv_dx: float = vv_fly.global_position.x - 5000.0 if is_alive_node(vv_fly) else -1.0
	check(vv_dx > 130.0 and vv_dx < 170.0 and absf(vv_fly.global_position.y) < 0.01, "VV2 the projectile flies along its direction at its speed (moved %.1f px in 30 frames)" % vv_dx)
	vv_fly.queue_free()

	# VV3: it hits an enemy through the normal damage path and is spent by it when pierce is off.
	var vv_g := parked_goblin(main, Vector2(5100, 400))
	await phys(2)
	var vv_hp: int = vv_g.health_component.health
	var vv_seen: Array = []
	var vv_hit := fire_projectile(main, p, Vector2(5000, 400), Vector2.RIGHT, {"damage": 3, "pierce": false})
	vv_hit.hit_confirmed.connect(func(_target, dealt): vv_seen.append(dealt))
	await phys(40)
	check(vv_g.health_component.health == vv_hp - 3 and vv_seen == [3], "VV3a an arrow damages a goblin once through apply_hit (health %d -> %d, hits %s)" % [vv_hp, vv_g.health_component.health, str(vv_seen)])
	check(not is_alive_node(vv_hit), "VV3b with pierce off the first target ends the projectile")

	# VV4: it never hits its shooter or a character on the shooter's team.
	var vv_shooter := parked_goblin(main, Vector2(5000, 800))
	var vv_mate := parked_goblin(main, Vector2(5100, 800))
	await phys(2)
	var vv_shooter_hp: int = vv_shooter.health_component.health
	var vv_mate_hp: int = vv_mate.health_component.health
	var vv_pass := fire_projectile(main, vv_shooter, vv_shooter.global_position, Vector2.RIGHT, {"damage": 3})
	await phys(40)
	check(vv_shooter.health_component.health == vv_shooter_hp, "VV4a a projectile never hits the character that fired it")
	check(vv_mate.health_component.health == vv_mate_hp and is_alive_node(vv_pass), "VV4b a teammate is not hit and the projectile flies on")
	vv_pass.queue_free()

	# VV5: a solid body on the world layer stops it, and what is behind the wall is safe.
	var vv_wall := StaticBody2D.new()
	vv_wall.collision_layer = 4
	vv_wall.collision_mask = 0
	var vv_wall_shape := CollisionShape2D.new()
	var vv_wall_rect := RectangleShape2D.new()
	vv_wall_rect.size = Vector2(10, 200)
	vv_wall_shape.shape = vv_wall_rect
	vv_wall.add_child(vv_wall_shape)
	main.add_child(vv_wall)
	vv_wall.global_position = Vector2(5100, 1200)
	var vv_behind := parked_goblin(main, Vector2(5160, 1200))
	await phys(2)
	var vv_behind_hp: int = vv_behind.health_component.health
	var vv_world: Array = []
	var vv_shot := fire_projectile(main, p, Vector2(5000, 1200), Vector2.RIGHT, {"lifetime": 3.0})
	vv_shot.world_hit.connect(func(point): vv_world.append(point))
	await phys(60)
	check(not is_alive_node(vv_shot) and vv_behind.health_component.health == vv_behind_hp, "VV5a a wall on the world layer stops the projectile before it reaches the target behind it")
	check(vv_world.size() == 1 and vv_world[0].x > 5080.0 and vv_world[0].x < 5110.0, "VV5b world_hit fires once, at the wall (%s)" % str(vv_world))

	# VV6: with nothing in its way it expires after its lifetime, without a world hit.
	var vv_ttl_world: Array = []
	var vv_ttl := fire_projectile(main, p, Vector2(5000, 1600), Vector2.RIGHT, {"speed": 100.0, "lifetime": 0.25})
	vv_ttl.world_hit.connect(func(point): vv_ttl_world.append(point))
	await phys(8)
	check(is_alive_node(vv_ttl), "VV6a the projectile is still flying before its lifetime is over")
	await phys(25)
	check(not is_alive_node(vv_ttl) and vv_ttl_world.is_empty(), "VV6b it removes itself when the lifetime ends, with no world hit")

	# VV7: pierce and max_targets (10.4) work on a projectile.
	var vv_p1 := parked_goblin(main, Vector2(5100, 2000))
	var vv_p2 := parked_goblin(main, Vector2(5200, 2000))
	await phys(2)
	var vv_p1_hp: int = vv_p1.health_component.health
	var vv_p2_hp: int = vv_p2.health_component.health
	var vv_pierce := fire_projectile(main, p, Vector2(5000, 2000), Vector2.RIGHT, {"lifetime": 3.0, "damage": 2})
	await phys(60)
	check(vv_p1.health_component.health == vv_p1_hp - 2 and vv_p2.health_component.health == vv_p2_hp - 2 and is_alive_node(vv_pierce), "VV7a a piercing projectile hits both targets in line and flies on")
	vv_pierce.queue_free()
	var vv_q1 := parked_goblin(main, Vector2(5100, 2400))
	var vv_q2 := parked_goblin(main, Vector2(5200, 2400))
	await phys(2)
	var vv_q1_hp: int = vv_q1.health_component.health
	var vv_q2_hp: int = vv_q2.health_component.health
	var vv_one := fire_projectile(main, p, Vector2(5000, 2400), Vector2.RIGHT, {"lifetime": 3.0, "damage": 2, "max_targets": 1})
	await phys(60)
	check(vv_q1.health_component.health == vv_q1_hp - 2 and vv_q2.health_component.health == vv_q2_hp and not is_alive_node(vv_one), "VV7b max_targets 1 hits the first target only, then the projectile ends")

	# VV8: the attack's hit_layers choose the targets: a mask of the player layer alone passes through a goblin.
	var vv_l := parked_goblin(main, Vector2(5100, 2800))
	await phys(2)
	var vv_l_hp: int = vv_l.health_component.health
	var vv_layer := fire_projectile(main, p, Vector2(5000, 2800), Vector2.RIGHT, {"lifetime": 3.0, "layers": 1})
	await phys(40)
	check(vv_l.health_component.health == vv_l_hp and is_alive_node(vv_layer), "VV8 a projectile whose hit_layers leave out the goblin's layer passes through it")
	vv_layer.queue_free()

	# VV9: AttackComponent2D spawns it like any effect: no change to the component, normal damage path, tracked until spent.
	var vv_def := definition_variant(p.attack_component.get_attack(&"player_light"), &"vv_arrow")
	vv_def.effect_scene = vv_scene
	vv_def.pierce = false
	check(p.attack_component.set_attack_definition(vv_def), "VV9pre the attack component accepts an attack whose effect scene is a projectile")
	e.global_position = p.global_position + Vector2(70, 0)
	await phys(2)
	var vv_e_hp: int = e.health_component.health
	p.attack_component.try_start(true, Vector2.RIGHT)
	await phys(60)
	check(e.health_component.health == vv_e_hp - vv_def.damage, "VV9a the attack component fires the projectile and it damages the goblin (health %d -> %d, expected -%d)" % [vv_e_hp, e.health_component.health, vv_def.damage])
	check(p.attack_component.get_active_effect_count() == 0, "VV9b the spent projectile is no longer tracked by the attack component (%d left)" % p.attack_component.get_active_effect_count())
	await cleanup(main)

	# ---------- WW. 11.2 arrow attack definitions and projectile_speed ----------
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	await phys(3)
	var ww_light := load(ARROW_LIGHT_PATH) as AttackDefinition2D
	var ww_heavy := load(ARROW_HEAVY_PATH) as AttackDefinition2D
	check(ww_light != null and ww_heavy != null and ww_light.effect_scene != null and ww_light.effect_scene.resource_path == ARROW_SCENE_PATH and ww_heavy.effect_scene == ww_light.effect_scene, "WW1 both arrow definitions load and use Arrow.tscn as their effect scene")
	var ww_probe := ww_light.effect_scene.instantiate()
	var ww_scene_speed: float = (ww_probe as ProjectileEffect2D).speed if ww_probe is ProjectileEffect2D else -1.0
	check(ww_probe is ProjectileEffect2D and ww_probe.has_node("Visual") and ww_probe.get_node("Visual") is Sprite2D and ww_probe.has_node("Hitbox/CollisionShape2D"), "WW2 Arrow.tscn is a ProjectileEffect2D with a sprite instead of the placeholder polygon, and a hit area")
	ww_probe.free()
	check(ww_light.id == &"arrow_shot" and ww_heavy.id == &"arrow_heavy" and ww_light.projectile_speed == 420.0 and ww_heavy.projectile_speed == 600.0 and not ww_light.pierce and ww_heavy.pierce and ww_heavy.max_targets == 3, "WW3 the arrow definitions carry their numbers as data (speeds 420 and 600, light stops at one target, heavy pierces up to 3)")
	check(ww_light.projectile_speed / 60.0 < ww_light.hitbox_size.x and ww_heavy.projectile_speed / 60.0 < ww_heavy.hitbox_size.x, "WW4 both speeds stay below the hitbox length per frame at 60 fps (no tunnelling, see 11.1 notes)")
	var ww_melee_ok := true
	for ww_path in ["res://Characters/Components/Combat/DefaultAttackDefinition.tres", "res://Characters/Components/Combat/PlayerLight2AttackDefinition.tres", "res://Characters/Components/Combat/PlayerHeavyAttackDefinition.tres", "res://Characters/Components/Combat/GoblinAttackDefinition.tres", "res://Characters/Components/Combat/GoblinLungeAttackDefinition.tres"]:
		ww_melee_ok = ww_melee_ok and (load(ww_path) as AttackDefinition2D).projectile_speed == 0.0
	check(ww_melee_ok, "WW5 every shipped melee definition keeps projectile_speed 0 (the field is ignored by melee)")

	# The speed reaches the projectile through configure().
	var ww_a := fire_arrow(main, p, Vector2(5000, 400), ww_light)
	await phys(30)
	var ww_dx := ww_a.global_position.x - 5000.0
	check(ww_a.speed == 420.0 and ww_dx > 190.0 and ww_dx < 230.0, "WW6 the definition's projectile_speed is the flight speed (speed %.0f, moved %.1f px in 30 frames, expected about 210)" % [ww_a.speed, ww_dx])
	ww_a.queue_free()
	var ww_zero := ww_light.duplicate() as AttackDefinition2D
	ww_zero.projectile_speed = 0.0
	var ww_b := fire_arrow(main, p, Vector2(5000, 500), ww_zero)
	await phys(2)
	check(ww_b.speed == ww_scene_speed, "WW7 projectile_speed 0 keeps the scene's own speed (%.0f)" % ww_b.speed)
	ww_b.queue_free()
	var ww_slow := ww_light.duplicate() as AttackDefinition2D
	ww_slow.projectile_speed = 250.0
	var ww_c := fire_arrow(main, p, Vector2(5000, 600), ww_slow)
	await phys(30)
	var ww_cdx := ww_c.global_position.x - 5000.0
	check(ww_c.speed == 250.0 and ww_cdx > 110.0 and ww_cdx < 140.0, "WW8 a different projectile_speed changes the flight (moved %.1f px in 30 frames, expected about 125)" % ww_cdx)
	ww_c.queue_free()

	# The hit policy comes from the definition: the light arrow stops at the first target, the heavy one pierces up to three.
	var ww_g1 := parked_goblin(main, Vector2(5100, 800))
	var ww_g2 := parked_goblin(main, Vector2(5200, 800))
	await phys(2)
	var ww_g1_hp := hp_of(ww_g1)
	var ww_g2_hp := hp_of(ww_g2)
	var ww_shot := fire_arrow(main, p, Vector2(5000, 800), ww_light)
	await phys(60)
	check(hp_of(ww_g1) == ww_g1_hp - ww_light.damage and hp_of(ww_g2) == ww_g2_hp and not is_alive_node(ww_shot), "WW9 the light arrow hits the first goblin for %d and is spent (second goblin untouched)" % ww_light.damage)
	var ww_h: Array = []
	for ww_i in 4:
		ww_h.append(parked_goblin(main, Vector2(5100 + 100 * ww_i, 1200)))
	await phys(2)
	var ww_h_hp: Array = ww_h.map(func(g): return hp_of(g))
	var ww_hshot := fire_arrow(main, p, Vector2(5000, 1200), ww_heavy)
	await phys(70)
	var ww_h_ok: bool = true
	for ww_i in 3:
		ww_h_ok = ww_h_ok and hp_of(ww_h[ww_i]) == ww_h_hp[ww_i] - ww_heavy.damage
	check(ww_h_ok and hp_of(ww_h[3]) == ww_h_hp[3] and not is_alive_node(ww_hshot), "WW10 the heavy arrow pierces three goblins for %d each and is spent before the fourth" % ww_heavy.damage)

	# Through AttackComponent2D, with the sword's clips, so only the effect is new: speed handed over, damage dealt, no slash.
	var ww_def := definition_variant(ww_light, &"ww_arrow")
	ww_def.weapon_animation = &"sword_slash_1"
	ww_def.recovery_animation = &"sword_slash_return_1"
	check(p.attack_component.set_attack_definition(ww_def), "WW11pre the attack component accepts the arrow attack with an existing weapon clip")
	e.global_position = p.global_position + Vector2(120, 0)
	await phys(2)
	var ww_e_hp := hp_of(e)
	var ww_seen_speed := -1.0
	var ww_slashes := 0
	p.attack_component.try_start(true, Vector2.RIGHT)
	for ww_i in 70:
		await phys(1)
		for ww_node in effects_from(main, ARROW_SCENE_PATH):
			ww_seen_speed = (ww_node as ProjectileEffect2D).speed
		ww_slashes += live_slashes(main).size()
	check(hp_of(e) == ww_e_hp - ww_def.damage and ww_seen_speed == 420.0 and ww_slashes == 0, "WW11 AttackComponent2D fires the arrow at the definition's speed (%.0f), it damages the goblin (%d -> %d) and no slash is spawned" % [ww_seen_speed, ww_e_hp, hp_of(e)])

	# Validation names the attack and the clip, as for melee: the sword has no 'bow_shoot'.
	var ww_msg: String = p.attack_component.validate_definition(ww_light)
	check(ww_msg.contains("arrow_shot") and ww_msg.contains("bow_shoot"), "WW12 a missing clip is reported with the attack and the clip name (%s)" % ww_msg)
	var ww_bad := definition_variant(ww_def, &"ww_bad_scene")
	ww_bad.effect_scene = null
	check(p.attack_component.validate_definition(ww_bad).contains("ww_bad_scene") and not p.attack_component.set_attack_definition(ww_bad), "WW13 an arrow attack with no effect scene is still refused, naming the attack")
	await cleanup(main)

	# ---------- XX. 11.3 bow weapon ----------
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	await phys(3)
	var xx_bow := load(BOW_WEAPON_PATH) as WeaponDefinition2D
	var xx_ctl: WeaponController2D = p.weapon_controller
	var xx_problems := xx_ctl.validate_equip(xx_bow)
	check(xx_bow != null and xx_bow.weapon_id == &"bow" and xx_problems.is_empty(), "XX1 validate_equip() for the bow returns no problems (%s)" % str(xx_problems))
	var xx_scene := load(BOW_SCENE_PATH) as PackedScene
	var xx_inst := xx_scene.instantiate()
	var xx_anim := xx_inst.get_node("HandAnim") as AnimationPlayer
	var xx_clips_ok := true
	for xx_clip in [&"bow_charge", &"bow_shoot", &"bow_heavy_shoot", &"bow_return"]:
		xx_clips_ok = xx_clips_ok and xx_anim.has_animation(xx_clip)
	check(xx_clips_ok and xx_anim.get_animation(&"bow_charge").loop_mode == Animation.LOOP_LINEAR, "XX2 Bow.tscn has the charge (looping), shoot, heavy shoot and return clips")
	var xx_events := {}
	for xx_clip in [&"bow_shoot", &"bow_heavy_shoot"]:
		var xx_a := xx_anim.get_animation(xx_clip)
		var xx_n := 0
		for xx_t in xx_a.get_track_count():
			if xx_a.track_get_type(xx_t) == Animation.TYPE_METHOD:
				for xx_k in xx_a.track_get_key_count(xx_t):
					var xx_params := xx_a.method_track_get_params(xx_t, xx_k)
					if xx_a.method_track_get_name(xx_t, xx_k) == &"attack_event" and xx_params.size() == 1 and xx_params[0] == &"spawn_effect":
						xx_n += 1
		xx_events[xx_clip] = xx_n
	check(xx_events[&"bow_shoot"] == 1 and xx_events[&"bow_heavy_shoot"] == 1, "XX3 each shot clip has exactly one spawn_effect key at the release (%s)" % str(xx_events))
	xx_inst.free()
	var xx_failed := []
	xx_ctl.equip_failed.connect(func(_w, problems): xx_failed.append(problems))
	check(xx_ctl.equip(xx_bow) and xx_failed.is_empty(), "XX4 the bow equips")
	check(p.context.weapon_pivot.scene_file_path == BOW_SCENE_PATH and p.get_default_attack_id() == &"arrow_shot" and p.get_heavy_attack_id() == &"arrow_heavy" and p.attack_component.has_attack(&"arrow_heavy") and p.context.weapon_animation_player.has_animation(&"bow_shoot"), "XX5 the bow is mounted and the player's light and heavy ids come from it")
	check(not p.attack_component.has_attack(&"player_light") and not p.attack_component.has_attack(&"player_heavy"), "XX6 the sword's attacks are gone from the attack component")

	# A light shot, straight right: one arrow, no slash, 4 damage, and the swing ends.
	e.global_position = p.global_position + Vector2(120, 0)
	var xx_g2 := parked_goblin(main, p.global_position + Vector2(240, 0))
	await phys(2)
	var xx_e_hp := hp_of(e)
	var xx_g2_hp := hp_of(xx_g2)
	var xx_arrows := 0
	var xx_slashes := 0
	check(p.attack_component.try_start_attack(&"arrow_shot", Vector2.RIGHT), "XX7pre the bow's light attack starts")
	for xx_i in 40:
		await phys(1)
		xx_arrows = maxi(xx_arrows, effects_from(main, ARROW_SCENE_PATH).size())
		xx_slashes += live_slashes(main).size()
	check(hp_of(e) == xx_e_hp - 4 and hp_of(xx_g2) == xx_g2_hp and xx_arrows == 1 and xx_slashes == 0, "XX7 a light shot spawns one arrow, hits the first goblin for 4, leaves the one behind it, and no slash appears (health %d -> %d)" % [xx_e_hp, hp_of(e)])
	await phys(60)
	check(not p.context.is_attacking and absf(p.context.weapon_facing_root.rotation) < 0.01, "XX8 the shot and its return clip finish and the weapon pivot is back at rest")

	# A charged shot: the charge runs, the release fires a piercing arrow through both goblins.
	var xx_e_hp2 := hp_of(e)
	var xx_g2_hp2 := hp_of(xx_g2)
	check(p.attack_component.begin_charge(&"arrow_heavy", Vector2.RIGHT), "XX9pre the bow's heavy attack begins charging")
	await phys(20)
	var xx_charging: bool = p.attack_component.is_charging()
	check(p.attack_component.release_charge(Vector2.RIGHT), "XX9pre2 the charge can be released")
	await phys(70)
	check(xx_charging and hp_of(e) == xx_e_hp2 - 9 and hp_of(xx_g2) == xx_g2_hp2 - 9, "XX9 the charged shot pierces both goblins for 9 each (health %d, %d)" % [hp_of(e), hp_of(xx_g2)])

	# Aim straight down: the arrow follows the attack direction, not the facing.
	e.global_position = p.global_position + Vector2(0, 120)
	await phys(2)
	var xx_e_hp3 := hp_of(e)
	p.attack_component.try_start_attack(&"arrow_shot", Vector2.DOWN)
	await phys(70)
	check(hp_of(e) == xx_e_hp3 - 4, "XX10 a shot aimed straight down hits a goblin below (health %d -> %d)" % [xx_e_hp3, hp_of(e)])
	check(xx_failed.is_empty(), "XX11 no equip failure was reported in this section")
	await cleanup(main)

	# ---------- YY. 11.4 weapon switching ----------
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	await phys(3)
	var yy_ctl: WeaponController2D = p.weapon_controller
	var yy_sword := load(SWORD_WEAPON_PATH) as WeaponDefinition2D
	var yy_bow := load(BOW_WEAPON_PATH) as WeaponDefinition2D
	var yy_events := InputMap.action_get_events(&"weapon_next") if InputMap.has_action(&"weapon_next") else []
	check(InputMap.has_action(&"weapon_next") and yy_events.size() == 1 and yy_events[0] is InputEventKey, "YY1 the weapon_next input action exists with a key bound")
	check(yy_ctl.loadout.size() == 2 and yy_ctl.loadout[0].weapon_id == &"sword" and yy_ctl.loadout[1].weapon_id == &"bow" and yy_ctl.get_equipped_weapon().weapon_id == &"sword", "YY2 the player's loadout is sword then bow and the sword is equipped at the start")
	check(p.get_light_attack_id() == &"player_light" and p.get_heavy_attack_id() == &"player_heavy", "YY3 with the sword the light and heavy ids are the sword's")
	check(yy_ctl.equip_next() and yy_ctl.get_equipped_weapon().weapon_id == &"bow" and p.context.weapon_pivot.scene_file_path == BOW_SCENE_PATH, "YY4 equip_next() switches sword to bow and mounts the bow scene")
	check(p.get_light_attack_id() == &"arrow_shot" and p.get_heavy_attack_id() == &"arrow_heavy", "YY5 the ids now come from the bow (9.7d-1)")
	check(yy_ctl.equip_next() and yy_ctl.get_equipped_weapon().weapon_id == &"sword" and p.context.weapon_pivot.scene_file_path == "res://Weapons/Sword.tscn" and p.get_light_attack_id() == &"player_light", "YY6 equip_next() wraps around from the bow back to the sword")

	# Refused during a swing, allowed after.
	check(p.attack_component.try_start_attack(&"player_light", Vector2.RIGHT), "YY7pre a sword swing starts")
	await phys(5)
	check(p.context.is_attacking and not yy_ctl.equip_next() and yy_ctl.get_equipped_weapon().weapon_id == &"sword", "YY7 equip_next() is refused during a swing and the sword stays")
	await phys(120)
	check(not p.context.is_attacking and yy_ctl.equip_next() and yy_ctl.get_equipped_weapon().weapon_id == &"bow", "YY8 after the swing ends the switch works")
	check(yy_ctl.equip_next() and yy_ctl.get_equipped_weapon().weapon_id == &"sword", "YY8b and back to the sword")

	# A weapon that cannot be equipped rolls back and the next one is tried.
	var yy_broken_attack := definition_variant(p.attack_component.get_attack(&"player_light"), &"yy_broken_attack")
	yy_broken_attack.weapon_animation = &"no_such_clip"
	var yy_broken := make_weapon(&"yy_broken", [yy_broken_attack]) as WeaponDefinition2D
	var yy_failed := []
	yy_ctl.equip_failed.connect(func(_w, problems): yy_failed.append(problems))
	var yy_only: Array[WeaponDefinition2D] = [yy_sword, yy_broken]
	yy_ctl.loadout = yy_only
	var yy_ids_before: Array = p.attack_component.get_attack_ids()
	check(not yy_ctl.equip_next() and yy_failed.size() == 1 and yy_ctl.get_equipped_weapon().weapon_id == &"sword" and p.attack_component.get_attack_ids() == yy_ids_before and p.context.weapon_pivot.scene_file_path == "res://Weapons/Sword.tscn", "YY9 a failed equip rolls back: same weapon, same attacks, same mount, equip_failed reported once")
	var yy_skip: Array[WeaponDefinition2D] = [yy_sword, yy_broken, yy_bow]
	yy_ctl.loadout = yy_skip
	check(yy_ctl.equip_next() and yy_ctl.get_equipped_weapon().weapon_id == &"bow", "YY10 equip_next() skips the weapon that fails and equips the next one")
	var yy_single: Array[WeaponDefinition2D] = [yy_bow]
	yy_ctl.loadout = yy_single
	check(not yy_ctl.equip_next() and yy_ctl.get_equipped_weapon().weapon_id == &"bow", "YY11 a loadout with nothing else to switch to does nothing")
	var yy_empty: Array[WeaponDefinition2D] = []
	yy_ctl.loadout = yy_empty
	check(not yy_ctl.equip_next(), "YY12 an empty loadout does nothing")
	var yy_both: Array[WeaponDefinition2D] = [yy_sword, yy_bow]
	yy_ctl.loadout = yy_both

	# The real input path: pressing the action switches once per press, through player.gd.
	check(yy_ctl.get_equipped_weapon().weapon_id == &"bow", "YY13pre the bow is equipped before the input test")
	Input.action_press("weapon_next")
	await phys(3)
	Input.action_release("weapon_next")
	await phys(2)
	check(yy_ctl.get_equipped_weapon().weapon_id == &"sword", "YY13 pressing weapon_next switches once (bow to sword), not once per frame held")
	Input.action_press("weapon_next")
	await phys(3)
	Input.action_release("weapon_next")
	await phys(2)
	check(yy_ctl.get_equipped_weapon().weapon_id == &"bow", "YY14 the next press switches again (sword to bow)")
	# A dead player does not switch.
	p.health_component.apply_hit(HitData.new(9999, e, Vector2.RIGHT))
	await phys(2)
	Input.action_press("weapon_next")
	await phys(3)
	Input.action_release("weapon_next")
	await phys(2)
	check(not p.is_alive() and yy_ctl.get_equipped_weapon().weapon_id == &"bow", "YY15 a dead player does not switch weapons")
	await cleanup(main)

	# ---------- ZZ. 11.5 goblin archer ----------
	var zz_archer_path := "res://Characters/Enemies/GoblinArcher.tscn"
	var zz_raw := (load("res://Main.tscn") as PackedScene).instantiate()
	check(zz_raw.has_node("GoblinArcher") and zz_raw.get_node("GoblinArcher") is BasicEnemy2D, "ZZ1 Main.tscn has a GoblinArcher in the arena")
	zz_raw.free()
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	var zz_a := (load(zz_archer_path) as PackedScene).instantiate() as BasicEnemy2D
	main.add_child(zz_a)
	zz_a.global_position = p.global_position + Vector2(160, 0)
	await phys(3)
	check(zz_a.team == &"enemy" and zz_a.is_in_group("enemy") and zz_a.attack_component.get_attack_ids() == [&"goblin_arrow"] and zz_a.attack_component.definition.effect_scene.resource_path == ARROW_SCENE_PATH, "ZZ2 the archer is an enemy whose only attack is goblin_arrow, with the arrow as its effect")
	check(zz_a.attack_component.validate_definition(zz_a.attack_component.definition) == "" and zz_a.context.weapon_animation_player.has_animation(&"bow_shoot") and zz_a.context.weapon_animation_player.has_animation(&"bow_return"), "ZZ3 the arrow attack validates against the archer's own bow clips")
	check(zz_a.get_node("AnimatedSprite2D/Weapon").texture.resource_path.ends_with("Bow.png") and zz_a.get_node("HealthComponent2D").max_health < e.health_component.max_health, "ZZ4 the archer carries a bow and has less health than a goblin")
	check(zz_a._ai_controller.get_effective_attack_range() == 170.0 and zz_a._ai_controller.get_detection_radius() == 260.0 and e._ai_controller.get_detection_radius() == 200.0, "ZZ5 its AI starts shooting at 170 px and notices targets at 260 px, without changing the goblin's 200 px")

	# It shoots from where it stands (inside its range), an arrow crosses a goblin of its own team, and the player is hurt.
	var zz_mate := parked_goblin(main, p.global_position + Vector2(80, 0))
	await phys(2)
	var zz_mate_hp := hp_of(zz_mate)
	var zz_p_hp := hp_of(p)
	var zz_start := zz_a.global_position
	var zz_arrows := 0
	var zz_slashes := 0
	var zz_min := 9999.0
	for zz_i in 150:
		await phys(1)
		zz_arrows = maxi(zz_arrows, effects_from(main, ARROW_SCENE_PATH).size())
		zz_slashes += live_slashes(main).size()
		zz_min = minf(zz_min, zz_a.global_position.distance_to(p.global_position))
	check(zz_arrows >= 1 and zz_slashes == 0, "ZZ6 the archer fires arrows and never swings a slash (arrows seen %d)" % zz_arrows)
	check(hp_of(p) < zz_p_hp and hp_of(p) >= zz_p_hp - 3, "ZZ7 its arrows hurt the player for 1 each (health %d -> %d)" % [zz_p_hp, hp_of(p)])
	check(hp_of(zz_mate) == zz_mate_hp, "ZZ8 an arrow flies through a goblin of its own team without hurting it")
	check(zz_a.global_position.distance_to(zz_start) < 10.0 and zz_min > 140.0 and zz_a._ai_controller.get_behavior_name() == "ATTACK", "ZZ9 it keeps its distance: it did not walk toward a player already inside its range (closest %.0f px, behavior %s)" % [zz_min, zz_a._ai_controller.get_behavior_name()])
	await cleanup(main)

	# From beyond its range but inside its detection radius it walks in until the player is in range, then shoots.
	main = await fresh_far()
	p = main.get_node("Player")
	e = main.get_node("BasicEnemy2D")
	e.set_physics_process(false)
	zz_a = (load(zz_archer_path) as PackedScene).instantiate() as BasicEnemy2D
	main.add_child(zz_a)
	zz_a.global_position = p.global_position + Vector2(240, 0)
	await phys(3)
	zz_p_hp = hp_of(p)
	var zz_far_arrows := 0
	var zz_walked := false
	for zz_i in 200:
		await phys(1)
		zz_far_arrows = maxi(zz_far_arrows, effects_from(main, ARROW_SCENE_PATH).size())
		zz_walked = zz_walked or zz_a._ai_controller.get_behavior_name() == "CHASE"
	var zz_dist := zz_a.global_position.distance_to(p.global_position)
	check(zz_walked and zz_far_arrows >= 1 and zz_dist < 200.0 and hp_of(p) < zz_p_hp, "ZZ10 an archer starting at 240 px chases until in range, then shoots (distance %.0f px, arrows seen %d, player health %d -> %d)" % [zz_dist, zz_far_arrows, zz_p_hp, hp_of(p)])
	# The player's own arrow kills it the normal way: the archer is a normal damageable character.
	var zz_hp := hp_of(zz_a)
	zz_a.apply_hit(HitData.new(4, p, Vector2.LEFT))
	check(hp_of(zz_a) == zz_hp - 4, "ZZ11 the archer takes damage through apply_hit like any character")
	await cleanup(main)
