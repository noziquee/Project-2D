extends Resource
class_name AttackDefinition2D
## One complete attack: what it does, how it plays, and when an AI should use it.
## Every default reproduces the original single-slash behaviour, so a definition only
## needs the fields it wants to change.

## Identifier for logs, tests and (later) attack selection.
## How a charged attack is released (9.6c).
enum ReleaseMode {
	## Released when the input is let go (AttackComponent2D.release_charge()).
	INPUT_RELEASE,
	## Released by itself once charge_threshold seconds have passed, even if the input is still held.
	THRESHOLD,
}

@export var id: StringName = &"light"

@export_group("Damage")
@export_range(0, 10000, 1) var damage: int = 1

@export_group("Critical")
## Chance (0 to 1) that a hit of this attack is a critical hit (12.3). 0 = never.
@export_range(0.0, 1.0, 0.01) var crit_chance: float = 0.0
## What a critical hit multiplies the damage by, before the target's defense is subtracted. Rounded to a whole number.
@export_range(1.0, 10.0, 0.05) var crit_multiplier: float = 2.0

@export_group("Status")
## Statuses (bleed, burn...) this attack puts on every target it damages (12.4). They only take hold on a character
## that has a StatusController2D; others take the damage and ignore them.
@export var status_effects: Array[StatusEffectDefinition2D] = []

@export_group("Timing")
## Seconds the attacker must wait AFTER a swing finishes before it can swing again.
## Total time between swing starts = weapon animation cycle + this value.
@export_range(0.0, 5.0, 0.01) var cooldown_duration: float = 0.05
## Scales normal (non-dash) movement for the whole swing. 1 = unchanged, 0 = rooted.
@export_range(0.0, 2.0, 0.01) var movement_multiplier: float = 1.0
## P7: a forward step taken when the attack's effect spawns (the thrust of a lunge). Speed in pixels per second along
## the attack direction, fading to nothing over impulse_duration. 0 = none. It is added to the movement and does not
## replace it, and it stops if the swing is cancelled or interrupted.
@export_range(0.0, 2000.0, 1.0) var forward_impulse: float = 0.0
@export_range(0.01, 1.0, 0.01) var impulse_duration: float = 0.15
## When true, a hit that lands on the attacker while this attack is running cancels the
## swing (and starts the cooldown). Off by default so swings are never flinched out of.
@export var interruptible: bool = false

@export_group("Animation")
## Clip played on the character's weapon AnimationPlayer when the attack starts.
@export var weapon_animation: StringName = &"slash"
## Optional clip played BEFORE the swing, and before the charge when this attack is charged (a bow draw: the arrow
## is nocked and the bow comes up). When it finishes, AttackComponent2D plays weapon_animation (swing) or
## charge_animation (charge) by itself. A combo link replays it, so a chain reads draw > shot > draw > shot. A swing
## that starts from a charge release skips it (the charge already drew). Leave empty for no draw (every melee attack).
@export var draw_animation: StringName = &""
## Optional clip played after weapon_animation. Leave empty to end the attack as soon
## as weapon_animation finishes.
@export var recovery_animation: StringName = &"sword_return"
## P10: a code-driven return instead of a return clip. Used only when recovery_animation is empty. When the weapon
## clip ends (or the combo window closes), the attack stays in recovery for this many seconds, no attack can start
## meanwhile, and FacingComponent2D blends the weapon pivot and hand from the pose the swing ended in to the weapon's
## idle pose. 0 ends the attack at once (and a short settle blend runs, see FacingComponent2D.settle_time).
@export_range(0.0, 3.0, 0.01) var recovery_time: float = 0.0
## Optional easing of that return: a Curve from x = 0 (swing end pose) to x = 1 (idle pose), y = 0 to 1. Empty is smoothstep.
@export var recovery_ease: Curve
## When true the weapon pivot (WeaponFacingPivot) is rotated toward the attack direction
## for the whole swing, so the authored arc is centred on where the attack is aimed.
## Only characters with a WeaponFacingPivot rig (the player) can aim; the goblin's weapon
## is a child of its sprite and ignores this.
@export var aim_weapon: bool = false

