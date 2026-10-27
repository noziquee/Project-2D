extends Resource
class_name SkillDefinition2D
## One active skill (13.1): what it costs, how long it takes and waits, and what it does. Data only: cooldowns, casts and
## costs paid are runtime state in SkillComponent2D, never here, because this resource is shared by every character that
## wields the weapon.
##
## A skill reuses the attack data the game already has: a projectile or area skill points `attack` at an
## AttackDefinition2D (damage, effect scene, hit policy, crit, statuses), and a buff points `status_effect` at a
## StatusEffectDefinition2D. What each behavior needs is checked in validate() as the behaviors arrive (13.3):
## PROJECTILE needs an attack whose effect_scene is a ProjectileEffect2D (13.3.1); AREA needs one whose effect_scene is an
## AreaEffect2D (13.3.2); DASH needs a max_range (its distance) and a dash_speed, and an optional attack that must also be
## an AreaEffect2D (13.3.3); BUFF needs a status_effect that lasts (13.3.4).

## What a skill does when its cast ends. Each behavior is built in its own step (13.3). PROJECTILE (13.3.1) and AREA
## (13.3.2), DASH (13.3.3) and BUFF (13.3.4) are built. NONE is last so
## the saved numbers of the others never change: it does nothing at all when it executes (it still pays, cools down and
## reports), which suits a placeholder or a skill whose effect a listener of skill_executed provides.
enum Behavior { PROJECTILE, AREA, DASH, BUFF, NONE }
## What a skill costs. Mana is the only resource so far; add one only when a skill needs it (guide section 10).
enum CostResource { NONE, MANA }
## Where the skill is aimed. AIM_DIRECTION uses the attack direction; SELF needs no direction.
enum Targeting { AIM_DIRECTION, SELF }

## Identifier for logs, tests, input and HUD. Required, unique within a weapon.
@export var id: StringName = &""
@export var display_name: String = ""
@export var icon: Texture2D
## Slot on the weapon, 0-based (slot 0 is the first). A weapon has WeaponDefinition2D.MAX_SKILL_SLOTS of them.
@export_range(0, 7, 1) var slot: int = 0
@export var behavior: Behavior = Behavior.PROJECTILE

@export_group("Cost")
@export var cost_resource: CostResource = CostResource.NONE
## Amount of the resource paid when the cast starts. With cost_resource NONE this must be 0.
@export_range(0.0, 1000.0, 0.5) var cost_amount: float = 0.0

@export_group("Timing")
## Seconds before the skill can be used again, counted from the moment the cast starts.
@export_range(0.0, 600.0, 0.1) var cooldown: float = 1.0
## Seconds between starting the skill and its effect. 0 = instant.
@export_range(0.0, 10.0, 0.05) var cast_time: float = 0.0
## Reserved for channel skills. Hidden from the Inspector (H2.3) but still stored, so older resources load, and validate()
## still rejects anything but 0. Make it an @export_range again when channel skills exist.
@export_storage var channel_time: float = 0.0
## When true a hit that damages the caster during the cast cancels it (cost back, cooldown cleared).
@export var interruptible: bool = true

@export_group("Targeting")
@export var targeting: Targeting = Targeting.AIM_DIRECTION
## Furthest distance the skill reaches, in px. 0 = whatever the behavior's own scene gives. A DASH skill needs it: it is
## the distance of the dash (the dash lasts max_range / dash_speed seconds). An AREA skill does not use it
## (a validation problem if set): place the area with the attack's hitbox_offset. A projectile skill turns it
## into a flight time (max_range / the arrow's speed), so the projectile ends there if it has hit nothing that stops it.
@export_range(0.0, 2000.0, 1.0) var max_range: float = 0.0
## Radius of an area skill's circle, or of a dash skill's strike, in px. 0 = use the attack's hitbox_size (its x is the
## diameter). Only AREA and DASH use it.
@export_range(0.0, 500.0, 1.0) var area_radius: float = 0.0

@export_group("Dash")
## Speed of a DASH skill in px/s (13.3.3). The dash lasts max_range / dash_speed seconds. Only DASH uses it.
@export_range(0.0, 3000.0, 1.0) var dash_speed: float = 700.0

@export_group("Animation + effect")
## Optional clip on the weapon's AnimationPlayer (H2.2, decision D3: cast, then execute). SkillComponent2D plays it the moment the
## skill starts; the effect executes when cast_time is over, as before. If the cast is cancelled the clip stops and the weapon
## returns to its RESET pose. Empty = no clip: the weapon player is left alone. validate() reports a clip the weapon lacks.
@export var weapon_animation: StringName = &""
## The attack a projectile, area or dash skill performs (damage, effect scene, hit policy).
@export var attack: AttackDefinition2D

