class_name H8AimChecks
## H8.2: checks for the aim shapes (AimShape2D and its Fan, Line and CircleSelf subclasses). Pure geometry: no scene,
## no physics. Kept in its own file so the 8,000-line smoke script only gains a part entry and a one-line runner.
## `check` is the suite's own check(cond, msg), so passes and failures land in the same totals. `host` is a node in the
## running tree (the suite's root) where the targeting checks put their stand-in characters; they free them again.

## A stand-in character: a position, a team and an alive flag, which is all the targeting service reads.
class Stub extends Node2D:
	var team: StringName = &""
	var alive := true
	func is_alive() -> bool:
		return alive

## H8.4: the player's persistent aim state and the activation hook. `main` is a fresh Main scene from the suite.
static func run_player(check: Callable, main: Node) -> void:
	var p = main.get_node("Player") # untyped on purpose: it calls player.gd methods Character2D does not declare
	var manager := main.get_node("InputModeManager") as InputModeManager
	var Device := InputModeManager.Device
	manager.set_device(Device.KEYBOARD_MOUSE)
	p.clear_manual_aim()
	p.context.last_aim_direction = Vector2.ZERO

	# --- The right stick: a live aim, remembered ---
	Input.action_press(&"aim_right", 1.0)
	check.call(p._get_aim_direction().distance_to(Vector2.RIGHT) < 0.001 and p.context.last_aim_direction.distance_to(Vector2.RIGHT) < 0.001, "H8-63 a pushed stick aims right and is remembered as the last valid aim")
	check.call(p._direction_for_activation(null).distance_to(Vector2.RIGHT) < 0.001, "H8-64 an action that starts now takes the stick aim, as before")
	Input.action_release(&"aim_right")
	check.call(p._direction_for_activation(null).distance_to(Vector2.RIGHT) < 0.001 and p.context.last_aim_direction.distance_to(Vector2.RIGHT) < 0.001, "H8-65 with the stick let go the last aim is kept (H7.4 rule) and is still the last valid aim")
	Input.action_press(&"aim_up", 1.0)
	check.call(p._direction_for_activation(null).distance_to(Vector2.UP) < 0.001 and p.context.last_aim_direction.distance_to(Vector2.UP) < 0.001, "H8-66 a new stick aim replaces the last valid aim")
	Input.action_release(&"aim_up")

	# --- The mouse is unchanged ---
	p._input(InputEventMouseMotion.new())
	check.call(p._direction_for_activation(null).is_equal_approx(p._get_aim_direction()), "H8-67 with the mouse aiming, an action takes exactly the live mouse aim (keyboard and mouse behave as before)")

	# --- A manual aim (a drag) overrides and is cleared again ---
	p.set_manual_aim(Vector2(0, 3))
	check.call(p.get_manual_aim().distance_to(Vector2.DOWN) < 0.001 and p._get_aim_direction().distance_to(Vector2.DOWN) < 0.001, "H8-68 a manual aim becomes the live aim, so the facing and weapon follow the drag")
	check.call(p._direction_for_activation(null).distance_to(Vector2.DOWN) < 0.001 and p.context.last_aim_direction.distance_to(Vector2.DOWN) < 0.001, "H8-69 an action takes the manual aim and remembers it")
	p.clear_manual_aim()
	check.call(p.get_manual_aim() == Vector2.ZERO and p._get_aim_direction().is_equal_approx(p._direction_for_activation(null)), "H8-70 clearing it returns the aim to the mouse for the next action")

	# --- Touch with no aim yet: the fallback chain, never a stale pointer ---
	p._input(InputEventMouseMotion.new()) # the aim source is the mouse, as at the start of a touch session
	manager.set_device(Device.TOUCH)
	p.context.last_aim_direction = Vector2(0.6, -0.8)
	check.call(p._direction_for_activation(null).distance_to(Vector2(0.6, -0.8)) < 0.001, "H8-71 on touch with no aim given, a tap goes along the last valid aim")
	p.context.last_aim_direction = Vector2.ZERO
	p.context.facing_direction = Vector2.LEFT
	check.call(p._direction_for_activation(null).distance_to(Vector2.LEFT) < 0.001, "H8-72 with no last aim it goes along the facing")
	p.context.facing_direction = Vector2.ZERO
	check.call(p._direction_for_activation(null) == Vector2.RIGHT, "H8-73 with nothing known it goes right (never a zero direction)")
	p.context.facing_direction = Vector2.RIGHT
	Input.action_press(&"aim_left", 1.0)
	check.call(p._direction_for_activation(null).distance_to(Vector2.LEFT) < 0.001, "H8-74 on touch a pushed stick still aims, and the aim is remembered")
	Input.action_release(&"aim_left")

	# --- Assistance is asked for once per request, not every frame ---
	p.context.last_aim_direction = Vector2(0.6, -0.8)
	p._input(InputEventMouseMotion.new())
	manager.set_device(Device.TOUCH)
	var plain: Vector2 = p._get_aim_direction()
	p._activation_open = false
	p._pending_light = &"light"
	check.call(p._get_attack_direction().is_equal_approx(plain), "H8-75 outside the activation window the attack direction is the plain live aim")
	p._activation_open = true
	check.call(p._get_attack_direction().distance_to(Vector2(0.6, -0.8)) < 0.001, "H8-76 inside it, with a request pending, the activation path is used")
	p._pending_light = &""
	check.call(p._get_attack_direction().is_equal_approx(p._get_aim_direction()), "H8-77 inside it with nothing pending (an empty attack request) it is still the plain aim")
	p._activation_open = false

	# --- The service ---
	var service: TargetingService2D = p.get_targeting_service()
	check.call(service != null and service.get_parent() == p and service.caster == p and p.get_targeting_service() == service, "H8-78 the player owns one targeting service, made on first use, with itself as the caster")

	# --- H8.5: light-attack assist (a tap steers toward the best target in the fan) ---
	var home: Vector2 = p.global_position
	p.global_position = Vector2(50000.0, 50000.0) # far from the arena's own enemies, so only the stand-ins count
	manager.set_device(Device.TOUCH)
	p._input(InputEventMouseMotion.new())
	p.context.last_aim_direction = Vector2.RIGHT
	var light_id: StringName = p.get_light_attack_id()
	var light_def: AttackDefinition2D = p.attack_component.get_attack(light_id)
	var reach: float = light_def.attack_range if light_def != null else 0.0
	check.call(reach > 0.0 and p.light_assist_angle == 360.0, "H8-79 the equipped weapon's light attack has an attack_range, and the project-wide angle is 360 (all round)")
	var near := Vector2(reach * 0.5 * 0.77, reach * 0.5 * 0.64) # inside the reach, about 40 degrees off the aim
	var stubs: Array = []
	stubs.append(_stub(main, p.global_position + near))
	var svc: TargetingService2D = p.get_targeting_service()
	svc.set_view_override(Rect2(p.global_position - Vector2(320.0, 200.0), Vector2(640.0, 400.0))) # a camera view round the player (H9.3)
	p._activation_open = true
	p._pending_light = light_id
	check.call(p._get_attack_direction().distance_to(near.normalized()) < 0.001, "H8-80 a light tap goes toward a target inside the fan, even though it is off the aim")
	check.call(p.context.last_aim_direction.distance_to(near.normalized()) < 0.001, "H8-81 the assisted direction is remembered as the last valid aim")
	svc.clear()
	p.context.last_aim_direction = Vector2.RIGHT
	stubs[0].global_position = p.global_position + Vector2(-reach * 0.5, 0.0)
	p.light_assist_angle = 120.0
	check.call(p._get_attack_direction().distance_to(Vector2.RIGHT) < 0.001, "H8-82 with a 120 degree fan a target behind the player is outside it: the tap keeps the aim (here the last aim)")
	p.light_assist_angle = 360.0
	svc.clear()
	p.context.last_aim_direction = Vector2.RIGHT
	check.call(p._get_attack_direction().distance_to(Vector2.LEFT) < 0.001, "H8-232 with the default all-round fan a target behind the player inside the reach is picked")
	svc.clear()
	p.context.last_aim_direction = Vector2.RIGHT
	var beyond := Vector2(reach + 60.0, reach + 60.0)
	stubs[0].global_position = p.global_position + beyond
	check.call(p._get_attack_direction().distance_to(beyond.normalized()) < 0.001, "H8-83 a target beyond attack_range but inside the camera view is still picked (H9.3: range decides nothing)")
	svc.clear()
	p.context.last_aim_direction = Vector2.RIGHT
	stubs[0].global_position = p.global_position + Vector2(0.0, 900.0)
	check.call(p._get_attack_direction().distance_to(Vector2.RIGHT) < 0.001, "H9-29 a target outside the camera view is ignored, however near the aim it is")
	svc.clear()
	stubs[0].global_position = p.global_position + near
	p.light_assist_angle = 0.0
	check.call(p._get_attack_direction().distance_to(Vector2.RIGHT) < 0.001, "H8-84 light_assist_angle 0 turns the assist off")
	p.light_assist_angle = 360.0
	svc.clear()
	if light_def != null:
		light_def.attack_range = 0.0
		check.call(p._get_attack_direction().distance_to(near.normalized()) < 0.001, "H8-85 an attack with attack_range 0 is assisted all the same: the camera view decides, not the range")
		light_def.attack_range = reach
	svc.clear()
	p.context.last_aim_direction = Vector2.RIGHT # H8-85 now remembers the assisted aim, so start from a known one
	p._pending_light = &""
	p._pending_begin = &"heavy"
	check.call(p._get_attack_direction().distance_to(Vector2.RIGHT) < 0.001, "H8-86 beginning a charge is not assisted yet (H8.7)")
	p._pending_begin = &""
	p._pending_light = light_id
	Input.action_press(&"aim_right", 1.0)
	check.call(p._get_attack_direction().distance_to(Vector2.RIGHT) < 0.001, "H8-87 a pushed aim stick is a manual aim: it overrides the assist")
	Input.action_release(&"aim_right")
	svc.clear()
	p._activation_open = false
	check.call(p._get_attack_direction().is_equal_approx(p._get_aim_direction()), "H8-88 outside the activation window the assist is never asked")
	p._pending_light = &""
	var shipped_ok := true
	for path in ["res://Weapons/Sword/Attacks/Sword_Slash1.tres", "res://Weapons/Sword/Attacks/Sword_Slash2.tres", "res://Weapons/Bow/Attacks/Bow_ArrowShot.tres"]:
		shipped_ok = shipped_ok and (load(path) as AttackDefinition2D).attack_range > 0.0
	check.call(shipped_ok and (load("res://Weapons/Bow/Attacks/Bow_ArrowEnemy.tres") as AttackDefinition2D).attack_range > 0.0, "H8-89 the sword slashes, the bow shot and the enemy arrow each have an attack_range (one number for the circle, the assist and the AI)")
	# --- Assist view: the range circle and the target marker ---
	svc.clear()
	p._activation_open = false
	p._pending_light = &""
	p.context.last_aim_direction = Vector2.RIGHT
	stubs[0].global_position = p.global_position + near
	p.show_attack_range = true
	p.show_target_marker = true
	p._update_assist_indicator()
	var view: AssistIndicator2D = p.get_assist_indicator()
	check.call(view != null and is_equal_approx(view.get_range_radius(), reach), "H8-233 the blue circle has the light attack's attack_range as its radius")
	check.call(view != null and view.get_target() == stubs[0], "H8-234 the target marker is on the target a tap would pick")
	stubs[0].global_position = p.global_position + Vector2(reach + 60.0, 0.0)
	p._update_assist_indicator()
	check.call(view.get_target() == stubs[0] and view.get_range_radius() > 0.0, "H8-235 a target beyond the reach but in view still gets the marker; the circle stays")
	stubs[0].global_position = p.global_position + Vector2(0.0, 900.0)
	p._update_assist_indicator()
	check.call(view.get_target() == null and view.get_range_radius() > 0.0, "H9-30 a target outside the camera view gets no marker at all; the circle stays")
	stubs[0].global_position = p.global_position + near
	p.show_target_marker = false
	p._update_assist_indicator()
	check.call(view.get_target() == null and view.get_range_radius() > 0.0, "H8-236 show_target_marker off hides the marker only")
	p.show_target_marker = true
	p.show_attack_range = false
	p._update_assist_indicator()
	check.call(view.get_range_radius() == 0.0 and view.get_target() == stubs[0], "H8-237 show_attack_range off hides the circle only")
	p.show_attack_range = true
	p.light_assist_angle = 0.0
	p._update_assist_indicator()
	check.call(not view.visible, "H8-238 with the assist off nothing is drawn")
	p.light_assist_angle = 360.0
	# --- H9.4.0: exactly one target is ever marked ---
	stubs[0].global_position = p.global_position + near
	stubs.append(_stub(main, p.global_position + Vector2(-reach * 3.0, reach * 2.0))) # visible but behind/off-axis
	stubs.append(_stub(main, p.global_position + Vector2(5000.0, 0.0))) # off screen
	p.context.last_aim_direction = Vector2.RIGHT
	p._update_assist_indicator()
	check.call(view.get_target() == stubs[0], "H9-31 several enemies in view still produce exactly one marker")
	var marker_shape: AimShape2D = p._light_shape_for(p.get_light_attack_id())
	check.call(view.get_target() == p.get_targeting_service().pick_target(p.global_position, Vector2.RIGHT, marker_shape), "H9-53 the target marker and the next light-tap target use the same selection rule")
	var tie_target := _stub(main, p.global_position + Vector2(101.0, 0.0))
	stubs.append(tie_target)
	stubs[0].global_position = p.global_position + Vector2(100.0, 0.0)
	p.get_targeting_service().clear()
	p._update_assist_indicator()
	tie_target.global_position = p.global_position + Vector2(99.0, 0.0)
	p._update_assist_indicator()
	check.call(view.get_target() == stubs[0], "H9-54 the marked target stays stable when two targets swap nearest by a few pixels")
	p.show_target_marker = false
	p._update_assist_indicator()
	check.call(view.get_target() == null and view.get_range_radius() > 0.0, "H9-34 show_target_marker off hides the single marker")
	p.show_target_marker = true
	stubs[1].alive = false
	p._update_assist_indicator()
	check.call(view.get_target() == stubs[0], "H9-35 a dead enemy cannot replace the marked target")
	# The live camera: its rectangle is what the screen shows.
	svc.clear_view_override()
	var cam := p.get_viewport().get_camera_2d()
	var view_rect := svc.get_view_rect()
	var visible_size: Vector2 = p.get_viewport().get_visible_rect().size
	check.call(cam != null and view_rect.size.is_equal_approx(visible_size / cam.zoom) and view_rect.get_center().distance_to(cam.get_screen_center_position()) < 1.0, "H9-36 the view rectangle is the camera's: the visible size divided by the zoom, centred where the camera looks (%s)" % view_rect)
	svc.set_view_override(Rect2(p.global_position - Vector2(320.0, 200.0), Vector2(640.0, 400.0)))
	# --- H9.1: the circle follows the equipped weapon ---
	p._update_assist_indicator()
	var swap: WeaponController2D = p.weapon_controller
	var swapped: bool = swap != null and swap.equip_next()
	check.call(swapped, "H8-245 the player can switch to the next weapon in this scenario")
	if swapped:
		var other_def: AttackDefinition2D = p.attack_component.get_attack(p.get_light_attack_id())
		p._update_assist_indicator()
		check.call(other_def != null and other_def.attack_range > 0.0 and not is_equal_approx(other_def.attack_range, reach) and is_equal_approx(view.get_range_radius(), other_def.attack_range), "H8-246 after a weapon swap the blue circle's radius is the new weapon's light attack_range")
		swap.equip_next()
		p._update_assist_indicator()
		check.call(is_equal_approx(view.get_range_radius(), reach), "H8-247 swapping back restores the first weapon's circle")
	_free_all(stubs)
	svc.clear_view_override()
	svc.clear()
	p.global_position = home

	# --- H8.7: heavy attack and skill assist ---
	p.global_position = Vector2(50000.0, 50000.0)
	manager.set_device(Device.TOUCH)
	p._input(InputEventMouseMotion.new())
	p.context.last_aim_direction = Vector2.RIGHT
	p.get_targeting_service().clear()
	var heavy_id: StringName = p.get_heavy_attack_id()
	var heavy_def: AttackDefinition2D = p.attack_component.get_attack(heavy_id)
	var heavy_shape: AimShape2D = heavy_def.aim_shape if heavy_def != null else null
	check.call(heavy_shape != null, "H8-108 the equipped weapon's heavy attack has an aim_shape")
	var stubs2: Array = []
	if heavy_shape != null:
		var inside := Vector2(heavy_shape.max_range * 0.5, 10.0)
		stubs2.append(_stub(main, p.global_position + inside))
		p._activation_open = true
		p._pending_release = true
		check.call(p._get_attack_direction().distance_to(inside.normalized()) < 0.001, "H8-109 a charge release goes toward a target inside the heavy attack's shape")
		p.get_targeting_service().clear()
		p.context.last_aim_direction = Vector2.RIGHT # the release above remembered its target as the last aim
		p._pending_release = false
		p._pending_begin = heavy_id
		check.call(p._get_attack_direction().distance_to(Vector2.RIGHT) < 0.001, "H8-110 a charge begin is not assisted (the direction is decided at release) (got %s)" % [p._get_attack_direction()])
		p._pending_begin = &""
		p._pending_release = true
		p.get_targeting_service().clear()
		p.context.last_aim_direction = Vector2.RIGHT
		stubs2[0].global_position = p.global_position + Vector2(-heavy_shape.max_range * 0.5, 0.0)
		check.call(p._get_attack_direction().distance_to(Vector2.RIGHT) < 0.001, "H8-111 a target outside the shape (behind) is ignored: the release keeps the aim (got %s)" % [p._get_attack_direction()])
		stubs2[0].global_position = p.global_position + inside
		p.get_targeting_service().clear()
		p.set_manual_aim(Vector2.DOWN)
		check.call(p._get_attack_direction().distance_to(Vector2.DOWN) < 0.001, "H8-112 a manual aim (a drag) overrides the assist at release")
		p.clear_manual_aim()
		p.context.last_aim_direction = Vector2.RIGHT # the manual aim above was remembered as the last aim
		p.get_targeting_service().clear()
		heavy_def.aim_shape = null
		check.call(p._get_attack_direction().distance_to(Vector2.RIGHT) < 0.001, "H8-113 a heavy attack with no aim_shape gets no assist (got %s)" % [p._get_attack_direction()])
		heavy_def.aim_shape = heavy_shape
		p._pending_release = false
		p._activation_open = false

	# Skills: the shape follows the skill; SELF skills and buffs get none.
	var skills_ok := true
	var aimed_slot := -1
	for skill in p.skill_component.get_skills():
		var expected: AimShape2D = null if (skill.targeting == SkillDefinition2D.Targeting.SELF) else skill.aim_shape
		skills_ok = skills_ok and p._skill_assist_shape(skill.slot) == expected
		if expected != null and aimed_slot < 0:
			aimed_slot = skill.slot
	check.call(skills_ok and aimed_slot >= 0, "H8-114 each equipped skill is assisted inside its own aim_shape; SELF skills and buffs get none")
	if aimed_slot >= 0:
		var skill_shape: AimShape2D = p._skill_assist_shape(aimed_slot)
		var skill_inside := Vector2(skill_shape.max_range * 0.5, 8.0)
		if not stubs2.is_empty():
			stubs2[0].global_position = p.global_position + skill_inside
		else:
			stubs2.append(_stub(main, p.global_position + skill_inside))
		p.get_targeting_service().clear()
		p.context.last_aim_direction = Vector2.RIGHT
		check.call(p._direction_for_activation(skill_shape).distance_to(skill_inside.normalized()) < 0.001, "H8-115 a skill cast goes toward a target inside its shape (got %s, target %s, last aim %s)" % [p._direction_for_activation(skill_shape), skill_inside.normalized(), p.context.last_aim_direction])
		p.get_targeting_service().clear()
		p.context.last_aim_direction = Vector2.RIGHT # the cast above remembered its target as the last aim
		stubs2[0].global_position = p.global_position + Vector2(-skill_shape.max_range * 0.5, 0.0)
		check.call(p._direction_for_activation(skill_shape).distance_to(Vector2.RIGHT) < 0.001, "H8-116 a target behind the player is ignored by a directional skill (got %s)" % [p._direction_for_activation(skill_shape)])
		p.get_targeting_service().clear()

	# The charge direction is fixed once the button has been released (the bow's draw is still playing).
	var ac = p.attack_component
	if ac.begin_charge(heavy_id, Vector2.RIGHT):
		ac.update_charge_direction(Vector2.UP)
		var followed: bool = p.context.attack_direction.distance_to(Vector2.UP) < 0.001
		ac._release_pending = true
		ac.update_charge_direction(Vector2.LEFT)
		var frozen: bool = p.context.attack_direction.distance_to(Vector2.UP) < 0.001
		ac._release_pending = false
		check.call(followed and frozen, "H8-117 the charge follows the live aim until released, then the direction is fixed")
		ac.cancel()
	else:
		check.call(false, "H8-117 a charge could not begin for the direction check")
	_free_all(stubs2)
	p.get_targeting_service().clear()
	p.global_position = home

	manager.set_device(Device.KEYBOARD_MOUSE)
	p.clear_manual_aim()