@export_group("Hit")
## Physics layers the hitbox looks at, as a flag value. Layer 1 (player) = 1, layer 2
## (enemy) = 2, layer 3 (world) = 4, so the default 3 = player + enemy. Add 4 for the
## world layer (7 = all three) to let the attack hit breakables or switches.
@export_flags_2d_physics var hit_layers: int = 3
## Initial speed (px/s) the target is pushed along the hit direction; it decays with the
## target's knockback_friction. 0 = no knockback.
@export_range(0.0, 3000.0, 1.0) var knockback: float = 0.0
## Seconds the target cannot start an attack or dash after being hit. 0 = none.
@export_range(0.0, 3.0, 0.01) var hit_stun: float = 0.0
## The most different targets one effect can hit (10.4). 0 = no limit, which is what a melee slash does today.
## A target that is touched but takes no damage (for example during invulnerability) still counts.
@export_range(0, 20, 1) var max_targets: int = 0
## When false the effect is spent by its first target, as if max_targets were 1, and a projectile ends there.
## When true (default) it keeps going until max_targets is reached. Hit-once per target stays per effect.
@export var pierce: bool = true

@export_group("Effect + Hitbox")
## Scene spawned by each of the weapon clip's attack_event(&"spawn_effect") events (root needs a script that extends AttackEffect2D, such as AttackSlash2D.gd).
## Required (10.1): an attack with no effect_scene is rejected with an error naming the attack.
@export var effect_scene: PackedScene:
	set(value):
		effect_scene = value
		notify_property_list_changed()
## The clip of the effect scene's AnimationPlayer that this attack plays (9.8a). `slash` is the default;
## AttackSlash2D.tscn also ships `heavy_slash`. Hidden for area/projectile scenes (which do not play this clip),
## but kept in storage so older resources retain their values and the H3.3 warning can still report them.
@export var effect_animation: StringName = &"slash"

## H9.7 / D22: hide a setting that has no effect for these effect types without deleting serialized legacy values.
func _validate_property(property: Dictionary) -> void:
	if property.name == &"effect_animation" and _uses_non_animated_effect_scene():
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR

func _uses_non_animated_effect_scene() -> bool:
	if effect_scene == null or not effect_scene.can_instantiate():
		return false
	var probe := effect_scene.instantiate()
	var unsupported := probe is AreaEffect2D or probe is ProjectileEffect2D
	probe.free()
	return unsupported
## Optional impact effect (root needs no script; it frees itself) spawned at the contact
## point of every hit this attack lands. Empty = no impact effect.
@export var hit_effect_scene: PackedScene
@export var hitbox_size: Vector2 = Vector2(16.0, 16.0)
## Offset of the hitbox's animated sweep origin from the attacking character.
@export var hitbox_offset: Vector2 = Vector2.ZERO

@export_group("Projectile")
## Flight speed in px/s handed to a projectile effect (11.2). 0 = the effect scene's own default speed. Melee effects
## ignore it. At 60 fps keep speed / 60 below the hitbox length (hitbox_size.x), or the projectile can step over a thin target.
@export_range(0.0, 3000.0, 1.0) var projectile_speed: float = 0.0

@export_group("Range")
## How far this attack reaches, in pixels, measured from the character centre (H9.1, D18). One number for every user of
## the attack: the light-attack circle the player sees, how far a light tap looks for a target (H8.5), and the distance
## at which an AI starts the swing (0 = the AI controller's FALLBACK_ATTACK_RANGE, 30 px). The real hitbox and damage are
## not changed by it, so keep it at or below the swing's real reach. A heavy attack or skill aims with its own
## aim_shape and does not use it.
@export_range(0.0, 1000.0, 1.0) var attack_range: float = 0.0

