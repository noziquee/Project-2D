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

func cleanup(main: Node) -> void:
	main.queue_free()
	await phys(2)

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
	for c in main.get_children():
		if c is AttackSlash2D:
			slash_count += 1
	check(slash_count >= 1 or e.health < e.max_health, "B2 a slash was spawned by the animation event")
	await phys(40)
	check(e.health == e.max_health - 1, "B3 enemy took exactly 1 damage (health=%d)" % e.health)
	check(p.global_position.is_equal_approx(start_pos), "B4 swing animation did not move the player body (pos=%s)" % str(p.global_position))
	await phys(60)
	check(not p.context.is_attacking, "B5 attack lifecycle finished")
	await cleanup(main)

	# ---------- C. hit reaction resumes locomotion ----------
	main = await fresh()
	p = main.get_node("Player")
	main.get_node("BasicEnemy2D").set_physics_process(false)
	var anim: AnimationPlayer = p.get_node("PlayerAnim")
	await phys(5)
	check(anim.current_animation == "idle", "C1 idle plays at start (got '%s')" % anim.current_animation)
	p.take_damage(1)
	await phys(5)
	check(anim.current_animation == "take_damage", "C2 take_damage plays (got '%s')" % anim.current_animation)
	await phys(40)
	check(anim.current_animation == "idle" and anim.is_playing(), "C3 idle resumes after take_damage/RESET (got '%s', playing=%s)" % [anim.current_animation, str(anim.is_playing())])
	Input.action_press("move_right")
	await phys(8)
	check(anim.current_animation == "run", "C4 run plays while moving (got '%s')" % anim.current_animation)
	p.take_damage(1)
	await phys(40)
	check(anim.current_animation == "run" and anim.is_playing(), "C5 run resumes after a hit while moving (got '%s')" % anim.current_animation)
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
	check(p.health < p.max_health, "F2 enemy damages the player (health=%d/%d)" % [p.health, p.max_health])
	var hp_seen: Array[int] = []
	await phys(60 * 20)
	check(p.health <= 0 and not p.is_alive(), "F3 repeated hits kill the player (health=%d)" % p.health)
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