static func run(check: Callable, host: Node) -> void:
	_shapes(check)
	_targeting(check, host)
	_definitions(check)
	_reach(check)
	_slash(check, host)
	_view(check, host)
	_in_reach(check, host)
	_approach(check, host)

## H9.2: the slash's reach is driven from the attack's one reach number, not from keyframes. `root` is a node in the
## running tree; every effect made here is freed again.
static func _slash(check: Callable, root: Node) -> void:
	var host := Node2D.new() # the attacker of every swing below; effects need a Node2D to hit for
	root.add_child(host)
	var scene := load("res://Characters/Components/Combat/AttackSlash2D.tscn") as PackedScene
	# The shipped clips keep timing, frames, scale, fade and the hit window, but no position tracks.
	var probe := scene.instantiate()
	var player := probe.get_node(AttackSlash2D.ANIMATION_PLAYER_PATH) as AnimationPlayer
	var clips_ok := true
	var window_ok := true
	for clip_name in [&"slash", &"heavy_slash"]:
		var clip := player.get_animation(clip_name)
		clips_ok = clips_ok and not AttackSlash2D._clip_moves_positions(clip)
		window_ok = window_ok and is_equal_approx(AttackSlash2D._hit_window_end(clip), 0.33333334) and AttackSlash2D._clip_opens_hit_window(clip)
	check.call(clips_ok, "H9-13 the slash and heavy_slash clips no longer animate the sprite or HitboxMotion position")
	check.call(window_ok, "H9-14 the hit window (0 to 0.333 s) is still authored in the clips and is what the driver reads")
	check.call(probe.get_scene_problems(&"slash").is_empty() and probe.get_scene_problems(&"heavy_slash").is_empty() and probe.get_scene_warnings().is_empty(), "H9-15 the shipped slash scene has no problems and no warnings")
	probe.free()

	var light := _swing(host, scene, 70.0, Vector2(16, 16), Vector2.ZERO, &"slash")
	var start_edge: float = light.get_leading_edge()
	check.call(light.is_reach_driven() and is_equal_approx(start_edge, 16.0), "H9-16 a driven swing starts at the scene's start position (leading edge %s)" % start_edge)
	light.seek_swing(0.16666667)
	var mid_edge: float = light.get_leading_edge()
	var linear_mid := lerpf(start_edge, 70.0, 0.5)
	check.call(mid_edge > linear_mid and mid_edge < 70.0, "H9-17 halfway through the window the edge is out ahead of a straight line (eased, %s of 70)" % mid_edge)
	light.seek_swing(0.33333334)
	check.call(is_equal_approx(light.get_leading_edge(), 70.0), "H9-18 at the end of the hit window the leading edge is exactly the attack's reach (%s)" % light.get_leading_edge())
	var sprite: Node2D = light.get_node(AttackSlash2D.ANIMATION_PLAYER_PATH).get_parent()
	var motion: Node2D = light.get_node("HitboxOrigin/HitboxMotion")
	check.call(is_equal_approx(sprite.position.x, motion.position.x - 8.0), "H9-19 the sprite travels the same distance as the hitbox")
	light.seek_swing(0.375)
	check.call(is_equal_approx(light.get_leading_edge(), 70.0), "H9-20 after the window closes the swing stays at its reach")
	light.free()

	var heavy := _swing(host, scene, 100.0, Vector2(28, 24), Vector2.ZERO, &"heavy_slash")
	heavy.seek_swing(0.33333334)
	check.call(is_equal_approx(heavy.get_leading_edge(), 100.0), "H9-21 the heavy swing's leading edge includes the hitbox's half width and its 1.5x scale and ends at 100 (%s)" % heavy.get_leading_edge())
	heavy.free()

	var offset := _swing(host, scene, 75.0, Vector2(16, 14), Vector2(10, 0), &"slash")
	offset.seek_swing(0.33333334)
	check.call(is_equal_approx(offset.get_leading_edge(), 75.0), "H9-22 a hitbox offset is part of the reach (edge %s)" % offset.get_leading_edge())
	offset.free()

	var far := _swing(host, scene, 160.0, Vector2(16, 16), Vector2.ZERO, &"slash")
	var near := _swing(host, scene, 40.0, Vector2(16, 16), Vector2.ZERO, &"slash")
	far.seek_swing(0.33333334)
	near.seek_swing(0.33333334)
	check.call(is_equal_approx(far.get_leading_edge(), 160.0) and is_equal_approx(near.get_leading_edge(), 40.0), "H9-23 the same scene reaches whatever the attack says (%s and %s)" % [far.get_leading_edge(), near.get_leading_edge()])
	far.free()
	near.free()

	var tiny := _swing(host, scene, 5.0, Vector2(16, 16), Vector2.ZERO, &"slash")
	tiny.seek_swing(0.33333334)
	check.call(tiny.is_reach_driven() and is_equal_approx(tiny.get_leading_edge(), 16.0), "H9-24 a reach shorter than the hitbox's starting edge never pulls it backwards (%s)" % tiny.get_leading_edge())
	tiny.free()

	var unknown := _swing(host, scene, 0.0, Vector2(16, 16), Vector2.ZERO, &"slash")
	unknown.seek_swing(0.33333334)
	check.call(is_equal_approx(unknown.get_leading_edge(), unknown.fallback_reach), "H9-25 an attack with no reach uses the swing's fallback reach (%s)" % unknown.get_leading_edge())
	unknown.free()

	# The shipped sword: one swing, one number.
	var slash1 := load("res://Weapons/Sword/Attacks/Sword_Slash1.tres") as AttackDefinition2D
	var heavy_def := load("res://Weapons/Sword/Attacks/Sword_HeavySlash.tres") as AttackDefinition2D
	var s1 := _swing(host, scene, slash1.get_reach(), slash1.hitbox_size, slash1.hitbox_offset, slash1.effect_animation)
	var hv := _swing(host, scene, heavy_def.get_reach(), heavy_def.hitbox_size, heavy_def.hitbox_offset, heavy_def.effect_animation)
	s1.seek_swing(0.33333334)
	hv.seek_swing(0.33333334)
	check.call(is_equal_approx(s1.get_leading_edge(), slash1.attack_range) and is_equal_approx(slash1.attack_range, 70.0), "H9-26 the sword's light swing really reaches its attack_range, 70 (%s)" % s1.get_leading_edge())
	check.call(is_equal_approx(hv.get_leading_edge(), heavy_def.get_reach()) and is_equal_approx(heavy_def.get_reach(), 100.0), "H9-27 the heavy swing reaches the 100 its fan says (%s)" % hv.get_leading_edge())
	s1.free()
	hv.free()

	# A scene whose clip still animates positions keeps its own motion and is warned about.
	var legacy: AttackSlash2D = scene.instantiate()
	var legacy_player := legacy.get_node(AttackSlash2D.ANIMATION_PLAYER_PATH) as AnimationPlayer
	var library := legacy_player.get_animation_library(&"").duplicate(true) as AnimationLibrary
	var old_clip := library.get_animation(&"slash")
	var track := old_clip.add_track(Animation.TYPE_VALUE)
	old_clip.track_set_path(track, NodePath(".:position"))
	old_clip.track_insert_key(track, 0.0, Vector2.ZERO)
	legacy_player.remove_animation_library(&"")
	legacy_player.add_animation_library(&"", library)
	legacy.configure(host, 1, Vector2.RIGHT, Vector2(16, 16), Vector2.ZERO, -1, 0.0, 0.0, &"slash", 0, true, 0.0, 0.0, 2.0, [], 70.0)
	host.add_child(legacy)
	var warnings: Array[String] = legacy.get_scene_warnings()
	check.call(not legacy.is_reach_driven() and warnings.size() == 1 and warnings[0].contains("'slash'") and warnings[0].contains("position"), "H9-28 a clip that still animates positions is left alone and reported (%s)" % str(warnings))
	legacy.free()
	host.free()