## How far this attack reaches from the character centre, in pixels, whatever kind of attack it is (H9.1c): the number
## auto-approach closes to before swinging and the radius an aim indicator is clipped to. A light attack answers with its
## `attack_range`; a heavy attack, which leaves `attack_range` at 0, answers with the reach of its `aim_shape`. 0 = no
## reach known (no `attack_range` and no `aim_shape`), so nothing can be measured against it.
func get_reach() -> float:
	if attack_range > 0.0:
		return attack_range
	if aim_shape != null:
		return aim_shape.max_range
	return 0.0

## R4: the reach at charge ratio `ratio` (0 to 1, clamped): get_reach() x lerp(charge_reach_min, 1, ratio). Equal to
## get_reach() whenever charge_reach_min is 1. The aim preview and assist read it live while charging; the swing, the reach
## gate and a projectile's flight take the value at release (AttackComponent2D freezes it).
func get_reach_at_charge(ratio: float) -> float:
	return get_reach() * lerpf(charge_reach_min, 1.0, eased_charge_ratio(ratio))

## RD6 step 3: index in `charge_stages` of the stage reached at charge `ratio`: the entry with the highest at_ratio that is at
## or below the ratio (the order of the list does not matter). -1 when there are no stages or none is reached yet.
func get_charge_stage_index(ratio: float) -> int:
	var best := -1
	for i in charge_stages.size():
		var stage := charge_stages[i]
		if stage == null or stage.at_ratio > ratio + 0.0001:
			continue
		if best < 0 or stage.at_ratio >= charge_stages[best].at_ratio:
			best = i
	return best

## RD6 step 2: the charge ratio (0 to 1, clamped) after the optional `charge_reach_ease` curve. With no curve it is the ratio
## itself (linear, the default). The curve only changes how fast the reach grows between the same two ends: its output is
## clamped to 0 to 1, and a curve that starts at 0 and ends at 1 keeps the minimum and maximum reach exactly.
func eased_charge_ratio(ratio: float) -> float:
	var clamped := clampf(ratio, 0.0, 1.0)
	if charge_reach_ease == null:
		return clamped
	return clampf(charge_reach_ease.sample_baked(clamped), 0.0, 1.0)

## R4: the charge ratio after `seconds` of charge for this attack (0 when it has no charge_threshold).
func charge_ratio_at(seconds: float) -> float:
	if charge_threshold <= 0.0:
		return 0.0
	return clampf(seconds / charge_threshold, 0.0, 1.0)

@export_group("Aim assist")
## The shape a HEAVY attack is aimed with (H8.6): the fan, line or arrow the player aims inside, and the area target
## assist looks in. Empty = no aim shape. Light attacks ignore it (they use attack_range; the weapon warns if a
## basic_combo attack sets one). A shape guides aiming only; the real hitbox and damage never change. Reserved: the
## heavy attack's assist and indicator read it from H8.7 and H8.9; nothing does yet.
@export var aim_shape: AimShape2D

@export_group("Combo")
## Attack started by a request that arrives inside this attack's combo window (the
## combo_window_open / combo_window_close events of its weapon clip). The link must be an
## attack registered on the same AttackComponent2D. An unregistered or self link is ignored
## and reported by AttackComponent2D.validate_combo_links(). Empty = no combo from this attack.
@export var next_attack: AttackDefinition2D
## A looping combo, listed in order, starting with this attack itself: [A1, A2, A3] plays
## A1 -> A2 -> A3 -> A1 ... while the combo window keeps getting a press. Empty = no sequence:
## the attack then follows next_attack, or repeats itself. Runtime progress is kept by the
## AttackComponent2D, never in this resource.
@export var combo_sequence: Array[AttackDefinition2D] = []

