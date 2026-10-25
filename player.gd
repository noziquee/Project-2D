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
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

func _get_dash_requested() -> bool:
	return is_alive() and Input.is_action_just_pressed("dash")

func _get_aim_direction() -> Vector2:
	if not is_alive():
		return context.facing_direction
	var direction := get_global_mouse_position() - global_position
	return direction.normalized() if direction.length_squared() > 0.0001 else context.facing_direction

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
	# Active skill input (13.4): SkillComponent2D remains the authority for refusal, mana and cooldowns.
	if is_instance_valid(skill_component):
		for slot in range(WeaponDefinition2D.MAX_SKILL_SLOTS):
			var action_name := "skill_%d" % (slot + 1)
			if Input.is_action_just_pressed(action_name):
				skill_component.try_use_slot(slot, _get_aim_direction())
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
	# attack_light: a tap or a charge, decided by how long it is held.
	if Input.is_action_just_pressed("attack_light"):
		_press_charged = false
		_charge_requested = false
		_hold_elapsed = 0.0
		_light_held = has_heavy
		if not has_heavy:
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
	# Always stop input/movement, even if the character has no ReactionComponent2D or its death clip is missing.
	set_physics_process(false)