## One slash swing configured like the attack component does it, added to `host`, with its animation already playing.
static func _swing(host: Node, scene: PackedScene, reach: float, size: Vector2, offset: Vector2, clip: StringName) -> AttackSlash2D:
	var effect := scene.instantiate() as AttackSlash2D
	effect.configure(host, 1, Vector2.RIGHT, size, offset, -1, 0.0, 0.0, clip, 0, true, 0.0, 0.0, 2.0, [], reach)
	host.add_child(effect)
	return effect

## H9.3: the camera view as the area a light tap targets in. Pure geometry plus the targeting service on stand-ins.
static func _view(check: Callable, host: Node) -> void:
	var rect := Rect2(-100.0, -150.0, 700.0, 300.0)
	var shape := ViewAimShape2D.make(rect, 360.0)
	check.call(shape.score(Vector2.ZERO, Vector2.RIGHT, Vector2(400, 0)) >= 0.0 and shape.score(Vector2.ZERO, Vector2.RIGHT, Vector2(900, 0)) < 0.0, "H9-37 a view shape holds what is inside the rectangle and nothing outside it")
	check.call(shape.contains(Vector2.ZERO, Vector2.RIGHT, Vector2(605, 0), 8.0) and not shape.contains(Vector2.ZERO, Vector2.RIGHT, Vector2(620, 0), 8.0), "H9-38 a body whose radius reaches into the view counts, one clear of it does not")
	check.call(shape.keeps_target(Vector2.ZERO, Vector2(580, 0)) and not shape.keeps_target(Vector2.ZERO, Vector2(700, 0)) and FanAimShape2D.make(90.0, 100.0).keeps_target(Vector2.ZERO, Vector2(90, 0)) and not FanAimShape2D.make(90.0, 100.0).keeps_target(Vector2.ZERO, Vector2(140, 0)), "H9-39 a view shape keeps a target while it is on screen at any distance; the other shapes still keep one inside their reach")
	check.call(ViewAimShape2D.make(Rect2(), 360.0).validate().size() > 0 and shape.validate().is_empty(), "H9-40 a view shape with no area reports a problem")

	var made: Array = []
	var caster := _stub(host, Vector2.ZERO, &"player")
	made.append(caster)
	var service := TargetingService2D.new()
	service.caster = caster
	host.add_child(service)
	made.append(service)
	service.set_view_override(rect)
	check.call(service.get_view_rect() == rect, "H9-41 the service can be told which rectangle to use (tests, cut scenes)")
	service.clear_view_override()
	check.call(service.get_view_rect().size.x > 0.0 and service.get_view_rect().size.y > 0.0, "H9-42 without an override the service reads the viewport")
	service.set_view_override(rect)

	var far_visible := _stub(host, Vector2(450, 0), &"enemy")
	var off_screen := _stub(host, Vector2(900, 0), &"enemy")
	made.append_array([far_visible, off_screen])
	var reach_fan := FanAimShape2D.make(360.0, 70.0)
	check.call(service.pick_target(Vector2.ZERO, Vector2.RIGHT, reach_fan) == null and service.pick_target(Vector2.ZERO, Vector2.RIGHT, shape) == far_visible, "H9-43 an enemy 450 px away is out of a 70 px reach but is the pick in the view: range no longer decides who can be targeted")
	var on_screen := service.candidates_in_shape(Vector2.ZERO, Vector2.RIGHT, shape)
	check.call(on_screen.size() == 1 and on_screen[0] == far_visible, "H9-44 only what is on screen is a candidate")

	var near_visible := _stub(host, Vector2(120, 0), &"enemy")
	made.append(near_visible)
	service.clear()
	check.call(service.pick_target(Vector2.ZERO, Vector2.RIGHT, ViewAimShape2D.make(rect, 360.0, 0.4)) == near_visible, "H9-45 of two enemies on the aim the nearer one wins")
	var behind := _stub(host, Vector2(-80, 0), &"enemy")
	made.append(behind)
	service.clear()
	var in_front := ViewAimShape2D.make(rect, 90.0)
	var all_round := ViewAimShape2D.make(rect, 360.0)
	check.call(not service.candidates_in_shape(Vector2.ZERO, Vector2.RIGHT, in_front).has(behind) and service.candidates_in_shape(Vector2.ZERO, Vector2.RIGHT, all_round).has(behind), "H9-46 the fan angle still narrows the search inside the view")
	var front_far := _stub(host, Vector2(300, 0), &"enemy")
	var back_near := _stub(host, Vector2(-30, 0), &"enemy")
	made.append_array([front_far, back_near])
	# H9-50 to H9-52 judge only these two: the earlier stubs are set aside, and far_visible comes back for H9-47.
	near_visible.alive = false
	behind.alive = false
	far_visible.alive = false
	service.clear()
	check.call(service.pick_target(Vector2.ZERO, Vector2.RIGHT, all_round) == front_far, "H9-50 a farther target inside the front cone beats a nearer target behind")
	front_far.global_position = Vector2(-300, 0)
	back_near.global_position = Vector2(-30, 0)
	service.clear()
	check.call(service.pick_target(Vector2.ZERO, Vector2.RIGHT, all_round) == back_near, "H9-51 when no target is in front, the nearest visible target wins")
	front_far.global_position = Vector2(300, 0)
	back_near.global_position = Vector2(120, 0)
	service.clear()
	check.call(service.pick_target(Vector2.ZERO, Vector2.RIGHT, all_round) == back_near, "H9-52 within the front cone the nearer target wins")
	front_far.alive = false
	back_near.alive = false
	far_visible.alive = true

	# One action keeps its target while it stays on screen, however far it walks from the caster, and drops it off screen.
	service.clear()
	service.begin_action()
	var first := service.resolve(Vector2.ZERO, Vector2.RIGHT, shape)
	check.call(first.target == far_visible, "H9-47 setup: the action picked the visible enemy")
	var other := _stub(host, Vector2(200, 0), &"enemy")
	made.append(other)
	far_visible.global_position = Vector2(590, 0)
	var kept := service.resolve(Vector2.ZERO, Vector2.RIGHT, shape)
	check.call(kept.target == far_visible, "H9-48 the action keeps its target while it is still in view, even with a nearer enemy now lined up")
	far_visible.global_position = Vector2(800, 0)
	var dropped := service.resolve(Vector2.ZERO, Vector2.RIGHT, shape)
	check.call(dropped.target == other, "H9-49 a target that leaves the view is replaced")
	_free_all(made)