@export_group("Input queue")
## Seconds a request for an attack made WHILE this attack is running (drawing, shooting or returning) is remembered.
## The remembered request plays when the combo window opens, when the weapon clip finishes, or as soon as the return
## is over, whichever comes first, so a click made a little early is not lost. 0 = no queue: a request during the
## attack is simply refused (the behaviour of every attack that does not set this).
@export_range(0.0, 2.0, 0.01) var input_queue_time: float = 0.0

@export_group("Aim follow")
## A1 (Track A): keep aiming while the shot is being drawn. When on, the direction of this attack is updated every
## frame from the press (or, for a heavy, from the release) until its spawn_effect event fires, so an arrow leaves toward
## where the target is then, not where it was. The controller decides what to follow (player.gd: the target picked at
## the press, or the live aim when the player aims by hand). Off by default: the direction is fixed when the attack starts.
@export var aim_follow: bool = false
## Fastest the direction may turn while following, in degrees per second. 0 = no limit (the direction snaps to the aim).
@export_range(0.0, 3600.0, 1.0) var aim_turn_speed: float = 0.0

@export_group("Charge")
## Clip played on the weapon AnimationPlayer while the attack is charging (begin_charge()). Empty =
## none. Make the clip loop in the animation if the charge can be held for a while.
@export var charge_animation: StringName = &""
## When on, the charge ratio starts rising the moment the charge begins, while draw_animation is still playing, instead of
## waiting for the draw to end. The bar fills at once and a full charge arrives that much sooner (raise charge_threshold by
## the draw length to keep the same total hold). A release during the draw still fires when the draw ends, at the ratio the
## button was let go at. Off (the default) keeps the charge starting after the draw. Does nothing without a draw_animation.
@export var charge_counts_during_draw: bool = false
## R4 (RD6): how much of its full reach a heavy attack has with no charge, 0 to 1. The reach grows linearly to the full
## reach (get_reach()) as the charge ratio goes from 0 to 1, so 1 (the default) means a fixed reach and existing data does
## not change. The ratio is seconds charged over `charge_threshold`; with no threshold the ratio stays 0 (warned).
@export_range(0.0, 1.0, 0.01) var charge_reach_min: float = 1.0
## RD6 step 2: how the reach grows between charge_reach_min and the full reach. X is the charge ratio (0 to 1), Y the share of
## the growth reached (0 to 1). Empty (the default) = linear. A curve below the diagonal at first is an ease-in (slow start);
## above it, an ease-out (fast start, slow near the maximum). Draw it from (0, 0) to (1, 1) to keep both ends of the reach.
@export var charge_reach_ease: Curve
## RD6 step 3: discrete charge levels (ChargeStage2D). Empty (the default) = no stages: the shot is the same at every charge.
## The stage is read from the same charge ratio as the reach, so it needs a charge_threshold above 0; it is frozen at release.
@export var charge_stages: Array[ChargeStage2D] = []
@export_group("Charge scaling")
## RD6 step 5: optional damage and area scaling with the charge. X is the charge ratio (0 to 1); Y is the multiplier itself
## (set the curve's min_value and max_value, for example 1 to 3). Empty (the default) = no scaling. Each one changes only its own
## property: the damage curve never changes reach or size, the area curve never changes damage or reach.
@export var charge_damage_curve: Curve
## Scales the radius of an area effect (AreaEffect2D; its hitbox_size) and does nothing for any other effect scene (warned).
@export var charge_area_curve: Curve

## Damage multiplier at charge `ratio` from charge_damage_curve (1 with no curve, never below 0).
func get_charge_damage_multiplier(ratio: float) -> float:
	if charge_damage_curve == null:
		return 1.0
	return maxf(charge_damage_curve.sample_baked(clampf(ratio, 0.0, 1.0)), 0.0)

## Area multiplier at charge `ratio` from charge_area_curve (1 with no curve, never below 0.1).
func get_charge_area_multiplier(ratio: float) -> float:
	if charge_area_curve == null:
		return 1.0
	return maxf(charge_area_curve.sample_baked(clampf(ratio, 0.0, 1.0)), 0.1)

