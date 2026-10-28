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

@export_group("Charge")
## Clip played on the weapon AnimationPlayer while the attack is charging (begin_charge()). Empty =
## none. Make the clip loop in the animation if the charge can be held for a while.
@export var charge_animation: StringName = &""
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
	return found