## H9.4.1: the in-reach helper. Stand-in targets, no scene. Pure distance: it changes nothing and nobody calls it yet.
static func _in_reach(check: Callable, host: Node) -> void:
	var made: Array = []
	var service := TargetingService2D.new()
	host.add_child(service)
	made.append(service)
	var small := _stub(host, Vector2(70, 0), &"enemy")
	made.append(small)
	var margin := service.target_margin
	check.call(is_equal_approx(service.get_body_allowance(small), margin), "H9-70 a target with no collision shape gets the 8 px margin as its size allowance")
	check.call(service.is_in_reach(Vector2.ZERO, small, 70.0), "H9-71 a target exactly at the reach is in reach")
	small.global_position = Vector2(70.0 + margin, 0)
	check.call(service.is_in_reach(Vector2.ZERO, small, 70.0), "H9-72 a target whose edge just touches the reach (distance 70 + its allowance) is in reach")
	small.global_position = Vector2(70.0 + margin + 1.0, 0)
	check.call(not service.is_in_reach(Vector2.ZERO, small, 70.0), "H9-73 one pixel farther is out of reach")
	check.call(is_equal_approx(service.distance_to_reach(Vector2.ZERO, small, 70.0), 1.0), "H9-74 distance_to_reach says how far outside the reach it is")
	small.global_position = Vector2(30, 0)
	check.call(service.distance_to_reach(Vector2.ZERO, small, 70.0) == 0.0, "H9-75 inside the reach the distance to close is 0, never negative")
	check.call(not service.is_in_reach(Vector2.ZERO, small, 0.0) and not service.is_in_reach(Vector2.ZERO, small, -5.0), "H9-76 a reach of 0 (a self action) is never in reach, even at the origin")
	check.call(not service.is_in_reach(Vector2.ZERO, null, 70.0) and service.distance_to_reach(Vector2.ZERO, null, 70.0) == INF, "H9-77 a missing target is not in reach")

	var big := _stub(host, Vector2(110, 0), &"enemy")
	made.append(big)
	var circle := CircleShape2D.new()
	circle.radius = 40.0
	var big_shape := CollisionShape2D.new()
	big_shape.shape = circle
	big.add_child(big_shape)
	check.call(is_equal_approx(service.get_body_allowance(big), 40.0), "H9-78 a big circle body counts its radius, not the small margin")
	check.call(service.is_in_reach(Vector2.ZERO, big, 70.0) and not service.is_in_reach(Vector2.ZERO, big, 69.0), "H9-79 a large target 110 px away is in a 70 reach (110 - 40) and not in a 69 one")
	var box := RectangleShape2D.new()
	box.size = Vector2(100, 20)
	big_shape.shape = box
	check.call(is_equal_approx(service.get_body_allowance(big), 10.0), "H9-80 a thin box counts its smaller half-side (10), above the margin")
	var capsule := CapsuleShape2D.new()
	capsule.radius = 5.0
	capsule.height = 12.0
	big_shape.shape = capsule
	check.call(is_equal_approx(service.get_body_allowance(big), margin), "H9-81 the goblin's capsule (radius 5) keeps the 8 px margin: it does not shrink the old behaviour")
	big_shape.shape = circle
	big_shape.disabled = true
	check.call(is_equal_approx(service.get_body_allowance(big), margin), "H9-82 a disabled shape is ignored")
	big_shape.disabled = false
	big.scale = Vector2(2, 2)
	check.call(is_equal_approx(service.get_body_allowance(big), 80.0), "H9-83 a scaled body counts its scaled size")

	var in_view_far := _stub(host, Vector2(450, 0), &"enemy")
	made.append(in_view_far)
	service.set_view_override(Rect2(-100.0, -150.0, 700.0, 300.0))
	check.call(service.is_in_view(in_view_far) and not service.is_in_reach(Vector2.ZERO, in_view_far, 70.0), "H9-84 an enemy on screen but 450 px away is in view and not in reach: visibility never grants range")
	_free_all(made)

## H9.4.2: the approach as data. Stand-in targets and a service with a fixed view; nothing moves by itself, the checks
## move the stand-in "character" by hand and call update() the way the player will each frame.
static func _approach(check: Callable, host: Node) -> void:
	var made: Array = []
	var service := TargetingService2D.new()
	host.add_child(service)
	made.append(service)
	service.set_view_override(Rect2(-100.0, -150.0, 700.0, 300.0))
	var enemy := _stub(host, Vector2(300, 0), &"enemy")
	made.append(enemy)
	var reach := 70.0
	var dt := 1.0 / 60.0
	var End := AutoApproach2D.End

	var a := AutoApproach2D.start(AutoApproach2D.Kind.LIGHT, enemy, &"slash1")
	check.call(a.is_active() and a.kind == AutoApproach2D.Kind.LIGHT and a.action_id == &"slash1" and a.slot == -1 and a.target == enemy and a.end_reason == End.NONE, "H9-90 a new approach is active and remembers its kind, attack id and target")
	check.call(a.direction(Vector2.ZERO).is_equal_approx(Vector2.RIGHT) and a.direction(Vector2(300, 100)).is_equal_approx(Vector2.UP) and a.direction(Vector2(300, 0)) == Vector2.ZERO, "H9-91 the direction is a unit vector toward the target, zero when standing on it")
	check.call(not a.in_reach(Vector2.ZERO, reach, service) and a.in_reach(Vector2(230, 0), reach, service), "H9-92 in_reach uses the service's in-reach test (here 300 - 8 allowance is within 70 from x=230)")

	# Walking toward the target ends in ARRIVED, and the object moved nothing.
	var pos := Vector2.ZERO
	var result := End.NONE
	var frames := 0
	while result == End.NONE and frames < 600:
		pos += a.direction(pos) * 200.0 * dt
		result = a.update(dt, pos, reach, service)
		frames += 1
	check.call(result == End.ARRIVED and not a.is_active() and a.end_reason == End.ARRIVED and service.is_in_reach(pos, enemy, reach), "H9-93 walking toward an out-of-reach target ends ARRIVED once it is in reach")
	check.call(enemy.global_position == Vector2(300, 0), "H9-94 the approach moves nothing of its own")
	check.call(a.update(dt, pos, reach, service) == End.ARRIVED and a.direction(pos) == Vector2.ZERO, "H9-95 an ended approach stays ended and gives no direction")

	# Already in reach: arrives at once.
	var near := AutoApproach2D.start(AutoApproach2D.Kind.HEAVY, enemy, &"heavy")
	check.call(near.update(dt, Vector2(250, 0), reach, service) == End.ARRIVED, "H9-96 a target already in reach arrives on the first update")

	# Timeout: the character walks but too slowly.
	var slow := AutoApproach2D.start(AutoApproach2D.Kind.LIGHT, enemy, &"slash1", -1, 1.0, 5.0)
	pos = Vector2.ZERO
	result = End.NONE
	frames = 0
	while result == End.NONE and frames < 600:
		pos += Vector2.RIGHT * 10.0 * dt
		result = slow.update(dt, pos, reach, service)
		frames += 1
	check.call(result == End.TIMEOUT and frames >= 59 and frames <= 61, "H9-97 a walk that lasts longer than max_time ends TIMEOUT (%d frames for 1 s)" % frames)

	# Stall: the character does not get closer (a wall).
	var stuck := AutoApproach2D.start(AutoApproach2D.Kind.LIGHT, enemy, &"slash1", -1, 3.0, 0.5)
	result = End.NONE
	frames = 0
	while result == End.NONE and frames < 600:
		result = stuck.update(dt, Vector2(100, 0), reach, service)
		frames += 1
	check.call(result == End.STALL and frames >= 29 and frames <= 32, "H9-98 no progress for stall_time ends STALL (%d frames for 0.5 s)" % frames)
	var creeping := AutoApproach2D.start(AutoApproach2D.Kind.LIGHT, enemy, &"slash1", -1, 3.0, 0.5)
	pos = Vector2.ZERO
	result = End.NONE
	for i in 120:
		pos += Vector2.RIGHT * 1.0 * dt * 60.0 # one pixel a frame: slow but steady progress
		result = creeping.update(dt, pos, reach, service)
		if result != End.NONE:
			break
	check.call(result != End.STALL, "H9-99 steady progress, however slow, never counts as a stall")

	# Target gone / left the view / freed.
	var dying := _stub(host, Vector2(300, 0), &"enemy")
	made.append(dying)
	var b := AutoApproach2D.start(AutoApproach2D.Kind.LIGHT, dying, &"slash1")
	dying.alive = false
	check.call(b.update(dt, Vector2.ZERO, reach, service) == End.TARGET_GONE, "H9-100 a target that died ends TARGET_GONE")
	var leaving := _stub(host, Vector2(300, 0), &"enemy")
	made.append(leaving)
	var c := AutoApproach2D.start(AutoApproach2D.Kind.LIGHT, leaving, &"slash1")
	check.call(c.update(dt, Vector2.ZERO, reach, service) == End.NONE, "H9-101 a target in view and out of reach lets the walk go on")
	leaving.global_position = Vector2(900, 0)
	check.call(c.update(dt, Vector2.ZERO, reach, service) == End.LEFT_VIEW, "H9-102 a target that leaves the camera view ends LEFT_VIEW")
	var doomed := _stub(host, Vector2(300, 0), &"enemy")
	var d := AutoApproach2D.start(AutoApproach2D.Kind.LIGHT, doomed, &"slash1")
	doomed.free()
	check.call(d.update(dt, Vector2.ZERO, reach, service) == End.TARGET_GONE and d.direction(Vector2.ZERO) == Vector2.ZERO, "H9-103 a target that was freed ends TARGET_GONE without an error")

	# Reach is read every call: a weapon swap changes it, an attack that is gone has none.
	var e := AutoApproach2D.start(AutoApproach2D.Kind.LIGHT, enemy, &"slash1")
	check.call(e.update(dt, Vector2(100, 0), 70.0, service) == End.NONE and e.update(dt, Vector2(100, 0), 300.0, service) == End.ARRIVED, "H9-104 a longer reach after a weapon swap (bow) makes the same position arrive")
	var f := AutoApproach2D.start(AutoApproach2D.Kind.LIGHT, enemy, &"slash1")
	check.call(f.update(dt, Vector2.ZERO, 0.0, service) == End.NO_REACH, "H9-105 an action with no reach ends NO_REACH")

	# Cancel and kinds.
	var g := AutoApproach2D.start(AutoApproach2D.Kind.SKILL, enemy, &"", 2)
	check.call(g.kind == AutoApproach2D.Kind.SKILL and g.slot == 2 and g.action_id == &"", "H9-106 a skill approach remembers its slot")
	g.cancel()
	check.call(not g.is_active() and g.end_reason == End.CANCELLED and g.direction(Vector2.ZERO) == Vector2.ZERO and g.update(dt, Vector2.ZERO, reach, service) == End.CANCELLED, "H9-107 cancel() ends it for good (manual movement, dash, hit stun)")
	var h := AutoApproach2D.start(AutoApproach2D.Kind.LIGHT, enemy, &"slash1")
	h.update(dt, Vector2(250, 0), reach, service)
	h.cancel()
	check.call(h.end_reason == End.ARRIVED, "H9-108 cancelling an approach that already ended keeps its first reason")
	_free_all(made)

## H9.1c: get_reach() on attacks and skills, the one "how far does this action hit" number. Pure data, no scene.
static func _reach(check: Callable) -> void:
	var slash1 := load("res://Weapons/Sword/Attacks/Sword_Slash1.tres") as AttackDefinition2D
	var slash2 := load("res://Weapons/Sword/Attacks/Sword_Slash2.tres") as AttackDefinition2D
	var heavy := load("res://Weapons/Sword/Attacks/Sword_HeavySlash.tres") as AttackDefinition2D
	var shot := load("res://Weapons/Bow/Attacks/Bow_ArrowShot.tres") as AttackDefinition2D
	check.call(slash1 != null and slash2 != null and is_equal_approx(slash1.get_reach(), slash1.attack_range) and is_equal_approx(slash2.get_reach(), slash2.attack_range) and slash1.get_reach() > 0.0, "H9-1 a light attack's reach is its attack_range")
	check.call(shot != null and is_equal_approx(shot.get_reach(), shot.attack_range) and shot.get_reach() > 0.0, "H9-2 the bow's light shot reaches its attack_range")
	check.call(heavy != null and heavy.attack_range == 0.0 and heavy.aim_shape != null and heavy.get_reach() > 0.0 and is_equal_approx(heavy.get_reach(), heavy.aim_shape.max_range), "H9-3 a heavy attack with no attack_range reaches as far as its aim_shape")
	var both := AttackDefinition2D.new()
	both.attack_range = 50.0
	both.aim_shape = FanAimShape2D.make(90.0, 120.0)
	check.call(is_equal_approx(both.get_reach(), 50.0) and AttackDefinition2D.new().get_reach() == 0.0, "H9-4 attack_range wins over an aim_shape, and an attack with neither has no reach (0)")

	var power := load("res://Weapons/Bow/Skills/Bow_PowerShot.tres") as SkillDefinition2D
	var spin := load("res://Weapons/Sword/Skills/Sword_Spin.tres") as SkillDefinition2D
	var lunge := load("res://Weapons/Sword/Skills/Sword_Lunge.tres") as SkillDefinition2D
	var empower := load("res://Weapons/Sword/Skills/Sword_Empower.tres") as SkillDefinition2D
	check.call(power != null and is_equal_approx(power.get_reach(), power.max_range) and power.get_reach() > 0.0, "H9-5 a projectile skill reaches its max_range")
	check.call(spin != null and spin.get_reach() > 0.0 and is_equal_approx(spin.get_reach(), spin.area_radius if spin.area_radius > 0.0 else spin.attack.hitbox_size.x * 0.5 + spin.attack.hitbox_offset.length()), "H9-6 a circle skill round the caster reaches its radius")
	check.call(lunge != null and lunge.get_reach() > lunge.max_range, "H9-7 a dash skill with a strike reaches its distance plus the strike's radius")
	check.call(empower != null and empower.get_reach() == 0.0, "H9-8 a buff has no reach (0)")

	var area := SkillDefinition2D.new()
	area.behavior = SkillDefinition2D.Behavior.AREA
	area.area_radius = 20.0
	area.attack = AttackDefinition2D.new()
	area.attack.hitbox_offset = Vector2(30.0, 0.0)
	area.targeting = SkillDefinition2D.Targeting.AIM_DIRECTION
	check.call(is_equal_approx(area.get_reach(), 50.0), "H9-9 an area skill placed in front reaches offset plus radius")
	area.targeting = SkillDefinition2D.Targeting.SELF
	check.call(is_equal_approx(area.get_reach(), 20.0), "H9-10 with SELF targeting the offset is dropped")
	var ground := GroundCircleAimShape2D.new()
	ground.max_range = 100.0
	ground.radius = 40.0
	area.aim_shape = ground
	check.call(is_equal_approx(area.get_reach(), 140.0), "H9-11 a ground-circle skill reaches its cast range plus the circle's radius")
	var arrow := SkillDefinition2D.new()
	arrow.behavior = SkillDefinition2D.Behavior.PROJECTILE
	arrow.aim_shape = LineAimShape2D.new()
	check.call(arrow.get_reach() == arrow.aim_shape.max_range and SkillDefinition2D.new().get_reach() == 0.0, "H9-12 a projectile skill with no max_range falls back to its aim_shape")

