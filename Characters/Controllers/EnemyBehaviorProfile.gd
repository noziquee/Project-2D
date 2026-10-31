extends Resource
class_name EnemyBehaviorProfile
## Tuning for EnemyAIController2D. One resource per enemy kind; the swing distance is not
## here, it comes from the attack definition (AttackDefinition2D.attack_range).

## Attacks the AI chooses between, with weights. Empty (default) = the AI always uses the
## character's default attack. Each entry must also be registered on the enemy's
## AttackComponent2D. The AI picks one entry at random by weight, starts walking until it is
## inside THAT attack's attack_range, swings, then picks again for the next swing.
@export var attack_choices: Array[AttackChoice2D] = []

## Radius of the detection circle. 0 (default) keeps the CircleShape2D exactly as drawn on
## the enemy's DetectionArea, so the radius can be changed by dragging it in the 2D view.
## A value above 0 overrides the drawn shape for this enemy kind.
@export_range(0.0, 2000.0, 1.0) var detection_radius: float = 0.0
## A target that is already being chased is only dropped beyond this distance.
@export_range(1.0, 2500.0, 1.0) var disengage_radius: float = 250.0
## How long a target may stay beyond disengage_radius before the enemy gives up.
@export_range(0.0, 5.0, 0.05) var lost_target_grace_duration: float = 0.75
## The enemy counts as home (and goes idle) once it is this close to its start position.
@export_range(0.0, 100.0, 1.0) var home_stop_distance: float = 5.0

## Seconds between the enemy getting in range with an attack ready and the swing starting. While it runs, a red lane
## (EnemyAttackTelegraph2D) shows where the attack will go. 0 attacks immediately, with no warning.
@export_range(0.0, 3.0, 0.05) var attack_windup_duration: float = 0.35
## Minimum seconds between the start of one swing and the request for the next (AI pacing). The attack's own cooldown still
## applies; this only adds a wait when the attack's cooldown is shorter. 0 (default) adds none. Use it to pace an enemy that
## shares a weapon's attack data with the player instead of making a second copy of the attack.
@export_range(0.0, 10.0, 0.05) var attack_interval: float = 0.0

## How many light attacks the enemy chains in one combo, counting the first swing. 1 (default) = never chains, the same as
## before. A higher value presses again whenever the combo window opens, the target is still inside the next attack's
## attack_range, and fewer than this many swings have been played. The links themselves come from the weapon's attacks
## (next_attack / combo_sequence); this only decides how far the enemy follows them.
@export_range(1, 8, 1) var preferred_combo_length: int = 1
## Seconds the enemy waits after a combo of two or more swings before it may start a new one: the opening the player can
## punish. It runs from the end of the last swing and counts together with attack_interval (the longer of the two wins).
## 0 (default) adds no wait.
@export_range(0.0, 5.0, 0.05) var combo_recovery_pause: float = 0.0

## Seconds the enemy waits for an opening before it starts a charged attack it has chosen. An opening is a target that is
## stunned, in the middle of its own swing, or moving so little that it cannot leave the attack's area during the charge.
## When none comes in time the enemy uses another attack of attack_choices (or its default attack) instead. 0 (default)
## starts the charged attack at once, as before.
@export_range(0.0, 5.0, 0.05) var heavy_wait_for_opening: float = 0.0

## How readily the enemy uses its equipped weapon's skills: the chance, rolled once each time a skill becomes usable, that it
## is used. 0 (default) = the enemy never uses skills. The enemy needs a SkillComponent2D child; the weapon supplies the
## skills. Dash skills are used to close a gap, projectile and area skills when the target is in their reach, and self buffs while the enemy has a target and the buff is not already running.
@export_range(0.0, 1.0, 0.05) var skill_usage_priority: float = 0.0

## A target closer than this makes the enemy back away (while it is free to move) before it attacks: the spacing of a ranged
## skirmisher or caster. 0 (default) = never retreats, the enemy closes to its attack range. Keep it below the attack's
## attack_range, or the enemy will retreat out of its own range.
@export_range(0.0, 600.0, 1.0) var minimum_combat_range: float = 0.0

## How many enemies may be winding up or swinging at the same target at once (DE2). An enemy that is in range but finds every
## slot taken waits where it stands and tries again, so a group takes turns instead of all hitting together. 0 (default) = no
## limit. The limit of the enemy asking is the one that counts, so give the whole group the same value.
@export_range(0, 8, 1) var max_simultaneous_attackers: int = 0
## Of those, how many may be charging or swinging a charged (heavy) attack at the same target at once. 0 (default) = no extra
## limit beyond max_simultaneous_attackers.
@export_range(0, 8, 1) var max_simultaneous_heavies: int = 0

## Seconds between the enemy choosing an attack skill and casting it, during which the skill's own aim shape (fan, circle or
## line) is drawn on the ground as a warning (DE3). The warning is dropped, and the skill not cast, if the skill stops being
## usable or the target is lost. A skill with no aim shape (buffs, a ground circle) is cast at once. 0 (default) = cast at
## once, as before.
@export_range(0.0, 3.0, 0.05) var skill_windup_duration: float = 0.0

## When an enemy is in range but has to wait for an attack slot (max_simultaneous_attackers), it walks around its target at
## about its attack range instead of standing still, so a group spreads out and the player cannot read who attacks next. It
## stops circling the moment it gets a slot. false (default) = it waits where it stands, as before. Only matters together with
## max_simultaneous_attackers.
@export var circle_while_waiting: bool = false

## The distance an enemy tries to hold from its target while it cannot attack yet (reloading, pacing interval, waiting). Inside the
## attack range it then walks sideways around the target (changing side every few seconds) and drifts toward this distance, instead
## of standing still or running away: the repositioning of a skirmisher or caster. Held at most 95% of the attack's range, so it
## stays able to shoot. minimum_combat_range still makes it back away when the target gets closer than that. 0 (default) = it stands
## still while it cannot attack, as before.
@export_range(0.0, 600.0, 1.0) var preferred_combat_range: float = 0.0

## What the enemy does about a target it is already chasing (Track E, Phase F). KEEP_CURRENT (default) = it stays on its target
## until it loses it, as before. NEAREST = it may change to another hostile that has come clearly closer, but only while it is
## free to move (no swing, cast, dash, charge, wind-up or stun) and holds no attack slot.
enum TargetSwitching { KEEP_CURRENT, NEAREST }
@export var target_switching: TargetSwitching = TargetSwitching.KEEP_CURRENT
## NEAREST only: the other hostile must be at least this many pixels closer than the current target to be worth a change.
@export_range(0.0, 500.0, 1.0) var target_switch_margin: float = 40.0
## NEAREST only: seconds an enemy keeps a target after choosing it, so it cannot flip back and forth.
@export_range(0.0, 10.0, 0.1) var target_switch_min_interval: float = 2.0

## Show the red lane during the wind-up of EVERY attack (a plain slash or lunge as well as a heavy). false (default) = only the
## heavy attack shows a lane, as before; a basic attack still waits out attack_windup_duration but shows nothing. Needs
## attack_windup_duration above 0 to be visible.
@export var telegraph_all_attacks: bool = false
