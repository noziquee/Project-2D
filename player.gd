extends Character2D
## Player controller: input and aim. Health lives in the HealthComponent2D child and the hit flash and death
## clip in the ReactionComponent2D child (see Character2D). Groups ("player", "damageable") are set on the
## scene root in player.tscn.

## Attack ids this controller asks the AttackComponent2D for (9.7d-1). Both are optional overrides:
## leave them empty and the ids come from the equipped weapon (the light attack is the component's
## default attack, which is the weapon's first combo attack; the heavy attack is the weapon's
## heavy_attack). A heavy attack must be registered on the component; until it is (or the weapon has
## none), attack_light fires its light attack on press and attack_heavy does nothing.
@export var light_attack_id: StringName = &""
@export var heavy_attack_id: StringName = &""
## Seconds attack_light must be held before it begins a charge of the heavy attack (9.6d). A shorter
## press is the light attack, sent when the button is released. Only used once a heavy attack exists.
@export_range(0.0, 2.0, 0.01) var charge_start_time: float = 0.1
## Light-attack assist (H8.5, H9.3): a tap looks for a target inside a fan of this many degrees, centred on the aim the
## player gives (or the last aim, or the facing, when there is none), among everything the camera shows. How far the
## weapon reaches does not decide who can be targeted: a visible enemy out of range is still selected (closing the
## distance is auto-approach, H9.4). 360 (the default) looks all round, so an enemy beside or behind you is found too;
## a narrower fan only looks in front. 0 turns the assist off. It only steers the direction; the swing's arc and hitbox
## are unchanged.
@export_range(0.0, 360.0, 1.0) var light_assist_angle: float = 360.0
## How much a light tap prefers a target that lines up with the aim over a closer one (0 to 1). Low = the nearest enemy
## wins, like a mobile MOBA's auto-target. The aim is often only the last direction on touch, so it is a weak guide.
const LIGHT_ASSIST_ANGLE_WEIGHT := 0.4

## Assist view: the blue circle is the equipped light attack's reach; the single red ring marks the target the next tap
## would select. The marker is visual only and never changes combat rules.
@export var show_attack_range := true
@export var show_target_marker := true

## Aim indicators (H8.9): while a heavy attack charges, or a finger rests on an aimed skill's touch button, the shape of
## that action is drawn round the player, with the targets inside it ringed. It draws the same AimShape2D the assist
## uses. Off turns the drawing off; the assist is unchanged.
@export var aim_indicators := true

## Auto-approach limits (H9.4.2). An attack aimed at a target out of reach walks toward it; these keep it from walking
## for ever. `max_approach_time` is the longest walk, `approach_stall_time` how long the distance may stay unchanged
## (against a wall, say) before the walk is dropped. Nothing reads them until H9.4.3.
@export_range(0.5, 10.0, 0.1) var max_approach_time: float = 3.0
@export_range(0.1, 3.0, 0.05) var approach_stall_time: float = 0.5

## Attack input for this frame, filled by _sample_attack_input() before the attack hooks are read.
var _pending_light: StringName = &""
var _pending_begin: StringName = &""
var _pending_release := false
## attack_light is held, and how long it has been held (only meaningful while held).
var _light_held := false
var _hold_elapsed := 0.0
## The current attack_light press has begun a charge (seen while the component was charging).
var _press_charged := false
## A charge has been requested for the current attack_light press (it may still be refused).
var _charge_requested := false
## attack_heavy is held: it charges the heavy attack directly, with no hold time.
var _heavy_held := false

func _get_movement_input() -> Vector2:
	if not is_alive():
		return Vector2.ZERO
	var manual := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if manual.length_squared() > 0.0001:
		_cancel_approach()
		_approach_target_override = null
		return manual
	if _is_approach_active():
		return _approach.direction(global_position)
	return manual

func _get_dash_requested() -> bool:
	return is_alive() and Input.is_action_just_pressed("dash")