static func _shapes(check: Callable) -> void:
	var o := Vector2.ZERO

	# --- Fan: 90 degrees (45 either side), reach 100, aimed right ---
	var fan := FanAimShape2D.make(90.0, 100.0)
	check.call(fan.contains(o, Vector2.RIGHT, Vector2(50, 0)), "H8-1 a fan holds a point straight ahead")
	check.call(fan.contains(o, Vector2.RIGHT, Vector2(50, 40)), "H8-2 and one 39 degrees off the aim (inside the 45)")
	check.call(not fan.contains(o, Vector2.RIGHT, Vector2(50, 60)), "H8-3 but not one 50 degrees off")
	check.call(not fan.contains(o, Vector2.RIGHT, Vector2(150, 0)), "H8-4 nor one past its reach")
	check.call(not fan.contains(o, Vector2.RIGHT, Vector2(-50, 0)), "H8-5 nor one behind the caster")
	check.call(fan.contains(o, Vector2.RIGHT, Vector2(50, 60), 20.0), "H8-6 a body with a radius of 20 whose centre is just outside still counts")
	check.call(fan.contains(o, Vector2(5, 0), Vector2(50, 0)), "H8-7 the aim direction does not need to be a unit vector")
	check.call(fan.contains(Vector2(100, 100), Vector2.UP, Vector2(100, 60)), "H8-8 the fan starts at the origin it is given, along any direction")
	check.call(not fan.contains(o, Vector2.ZERO, Vector2(50, 0)), "H8-9 a directional shape holds nothing when there is no direction")
	check.call(fan.contains(o, Vector2.RIGHT, o), "H8-10 a target standing on the caster is inside")
	var full := FanAimShape2D.make(360.0, 100.0)
	check.call(full.contains(o, Vector2.RIGHT, Vector2(-50, 0)), "H8-11 a 360 degree fan reaches behind")

	# --- Scoring: direction first, distance second ---
	var wide := FanAimShape2D.make(120.0, 100.0)
	var ahead_far := wide.score(o, Vector2.RIGHT, Vector2(90, 0))
	var side_near := wide.score(o, Vector2.RIGHT, Vector2(20, 30))
	check.call(ahead_far > side_near and side_near > 0.0, "H8-12 a target dead ahead but far beats a nearer one off to the side (%.2f vs %.2f)" % [ahead_far, side_near])
	check.call(wide.score(o, Vector2.RIGHT, Vector2(30, 0)) > wide.score(o, Vector2.RIGHT, Vector2(80, 0)), "H8-13 on the same line, the closer target scores higher")
	check.call(wide.score(o, Vector2.RIGHT, Vector2(-50, 0)) == -1.0, "H8-14 a point outside scores -1")
	var best := wide.score(o, Vector2.RIGHT, Vector2(1, 0))
	check.call(best > 0.0 and best <= 1.0, "H8-15 scores stay between 0 and 1 inside the shape (got %.2f)" % best)

	# --- Line: width 20, length 100 ---
	var line := LineAimShape2D.new()
	line.width = 20.0
	line.max_range = 100.0
	check.call(line.contains(o, Vector2.RIGHT, Vector2(50, 5)) and line.contains(o, Vector2.RIGHT, Vector2(50, -9)), "H8-16 a line holds points within half its width either side")
	check.call(not line.contains(o, Vector2.RIGHT, Vector2(50, 15)), "H8-17 but not one 15 pixels to the side")
	check.call(not line.contains(o, Vector2.RIGHT, Vector2(101, 0)) and not line.contains(o, Vector2.RIGHT, Vector2(-5, 0)), "H8-18 nor one past the end or behind the start")
	check.call(line.contains(o, Vector2.DOWN, Vector2(5, 50)) and not line.contains(o, Vector2.DOWN, Vector2(50, 5)), "H8-19 the strip turns with the aim direction")
	check.call(line.score(o, Vector2.RIGHT, Vector2(50, 0)) > line.score(o, Vector2.RIGHT, Vector2(50, 8)), "H8-20 a target on the centre line scores higher than one near the edge")
	check.call(line.contains(o, Vector2.RIGHT, Vector2(50, 15), 6.0), "H8-21 a body radius widens the strip")

	# --- Circle around the caster: radius 80 ---
	var circle := CircleSelfAimShape2D.new()
	circle.max_range = 80.0
	check.call(circle.contains(o, Vector2.ZERO, Vector2(0, -70)), "H8-22 a circle around the caster works with no aim direction")
	check.call(not circle.contains(o, Vector2.RIGHT, Vector2(0, 90)), "H8-23 and stops at its radius")
	check.call(circle.contains(o, Vector2.RIGHT, Vector2(-60, 0)), "H8-24 it also holds a point behind (the direction is ignored)")
	check.call(circle.score(o, Vector2.RIGHT, Vector2(10, 0)) > circle.score(o, Vector2.RIGHT, Vector2(70, 0)), "H8-25 inside a circle, only the distance orders targets")

	# --- Kinds and direction ---
	check.call(fan.get_kind() == AimShape2D.Kind.FAN and line.get_kind() == AimShape2D.Kind.LINE and circle.get_kind() == AimShape2D.Kind.CIRCLE_SELF, "H8-26 each shape reports its kind (the indicator picks its drawing from it)")
	check.call(fan.needs_direction() and line.needs_direction() and not circle.needs_direction(), "H8-27 only the circle around the caster needs no direction")

	# --- Validation ---
	check.call(fan.validate().is_empty() and line.validate().is_empty() and circle.validate().is_empty(), "H8-28 well-formed shapes report no problems")
	var bad_fan := FanAimShape2D.new()
	bad_fan.angle_degrees = 0.0
	check.call(not bad_fan.validate().is_empty(), "H8-29 a fan with no opening is reported")
	var bad_line := LineAimShape2D.new()
	bad_line.width = 0.0
	check.call(not bad_line.validate().is_empty(), "H8-30 a line with no width is reported")
	var no_reach := AimShape2D.new()
	no_reach.max_range = 0.0
	check.call(not no_reach.validate().is_empty() and not no_reach.contains(o, Vector2.RIGHT, Vector2(1, 0)), "H8-31 a shape with no reach is reported and holds nothing")

	# --- Resources are plain data ---
	var copy := fan.duplicate() as FanAimShape2D
	copy.angle_degrees = 30.0
	check.call(fan.angle_degrees == 90.0 and copy.max_range == 100.0, "H8-32 a duplicated shape keeps its values and changes alone")

static func _stub(host: Node, at: Vector2, team: StringName = &"", grouped: bool = true) -> Stub:
	var stub := Stub.new()
	stub.team = team
	host.add_child(stub)
	stub.global_position = at
	if grouped:
		stub.add_to_group(TargetingService2D.GROUP)
	return stub

