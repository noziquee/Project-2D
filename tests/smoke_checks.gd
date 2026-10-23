extends SceneTree

var failures := 0
var passes := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
	else:
		failures += 1
	print(("CHECK PASS  " if cond else "CHECK FAIL  ") + msg)

func phys(n: int) -> void:
	for i in n:
		await physics_frame

func fresh() -> Node:
	var main: Node = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await phys(3)
	return main

## Like fresh(), but the goblin starts 400 px away, outside its detection area.
func fresh_far() -> Node:
	var main: Node = load("res://Main.tscn").instantiate()
	(main.get_node("BasicEnemy2D") as Node2D).position = Vector2(400, 0)
	root.add_child(main)
	await phys(3)
	return main

func cleanup(main: Node) -> void:
	main.queue_free()
	await phys(2)

## Weapon swing length in seconds (slash + sword_return, scaled by the player's speed).
func weapon_cycle_seconds(ch: Character2D) -> float:
	var ap: AnimationPlayer = ch.context.weapon_animation_player
	var total: float = ap.get_animation(&"slash").length + ap.get_animation(&"sword_return").length
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
		if comp.try_start(true, Vector2.RIGHT):
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
	check(absf(b.gap_frames - 0.5 * fps) <= tol, "%s6 raising cooldown_duration to 0.5 widens the gap (%d frames, expected %.1f)" % [label, b.gap_frames, 0.5 * fps])
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
	return d

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
		out.append(str(state.get_node_path(i)))
	return out

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
	check(p.context.weapon_animation_player != null and p.context.weapon_animation_player.has_animation(&"slash"), "A4 player weapon player has 'slash'")
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
	check(e.health_component.health == e.health_component.max_health - 1, "B3 enemy took exactly 1 damage (health=%d)" % e.health_component.health)
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
	e.global_position = p.global_position + Vector2(150, 0)
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
	check(p.attack_definition.weapon_animation == &"slash" and p.attack_definition.recovery_animation == &"sword_return", "I1 player definition names its weapon and recovery clips")
	check(p.attack_definition.effect_scene != null and e.attack_definition.effect_scene != null, "I2 both shipped definitions carry their own effect scene")
	check(e.attack_definition.ai_attack_range > 0.0 and is_equal_approx(ai.get_effective_attack_range(), e.attack_definition.ai_attack_range), "I3 goblin AI takes its range from the definition (%.0f)" % ai.get_effective_attack_range())
	await cleanup(main)

	# I4-I6: a definition with different clip names plays correctly.
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	var ap: AnimationPlayer = p.context.weapon_animation_player
	var heavy_lib := add_clip_aliases(ap, {&"heavy_swing": &"slash", &"heavy_recover": &"sword_return"})
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
	var quick_lib := add_clip_aliases(ap, {&"quick_swing": &"slash"})
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

	# I26-I27: effect_scene on the definition overrides the character's legacy scene.
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
	var no_effect := definition_variant(p.attack_definition, &"test_no_effect")
	no_effect.effect_scene = null
	p.attack_definition = no_effect
	p.attack_component.try_start(true, Vector2.RIGHT)
	await phys(8)
	check(count_slashes(main) >= 1 and count_slashes(main, &"from_definition") == 0, "I27 with no effect_scene the character's legacy slash scene is used")
	await cleanup(main)

	# ---------- J. Phase 3: generic animation events and multi-hit ----------
	main = await fresh()
	p = main.get_node("Player")
	var ge: Character2D = main.get_node("BasicEnemy2D")
	ge.set_physics_process(false)
	check(p.has_method("attack_event") and not p.has_method("spawn_slash"), "J1 attack_event exists and the spawn_slash alias is gone")
	for pair in [["player", p], ["goblin", ge]]:
		var ch: Character2D = pair[1]
		var evs := clip_events(ch.context.weapon_animation_player.get_animation(&"slash"))
		check(evs.size() == 1 and evs[0][0] == &"attack_event" and evs[0][1] == [&"spawn_effect"], "J2 %s slash clip fires attack_event(spawn_effect) (%s)" % [pair[0], str(evs)])
	check(AttackComponent2D.is_known_event(&"spawn_effect") and AttackComponent2D.is_known_event(&"combo_window_open") and AttackComponent2D.is_known_event(&"combo_window_close") and not AttackComponent2D.is_known_event(&"nope"), "J3 spawn_effect and the reserved combo events are the known events")

	# Events outside an attack are ignored.
	p.attack_event(&"spawn_effect")
	await phys(2)
	check(count_slashes(main) == 0 and p.attack_component.get_active_effect_count() == 0, "J4 attack_event(spawn_effect) with no attack running spawns nothing")

	# J5-J9: a clip with two spawn_effect events creates two slashes (flurry).
	var ap2: AnimationPlayer = p.context.weapon_animation_player
	var flurry_lib := add_clip_aliases(ap2, {&"flurry_swing": &"slash"})
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
	check(p.health_component is HealthComponent2D and p.health_component.max_health == 5 and p.health_component.health == 5, "K1 player has a HealthComponent2D (max 5, full health)")
	check(ke.health_component is HealthComponent2D and ke.health_component.max_health == 3 and ke.health_component.health == 3, "K2 goblin has a HealthComponent2D (max 3)")

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
	ke.health_component.max_health = 6
	check(ke.health_component.max_health == 6 and announced.back() == [3, 6], "K20 setting the component's max_health emits health_changed (%s)" % str(announced))
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
	check(swing_results[&"third_faction"] == 1, "L4 a third team is damaged without any script change (took %d)" % swing_results[&"third_faction"])
	check(swing_results[&""] == 1, "L5 a neutral (empty-team) target can be hit (took %d)" % swing_results[&""])
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
	check(layer_results[2] == 1, "L8 the enemy layer hits the goblin (took %d)" % layer_results[2])
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
	check(p.movement_component.move_speed == 200.0 and p.dash_component.dash_speed == 600.0 and p.dash_component.dash_duration == 0.16 and p.dash_component.dash_cooldown == 0.45, "M3 player keeps the default move and dash values")
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
		var good := forward.is_equal_approx(aim) or (absf(aim.x) < 0.001 and forward.is_equal_approx(aim))
		aim_ok = aim_ok and good
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
	check(det != null and det.collision_layer == 0 and det.collision_mask == 1 and not det.monitorable, "Q1 the goblin has a DetectionArea that watches the player layer only")
	check(det_shape != null and det_shape.shape is CircleShape2D and is_equal_approx((det_shape.shape as CircleShape2D).radius, 180.0), "Q2 DetectionArea has a drawn CircleShape2D (radius 180)")
	check(ai.detection_area == det and ai.profile is EnemyBehaviorProfile, "Q3 the AI controller points at the area and a profile resource")
	check(is_equal_approx(ai.profile.disengage_radius, 250.0) and is_equal_approx(ai.profile.lost_target_grace_duration, 0.75) and is_equal_approx(ai.profile.home_stop_distance, 5.0) and is_zero_approx(ai.profile.detection_radius), "Q4 the goblin profile carries the old controller values (detection 0 = use the drawn shape)")
	check(is_equal_approx(ai.get_detection_radius(), 180.0), "Q5 detection radius is read from the drawn shape (%.0f)" % ai.get_detection_radius())
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
	e.global_position = p.global_position + Vector2(400, 0)
	await phys(10)
	check(ai.get_current_target() == null and ai.behavior == EnemyAIController2D.Behavior.IDLE and ai.get_candidate_count() == 0, "Q8 a player outside the detection area is ignored (behavior=%s)" % ai.get_behavior_name())
	var seen_behaviors: Array = []
	ai.behavior_changed.connect(func(_prev, cur): seen_behaviors.append(cur))
	e.global_position = p.global_position + Vector2(150, 0)
	await phys(10)
	check(ai.get_current_target() == p and ai.get_candidate_count() == 1 and ai.behavior == EnemyAIController2D.Behavior.CHASE, "Q9 once inside the area the goblin targets and chases (behavior=%s)" % ai.get_behavior_name())
	check(not seen_behaviors.is_empty() and seen_behaviors[0] == EnemyAIController2D.Behavior.CHASE, "Q10 behavior_changed reports enum values")
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
	custom_profile.detection_radius = 50.0
	var tuned: Character2D = (load(GOBLIN_SCENE) as PackedScene).instantiate()
	tuned.get_node("EnemyAIController2D").profile = custom_profile
	main.add_child(tuned)
	tuned.global_position = p.global_position + Vector2(100, 0)
	await phys(10)
	var tuned_ai: EnemyAIController2D = tuned.get_node("EnemyAIController2D")
	check(is_equal_approx(tuned_ai.get_detection_radius(), 50.0) and tuned_ai.get_current_target() == null, "Q15 profile.detection_radius = 50 overrides the drawn 180 (player at 100 px ignored)")
	var other: Character2D = (load(GOBLIN_SCENE) as PackedScene).instantiate()
	main.add_child(other)
	await phys(2)
	check(is_equal_approx(other.get_node("EnemyAIController2D").get_detection_radius(), 180.0), "Q16 the override did not change the shared scene shape (another goblin still has 180)")
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
	check(bar.get_shown_health() == 5.0 and bar.get_counter_text() == "5 / 5", "R8 the bar starts full (%s)" % bar.get_counter_text())
	var full_color: Color = bar.progress_bar.modulate
	check(full_color.is_equal_approx(bar.color_gradient.sample(1.0)), "R9 a full bar uses the high colour")

	await phys(25) # let the intro clip finish
	p.take_damage(2)
	await phys(2)
	check(bar_clips.current_animation == "hit" and bar_clips.is_playing(), "R10 a hit plays the hit clip (got '%s')" % bar_clips.current_animation)
	await phys(20)
	check(is_equal_approx(bar.get_shown_health(), 3.0) and bar.get_counter_text() == "3 / 5", "R11 the bar value and counter follow health_changed (%s)" % bar.get_counter_text())
	check(bar.get_trail_health() > 3.0, "R12 the damage trail lags behind the bar (%.2f)" % bar.get_trail_health())
	await phys(90)
	check(is_equal_approx(bar.get_trail_health(), 3.0), "R13 the damage trail catches up (%.2f)" % bar.get_trail_health())
	p.take_damage(1)
	await phys(40)
	check(bar.progress_bar.modulate.is_equal_approx(bar.color_gradient.sample(0.4)) and not bar.progress_bar.modulate.is_equal_approx(full_color), "R14 40 percent health switches to the mid colour")
	check(not bar.is_critical(), "R15 40 percent is not critical")
	p.take_damage(1)
	await phys(40)
	check(bar.is_critical() and bar_clips.current_animation == "critical" and bar_clips.is_playing(), "R16 20 percent health runs the critical clip (got '%s')" % bar_clips.current_animation)
	check(bar.progress_bar.modulate.is_equal_approx(bar.color_gradient.sample(0.2)), "R17 20 percent uses the low colour")
	p.heal(2)
	await phys(2)
	check(bar_clips.current_animation == "heal", "R18 healing plays the heal clip (got '%s')" % bar_clips.current_animation)
	await phys(40)
	check(is_equal_approx(bar.get_shown_health(), 3.0) and not bar.is_critical() and bar_clips.current_animation != "critical", "R19 healing out of the critical range stops the pulse (%s)" % bar_clips.current_animation)
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
	check(ebar.visible and ebar.get_counter_text() == "2 / 3" and is_equal_approx(ebar.get_shown_health(), 2.0), "R25 the first hit reveals the bar and it follows health (%s)" % ebar.get_counter_text())
	check(ebar.get_node("Card/Padding/Content/BarStack/BarLabel").text == "2 / 3", "R26 the on-bar label shows the same counter")
	await cleanup(main)