@export_group("Projectile Volley")
## Number of projectiles spawned by a projectile skill. 1 preserves the original single-projectile behavior.
@export_range(1, 12, 1) var projectile_count: int = 1
## Total fan angle across the volley. For 3 projectiles and 24 degrees, the shots are -12, 0 and +12 degrees.
@export_range(0.0, 180.0, 0.5) var spread_degrees: float = 0.0

## The status a buff skill puts on the caster.
@export var status_effect: StatusEffectDefinition2D

## Problems with this skill's own data as readable messages naming the skill. Empty when it is valid. With an
## AnimationPlayer the weapon_animation clip must exist on it. `slot_count` is how many slots the weapon has.
func validate(animation_player: AnimationPlayer = null, slot_count: int = 3) -> Array[String]:
	var problems: Array[String] = []
	var label := _label()
	if id == &"":
		problems.append("%s: id is empty." % label)
	if slot < 0 or slot >= slot_count:
		problems.append("%s: slot %d is outside the weapon's %d slots (0 to %d)." % [label, slot, slot_count, slot_count - 1])
	if cost_amount < 0.0:
		problems.append("%s: cost_amount is negative." % label)
	if cost_resource == CostResource.NONE and cost_amount > 0.0:
		problems.append("%s: cost_amount is %s but cost_resource is NONE; set a resource or make the amount 0." % [label, cost_amount])
	if cost_resource != CostResource.NONE and cost_amount <= 0.0:
		problems.append("%s: cost_resource is set but cost_amount is 0; set an amount or use NONE." % label)
	if cooldown < 0.0:
		problems.append("%s: cooldown is negative." % label)
	if cast_time < 0.0:
		problems.append("%s: cast_time is negative." % label)
	if channel_time != 0.0:
		problems.append("%s: channel_time is reserved for channel skills and must be 0 for now." % label)
	if max_range < 0.0 or area_radius < 0.0:
		problems.append("%s: max_range and area_radius cannot be negative." % label)
	if projectile_count < 1 or projectile_count > 12:
		problems.append("%s: projectile_count must be between 1 and 12." % label)
	if spread_degrees < 0.0 or spread_degrees > 180.0:
		problems.append("%s: spread_degrees must be between 0 and 180." % label)
	if behavior == Behavior.PROJECTILE and projectile_count == 1 and spread_degrees > 0.0:
		problems.append("%s: spread_degrees needs projectile_count above 1." % label)
	if behavior != Behavior.PROJECTILE and (projectile_count != 1 or not is_zero_approx(spread_degrees)):
		problems.append("%s: projectile_count and spread_degrees are only valid for PROJECTILE skills." % label)
	if animation_player != null and weapon_animation != &"" and not animation_player.has_animation(weapon_animation):
		problems.append("%s: needs clip '%s' (weapon_animation) on the weapon AnimationPlayer." % [label, weapon_animation])
	if behavior == Behavior.PROJECTILE:
		problems.append_array(_projectile_problems(label))
	elif behavior == Behavior.AREA:
		problems.append_array(_area_problems(label))
	elif behavior == Behavior.DASH:
		problems.append_array(_dash_problems(label))
	elif behavior == Behavior.BUFF:
		problems.append_array(_buff_problems(label))
	return problems

## Fields that are set but this skill's behavior never reads (H3.3), as readable messages naming the skill. A warning,
## never a problem: the skill still works. Empty when nothing is ignored.
func get_warnings() -> Array[String]:
	var found: Array[String] = []
	var label := _label()
	if behavior != Behavior.BUFF and status_effect != null:
		found.append("%s: status_effect is only used by BUFF skills; it is ignored here (put statuses on the attack's status_effects instead)." % label)
	if (behavior == Behavior.BUFF or behavior == Behavior.NONE) and attack != null:
		found.append("%s: attack is ignored by %s skills." % [label, Behavior.keys()[behavior]])
	if behavior != Behavior.AREA and behavior != Behavior.DASH and area_radius > 0.0:
		found.append("%s: area_radius is only used by AREA and DASH skills." % label)
	if (behavior == Behavior.BUFF or behavior == Behavior.NONE) and max_range > 0.0:
		found.append("%s: max_range is only used by PROJECTILE and DASH skills." % label)
	if behavior == Behavior.BUFF and status_effect != null and status_effect.tick_damage > 0:
		found.append("%s: the buff's status_effect ticks %d damage on the caster; a buff normally does not." % [label, status_effect.tick_damage])
	if attack != null and (behavior == Behavior.PROJECTILE or behavior == Behavior.AREA or behavior == Behavior.DASH):
		for message in attack.get_warnings():
			found.append("%s: %s" % [label, message])
	return found