## Which device aims (H7.4). The right stick takes over as soon as it is pushed past its dead zone and keeps the last
## direction it was pointing when it is let go; any mouse movement or click hands the aim back to the mouse. So a
## controller player is not pulled toward a mouse that is lying still, and a mouse player is not affected at all.
enum AimSource { MOUSE, STICK }
## The mouse aim before the pointer moved onto the HUD (the hotbar), so clicking a skill slot casts toward where the
## player was aiming and not toward the hotbar.
var _last_mouse_aim := Vector2.ZERO
var _aim_source: AimSource = AimSource.MOUSE
var _stick_aim := Vector2.ZERO

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_aim_source = AimSource.MOUSE

func _get_aim_direction() -> Vector2:
	if not is_alive():
		return context.facing_direction
	# On arrival, keep the requested target as the action aim for this physics pass.
	if is_instance_valid(_approach_target_override):
		var to_target := _approach_target_override.global_position - global_position
		if to_target.length_squared() > 0.0001:
			return to_target.normalized()
	# While closing distance, face the movement direction rather than a stale mouse/stick aim.
	if _is_approach_active():
		return _approach.direction(global_position)
	# A manual aim (a drag on a touch button, H8.4) is the aim while it lasts, so the facing and the weapon follow it.
	if _manual_aim.length_squared() > 0.0001:
		_remember_aim(_manual_aim)
		return _manual_aim.normalized()
	# get_vector applies the dead zone of the aim actions, so a resting stick reads as zero.
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length_squared() > 0.0:
		_aim_source = AimSource.STICK
		_stick_aim = stick.normalized()
		_remember_aim(_stick_aim)
		return _stick_aim
	if _aim_source == AimSource.STICK:
		return _stick_aim if _stick_aim.length_squared() > 0.0001 else context.facing_direction
	if _pointer_over_hud():
		return _last_mouse_aim if _last_mouse_aim.length_squared() > 0.0001 else context.facing_direction
	var direction := get_global_mouse_position() - global_position
	_last_mouse_aim = direction.normalized() if direction.length_squared() > 0.0001 else context.facing_direction
	# A finger has no pointer: on touch the mouse position is stale, so it is not a valid aim to remember.
	if direction.length_squared() > 0.0001 and not _on_touch():
		_remember_aim(_last_mouse_aim)
	return _last_mouse_aim

## Assisted aiming (H8.4). The aim above is the cheap per-frame read (facing, weapon pivot, charge follow). The
## targeting service is asked only when an action starts, so its choice is not remade every frame.
##
## A manual aim is a deliberate direction (a drag on an attack or skill button, set by the touch controls); it
## overrides assistance for as long as it is set. Whoever sets it clears it when the drag ends, so the next action
## returns to assistance. The right stick counts as manual while it is pushed.
var _manual_aim := Vector2.ZERO
var _targeting: TargetingService2D
## True from the end of _sample_attack_input() to the start of the next physics frame: the window in which the
## pending light, charge-begin and release requests are real activations.
var _activation_open := false

## One interruptible approach request. AutoApproach2D owns decisions only; Character2D's existing movement path still
## performs all movement, and the player rechecks the current weapon/skill reach every physics frame.
var _approach: AutoApproach2D
var _approach_kind: int = AutoApproach2D.Kind.LIGHT
var _approach_action_id: StringName = &""
var _approach_slot := -1
var _approach_target_override: Node2D

func set_manual_aim(direction: Vector2) -> void:
	_manual_aim = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.ZERO

func clear_manual_aim() -> void:
	_manual_aim = Vector2.ZERO

func get_manual_aim() -> Vector2:
	return _manual_aim

## How far out a drag puts a ground circle (H8.8): 0 to 1 of the skill's cast range, or -1 for none given. Set by the
## touch controls along with the manual aim; the mouse and a pushed stick give their own (see _ground_pull).
var _manual_pull := -1.0

func set_manual_pull(pull: float) -> void:
	_manual_pull = clampf(pull, 0.0, 1.0) if pull >= 0.0 else -1.0

func clear_manual_pull() -> void:
	_manual_pull = -1.0

func get_manual_pull() -> float:
	return _manual_pull

## The ground circle's centre chosen by the latest activation (H8.8), in world space. Valid only when the shape the
## activation used was a placed one (has_ground_point()); it is decided before the skill starts and stays the same for
## the whole cast. A ground-target skill reads it while it is being cast.
var _ground_point := Vector2.ZERO
var _has_ground_point := false