static func _free_all(nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.free()

## H8.3: the targeting service.
static func _targeting(check: Callable, host: Node) -> void:
	var o := Vector2.ZERO
	var wide := FanAimShape2D.make(120.0, 200.0)
	var made: Array = []
	var caster := _stub(host, o, &"player") # in the damageable group too, to prove it never targets itself
	made.append(caster)
	var service := TargetingService2D.new()
	service.caster = caster
	host.add_child(service)
	made.append(service)

	# --- Who is eligible ---
	var a := _stub(host, Vector2(100, 0), &"enemy")
	var dead := _stub(host, Vector2(50, 0), &"enemy")
	dead.alive = false
	var friend := _stub(host, Vector2(60, 0), &"player")
	var scenery := _stub(host, Vector2(40, 0), &"enemy", false)
	var behind := _stub(host, Vector2(-80, 0), &"enemy")
	var far := _stub(host, Vector2(400, 0), &"enemy")
	made.append_array([a, dead, friend, scenery, behind, far])
	check.call(service.is_eligible(a) and not service.is_eligible(dead) and not service.is_eligible(friend) and not service.is_eligible(scenery), "H8-33 an enemy is eligible; a dead one, one on the caster's own team and one outside the damageable group are not")
	check.call(not service.is_eligible(caster), "H8-34 the caster is never its own target (even when it is in the group)")
	service.begin_action()
	var res := service.resolve(o, Vector2.RIGHT, wide)
	check.call(res.target == a and res.source == TargetingService2D.Source.TARGET, "H8-35 of everything in front, only the live enemy is picked (the nearer dead, friendly and scenery ones are skipped)")
	check.call(res.direction.distance_to(Vector2.RIGHT) < 0.001, "H8-36 the direction points from the origin to the target")
	check.call(service.get_action_target() == a, "H8-37 the pick is kept as the action's target")
	check.call(service.pick_target(o, Vector2.RIGHT, wide) == a, "H8-38 the enemy behind the caster and the one past the reach are outside a forward fan")
	var circle := CircleSelfAimShape2D.new()
	circle.max_range = 200.0
	a.alive = false
	service.begin_action()
	res = service.resolve(o, Vector2.RIGHT, circle)
	check.call(res.target == behind and res.direction.distance_to(Vector2.LEFT) < 0.001, "H8-39 a circle around the caster also picks the enemy behind it")
	a.alive = true

	# --- Direction toward an off-axis target ---
	_free_all([a, dead, friend, scenery, behind, far])
	var side := _stub(host, Vector2(60, 90), &"enemy")
	made.append(side)
	service.clear()
	res = service.resolve(o, Vector2.RIGHT, wide)
	check.call(res.target == side and res.direction.distance_to(Vector2(60, 90).normalized()) < 0.001, "H8-40 a target at the edge of the fan is picked and the direction turns toward it")

	# --- Stability: the choice is kept for an action, then re-made ---
	_free_all([side])
	var first := _stub(host, Vector2(100, 0), &"enemy")
	var second := _stub(host, Vector2(80, 70), &"enemy")
	made.append_array([first, second])
	service.clear()
	service.begin_action()
	res = service.resolve(o, Vector2.RIGHT, wide)
	check.call(res.target == first, "H8-41 the target dead ahead is picked at the start of an action")
	first.global_position = Vector2(60, 90)
	second.global_position = Vector2(100, 0)
	res = service.resolve(o, Vector2.RIGHT, wide)
	check.call(res.target == first, "H8-42 within the same action the choice stays, even though another enemy is now better placed")
	service.begin_action()
	res = service.resolve(o, Vector2.RIGHT, wide)
	check.call(res.target == second, "H8-43 the next action chooses afresh")

	# --- Re-choosing when the target is lost ---
	first.global_position = Vector2(100, 0)
	second.global_position = Vector2(60, 90)
	service.clear()
	service.begin_action()
	res = service.resolve(o, Vector2.RIGHT, wide)
	check.call(res.target == first, "H8-44 setup: the enemy ahead is the action's target")
	first.alive = false
	res = service.resolve(o, Vector2.RIGHT, wide)
	check.call(res.target == second, "H8-45 the target dying mid-action makes the service pick another")
	first.alive = true
	service.clear()
	service.begin_action()
	res = service.resolve(o, Vector2.RIGHT, wide)
	first.global_position = Vector2(400, 0)
	res = service.resolve(o, Vector2.RIGHT, wide)
	check.call(res.target == second, "H8-46 the target leaving range mid-action makes the service pick another")
	first.global_position = Vector2(100, 0)
	service.clear()
	service.begin_action()
	res = service.resolve(o, Vector2.RIGHT, wide)
	first.free()
	res = service.resolve(o, Vector2.RIGHT, wide)
	check.call(res.target == second and service.get_action_target() == second, "H8-47 a target freed mid-action is dropped without an error")
	check.call(not service.is_eligible(first), "H8-48 a freed node is simply not eligible")

	# --- Near ties keep the last target across actions ---
	_free_all([second])
	var left := _stub(host, Vector2(100, 10), &"enemy")
	var right := _stub(host, Vector2(100, -10), &"enemy")
	made.append_array([left, right])
	service.clear()
	service.begin_action()
	res = service.resolve(o, Vector2.RIGHT, wide)
	var kept := res.target
	check.call(kept != null, "H8-49 setup: two almost equal enemies, one is picked")
	var other: Node2D = right if kept == left else left
	other.global_position = Vector2(100, 0)
	service.begin_action()
	res = service.resolve(o, Vector2.RIGHT, wide)
	check.call(res.target == kept, "H8-50 a slightly better placed rival does not take over from the last target on the next action")

	# --- No target: the fallback chain ---
	_free_all([left, right])
	service.clear()
	service.begin_action()
	res = service.resolve(o, Vector2(0, 1), wide)
	check.call(res.target == null and res.source == TargetingService2D.Source.INTENDED and res.direction.distance_to(Vector2.DOWN) < 0.001, "H8-51 with no target the intended aim is used")
	res = service.resolve(o, Vector2.ZERO, wide, Vector2(-3, 0), Vector2(0, -1))
	check.call(res.source == TargetingService2D.Source.LAST_AIM and res.direction.distance_to(Vector2.LEFT) < 0.001, "H8-52 with no intended aim the last valid aim is used")
	res = service.resolve(o, Vector2.ZERO, wide, Vector2.ZERO, Vector2(0, -1))
	check.call(res.source == TargetingService2D.Source.FACING and res.direction.distance_to(Vector2.UP) < 0.001, "H8-53 with no last aim the last facing is used")
	res = service.resolve(o, Vector2.ZERO, wide)
	check.call(res.source == TargetingService2D.Source.DEFAULT and res.direction == Vector2.RIGHT, "H8-54 with nothing known the aim is right")
	var ahead := _stub(host, Vector2(100, 0), &"enemy")
	made.append(ahead)
	service.begin_action()
	res = service.resolve(o, Vector2.ZERO, wide, Vector2.RIGHT)
	check.call(res.target == ahead and res.source == TargetingService2D.Source.TARGET, "H8-55 a plain tap (no intended aim) searches along the last valid aim")
	service.begin_action()
	res = service.resolve(o, Vector2.RIGHT, null)
	check.call(res.target == null and res.direction == Vector2.RIGHT, "H8-56 an action with no aim shape gets no assist, only the fallback direction")

	# --- Manual aim overrides assistance ---
	service.begin_action()
	res = service.resolve(o, Vector2(0, 1), wide, Vector2.ZERO, Vector2.ZERO, true)
	check.call(res.target == null and res.source == TargetingService2D.Source.MANUAL and res.direction.distance_to(Vector2.DOWN) < 0.001, "H8-57 a manual aim is used as given even with an enemy dead ahead")
	check.call(service.get_action_target() == null, "H8-58 and a manual aim searches for nothing and keeps no target")

	# --- Hurtbox2D.targetable: objects opt in ---
	_free_all([ahead])
	var crate := _hurtbox(host, Vector2(50, 0))
	var barrel := _hurtbox(host, Vector2(30, 0))
	made.append_array([crate, barrel])
	check.call(not crate.is_in_group(TargetingService2D.GROUP) and not barrel.is_in_group(TargetingService2D.GROUP), "H8-59 a Hurtbox2D is not in the damageable group by default")
	crate.targetable = true
	check.call(crate.is_in_group(TargetingService2D.GROUP), "H8-60 switching targetable on registers it")
	service.clear()
	service.begin_action()
	res = service.resolve(o, Vector2.RIGHT, wide)
	check.call(res.target == crate, "H8-61 the registered crate is picked; the nearer unregistered one is ignored")
	crate.targetable = false
	check.call(not crate.is_in_group(TargetingService2D.GROUP), "H8-62 switching it off again removes it")

	_free_all(made) # this frees the service too, so there is nothing left to clear

static func _hurtbox(host: Node, at: Vector2) -> Hurtbox2D:
	var hurtbox := Hurtbox2D.new()
	var health := HealthComponent2D.new()
	health.name = "HealthComponent2D"
	hurtbox.add_child(health)
	host.add_child(hurtbox)
	hurtbox.global_position = at
	return hurtbox

## H8.6: aim_shape on heavy attacks and skills. Only the messages about the shape are looked at, so these skills need
## no attack or status to be built.
static func _aim_messages(messages: Array) -> Array:
	var found: Array = []
	for message in messages:
		if String(message).contains("aim_shape"):
			found.append(message)
	return found

static func _definitions(check: Callable) -> void:
	var fan := FanAimShape2D.make(40.0, 300.0)
	var circle := CircleSelfAimShape2D.new()
	circle.max_range = 52.0
	var buff := SkillDefinition2D.new()
	buff.id = &"t_buff"
	buff.behavior = SkillDefinition2D.Behavior.BUFF
	buff.aim_shape = fan
	check.call(not _aim_messages(buff.validate()).is_empty(), "H8-90 a buff skill with an aim_shape is a validation problem (D16)")
	buff.aim_shape = null
	check.call(_aim_messages(buff.validate()).is_empty(), "H8-91 a buff with no aim_shape has no aim_shape problem")
	var none := SkillDefinition2D.new()
	none.id = &"t_none"
	none.behavior = SkillDefinition2D.Behavior.NONE
	none.aim_shape = fan
	check.call(not _aim_messages(none.validate()).is_empty(), "H8-92 a NONE skill with an aim_shape is a validation problem")
	var spin := SkillDefinition2D.new()
	spin.id = &"t_spin"
	spin.behavior = SkillDefinition2D.Behavior.AREA
	spin.targeting = SkillDefinition2D.Targeting.SELF
	spin.area_radius = 52.0
	spin.aim_shape = fan
	check.call(not _aim_messages(spin.validate()).is_empty(), "H8-93 targeting SELF with an aimed shape (a fan) is a validation problem")
	spin.aim_shape = circle
	check.call(_aim_messages(spin.validate()).is_empty() and _aim_messages(spin.get_warnings()).is_empty(), "H8-94 targeting SELF with a circle around the caster is accepted, and its radius matches area_radius")
	circle.max_range = 120.0
	check.call(_aim_messages(spin.validate()).is_empty() and not _aim_messages(spin.get_warnings()).is_empty(), "H8-95 a circle far from area_radius is only a warning, never a problem")
	circle.max_range = 52.0
	var shot := SkillDefinition2D.new()
	shot.id = &"t_shot"
	shot.behavior = SkillDefinition2D.Behavior.PROJECTILE
	shot.max_range = 300.0
	var bad := FanAimShape2D.make(40.0, 300.0)
	bad.angle_degrees = 0.0
	shot.aim_shape = bad
	check.call(not _aim_messages(shot.validate()).is_empty(), "H8-96 a shape with invalid values (angle 0) is reported by the skill's validation")
	shot.aim_shape = FanAimShape2D.make(40.0, 300.0)
	check.call(_aim_messages(shot.validate()).is_empty() and _aim_messages(shot.get_warnings()).is_empty(), "H8-97 a shape that matches max_range raises nothing")
	shot.aim_shape = FanAimShape2D.make(40.0, 360.0)
	check.call(_aim_messages(shot.get_warnings()).is_empty(), "H8-98 a reach 20% off the skill's is inside the tolerance")
	shot.aim_shape = FanAimShape2D.make(40.0, 100.0)
	check.call(not _aim_messages(shot.get_warnings()).is_empty(), "H8-99 a reach far from max_range warns")
	check.call(not buff.wants_aim_shape() and not none.wants_aim_shape() and not shot.wants_aim_shape(), "H8-100 wants_aim_shape is false for a buff, NONE and a skill with no attack")
	shot.attack = AttackDefinition2D.new()
	check.call(shot.wants_aim_shape(), "H8-101 a damage skill (with an attack) wants an aim shape")

	# --- A weapon: the heavy attack's shape is checked; a basic_combo shape is a warning ---
	var weapon := WeaponDefinition2D.new()
	weapon.weapon_id = &"t_weapon"
	var light := AttackDefinition2D.new()
	light.id = &"t_light"
	weapon.basic_combo = [light]
	var heavy := AttackDefinition2D.new()
	heavy.id = &"t_heavy"
	weapon.heavy_attack = heavy
	heavy.aim_shape = bad
	check.call(not _aim_messages(weapon.validate()).is_empty(), "H8-102 a heavy attack with an invalid shape is a weapon validation problem")
	heavy.aim_shape = FanAimShape2D.make(100.0, 64.0)
	light.aim_shape = fan
	check.call(_aim_messages(weapon.validate()).is_empty() and not _aim_messages(weapon.get_warnings()).is_empty(), "H8-103 a light attack in basic_combo with a shape is only a warning (only the heavy attack uses one)")

	# --- The shipped content (definition of done, roadmap section 6) ---
	var skills := {
		"res://Weapons/Bow/Skills/Bow_PowerShot.tres": AimShape2D.Kind.LINE,
		"res://Weapons/Bow/Skills/Bow_MultiShot.tres": AimShape2D.Kind.FAN,
		"res://Weapons/Sword/Skills/Sword_Lunge.tres": AimShape2D.Kind.LINE,
		"res://Weapons/Sword/Skills/Sword_Spin.tres": AimShape2D.Kind.CIRCLE_SELF,
	}
	var skills_ok := true
	for path in skills:
		var skill := load(path) as SkillDefinition2D
		skills_ok = skills_ok and skill.wants_aim_shape() and skill.aim_shape != null and skill.aim_shape.get_kind() == skills[path]
		skills_ok = skills_ok and _aim_messages(skill.validate()).is_empty() and _aim_messages(skill.get_warnings()).is_empty()
	check.call(skills_ok, "H8-104 every shipped damage skill has an aim shape of the intended kind (power shot and lunge: line, multi-shot: fan, spin: circle), valid and matching its reach")
	var empower := load("res://Weapons/Sword/Skills/Sword_Empower.tres") as SkillDefinition2D
	check.call(not empower.wants_aim_shape() and empower.aim_shape == null, "H8-105 the buff (Empower) has no aim shape")
	var sword_heavy := load("res://Weapons/Sword/Attacks/Sword_HeavySlash.tres") as AttackDefinition2D
	var bow_heavy := load("res://Weapons/Bow/Attacks/Bow_ArrowHeavy.tres") as AttackDefinition2D
	check.call(sword_heavy.aim_shape != null and sword_heavy.aim_shape.get_kind() == AimShape2D.Kind.FAN and bow_heavy.aim_shape != null and bow_heavy.aim_shape.get_kind() == AimShape2D.Kind.LINE, "H8-106 the sword's heavy slash has a fan and the bow's heavy shot a line")
	var weapons_ok := true
	for path in ["res://Weapons/Sword/Sword_WeaponDefinition.tres", "res://Weapons/Bow/Bow_WeaponDefinition.tres"]:
		var definition := load(path) as WeaponDefinition2D
		weapons_ok = weapons_ok and _aim_messages(definition.validate()).is_empty() and _aim_messages(definition.get_warnings()).is_empty()
	check.call(weapons_ok, "H8-107 the shipped sword and bow weapons raise no aim_shape problem or warning")

## ---------- H8.9: aim indicators ----------

## True when `point` lies inside `polygon` and at least `edge` pixels from every edge, or outside and at least `edge`
## pixels from every edge. Points that close to the edge are skipped by the agreement test: a drawn arc is a chord
## polygon, so the last pixel or two along a curved edge may differ.
static func _clear_of_edge(polygon: PackedVector2Array, point: Vector2, edge: float) -> bool:
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		if Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point) < edge:
			return false
	return true

## How many grid points the drawn outline and `contains` disagree on (away from the edge), for a shape aimed `direction`.
static func _outline_disagreements(shape: AimShape2D, direction: Vector2, reach: float) -> int:
	var outline := shape.get_outline(direction)
	var wrong := 0
	var step := reach / 20.0
	for ix in range(-30, 31):
		for iy in range(-30, 31):
			var point := Vector2(ix, iy) * step
			if not _clear_of_edge(outline, point, 3.0):
				continue
			if Geometry2D.is_point_in_polygon(point, outline) != shape.contains(Vector2.ZERO, direction, point):
				wrong += 1
	return wrong

