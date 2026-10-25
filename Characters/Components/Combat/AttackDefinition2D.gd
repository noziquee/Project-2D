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
## When true, a hit that lands on the attacker while this attack is running cancels the
## swing (and starts the cooldown). Off by default so swings are never flinched out of.
@export var interruptible: bool = false

@export_group("Animation")
## Clip played on the character's weapon AnimationPlayer when the attack starts.
@export var weapon_animation: StringName = &"slash"
## Optional clip played after weapon_animation. Leave empty to end the attack as soon
## as weapon_animation finishes.
@export var recovery_animation: StringName = &"sword_return"
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
@export var effect_scene: PackedScene
## The clip of the effect scene's AnimationPlayer that this attack plays (9.8a). `slash` is the default;
## AttackSlash2D.tscn also ships `heavy_slash`. A scene without the clip is rejected with a message naming it.
@export var effect_animation: StringName = &"slash"
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

@export_group("AI")
## Centre-to-centre distance at which an AI starts this attack. 0 = use the AI
## controller's FALLBACK_ATTACK_RANGE (30 px). Keep it at or below the swing's real reach.
@export_range(0.0, 300.0, 1.0) var ai_attack_range: float = 0.0

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

@export_group("Charge")
## Clip played on the weapon AnimationPlayer while the attack is charging (begin_charge()). Empty =
## none. Make the clip loop in the animation if the charge can be held for a while.
@export var charge_animation: StringName = &""
## When the charge is released: INPUT_RELEASE (on release_charge()) or THRESHOLD (by itself).
@export var release_mode: ReleaseMode = ReleaseMode.INPUT_RELEASE
## Seconds of charge after which a THRESHOLD attack releases by itself. Must be above 0 for THRESHOLD.
@export_range(0.0, 10.0, 0.01) var charge_threshold: float = 0.0