func has_ground_point() -> bool:
	return _has_ground_point

func get_ground_point() -> Vector2:
	return _ground_point

## The targeting service (a child named TargetingService2D; made on first use when the scene has none).
func get_targeting_service() -> TargetingService2D:
	if not is_instance_valid(_targeting):
		_targeting = get_node_or_null("TargetingService2D") as TargetingService2D
		if _targeting == null:
			_targeting = TargetingService2D.new()
			_targeting.name = "TargetingService2D"
			_targeting.caster = self
			add_child(_targeting)
	return _targeting

## The direction an action that starts now should take: the aim the player gives, or a target near it when `shape`
## allows assistance, else the last valid aim, else the facing. `shape` null means no assistance yet (H8.5 to H8.7 pass
## the light arc, the heavy attack's shape and the skill's shape). On keyboard and mouse and on a controller the
## result is the live aim exactly as before; only a touch player with no aim yet gets the fallback chain.
func _direction_for_activation(shape: AimShape2D) -> Vector2:
	var manual := _manual_aim.length_squared() > 0.0001 or Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down").length_squared() > 0.0
	var service := get_targeting_service()
	service.begin_action()
	var result := service.resolve(global_position, _intended_aim(), shape, context.last_aim_direction, context.facing_direction, manual)
	match result.source:
		TargetingService2D.Source.MANUAL, TargetingService2D.Source.TARGET, TargetingService2D.Source.INTENDED:
			_remember_aim(result.direction)
	_has_ground_point = shape != null and shape.is_placed()
	if _has_ground_point:
		_ground_point = _resolve_ground_point(shape, result)
	return result.direction

## Where a placed shape (the ground circle) goes for an activation that resolved to `result`: on the target the assist
## picked (held inside the cast range), else the pull the player gives along the resolved direction.
func _resolve_ground_point(shape: AimShape2D, result: TargetingService2D.AimResult) -> Vector2:
	if result.target != null and is_instance_valid(result.target):
		return shape.place_on(global_position, result.target.global_position)
	return shape.place(global_position, result.direction, _ground_pull(shape))

## How far out the player is putting a ground circle, 0 to 1 of its cast range, or -1 when no distance is given (the
## shape then uses its default). A drag's pull first; then a pushed stick (how far it is pushed); then the mouse (where
## the pointer is, but not on touch, where it is stale, nor over the HUD).
func _ground_pull(shape: AimShape2D) -> float:
	if _manual_pull >= 0.0:
		return _manual_pull
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length_squared() > 0.0:
		return clampf(stick.length(), 0.0, 1.0)
	if _aim_source == AimSource.MOUSE and not _on_touch() and not _pointer_over_hud() and shape.max_range > 0.0:
		return clampf((get_global_mouse_position() - global_position).length() / shape.max_range, 0.0, 1.0)
	return -1.0

## The aim the player is giving right now, or zero when there is none. On touch that is only a drag that is on right now
## (it presses the aim actions, like a stick) or a manual aim: a pointer that never moved is no aim, and neither is the
## direction an earlier drag left behind, so a plain tap after a drag is assisted again (H8.8).
func _intended_aim() -> Vector2:
	var live := _get_aim_direction()
	if _on_touch() and _manual_aim.length_squared() < 0.0001:
		if Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down").length_squared() <= 0.0:
			return Vector2.ZERO
	return live