@export_group("Timed release")
## RD6 step 4: an optional "perfect release" window on the charge ratio (0 to 1, the same ratio the reach and the stages use).
## A release before `perfect_window_start` is EARLY, inside the window PERFECT, after `perfect_window_end` LATE. The window is
## off while the end is not above the start (the default 0 / 0), and then nothing below applies. Needs a charge_threshold.
@export_range(0.0, 1.0, 0.01) var perfect_window_start: float = 0.0
@export_range(0.0, 1.0, 0.01) var perfect_window_end: float = 0.0
## Damage multiplier for each outcome (1 = unchanged), and a crit chance bonus for a perfect release (capped with the attack's at 1).
@export_range(0.1, 10.0, 0.05) var early_release_multiplier: float = 1.0
@export_range(0.1, 10.0, 0.05) var perfect_release_multiplier: float = 1.0
@export_range(0.1, 10.0, 0.05) var late_release_multiplier: float = 1.0
@export_range(0.0, 1.0, 0.01) var perfect_crit_bonus: float = 0.0

## Outcome of a release at a charge ratio (RD6 step 4).
enum ReleaseTiming { NONE, EARLY, PERFECT, LATE }

## True when the perfect-release window is configured.
func has_release_window() -> bool:
	return perfect_window_end > perfect_window_start

## The outcome of releasing at charge `ratio`: NONE when no window is configured, else EARLY, PERFECT or LATE.
func get_release_timing(ratio: float) -> ReleaseTiming:
	if not has_release_window():
		return ReleaseTiming.NONE
	if ratio < perfect_window_start - 0.0001:
		return ReleaseTiming.EARLY
	if ratio > perfect_window_end + 0.0001:
		return ReleaseTiming.LATE
	return ReleaseTiming.PERFECT

## Damage multiplier of a timing outcome.
func release_multiplier_for(timing: ReleaseTiming) -> float:
	match timing:
		ReleaseTiming.EARLY:
			return early_release_multiplier
		ReleaseTiming.PERFECT:
			return perfect_release_multiplier
		ReleaseTiming.LATE:
			return late_release_multiplier
	return 1.0

@export_group("Charge")
## When the charge is released: INPUT_RELEASE (on release_charge()) or THRESHOLD (by itself).
@export var release_mode: ReleaseMode = ReleaseMode.INPUT_RELEASE
## Seconds of charge after which a THRESHOLD attack releases by itself. Must be above 0 for THRESHOLD.
@export_range(0.0, 10.0, 0.01) var charge_threshold: float = 0.0

## The effect_animation every new attack starts with. A different, non-empty value on an area or projectile attack is a
## deliberate choice that will never play, so it is worth a warning; the default is not.
const DEFAULT_EFFECT_ANIMATION := &"slash"