## What an area skill needs (13.3.2): an attack whose effect scene has an AreaEffect2D root. Either targeting works: SELF
## centres the area on the caster, AIM_DIRECTION places it hitbox_offset in front of the caster along the aim.
func _area_problems(label: String) -> Array[String]:
	var found: Array[String] = []
	if max_range > 0.0:
		found.append("%s: max_range does nothing for an area skill; set area_radius and the attack's hitbox_offset instead." % label)
	if attack == null:
		found.append("%s: an area skill needs an attack (AttackDefinition2D)." % label)
		return found
	if attack.effect_scene == null:
		found.append("%s: the attack has no effect_scene; an area skill needs a scene whose root is an AreaEffect2D (such as AreaEffect2D.tscn)." % label)
	elif not attack.effect_scene.can_instantiate():
		found.append("%s: the attack's effect_scene cannot be instantiated." % label)
	else:
		var probe := attack.effect_scene.instantiate()
		if not probe is AreaEffect2D:
			found.append("%s: the attack's effect_scene root must be an AreaEffect2D (such as AreaEffect2D.tscn), not a melee or projectile effect." % label)
		probe.free()
	return found

## What a projectile skill needs (13.3.1): aimed, with an attack whose effect scene has a ProjectileEffect2D root.
func _projectile_problems(label: String) -> Array[String]:
	var found: Array[String] = []
	if targeting == Targeting.SELF:
		found.append("%s: a projectile skill needs targeting AIM_DIRECTION, not SELF." % label)
	if attack == null:
		found.append("%s: a projectile skill needs an attack (AttackDefinition2D)." % label)
		return found
	if attack.effect_scene == null:
		found.append("%s: the attack has no effect_scene; a projectile skill needs a scene whose root is a ProjectileEffect2D (such as Arrow.tscn)." % label)
	elif not attack.effect_scene.can_instantiate():
		found.append("%s: the attack's effect_scene cannot be instantiated." % label)
	else:
		var probe := attack.effect_scene.instantiate()
		if not probe is ProjectileEffect2D:
			found.append("%s: the attack's effect_scene root must be a ProjectileEffect2D (such as Arrow.tscn), not a melee effect." % label)
		probe.free()
	return found

## What a dash skill needs (13.3.3): a distance (max_range) and a speed. The attack is optional: with none the skill is a
## plain dash; with one, its effect_scene must be an AreaEffect2D, the strike that travels with the caster.
func _dash_problems(label: String) -> Array[String]:
	var found: Array[String] = []
	if max_range <= 0.0:
		found.append("%s: a dash skill needs max_range above 0 (the distance of the dash)." % label)
	if dash_speed <= 0.0:
		found.append("%s: a dash skill needs dash_speed above 0." % label)
	if attack == null:
		return found
	if attack.effect_scene == null:
		found.append("%s: the attack has no effect_scene; give it an AreaEffect2D scene for the dash strike, or remove the attack for a plain dash." % label)
	elif not attack.effect_scene.can_instantiate():
		found.append("%s: the attack's effect_scene cannot be instantiated." % label)
	else:
		var probe := attack.effect_scene.instantiate()
		if not probe is AreaEffect2D:
			found.append("%s: the dash strike's effect_scene root must be an AreaEffect2D (such as AreaEffect2D.tscn)." % label)
		probe.free()
	return found

## What a buff skill needs (13.3.4): a status that actually runs (duration above 0). The direction is ignored, so either
## targeting works; the status goes on the caster.
func _buff_problems(label: String) -> Array[String]:
	var found: Array[String] = []
	if status_effect == null:
		found.append("%s: a buff skill needs a status_effect (StatusEffectDefinition2D)." % label)
	elif status_effect.duration <= 0.0:
		found.append("%s: the status_effect has no duration; it would never start." % label)
	return found

func _label() -> String:
	if id != &"":
		return "skill '%s'" % id
	if display_name != "":
		return "skill '%s'" % display_name
	return "skill (unnamed)"