func _remember_aim(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		context.last_aim_direction = direction.normalized()

func _on_touch() -> bool:
	if not is_inside_tree():
		return false
	var manager := get_tree().get_first_node_in_group(InputModeManager.GROUP) as InputModeManager
	return manager != null and manager.is_touch()

## Light attack, charge begin and charge release are activations: assistance is decided here, once per request. Every
## other call (the live charge follow, the argument of an empty attack request) is the plain aim.
func _get_attack_direction() -> Vector2:
	if _activation_open and (_pending_light != &"" or _pending_begin != &"" or _pending_release):
		return _direction_for_activation(_activation_shape())
	return _get_aim_direction()

## The shape the request pending this frame is assisted inside (H8.5 to H8.7), or null for none. A light tap uses the
## project-wide fan, a charge release the heavy attack's aim_shape. A charge begin is not assisted: its direction is only
## the starting pose, the live aim is followed while the button is held, and the direction is decided once, at release.
func _activation_shape() -> AimShape2D:
	if _pending_light != &"":
		return _light_assist_shape()
	if _pending_release:
		return _heavy_assist_shape()
	return null

## The heavy attack's aim_shape (H8.7), or null when the weapon has no heavy attack or its attack sets none.
func _heavy_assist_shape() -> AimShape2D:
	if not is_instance_valid(attack_component):
		return null
	var attack := attack_component.get_attack(get_heavy_attack_id())
	return attack.aim_shape if attack != null else null

## True when the skill in `slot` has an aim to give by hand (it has an aim_shape and is not a SELF skill or a buff). The
## touch controls ask this to know whether that button aims on a drag and casts when the finger lifts (H8.8, D16).
func slot_has_aim_shape(slot: int) -> bool:
	return _skill_assist_shape(slot) != null

## The aim_shape of the skill in `slot` (H8.7), or null: an empty slot, a SELF skill (its direction is ignored), a buff
## or any skill that sets none. The cast direction is decided here once and kept for the whole cast.
func _skill_assist_shape(slot: int) -> AimShape2D:
	if not is_instance_valid(skill_component):
		return null
	var skill := skill_component.get_skill_in_slot(slot)
	if skill == null or skill.targeting == SkillDefinition2D.Targeting.SELF:
		return null
	return skill.aim_shape

## What a light tap searches (H8.5, H9.3): the camera view, `light_assist_angle` wide round the aim. Range plays no part.
## Null (no assist, plain aim) when the angle is 0 or the attack is unknown.
func _light_assist_shape() -> AimShape2D:
	return _light_shape_for(_pending_light)

## The light-assist fan for attack `attack_id` (also used to draw the assist view for the attack a tap would start).
func _light_shape_for(attack_id: StringName) -> AimShape2D:
	if light_assist_angle <= 0.0 or not is_instance_valid(attack_component):
		return null
	if attack_component.get_attack(attack_id) == null:
		return null
	return get_targeting_service().make_view_shape(light_assist_angle, LIGHT_ASSIST_ANGLE_WEIGHT)

## The indicator scenes hold the draw order and the colours; the code only tells them what to show.
const ASSIST_INDICATOR_SCENE := preload("res://Characters/Components/Aim/AssistIndicator2D.tscn")
const AIM_INDICATOR_SCENE := preload("res://Characters/Components/Aim/AimIndicator2D.tscn")

var _assist_indicator: AssistIndicator2D

## The assist view node (a child named AssistIndicator2D), or null until it is first needed.
func get_assist_indicator() -> AssistIndicator2D:
	if not is_instance_valid(_assist_indicator):
		_assist_indicator = get_node_or_null("AssistIndicator2D") as AssistIndicator2D
	return _assist_indicator

## Tells the assist view what to draw: the range circle of the light attack a tap would start and the one target that
## tap would pick. The marker and swing use the same targeting service. Hidden when the player is dead or assist is off.
func _update_assist_indicator() -> void:
	var view := get_assist_indicator()
	var shape: AimShape2D = null
	var previewing := _preview_shape() != null
	if (show_attack_range or show_target_marker) and aim_indicators and is_alive():
		shape = _light_shape_for(get_light_attack_id())
	if shape == null:
		if view != null:
			view.clear()
		return
	if view == null:
		_assist_indicator = ASSIST_INDICATOR_SCENE.instantiate() as AssistIndicator2D
		add_child(_assist_indicator)
		view = _assist_indicator
	var manual := _manual_aim.length_squared() > 0.0001 or Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down").length_squared() > 0.0
	var axis := _intended_aim()
	if axis.length_squared() < 0.0001:
		axis = context.last_aim_direction
	if axis.length_squared() < 0.0001:
		axis = context.facing_direction
	if axis.length_squared() < 0.0001:
		axis = Vector2.RIGHT
	var service := get_targeting_service()
	var target: Node2D = null
	if show_target_marker and not manual and not previewing:
		target = service.pick_marked_target(global_position, axis, shape)
	var light := attack_component.get_attack(get_light_attack_id())
	var radius := light.attack_range if light != null and show_attack_range else 0.0
	view.show_state(radius, target)

## --- Aim indicator (H8.9) ---
var _indicator: AimIndicator2D
## The skill slot a finger is resting on (an aimed skill's touch button), or -1. Set by the touch controls.
var _preview_slot := -1

## The skill in `slot` is about to be cast by hand: show its aim shape until end_skill_preview(). A slot with no aim
## (a buff, a self skill, an empty slot) shows nothing (D16).
func begin_skill_preview(slot: int) -> void:
	_preview_slot = slot

func end_skill_preview() -> void:
	_preview_slot = -1

## The indicator node (a child named AimIndicator2D), or null while none has been needed yet.
func get_aim_indicator() -> AimIndicator2D:
	if not is_instance_valid(_indicator):
		_indicator = get_node_or_null("AimIndicator2D") as AimIndicator2D
	return _indicator

## The shape to draw now, or null: a finger on an aimed skill first, else the heavy attack while it charges.
func _preview_shape() -> AimShape2D:
	if not aim_indicators or not is_alive():
		return null
	if _preview_slot >= 0:
		return _skill_assist_shape(_preview_slot)
	if is_instance_valid(attack_component) and attack_component.is_charging():
		return _heavy_assist_shape()
	return null

## Works out what the action would do if it started this frame, without starting it and without touching the
## targeting service's kept target (pick_target is stateless), and tells the indicator. It follows the same rules as
## _direction_for_activation: a manual aim is used as given; otherwise the best target inside the shape, else the aim.
func _update_aim_indicator() -> void:
	var shape := _preview_shape()
	var indicator := get_aim_indicator()
	if shape == null:
		if indicator != null:
			indicator.clear()
		return
	if indicator == null:
		_indicator = AIM_INDICATOR_SCENE.instantiate() as AimIndicator2D
		add_child(_indicator)
		indicator = _indicator
	var manual := _manual_aim.length_squared() > 0.0001 or Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down").length_squared() > 0.0
	var axis := _intended_aim()
	if axis.length_squared() < 0.0001:
		axis = context.last_aim_direction
	if axis.length_squared() < 0.0001:
		axis = context.facing_direction
	if axis.length_squared() < 0.0001:
		axis = Vector2.RIGHT
	var service := get_targeting_service()
	var picked: Node2D = null
	var direction := axis.normalized()
	if not manual:
		picked = service.pick_target(global_position, axis, shape)
		if picked != null and (picked.global_position - global_position).length_squared() > 0.0001:
			direction = (picked.global_position - global_position).normalized()
	if shape.is_placed():
		# A ground circle: the same centre the cast will use, and the targets that circle covers.
		var point := shape.place_on(global_position, picked.global_position) if picked != null else shape.place(global_position, direction, _ground_pull(shape))
		var offset := point - global_position
		indicator.show_shape(shape, offset.normalized() if offset.length_squared() > 0.0001 else direction, service.candidates_in_circle(point, shape.area_radius()), picked, offset, shape.max_range)
		return
	# SkillDefinition2D.get_reach() can include a dash strike radius or an area offset; a heavy
	# attack uses AttackDefinition2D.get_reach(). Pass the active definition's reach rather than
	# reusing the light-attack radius or blindly assuming all skills have the same range.
	var action_range := shape.max_range
	if _preview_slot >= 0 and is_instance_valid(skill_component):
		var aimed_skill := skill_component.get_skill_in_slot(_preview_slot)
		if aimed_skill != null:
			action_range = aimed_skill.get_reach()
	elif is_instance_valid(attack_component) and attack_component.is_charging():
		var heavy := attack_component.get_attack(get_heavy_attack_id())
		if heavy != null:
			action_range = heavy.get_reach()
	indicator.show_shape(shape, direction, service.candidates_in_shape(global_position, axis, shape), picked, Vector2.ZERO, action_range)

func _physics_process(delta: float) -> void:
	_activation_open = false
	_update_approach(delta)
	super._physics_process(delta)
	_approach_target_override = null
	_update_aim_indicator()
	_update_assist_indicator()

## True while a target approach is moving the player. An arrived request is kept for one input-sampling pass.
func _is_approach_active() -> bool:
	return is_instance_valid(_approach) and _approach.is_active()

func _cancel_approach() -> void:
	if is_instance_valid(_approach):
		_approach.cancel()
	_approach = null

func _approach_reach() -> float:
	match _approach_kind:
		AutoApproach2D.Kind.LIGHT:
			if not is_instance_valid(attack_component):
				return 0.0
			_approach_action_id = get_light_attack_id() # weapon swaps during the walk use the new light attack
			var light := attack_component.get_attack(_approach_action_id)
			return light.get_reach() if light != null else 0.0
		AutoApproach2D.Kind.HEAVY:
			if not is_instance_valid(attack_component):
				return 0.0
			_approach_action_id = get_heavy_attack_id() # stop if the new weapon has no registered heavy attack
			var heavy := attack_component.get_attack(_approach_action_id)
			return heavy.get_reach() if heavy != null else 0.0
		AutoApproach2D.Kind.SKILL:
			if not is_instance_valid(skill_component):
				return 0.0
			var skill := skill_component.get_skill_in_slot(_approach_slot)
			return skill.get_reach() if skill != null else 0.0
	return 0.0

func _update_approach(delta: float) -> void:
	if not _is_approach_active():
		return
	var manual := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var released_heavy := _approach_kind == AutoApproach2D.Kind.HEAVY and not _heavy_held and not _light_held
	if not is_alive() or manual.length_squared() > 0.0001 or Input.is_action_just_pressed("dash") or is_stunned() or context.is_attacking or context.is_dashing or released_heavy or (is_instance_valid(skill_component) and skill_component.is_casting()):
		_cancel_approach()
		return
	var service := get_targeting_service()
	var result := _approach.update(delta, global_position, _approach_reach(), service)
	if result != AutoApproach2D.End.NONE and result != AutoApproach2D.End.ARRIVED:
		_approach = null # timeout, stall, invalid target, lost view or a weapon/skill with no reach

## Resolve an approach target using the action's aim shape when available. Without one, acquire a visible target
## from the camera view so that range can be closed rather than silently refusing the action.
func _begin_approach_if_needed(kind: int, action_id: StringName, slot: int, shape: AimShape2D, direction: Vector2) -> bool:
	if _is_approach_active() and _approach_kind == kind and _approach_action_id == action_id and _approach_slot == slot:
		return true # held charge input may request the same action every frame; do not reset its timers
	if _is_approach_active():
		_cancel_approach() # a new action request replaces the old approach
	# Let the existing combat gates handle combo inputs and requests during an active cast/swing.
	if context.is_attacking or context.is_dashing or (is_instance_valid(attack_component) and attack_component.is_charging()) or (is_instance_valid(skill_component) and skill_component.is_casting()):
		return false
	if _manual_aim.length_squared() > 0.0001 or Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down").length_squared() > 0.0:
		return false
	# Rule 4 (H9.4): an action with no reach (a self buff) never walks anywhere. is_in_reach() is false for reach 0, so
	# without this guard a buff cast with an enemy on screen would start an approach instead of casting.
	if _reach_for(kind, action_id, slot) <= 0.0:
		return false
	var service := get_targeting_service()
	var target := service.get_action_target()
	if not is_instance_valid(target):
		service.begin_action()
		var fallback := service.resolve(global_position, direction, service.make_view_shape(360.0), context.last_aim_direction, context.facing_direction, false)
		target = fallback.target
	if not is_instance_valid(target) or not service.is_eligible(target) or not service.is_in_view(target):
		return false
	var reach := _reach_for(kind, action_id, slot)
	if service.is_in_reach(global_position, target, reach):
		return false
	_cancel_approach()
	_approach_kind = kind
	_approach_action_id = action_id
	_approach_slot = slot
	_approach = AutoApproach2D.start(kind, target, action_id, slot, max_approach_time, approach_stall_time)
	return true

func _reach_for(kind: int, action_id: StringName, slot: int) -> float:
	if kind == AutoApproach2D.Kind.SKILL:
		var skill := skill_component.get_skill_in_slot(slot) if is_instance_valid(skill_component) else null
		return skill.get_reach() if skill != null else 0.0
	var attack := attack_component.get_attack(action_id) if is_instance_valid(attack_component) else null
	return attack.get_reach() if attack != null else 0.0

## Arriving starts the originally requested action once. The current range and target are checked again first; if a
## weapon swap changed the reach, the walk restarts with the new definition instead of attacking out of range.
func _consume_arrived_approach() -> void:
	if not is_instance_valid(_approach) or _approach.end_reason != AutoApproach2D.End.ARRIVED:
		return
	var target := _approach.target
	var service := get_targeting_service()
	var reach := _approach_reach()
	if not is_instance_valid(target) or not service.is_eligible(target) or not service.is_in_view(target) or reach <= 0.0:
		_approach = null
		return
	if not service.is_in_reach(global_position, target, reach):
		_approach = AutoApproach2D.start(_approach_kind, target, _approach_action_id, _approach_slot, max_approach_time, approach_stall_time)
		return
	var kind := _approach_kind
	var action_id := _approach_action_id
	var slot := _approach_slot
	_approach_target_override = target
	_approach = null
	match kind:
		AutoApproach2D.Kind.LIGHT:
			_pending_light = action_id
		AutoApproach2D.Kind.HEAVY:
			if _heavy_held or _light_held:
				_pending_begin = action_id
		AutoApproach2D.Kind.SKILL:
			if is_instance_valid(skill_component):
				var shape := _skill_assist_shape(slot)
				var direction := _direction_for_activation(shape)
				# If the target left the skill's shape while approaching, do not cast toward a stale direction.
				if service.get_action_target() == target:
					skill_component.try_use_slot(slot, direction)

## True while the mouse is over a HUD control that takes the pointer (a hotbar slot): such a click is the HUD's and
## must not also swing the weapon. Always false when nothing is hovered, which is the case in a headless run.
func _pointer_over_hud() -> bool:
	var node: Node = get_viewport().gui_get_hovered_control()
	while node != null:
		if node.is_in_group(SkillSlot.POINTER_BLOCK_GROUP):
			return true
		node = node.get_parent()
	return false

## The light attack a tap starts: the light_attack_id override, else the component's default attack.
func get_light_attack_id() -> StringName:
	return light_attack_id if light_attack_id != &"" else get_default_attack_id()

## The heavy attack a hold charges: the heavy_attack_id override, else the equipped weapon's heavy
## attack. Empty when there is neither (no weapon controller, or a weapon with no heavy attack).
func get_heavy_attack_id() -> StringName:
	if heavy_attack_id != &"":
		return heavy_attack_id
	if is_instance_valid(weapon_controller):
		var weapon := weapon_controller.get_equipped_weapon()
		if weapon != null and weapon.heavy_attack != null:
			return weapon.heavy_attack.id
	return &""

## Reads the attack buttons once per physics frame (before the attack hooks). A tap of attack_light
## is the light attack on release; a hold past charge_start_time begins a charge of the heavy attack,
## which the release (or the threshold, for a THRESHOLD heavy) lets go. Without a heavy attack,
## attack_light is the light attack on press.
func _sample_attack_input(delta: float) -> void:
	_activation_open = true
	_pending_light = &""
	_pending_begin = &""
	_pending_release = false
	if not is_alive():
		_light_held = false
		_heavy_held = false
		_press_charged = false
		_charge_requested = false
		return
	# Weapon switch (11.4): before the ids below are read, so this frame already uses the new weapon. The
	# controller refuses it during a swing or charge, so a press then is simply dropped.
	if Input.is_action_just_pressed("weapon_next") and is_instance_valid(weapon_controller):
		weapon_controller.equip_next()
	# Finish a previously requested approach before reading fresh input. The action is revalidated against the
	# current target, weapon/skill range and input state; a weapon swap during the walk cannot use stale reach.
	_consume_arrived_approach()
	# Active skill input (13.4): SkillComponent2D remains the authority for refusal, mana and cooldowns.
	if is_instance_valid(skill_component):
		for slot in range(WeaponDefinition2D.MAX_SKILL_SLOTS):
			var action_name := "skill_%d" % (slot + 1)
			if Input.is_action_just_pressed(action_name):
				var shape := _skill_assist_shape(slot)
				var direction := _direction_for_activation(shape)
				if not _begin_approach_if_needed(AutoApproach2D.Kind.SKILL, &"", slot, shape, direction):
					skill_component.try_use_slot(slot, direction)
	var heavy_id := get_heavy_attack_id()
	var has_heavy := is_instance_valid(attack_component) and heavy_id != &"" and attack_component.has_attack(heavy_id)
	var light_id := get_light_attack_id()
	if attack_component.is_charging():
		_press_charged = true
	# attack_heavy: charge the heavy attack directly; releasing it lets the charge go.
	if has_heavy and Input.is_action_just_pressed("attack_heavy"):
		_heavy_held = true
		_pending_begin = heavy_id
	if _heavy_held and Input.is_action_just_released("attack_heavy"):
		_heavy_held = false
		_pending_release = attack_component.is_charging()
		if _pending_begin != &"" and not _pending_release:
			_pending_begin = &"" # do not begin a heavy charge after its input was released during approach
	# attack_light: a tap or a charge, decided by how long it is held.
	if Input.is_action_just_pressed("attack_light") and not _pointer_over_hud():
		_press_charged = false
		_charge_requested = false
		_hold_elapsed = 0.0
		_light_held = has_heavy
		if not has_heavy:
			_pending_light = light_id
		elif Input.is_action_just_released("attack_light"):
			# Pressed and released inside one physics frame (a very quick touch, or a frame hitch): a tap. Without this
			# _light_held stays on with nobody holding the button, and the weapon charges until the next press.
			_light_held = false
			_pending_light = light_id
	elif _light_held and Input.is_action_just_released("attack_light"):
		_light_held = false
		if _pending_begin != &"":
			_pending_begin = &"" # the charge was only requested this frame: this press is a tap
		if _press_charged:
			_pending_release = attack_component.is_charging()
		else:
			_pending_light = light_id # a tap, or a charge that was refused (for example in a combo window)
		_charge_requested = false
	elif _light_held:
		_hold_elapsed += delta
		# Keep asking until the charge actually begins: a swing, a return clip or a cooldown can still
		# be running when the hold passes charge_start_time (9.R2). A release before it begins is a tap.
		if not _press_charged and _hold_elapsed >= charge_start_time:
			_charge_requested = true
			_pending_begin = heavy_id

	# A request that is out of reach becomes a walk request. It is not also sent to the combat component this frame.
	if _pending_begin != &"":
		var heavy_shape := _heavy_assist_shape()
		var heavy_direction := _direction_for_activation(heavy_shape)
		if _begin_approach_if_needed(AutoApproach2D.Kind.HEAVY, _pending_begin, -1, heavy_shape, heavy_direction):
			_pending_begin = &""
	if _pending_light != &"":
		var light_shape := _light_assist_shape()
		var light_direction := _direction_for_activation(light_shape)
		if _begin_approach_if_needed(AutoApproach2D.Kind.LIGHT, _pending_light, -1, light_shape, light_direction):
			_pending_light = &""

## The light attack to start this frame (empty for none).
func _get_attack_requested() -> StringName:
	return _pending_light

## The heavy attack to begin charging this frame (empty for none).
func _get_charge_begin_requested() -> StringName:
	return _pending_begin

## True when the charge in progress should be released this frame.
func _get_charge_release_requested() -> bool:
	return _pending_release

## The death clip and the flash reset are played by ReactionComponent2D (P1). This only stops the input.
func _on_death() -> void:
	_cancel_approach()
	# Physics processing is switched off below, so _sample_attack_input() never runs again to drop a button
	# that was held (or a request made) when the player died. Clear that state here (V2a, test U15).
	_light_held = false
	_heavy_held = false
	_press_charged = false
	_charge_requested = false
	_hold_elapsed = 0.0
	_pending_light = &""
	_pending_begin = &""
	_pending_release = false
	# The aim indicator is updated in _physics_process, which is off from here on (H8.9): hide it now.
	_preview_slot = -1
	_manual_pull = -1.0
	_has_ground_point = false
	if get_aim_indicator() != null:
		get_aim_indicator().clear()
	# Always stop input/movement, even if the character has no ReactionComponent2D or its death clip is missing.
	set_physics_process(false)