## Things that are set but will have no effect (H3.3), as readable messages naming the attack. Unlike a problem, a
## warning never stops a weapon from being equipped. Empty when nothing is ignored.
func get_warnings() -> Array[String]:
	var found: Array[String] = []
	var label := "attack '%s'" % id
	if charge_animation == &"" and (charge_threshold > 0.0 or release_mode != ReleaseMode.INPUT_RELEASE):
		found.append("%s: charge_threshold or release_mode is set but charge_animation is empty; nothing will show while it charges." % label)
	if effect_animation != &"" and effect_animation != DEFAULT_EFFECT_ANIMATION and effect_scene != null and effect_scene.can_instantiate():
		var probe := effect_scene.instantiate()
		if probe is AreaEffect2D or probe is ProjectileEffect2D:
			found.append("%s: effect_animation '%s' is ignored: area and projectile effects have no effect AnimationPlayer." % [label, effect_animation])
		probe.free()
	found.append_array(_aim_shape_reach_warnings(label))
	found.append_array(_reach_cap_warnings(label))
	if (charge_damage_curve != null or charge_area_curve != null) and charge_threshold <= 0.0:
		found.append("%s: a charge damage or area curve is set but charge_threshold is 0, so the charge ratio never rises and only the curve's value at 0 is used." % label)
	if charge_area_curve != null and effect_scene != null and effect_scene.can_instantiate():
		var area_probe := effect_scene.instantiate()
		if not area_probe is AreaEffect2D:
			found.append("%s: charge_area_curve is set but the effect is not an area effect, so it has no radius to scale." % label)
		area_probe.free()
	if (perfect_window_start > 0.0 or perfect_window_end > 0.0) and not has_release_window():
		found.append("%s: perfect_window_end must be above perfect_window_start; the timed-release window is off." % label)
	if has_release_window() and charge_threshold <= 0.0:
		found.append("%s: a perfect-release window is set but charge_threshold is 0, so the charge ratio never rises and every release is EARLY." % label)
	if not charge_stages.is_empty() and charge_threshold <= 0.0:
		found.append("%s: charge_stages are set but charge_threshold is 0, so the charge ratio never rises and only a stage at ratio 0 can be reached." % label)
	if charge_reach_min < 1.0 and charge_threshold <= 0.0:
		found.append("%s: charge_reach_min is %s but charge_threshold is 0, so the charge ratio never rises and the reach stays at %s of its full value. Set charge_threshold to the seconds a full charge takes." % [label, charge_reach_min, charge_reach_min])
	return found

## How far, in pixels, an aim shape's own `max_range` may differ from `attack_range` before validation warns (R2).
const SHAPE_REACH_TOLERANCE_PX := 1.0

## R2: an attack that sets both `attack_range` and a shape that follows the action's reach. `get_reach()` answers with
## `attack_range`, so the aim indicator, the assist and auto-approach use that number and ignore the shape's own length.
## A heavy attack that leaves `attack_range` at 0 takes its reach from the shape and never warns here.
func _aim_shape_reach_warnings(label: String) -> Array[String]:
	var found: Array[String] = []
	if aim_shape == null or attack_range <= 0.0 or not aim_shape.follows_action_reach():
		return found
	if absf(aim_shape.max_range - attack_range) > SHAPE_REACH_TOLERANCE_PX:
		found.append("%s: aim_shape max_range is %s px but attack_range is %s px; the shape's own value is ignored in game (it is drawn and aimed at %s px). Set the shape's max_range to %s, or leave attack_range at 0 so the shape sets the reach." % [label, aim_shape.max_range, attack_range, attack_range, attack_range])
	return found

## R3: reach problems the attack's own numbers show. (RD3) A projectile attack with no reach has nothing to cap its flight
## except the scene's lifetime. (RD1) A melee attack whose clip moves the hitbox by itself (so the reach driver is off) and
## whose static hit box ends short of `attack_range` cannot hit all the way out. Warnings only.
func _reach_cap_warnings(label: String) -> Array[String]:
	var found: Array[String] = []
	if effect_scene == null or not effect_scene.can_instantiate():
		return found
	var probe := effect_scene.instantiate()
	if probe is ProjectileEffect2D and get_reach() <= 0.0:
		found.append("%s: a projectile attack with no reach (attack_range 0 and no aim shape); nothing caps its flight but the effect scene's own lifetime. Set attack_range to the distance it should travel." % label)
	elif probe is AttackSlash2D and attack_range > 0.0:
		var static_edge := hitbox_offset.x + hitbox_size.x * 0.5
		if static_edge < attack_range - SHAPE_REACH_TOLERANCE_PX and AttackSlash2D.scene_clip_moves_positions(effect_scene, effect_animation):
			found.append("%s: its hit box ends %s px from the attack origin but attack_range is %s px, and the effect clip moves the hit box itself, so the swing cannot hit out to its reach. Lengthen hitbox_size or the offset, or remove the clip's position tracks so the attack's range drives the swing." % [label, static_edge, attack_range])
	probe.free()
	return found