## H8.9: the indicator draws what the assist uses. Pure geometry, no scene.
static func run_indicator_shapes(check: Callable) -> void:
	var fan := FanAimShape2D.make(90.0, 100.0)
	var fan_outline := fan.get_outline(Vector2.UP)
	check.call(fan_outline.size() >= 4 and fan_outline[0] == Vector2.ZERO, "H8-140 a fan's outline starts at the caster and runs along its arc")
	var reach_ok := true
	for i in range(1, fan_outline.size()):
		reach_ok = reach_ok and is_equal_approx(fan_outline[i].length(), 100.0)
	check.call(reach_ok, "H8-141 every arc point of the fan is exactly its reach from the caster")
	check.call((fan_outline[1].angle_to(Vector2.UP) < 0.0) != (fan_outline[fan_outline.size() - 1].angle_to(Vector2.UP) < 0.0), "H8-142 the arc spans both sides of the aim")
	check.call(_outline_disagreements(fan, Vector2.UP, 100.0) == 0 and _outline_disagreements(fan, Vector2(1, 1), 100.0) == 0, "H8-143 the fan's drawn outline and its contains() agree everywhere (aimed up and diagonally)")
	var full := FanAimShape2D.make(360.0, 80.0)
	var full_outline := full.get_outline(Vector2.RIGHT)
	check.call(full_outline.size() >= 30 and not full_outline.has(Vector2.ZERO) and _outline_disagreements(full, Vector2.RIGHT, 80.0) == 0, "H8-144 a 360 degree fan draws as a whole circle with no point")

	var line := LineAimShape2D.new()
	line.max_range = 200.0
	line.width = 40.0
	var line_outline := line.get_outline(Vector2.RIGHT)
	check.call(line_outline.size() == 4 and Geometry2D.is_point_in_polygon(Vector2(100, 0), line_outline) and not Geometry2D.is_point_in_polygon(Vector2(100, 30), line_outline), "H8-145 a line's outline is a four-cornered strip, as wide as its width")
	check.call(_outline_disagreements(line, Vector2.RIGHT, 200.0 / 1.5) == 0 and _outline_disagreements(line, Vector2(-1, 2), 200.0 / 1.5) == 0, "H8-146 the line's drawn outline and its contains() agree (aimed right and slanted)")
	check.call(line.get_head_outline(Vector2.RIGHT).is_empty(), "H8-147 a rectangle line has no arrow head")
	line.style = LineAimShape2D.Style.ARROW
	var head := line.get_head_outline(Vector2.RIGHT)
	var head_inside := head.size() == 3 and head.has(Vector2(200, 0))
	for corner in head:
		head_inside = head_inside and line.contains(Vector2.ZERO, Vector2.RIGHT, corner)
	check.call(head_inside, "H8-148 an arrow's head points at the far end and sits inside the strip")
	check.call(line.get_outline(Vector2.RIGHT) == line_outline, "H8-149 the arrow style targets the same strip as the rectangle")

	var circle := CircleSelfAimShape2D.new()
	circle.max_range = 90.0
	check.call(circle.get_outline(Vector2.RIGHT) == circle.get_outline(Vector2.UP) and _outline_disagreements(circle, Vector2.RIGHT, 90.0) == 0, "H8-150 a circle's outline ignores the direction and matches contains()")
	check.call(AimShape2D.new().get_outline(Vector2.RIGHT).is_empty() and FanAimShape2D.make(90.0, 100.0).get_outline(Vector2.ZERO).size() >= 4, "H8-151 a bare shape draws nothing, and a zero direction still draws a fan (it points right)")

	# H9.5: the displayed area must stay inside its own action range, even when a line's
	# corners extend beyond the radius. These are geometry checks, not a substitute for play-test.
	var clipped_line := AimIndicator2D.clip_polygon_to_range(line_outline, 200.0)
	var line_clip_ok := not clipped_line.is_empty()
	for polygon in clipped_line:
		for point in polygon:
			line_clip_ok = line_clip_ok and point.length() <= 200.1
	check.call(line_clip_ok, "H9-55 line aim area is clipped to its own range circle")
	var wide_line := LineAimShape2D.new()
	wide_line.max_range = 80.0
	wide_line.width = 100.0
	var wide_clipped := AimIndicator2D.clip_polygon_to_range(wide_line.get_outline(Vector2.RIGHT), wide_line.max_range)
	var wide_clip_ok := not wide_clipped.is_empty()
	for polygon in wide_clipped:
		for point in polygon:
			wide_clip_ok = wide_clip_ok and point.length() <= 80.1
	check.call(wide_clip_ok, "H9-56 a very wide line remains within its action range after clipping")
	var fan_clipped := AimIndicator2D.clip_polygon_to_range(fan.get_outline(Vector2.UP), fan.max_range)
	check.call(not fan_clipped.is_empty(), "H9-57 a fan remains drawable after range clipping")
	check.call(AimIndicator2D.clip_polygon_to_range(line_outline, 0.0).is_empty(), "H9-58 zero range produces no clipped aim area")
	var full_circle := CircleSelfAimShape2D.new()
	full_circle.max_range = 90.0
	var circle_clipped := AimIndicator2D.clip_polygon_to_range(full_circle.get_outline(Vector2.RIGHT), full_circle.max_range)
	var circle_clip_ok := not circle_clipped.is_empty()
	for polygon in circle_clipped:
		for point in polygon:
			circle_clip_ok = circle_clip_ok and point.length() <= 90.1
	check.call(circle_clip_ok, "H9-59 a self-circle aim stays within its own range")

## H8.9: the indicator node and the targeting service's candidate list.
static func run_indicator_node(check: Callable, host: Node) -> void:
	var indicator := AimIndicator2D.new()
	host.add_child(indicator)
	check.call(not indicator.is_showing(), "H8-152 an indicator shows nothing until it is told to")
	var fan := FanAimShape2D.make(90.0, 100.0)
	indicator.show_shape(fan, Vector2(0, -5))
	check.call(indicator.is_showing() and indicator.get_shape() == fan and indicator.get_direction().distance_to(Vector2.UP) < 0.001 and indicator.visible, "H8-153 show_shape stores the shape and a unit direction")
	indicator.show_shape(fan, Vector2.RIGHT, [], null, Vector2.ZERO, 150.0)
	check.call(is_equal_approx(indicator.get_range_radius(), 150.0), "H9-60 aim clipping uses the active definition's supplied reach, not a shared radius")
	indicator.clear()
	check.call(is_equal_approx(indicator.get_range_radius(), 0.0), "H9-61 clearing the aim indicator resets its clipping range")
	indicator.show_shape(fan, Vector2.ZERO)
	check.call(indicator.get_direction() == Vector2.RIGHT, "H8-154 a zero direction draws toward the right, never a zero vector")
	indicator.clear()
	check.call(not indicator.is_showing() and not indicator.visible and indicator.get_shape() == null, "H8-155 clear hides it and forgets the shape")
	indicator.show_shape(null, Vector2.RIGHT)
	check.call(not indicator.is_showing(), "H8-156 showing no shape is the same as clearing")

	var made: Array = []
	var service := TargetingService2D.new()
	host.add_child(service)
	var front := _stub(host, Vector2(40, 0))
	var side := _stub(host, Vector2(40, 30))
	var behind := _stub(host, Vector2(-40, 0))
	var dead := _stub(host, Vector2(50, 0))
	dead.alive = false
	var scenery := _stub(host, Vector2(30, 0), &"", false)
	made.append_array([front, side, behind, dead, scenery])
	var inside := service.candidates_in_shape(Vector2.ZERO, Vector2.RIGHT, FanAimShape2D.make(90.0, 100.0))
	check.call(inside.size() == 2 and inside[0] == front and inside[1] == side, "H8-157 the candidate list holds only live, registered targets inside the shape, best first (got %s)" % [inside])
	check.call(service.get_action_target() == null and service.pick_target(Vector2.ZERO, Vector2.RIGHT, FanAimShape2D.make(90.0, 100.0)) == inside[0], "H8-158 asking for the list changes no kept target, and its first entry is the one pick_target chooses")
	check.call(service.candidates_in_shape(Vector2.ZERO, Vector2.RIGHT, null).is_empty(), "H8-159 no shape, no candidates")

	indicator.show_shape(fan, Vector2.RIGHT, inside, front)
	check.call(indicator.get_candidates().size() == 2 and indicator.get_picked() == front, "H8-160 the indicator keeps the ringed targets and the picked one")
	side.free()
	check.call(indicator.get_candidates().size() == 1 and indicator.get_picked() == front, "H8-161 a target freed while ringed is dropped without an error")
	front.free()
	check.call(indicator.get_picked() == null, "H8-162 a freed picked target reads as none")
	service.free()
	indicator.free()
	for node in made:
		if is_instance_valid(node):
			node.free()


## ---------- H8.8b: the ground circle (drag-to-place) ----------

## The indicator scenes (Priority 1 of the scene review): each holds its draw order and is the same node the code used to build.
static func run_indicator_scenes(check: Callable, host: Node) -> void:
	var aim := (load("res://Characters/Components/Aim/AimIndicator2D.tscn") as PackedScene).instantiate() as AimIndicator2D
	var assist := (load("res://Characters/Components/Aim/AssistIndicator2D.tscn") as PackedScene).instantiate() as AssistIndicator2D
	check.call(aim != null and assist != null, "H8-239 both indicator scenes instantiate as their script types")
	if aim == null or assist == null:
		return
	host.add_child(aim)
	host.add_child(assist)
	check.call(aim.z_index == 50 and aim.z_as_relative, "H8-240 the aim indicator scene draws above the characters (z 50)")
	check.call(assist.z_index == -1 and not assist.z_as_relative, "H8-241 the assist indicator scene draws below the characters (absolute z -1)")
	check.call(not aim.is_showing() and assist.get_range_radius() == 0.0 and assist.get_target() == null, "H8-242 a scene instance shows nothing until it is told to")
	aim.queue_free()
	assist.queue_free()

## H8.8b: the shape's geometry. Pure, no scene.
static func run_ground_shapes(check: Callable) -> void:
	var ground := GroundCircleAimShape2D.new()
	ground.max_range = 200.0
	ground.radius = 50.0
	ground.default_pull = 0.5
	check.call(ground.get_kind() == AimShape2D.Kind.GROUND_CIRCLE and ground.is_placed() and ground.area_radius() == 50.0, "H8-183 a ground circle is a placed shape of its own kind, and reports its radius")
	check.call(not FanAimShape2D.make(90.0, 100.0).is_placed() and not LineAimShape2D.new().is_placed() and not CircleSelfAimShape2D.new().is_placed() and CircleSelfAimShape2D.new().place(Vector2(5, 5), Vector2.RIGHT) == Vector2(5, 5), "H8-184 the other shapes are not placed and their placement calls are inert")
	check.call(ground.place(Vector2.ZERO, Vector2.RIGHT, 1.0) == Vector2(200, 0) and ground.place(Vector2.ZERO, Vector2(0, -3), 0.25).distance_to(Vector2(0, -50)) < 0.001, "H8-185 the centre goes pull of the way out along the aim (full pull = the cast range)")
	check.call(ground.place(Vector2.ZERO, Vector2.RIGHT, -1.0) == Vector2(100, 0) and ground.place(Vector2.ZERO, Vector2.RIGHT, 5.0) == Vector2(200, 0), "H8-186 no pull given uses default_pull; a pull past 1 stops at the cast range")
	check.call(ground.place(Vector2(3, 4), Vector2.ZERO, 1.0) == Vector2(3, 4), "H8-187 with no direction at all it stays on the caster")
	check.call(ground.place_on(Vector2.ZERO, Vector2(80, 0)) == Vector2(80, 0) and ground.place_on(Vector2.ZERO, Vector2(0, 500)).distance_to(Vector2(0, 200)) < 0.001, "H8-188 a circle put on a target is centred on it, held inside the cast range")
	check.call(ground.covers(Vector2(100, 0), Vector2(140, 0)) and not ground.covers(Vector2(100, 0), Vector2(160, 0)) and ground.covers(Vector2(100, 0), Vector2(160, 0), 10.0), "H8-189 covers() is the placed circle, and a big body just outside the edge still counts")
	var area := ground.get_area_outline()
	var radius_ok := area.size() >= 30
	for point in area:
		radius_ok = radius_ok and is_equal_approx(point.length(), 50.0)
	check.call(radius_ok and ground.get_outline(Vector2.RIGHT).is_empty(), "H8-190 the area outline is a circle of the radius round its own centre; nothing is drawn from the caster")
	var reach := ground.get_range_outline()
	check.call(reach.size() == area.size() and is_equal_approx(reach[0].length(), 200.0), "H8-191 the range outline is the cast range round the caster")
	check.call(ground.contains(Vector2.ZERO, Vector2.RIGHT, Vector2(240, 0)) and not ground.contains(Vector2.ZERO, Vector2.RIGHT, Vector2(260, 0)), "H8-192 the assist region reaches as far as the circle can (cast range plus radius)")
	check.call(not ground.contains(Vector2.ZERO, Vector2.RIGHT, Vector2(-50, 0)) and ground.contains(Vector2.ZERO, Vector2.RIGHT, Vector2(50, 40)) and not ground.contains(Vector2.ZERO, Vector2.RIGHT, Vector2(-5, 50)), "H8-193 the assist region is limited to assist_angle round the aim (180 degrees: not behind)")
	check.call(ground.score(Vector2.ZERO, Vector2.RIGHT, Vector2(50, 0)) > ground.score(Vector2.ZERO, Vector2.RIGHT, Vector2(50, 40)), "H8-194 a target on the aim scores above one off to the side")
	ground.assist_angle = 360.0
	check.call(ground.contains(Vector2.ZERO, Vector2.RIGHT, Vector2(-50, 0)), "H8-195 a 360 degree assist looks all round")
	check.call(ground.validate().is_empty(), "H8-196 a well-formed ground circle validates")
	ground.radius = 0.0
	check.call(not ground.validate().is_empty() and not ground.contains(Vector2.ZERO, Vector2.RIGHT, Vector2(10, 0)), "H8-197 a ground circle with no radius is reported and targets nothing")

