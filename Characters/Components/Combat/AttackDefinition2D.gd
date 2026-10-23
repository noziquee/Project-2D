extends Resource
class_name AttackDefinition2D
## One complete attack: what it does, how it plays, and when an AI should use it.
## Every default reproduces the original single-slash behaviour, so a definition only
## needs the fields it wants to change.

## Identifier for logs, tests and (later) attack selection.
@export var id: StringName = &"light"

@export_group("Damage")
@export_range(0, 10000, 1) var damage: int = 1

@export_group("Timing")
## Seconds the attacker must wait AFTER a swing finishes before it can swing again.
## Total time between swing starts = weapon animation cycle + this value.
@export_range(0.0, 5.0, 0.01) var cooldown_duration: float = 0.4
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
## Physics layers the hitbox looks at (default 3 = player + enemy). Add the world layer
## (4) to let the attack hit breakables or switches.
@export_flags_2d_physics var hit_layers: int = 3
## Initial speed (px/s) the target is pushed along the hit direction; it decays with the
## target's knockback_friction. 0 = no knockback.
@export_range(0.0, 3000.0, 1.0) var knockback: float = 0.0
## Seconds the target cannot start an attack or dash after being hit. 0 = none.
@export_range(0.0, 3.0, 0.01) var hit_stun: float = 0.0

@export_group("Effect + Hitbox")
## Scene spawned by each of the weapon clip's attack_event(&"spawn_effect") events (root needs AttackSlash2D.gd).
## When empty, the AttackComponent2D's legacy attack_slash_scene is used.
@export var effect_scene: PackedScene
## Optional impact effect (root needs no script; it frees itself) spawned at the contact
## point of every hit this attack lands. Empty = no impact effect.
@export var hit_effect_scene: PackedScene
@export var hitbox_size: Vector2 = Vector2(16.0, 16.0)
## Offset of the hitbox's animated sweep origin from the attacking character.
@export var hitbox_offset: Vector2 = Vector2.ZERO

@export_group("AI")
## Centre-to-centre distance at which an AI starts this attack. 0 = use the AI
## controller's FALLBACK_ATTACK_RANGE (30 px). Keep it at or below the swing's real reach.
@export_range(0.0, 300.0, 1.0) var ai_attack_range: float = 0.0