## H8.8b: the circle candidates, the indicator's centre, and the touch button's pull. `host` is in the running tree.
static func run_ground_node(check: Callable, host: Node) -> void:
	var made: Array = []
	var service := TargetingService2D.new()
	host.add_child(service)
	var near := _stub(host, Vector2(100, 0))
	var next := _stub(host, Vector2(130, 0))
	var far := _stub(host, Vector2(300, 0))
	var scenery := _stub(host, Vector2(105, 0), &"", false)
	var dead := _stub(host, Vector2(108, 0))
	dead.alive = false
	made.append_array([near, next, far, scenery, dead])
	var covered := service.candidates_in_circle(Vector2(110, 0), 30.0)
	check.call(covered.size() == 2 and covered[0] == near and covered[1] == next, "H8-198 the circle covers live, registered targets only, nearest the centre first (got %s)" % [covered])
	check.call(service.candidates_in_circle(Vector2(110, 0), 0.0).is_empty() and service.get_action_target() == null, "H8-199 no radius covers nothing, and asking keeps no target")
	var ground := GroundCircleAimShape2D.new()
	ground.max_range = 200.0
	ground.radius = 50.0
	check.call(service.pick_target(Vector2.ZERO, Vector2.RIGHT, ground) == near, "H8-200 the assist puts a tap's circle on the best target inside the region")

	var indicator := AimIndicator2D.new()
	host.add_child(indicator)
	indicator.show_shape(ground, Vector2.RIGHT, covered, near, Vector2(100, 0))
	check.call(indicator.is_showing() and indicator.get_center_offset() == Vector2(100, 0), "H8-201 the indicator keeps where the circle is put")
	indicator.show_shape(FanAimShape2D.make(90.0, 100.0), Vector2.RIGHT)
	check.call(indicator.get_center_offset() == Vector2.ZERO, "H8-202 a shape that is not placed has no centre offset")
	indicator.show_shape(ground, Vector2.RIGHT, [], null, Vector2(10, 0))
	indicator.clear()
	check.call(indicator.get_center_offset() == Vector2.ZERO and not indicator.is_showing(), "H8-203 clearing the indicator forgets the centre")
	indicator.free()
	service.free()
	_free_all(made)

## H8.8b: a drag reports how far out the finger is (the pull) as well as where it points. Needs the tree for the button.
static func run_ground_pull(check: Callable, host: Node) -> void:
	var button := TouchActionButton.new()
	button.action = &"skill_1"
	button.mode = TouchActionButton.Mode.AIM_ON_RELEASE
	button.size = Vector2(80, 80)
	host.add_child(button)
	button.position = Vector2(100, 100)
	var pulls: Array = []
	var directions: Array = []
	button.pull_changed.connect(func(pull: float) -> void: pulls.append(pull))
	button.aim_changed.connect(func(direction: Vector2) -> void: directions.append(direction))
	var centre := button.get_global_rect().get_center()
	var down := InputEventScreenTouch.new()
	down.index = 1
	down.pressed = true
	down.position = centre
	button._input(down)
	check.call(button.get_pull() == -1.0 and pulls.is_empty(), "H8-204 a finger that has only landed has no pull")
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = centre + Vector2(40, 0)
	button._input(drag)
	check.call(button.is_dragging() and absf(button.get_pull() - 0.5) < 0.001 and button.get_aim() == Vector2.RIGHT, "H8-205 dragging half the aim reach gives a pull of one half (got %s)" % button.get_pull())
	var aim_events := directions.size()
	drag.position = centre + Vector2(60, 0)
	button._input(drag)
	check.call(absf(button.get_pull() - 0.75) < 0.001 and directions.size() == aim_events, "H8-206 going farther the same way changes the pull, not the aim")
	drag.position = centre + Vector2(400, 0)
	button._input(drag)
	check.call(button.get_pull() == 1.0, "H8-207 the pull stops at 1")
	drag.position = centre + Vector2(5, 0)
	button._input(drag)
	check.call(button.get_pull() == -1.0 and button.get_aim() == Vector2.ZERO and pulls.back() == -1.0, "H8-208 back in the dead zone there is no manual aim and no pull")
	button.release()
	button.free()

## H8.8b: the player puts the circle where the aim says. `main` is a fresh Main scene from the suite.
static func run_ground_player(check: Callable, main: Node) -> void:
	var p = main.get_node("Player") # untyped: it calls player.gd methods Character2D does not declare
	var manager := main.get_node("InputModeManager") as InputModeManager
	manager.set_device(InputModeManager.Device.TOUCH)
	p.clear_manual_aim()
	p.clear_manual_pull()
	var home: Vector2 = p.global_position
	p.global_position = Vector2(50000.0, 50000.0) # far from the arena's own enemies, so only the stand-ins count
	var origin: Vector2 = p.global_position
	var ground := GroundCircleAimShape2D.new()
	ground.max_range = 200.0
	ground.radius = 50.0
	ground.default_pull = 0.5
	p.context.last_aim_direction = Vector2.RIGHT
	p._direction_for_activation(null)
	check.call(not p.has_ground_point(), "H8-209 an activation with no placed shape makes no ground point")
	p._direction_for_activation(ground)
	check.call(p.has_ground_point() and p.get_ground_point().distance_to(origin + Vector2(100, 0)) < 0.01, "H8-210 a tap with no target puts the circle at the default distance along the last aim")
	p.set_manual_aim(Vector2.UP)
	p.set_manual_pull(1.0)
	p._direction_for_activation(ground)
	check.call(p.get_ground_point().distance_to(origin + Vector2(0, -200)) < 0.01, "H8-211 a drag puts the circle that far out along the drag, at full range for a full pull")
	p.set_manual_pull(0.25)
	p._direction_for_activation(ground)
	check.call(p.get_ground_point().distance_to(origin + Vector2(0, -50)) < 0.01, "H8-212 a short drag puts it close to the caster")
	var target := _stub(main, origin + Vector2(0, -120))
	p._direction_for_activation(ground)
	check.call(p.get_ground_point().distance_to(origin + Vector2(0, -50)) < 0.01, "H8-213 a drag ignores targets: the circle goes where it was put")
	p.clear_manual_aim()
	p.clear_manual_pull()
	p.context.last_aim_direction = Vector2.UP
	p._direction_for_activation(ground)
	check.call(p.get_ground_point().distance_to(target.global_position) < 0.01, "H8-214 a tap with a target inside the region puts the circle on the target")
	target.global_position = origin + Vector2(0, -230)
	p._direction_for_activation(ground)
	check.call(p.get_ground_point().distance_to(origin + Vector2(0, -200)) < 0.01, "H8-215 a target beyond the cast range gets the circle at the edge of the range, not past it")
	target.free()
	p.set_manual_pull(2.0)
	check.call(p.get_manual_pull() == 1.0, "H8-216 a pull is held between 0 and 1")
	p.set_manual_pull(-5.0)
	check.call(p.get_manual_pull() == -1.0, "H8-217 a negative pull means none given")
	p.clear_manual_aim()
	p.clear_manual_pull()
	p.global_position = home

## ---------- H8.8c: the touch layout lives in a scene ----------

## MobileControls.tscn (the layout saved in the scene) must be the same layout the code builds, button for button, and
## wired the same. `host` is a node in the running tree. Needs two frames for the layout to settle, so await it.
static func run_scene_layout(check: Callable, host: Node) -> void:
	var tree := host.get_tree()
	var parents: Array = []
	for i in 2:
		var parent := Control.new()
		parent.size = Vector2(1280, 720)
		host.add_child(parent)
		parents.append(parent)
	var code := MobileControls.new()
	code.debug_force_visible = true
	parents[0].add_child(code)
	var scene := (load("res://UI/Touch/MobileControls.tscn") as PackedScene).instantiate() as MobileControls
	scene.debug_force_visible = true
	parents[1].add_child(scene)
	await tree.process_frame
	await tree.process_frame
	var sticks := scene.find_children("*", "VirtualStick", true, false)
	check.call(sticks.size() == 1 and sticks[0] == scene.get_move_stick() and scene.get_move_stick().name == &"MoveStick" and scene.find_children("*", "ColorRect", true, false).is_empty(), "H8-218 the scene has exactly one VirtualStick, its MoveStick, and no placeholder")
	var stick_a := code.get_move_stick().get_global_rect()
	var stick_b := scene.get_move_stick().get_global_rect()
	check.call(stick_a.position.distance_to(stick_b.position) < 0.01 and stick_a.size.distance_to(stick_b.size) < 0.01, "H8-219 the scene's move stick sits where the code puts it (%s vs %s)" % [stick_a, stick_b])
	var cluster_a := (code.get_node("RightCluster") as Control).get_global_rect()
	var cluster_b := (scene.get_node("RightCluster") as Control).get_global_rect()
	check.call(cluster_a.position.distance_to(cluster_b.position) < 0.01 and cluster_a.size.distance_to(cluster_b.size) < 0.01, "H8-220 the right-hand cluster has the same rectangle (%s vs %s)" % [cluster_a, cluster_b])
	var same_place := true
	var same_wiring := true
	var names := ["attack_light", "dash", "weapon_next", "skill_1", "skill_2", "skill_3"]
	for action in names:
		var a := code.get_button(StringName(action))
		var b := scene.get_button(StringName(action))
		if a == null or b == null:
			same_place = false
			continue
		same_place = same_place and a.get_global_rect().position.distance_to(b.get_global_rect().position) < 0.01 and a.get_global_rect().size.distance_to(b.get_global_rect().size) < 0.01 and a.caption == b.caption
		same_wiring = same_wiring and a.mode == b.mode and a.drag_aim == b.drag_aim and a.aim_query.is_valid() == b.aim_query.is_valid() and a.cast_pending_changed.get_connections().size() == b.cast_pending_changed.get_connections().size() and a.pull_changed.get_connections().size() == b.pull_changed.get_connections().size()
	check.call(same_place, "H8-221 every button of the scene has the position, size and caption the code gives it")
	check.call(same_wiring, "H8-222 every button is wired the same: modes, drag aim, skill callbacks")
	var scene_actions := scene.get_actions()
	var code_actions := code.get_actions()
	scene_actions.sort()
	code_actions.sort()
	check.call(scene_actions == code_actions and scene.get_button(&"attack_heavy") == null, "H8-223 the scene offers the same actions, and no heavy button (D13, D15)")
	var bare := MobileControls.new()
	parents[0].add_child(bare)
	check.call(bare.get_node_or_null("RightCluster") != null and bare.get_button(&"attack_light") != null, "H8-224 a MobileControls node with no children still builds the layout in code")
	for parent in parents:
		parent.free()
