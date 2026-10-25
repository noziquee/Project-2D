# Character System Integration

This project now combines the layered player rig and custom sword-slash effect from the working project with the component-oriented character architecture and goblin enemy form from `2D_RPG_Game`.

## Controls

- **WASD / Arrow keys:** Move
- **Left mouse button (`attack_light`), tap:** Light attack toward the mouse cursor, sent when the button is released. Tapping again inside the light attack's combo window chains into the next light attack (`player_light`, then `player_light2`, then back to the first).
- **Left mouse button, hold (longer than 0.1 s):** Starts charging the equipped weapon's heavy attack; releasing the button swings it. The sword's heavy releases on input release. A heavy set to the Threshold release mode swings by itself while the button is still held.
- **`attack_heavy`:** Charges the heavy attack directly. It has **no default binding**: add a key or button in Project Settings > Input Map to use it.
- **Space:** Dash in the movement direction, or the last horizontal facing direction when standing still
- **Q:** switch between the sword and bow (weapon cooldowns persist)
- **1 / 2 / 3:** use the active skill in that slot. Sword: Lunge / Sword Spin / Empowerment. Bow: Power Shot / Multi-shot / Empowerment. The HUD reads the hotkey labels from Input Map events.

If the equipped weapon has no heavy attack, `attack_light` is the light attack on press and holding it does nothing special.

## Implemented systems

- `Characters/Core/Character2D.gd`: shared character coordinator and controller hooks
- `Characters/Core/CharacterContext2D.gd`: scene-adapted references and shared action data
- `Characters/Components/Movement/MovementComponent2D.gd`: movement velocity and `move_and_slide()` authority
- `Characters/Components/Dash/DashComponent2D.gd`: dash duration, direction, cooldown, and signals
- `Characters/Components/Combat/AttackComponent2D.gd`: attack gating, animation lifecycle, cooldown, and spawning
- `Characters/Components/Combat/AttackDefinition2D.gd`: one resource per attack (damage, cooldown, movement multiplier, weapon/recovery clip names, effect scene, hitbox, AI swing range)
- `Characters/Components/Combat/AttackEffect2D.gd`: base class of every effect scene (10.2): `configure(...)`, the `hit_contact` / `hit_confirmed` signals, the target filter, team check, hit-once tracking and the `HitData` call into `apply_hit()`. It also applies the attack's hit policy (10.4): `max_targets` (0 = no limit) and `pierce` (off = spent by the first target), with `is_spent()` and an `_on_spent()` hook for subclasses. `AttackComponent2D` only knows this class.
- Attack spawn point (10.5): `Character2D.attack_spawn_point` is an optional `Marker2D` (a child named `AttackSpawnPoint` is found by name, or assign any marker in the exported field). `CharacterContext2D.get_attack_origin()` returns its position, or the character's origin when there is none; `AttackComponent2D._spawn_effect()` places every effect there. The shipped scenes have no marker, so nothing moves.
- `Characters/Components/Combat/AttackSlash2D.gd`: the melee slash, a subclass of `AttackEffect2D`: effect animation, hitbox sweep and its hit window. It finds its animation player, hitbox, collision shape and hitbox origin through exported paths (`animation_player_path`, `hitbox_path`, `collision_shape_path`, `hitbox_origin_path`, 10.3) whose defaults match `AttackSlash2D.tscn`
- `Characters/Components/Combat/ProjectileEffect2D.gd` and `.tscn` (11.1): a projectile effect, a subclass of `AttackEffect2D`. It flies along the attack direction at `speed` for `lifetime` seconds, hits through the shared rules (team filter, hit-once, `max_targets` / `pierce`), stops on the world layer (always in its mask) and emits `world_hit(point)`. `AttackComponent2D` spawns it like any effect scene; the arrow and the bow that use it come in 11.2 and 11.3 (`docs/phase11/11.1-notes.md`).
- Arrow and bow (11.2 to 11.4): `AttackDefinition2D.projectile_speed` (0 = the effect scene's own speed; melee ignores it) is the new last argument of `configure(...)`, passed by `AttackComponent2D._spawn_effect()` and applied by `ProjectileEffect2D`. `Characters/Components/Combat/Arrow.tscn` is the arrow effect (a sprite and a 16 x 8 hit area); `ArrowAttackDefinition.tres` (`arrow_shot`: stops at the first target) and `ArrowHeavyAttackDefinition.tres` (`arrow_heavy`: charged, pierces up to 3) are its attacks. `Weapons/Bow.tscn` and `Data/Weapons/BowWeaponDefinition.tres` are the bow; no component needed a change for it. `WeaponController2D.loadout` and `equip_next()` cycle weapons, and `player.gd` calls it on the `weapon_next` action (Q). `Characters/Enemies/GoblinArcher.tscn` (11.5) is an inherited goblin with a bow, `GoblinArrowAttackDefinition.tres` and `GoblinArcherBehaviorProfile.tres`; the AI needed no change, because it already stops inside the chosen attack's `ai_attack_range`. One archer stands in `Main.tscn`. Details: `docs/phase11/`.
- Combat resolver (Phase 12): `Characters/Components/Combat/CombatResolver2D.gd` has one static function, `resolve(hit, health) -> HitData`, called by `HealthComponent2D.apply_hit()` for every hit that can land (ignored hits never reach it). It rolls the crit (`AttackDefinition2D.crit_chance` and `crit_multiplier`, a seedable generator), then subtracts the target's `HealthComponent2D.defense` (flat, never below 1), and returns the same hit or a changed copy. Statuses are data plus one optional node: `StatusEffectDefinition2D` (a `.tres`: duration, tick, stack rule) applied by an attack's `status_effects` array and run by a `StatusController2D` child of the character; a tick is a periodic hit that skips crit and defense. `BleedStatusDefinition.tres` is the example. Details: `docs/phase12/`.
- `Characters/StateMachine/`: idle, move, dash, and attack presentation states
- `Characters/Components/Health/HealthComponent2D.gd`: health, damage, healing, death and an optional invulnerability window
- `Characters/Components/Combat/HitData.gd`: the hit payload (`damage`, `source`, `direction`, `knockback`, `hit_stun`)
- `Characters/Components/Weapons/WeaponDefinition2D.gd`: one weapon as a resource (`weapon_id`, `display_name`, `weapon_scene`, `basic_combo`, `heavy_attack`) with validation
- `Characters/Components/Weapons/WeaponController2D.gd`: validates and equips a weapon (swaps the weapon scene, sets the character's attacks, rolls back on failure)
- `Weapons/Sword.tscn` and `Data/Weapons/SwordWeaponDefinition.tres`: the shipped sword (sprite, `HandAnim` with its clips) and its definition
- `Characters/Controllers/AttackChoice2D.gd`: one weighted attack choice for an enemy's `EnemyBehaviorProfile`
- `player.gd`: player controls (tap, hold and release of the attack buttons, taking attack ids from the equipped weapon) and stopping input on death
- `Characters/Components/Reaction/ReactionComponent2D.gd` (Track P1): hit flash, death clip, death effect and free-on-death as exported data on a child node of the character; `player.gd` and `BasicEnemy2D.gd` no longer play clips or spawn effects (`docs/trackP/P1-notes.md`)
- `Characters/Components/Facing/FacingComponent2D.gd` (Track P8): which way a character faces, mirroring of the body and weapon pivot, and the weapon-pivot aim, with fields for what to mirror and which way the art faces; `Character2D` calls it every physics frame and makes a default one when a scene has none (`docs/trackP/P8-notes.md`)
- Track P9 (`docs/trackP/P9-notes.md`): the charge aim follows the mouse (`AttackComponent2D.update_charge_direction()`), `FacingComponent2D` gets `facing_dead_zone`, `sticky_facing` and `settle_time` (the pivot and the weapon hand blend to rest when a swing ends or is cancelled, via the new `swing_ended` signal), and the bow's `RESET` pose matches its `idle` pose
- Track P10 (`docs/trackP/P10-notes.md`): `AttackDefinition2D.recovery_time` and `recovery_ease` give an attack a code-driven return (the weapon pivot and hand blend from the pose the swing ended in to the weapon's `idle` pose) instead of a return clip; the shipped player and bow attacks use it
- `Characters/Controllers/EnemyAIController2D.gd` and `Characters/Enemies/BasicEnemy2D.gd`: goblin target acquisition, chase, melee attacks and return-home behavior

## Integration and improvements

The player's existing `MainHand/HandAnim` animations are preserved, with an added `attack_event(&"spawn_effect")` event in the swing animation. The enemy keeps the reference goblin art/scene and routes its existing weapon animation event to the shared character base.

The working project's slash scene now lives at `Characters/Components/Combat/AttackSlash2D.tscn` (moved from `sword_slash.tscn`). Its configurable hitbox origin is now separated from the animated forward sweep, so changing hitbox offset/size in an attack resource is not overwritten by the animation. The hitbox checks both player and enemy physics layers while enforcing team groups and one hit per target per swing.

Enemy hit feedback uses a tween instead of animating `AnimatedSprite2D.frame`, avoiding conflicts with its idle/run sprite animation. Target searches are throttled instead of scanning the scene tree every physics frame. Move, dash and attack properties are edited directly on the component nodes (changes take effect immediately).

## Tuning

Open `Characters/Components/Combat/DefaultAttackDefinition.tres` for player attack settings and `Characters/Components/Combat/GoblinAttackDefinition.tres` for goblin settings.

An attack is one `AttackDefinition2D` resource. Everything below can be changed from the `.tres` alone:

- `weapon_animation` / `recovery_animation`: clip names on the character's weapon `AnimationPlayer` (defaults `slash` / `sword_return`). Leave `recovery_animation` empty to end the attack when the weapon clip ends. A definition that names a missing clip is rejected with an error naming the clip, both at start-up and when swapped at runtime.
- `effect_scene`: the scene spawned by each `spawn_effect` event in the clip. Required (10.1): an attack with no `effect_scene` is rejected with an error naming the attack. The old `attack_slash_scene` fallback no longer exists.
- `movement_multiplier`: scales walking for the whole swing (1 = unchanged, 0 = rooted). Dashing is not affected.
- `ai_attack_range`: distance at which an AI starts the swing. `0` falls back to the controller's own `attack_range`. The goblin uses 60 px: its slash was measured to connect out to about 72 px centre to centre, and the old fallback (30 px) was well inside that.

`cooldown_duration` is the wait **after a swing finishes** before the next one can start (it begins when `sword_return` ends). Time between swing starts is therefore the weapon animation cycle (about 0.95 s for both characters, plus roughly 40 ms of animation hand-off) plus this value. Both shipped definitions use 0.05 s, which keeps the pre-Phase-1 attack rate; raise it to slow an attack. Move speed is on the character's `MovementComponent2D` node and the dash values are on its `DashComponent2D` node. Detection radius, disengage radius, attack range, and return-home distance are exposed on `EnemyAIController2D`.

## Validation note

The editing environment has no Godot executable, so every step is written statically and then run by you. Phases 0 to 8 and Phase 9 steps 9.0 to 9.3 were run in Godot 4.7.2 (see the status table in `docs/phase9/PLAN.md`). Steps 9.4 and later (combos, heavy attack, charge, weapons, effect framework) were written and tested in code, and the smoke test now confirms them (607 / 0 at Phase V; 680 / 0 after 11.5, run headless in Godot 4.7.2). Several scenes and resources were edited as text, so also open the project in the editor once and read the Output panel.

**Phase V status (see `docs/phaseV/`):** the smoke test was run in Godot 4.7.2 on Oct 24 2026 and gave `SUMMARY passes=607 failures=0` after the V2b fixes (the first run gave 585 / 22). The import step finished with no errors. Phase 9.4 to 10.5 are therefore confirmed by the checks. The leftover Threshold values on `DefaultAttackDefinition.tres` were cleared in V4. Still open and only you can do them: playing `Main.tscn` in the editor (V1) and the play-test (V3).

Smoke test: `godot --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd`. Run `godot --headless --import --path .` first after adding new scripts, so new classes are registered.

## Review fixes (checked against `2D_RPG_Game`, verified in headless Godot 4.7.2)

- `player.tscn`: `weapon` and `HandAnim` pointed at a parent path that no longer existed, so Godot re-parented them to the player root. The swing animation moved the player body and the spawn event never reached the character. Both now sit under `WeaponFacingPivot/MainHand`.
- Player weapon clips renamed to `slash` / `sword_return` (same as the goblin and the reference), so `AttackComponent2D` no longer branches on animation names.
- `CharacterContext2D` resolves two explicit rig layouts and warns if the weapon player or an `attack_event` method track does not resolve; the recursive "search anywhere" fallbacks that hid the scene bug are gone.
- Idle/Move/Dash states re-assert their clip each frame, so idle/run resume after the `take_damage` -> `RESET` hit reaction.
- `player.gd`: `set_physics_process(false)` on death no longer depends on the AnimationPlayer existing.
- Static typing restored (preload-alias pattern from the reference) across Character2D, context, states, components and the AI controller.
- Ported `PlayerHealthBar` + HUD `CanvasLayer` into `Main.tscn`; named the physics layers (player / enemy / world); removed the hardcoded hitbox mask from `AttackSlash2D.gd`.

Smoke test: `godot --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd`

## Phase 3: generic animation events and multi-hit

- Weapon clips now fire `attack_event(<name>)` through a method track (path `../..`, one argument: the event name). `Character2D.attack_event()` forwards to `AttackComponent2D.handle_event()`. The old `spawn_slash()` alias was removed after both the player and goblin `slash` clips were migrated.
- Events: `spawn_effect` spawns one effect scene, so a flurry is just extra `spawn_effect` keys in a clip. `combo_window_open` / `combo_window_close` are reserved for Phase 9 and are accepted but ignored. Unknown names log a warning. Events arriving when no attack is running are ignored.
- `AttackComponent2D` tracks all live effects in `_active_effects` (`get_active_effect_count()`). A new spawn no longer frees the previous effect. Entries remove themselves when the effect leaves the tree, `cancel()` frees all of them, and a finished swing just stops tracking them (they finish on their own).
- `CharacterContext2D._validate_attack_event_tracks()` now checks every method key: the track must resolve to the character, the method must exist on it, and `attack_event` needs exactly one known event name. Anything else warns at start-up.
- Each effect keeps its own once-per-target hit list, so a flurry can hit the same target once per effect. That is intended.
- Smoke test section J covers migration, ignored events, two events giving two slashes, reserved events, freed-effect pruning, `cancel()` and finish. It has not been run in this environment (no Godot executable), so run it once in Godot 4.7.

## Phase 4: HealthComponent2D and HitData

- `HitData` (`RefCounted`) replaces the bare damage `int`. `knockback` and `hit_stun` are carried but not used until Phase 5.
- `HealthComponent2D` (a `Node`) owns `health`/`max_health` and has `apply_hit(hit) -> int` (damage actually dealt, 0 if ignored), `heal(amount) -> int`, `is_alive()`, `is_invulnerable()` and `grant_invulnerability(seconds)`. Signals: `health_changed(current, maximum)`, `damaged(hit)`, `healed(amount)`, `died`. For one hit they fire in the order health_changed, damaged (also for the killing hit), died, and the dead state is already set when they fire.
- `invulnerability_duration` (default 0, off) opens a window after any non-lethal hit; hits inside it are ignored entirely (they also do not count as a slash hit).
- `player.tscn` (max 5) and `BasicEnemy2D.tscn` (max 3) each have a `HealthComponent2D` child. `Character2D` finds it by name and creates a default one with a warning if it is missing.
- `Character2D` re-emits `health_changed`, `damaged` and `died`, exposes `apply_hit()`, `heal()` and read-through `health` / `max_health` (the HUD and tests still use these; remove them in Phase 8). `take_damage(amount)` is now a shim that wraps a `HitData`.
- Shared death handling lives in `Character2D` (emit `died`, clear velocity, cancel attack and dash). Hit and death presentation (flash, `death` clip, death effect, freeing) is a `ReactionComponent2D` child since Track P1. The `_on_damaged(hit)` and `_on_death()` hooks remain for behavior a component cannot express (the player stops its input in `_on_death()`).
- `AttackSlash2D` builds `HitData(damage, source, direction)` and calls `apply_hit` when the target has it, otherwise falls back to `take_damage`. `attack_hit` / `hit_confirmed` now report the damage actually dealt.
- The `max_health` export on the player and goblin scripts is gone: set it on the `HealthComponent2D` node instead.
- New tests are in smoke section K. As before, nothing here has been run in this environment, so open the project once in Godot 4.7 (this refreshes the global class cache for `HitData` and `HealthComponent2D`) and then run the smoke test.
- The new component script is referenced by path only in the two scenes; Godot will create its `.gd.uid` files the first time the project is opened.

## Phase 5: teams, hit layers, knockback, interrupts

- **Teams.** `Character2D.team` (`StringName`, set in the scenes: `player` and `enemy`). `AttackSlash2D` compares `source.team` with `target.team`: the same non-empty team is never hit, an empty team is neutral and can always be hit, and any other name is simply another faction. The old group-based friendly-fire checks are gone; the `player` / `enemy` / `damageable` groups remain only for target searches (`EnemyAIController2D.target_group`, the HUD, and the "damageable" opt-in on the hit target).
- **Hit layers.** `AttackDefinition2D.hit_layers` (`@export_flags_2d_physics`, default 3 = player + enemy) becomes the hitbox `Area2D` mask when the slash spawns. Add layer 3 (value 4) to let an attack hit world objects.
- **Knockback.** `AttackDefinition2D.knockback` (px/s) is carried on the `HitData`. `Character2D` stores `hit.direction * hit.knockback` in `context.knockback_velocity`, decays it by `knockback_friction` (px/s², default 1200) every physics frame, and `MovementComponent2D` adds it to normal and dash movement. Distance travelled is roughly knockback² / (2 x friction).
- **Hit stun.** `AttackDefinition2D.hit_stun` (seconds) blocks the target from starting an attack or a dash (`context.hit_stun_remaining`, `Character2D.is_stunned()`).
- **Interrupts.** `AttackDefinition2D.interruptible` belongs to the attack being performed: when the attacker is hit mid-swing and that attack is interruptible, `AttackComponent2D.interrupt()` cancels the swing (freeing its effects) and starts that attack's cooldown.
- A killing hit applies none of this; the death handler clears knockback and stun.
- **Shipped values (these change game feel, tune them in the `.tres` files):** player attack `knockback = 160`, `hit_stun = 0.15`, not interruptible; goblin attack `knockback = 100`, `hit_stun = 0.1`, `interruptible = true`. The defaults for new definitions are 0 / 0 / false, so a definition that does not mention them behaves as before.
- The AI still finds targets through its `target_group`; it does not use teams yet.
- Smoke test section L covers: same-team, third-team and neutral targets; `hit_layers` masks; knockback direction and decay; stun blocking attack and dash; interrupt and cooldown. Not run here (no Godot executable available).

## Phase 6: components and states are scene nodes

Done as two commits (`phase-6a-done`, `phase-6-done`).

**6a: components.** `player.tscn` and `BasicEnemy2D.tscn` now contain `MovementComponent2D`, `DashComponent2D`, `AttackComponent2D` and `HealthComponent2D` child nodes. Select one in the Scene dock to tune it per character:
- `MovementComponent2D.move_speed`; `DashComponent2D.dash_speed` / `dash_duration` / `dash_cooldown`; `AttackComponent2D.attack_definition` (required since 10.1; there is no default, every character scene sets its own); `HealthComponent2D.max_health` / `invulnerability_duration`.
- The goblin's old root-node overrides were re-entered on its components: `move_speed = 50`, `dash_speed = 150`, `attack_definition = GoblinAttackDefinition.tres`.
- `Character2D` no longer has `move_speed`, `dash_*` or `attack_slash_scene`. It keeps a read/write `attack_definition` shim that forwards to the attack component's `set_attack_definition()` (rejects a definition with a missing clip and keeps the old one); remove it whenever the tests stop using it.
- `Character2D` has typed `@export` references to the components and the state machine. They are left empty in the scenes and resolved by default child name (`MovementComponent2D`, ...). If a required node is missing it logs a `push_error` naming it and disables the character (`set_physics_process(false)`). A missing `HealthComponent2D` is still replaced by a default one with a warning.
- Components only receive the context in `initialize(context)`, never in their own `_ready()` (children are ready before the parent).

**6b: states.** `CharacterState` now extends `Node`. Each scene has a `CharacterStateMachine` node with `Idle`, `Move`, `Dash` and `Attack` children. The machine registers its `CharacterState` children by node name in `_ready()`, and `initialize(context)` (called by `Character2D`) sets them up and enters `initial_state` (export, default `Idle`). The `register_state(...)` block is gone from `Character2D`. To add a state, add a node with a `CharacterState` script under the machine and transition to it by node name.

**Scene files.** The new scripts are referenced by path only (no UIDs written); Godot adds the `.gd.uid` files and may rewrite the scene headers when you first open and save. Smoke test sections M (6a) and N (6b) check the scene files themselves (via `PackedScene.get_state()`), the per-character values, state transitions, and the missing-node errors. Not run in this environment.

## Phase 7: scene-driven feedback and VFX

Nothing here has been run in this environment (no Godot executable). Open the project once in Godot 4.7 (this registers the new `Effects2D` class and imports the new scenes), then run the smoke test (new sections O and P).

- **Enemy hit flash.** The `:frame` tracks are gone from the goblin's `take_damage` and `RESET` clips, so the flash no longer fights the idle/run `AnimatedSprite2D` animation. `BasicEnemy2D._on_damaged()` plays `AnimatedSprite2D/AnimationPlayer`'s `take_damage`; the tween (`_play_hit_feedback`) is deleted. The shake's position track now returns to (0, 0) by itself (the tween used to do that). The clip's very bright modulate (about 18.9) is the authored value; check it visually, it was a 2.2 tween before.
- **Player reactions.** New `ReactionAnim` `AnimationPlayer` on the player with `take_damage` and `RESET`; they only animate the flash material's `enabled` parameter. `PlayerAnim` no longer has a `take_damage` clip and its `RESET` lost the shader tracks. `player.gd` plays `ReactionAnim` and no longer needs the finished-callback that played `RESET`. `CharacterContext2D.play_locomotion_animation()` now only protects the `death` clip.
- **One shared flash material.** `Shader/hit_flash_material.tres` replaces the four `ShaderMaterial` sub-resources, so the flash clip has a single track (through `LayeredRig/Torso`) that flashes all four layers. If a second player instance ever exists they would share the flash state: use *Make Unique* on the material then.
- **Effects container.** `Main.tscn` has an `Effects` `Node2D` in group `effects_root`. `Effects2D` (`Characters/Effects/Effects2D.gd`) resolves it (fallback: current scene, then the caller's parent) and has `spawn(scene, from, world_position)`. Attack effects spawn there instead of `current_scene`.
- **Hit effect.** `Characters/Effects/HitEffect.tscn` (from `hit_effect_anim_spritesheet`) is a scene with no script: its own `AnimationPlayer` autoplays `play`, and a method track calls `queue_free` at the end. `AttackDefinition2D.hit_effect_scene` (new, empty = none) names it per attack; both shipped definitions use it. `AttackSlash2D` has a new `hit_contact(target, damage, point)` signal (point is halfway between the hitbox and the target); `AttackComponent2D` spawns the effect from it. `hit_confirmed` is unchanged.
- **Death effect.** `Characters/Effects/DeathEffect.tscn` (from `enemy_afterdead_explosion_anim_spritesheet`, built the same way). `BasicEnemy2D.death_effect_scene` (set in the scene) is spawned at the enemy's position when it dies, then the enemy frees itself. `explosion_anim_spritesheet` is still unused.
- **Static properties out of code.** Groups are on the scene roots (`player`/`damageable`, `enemy`/`damageable`); the `add_to_group` calls are gone. `z_index = 1` is set on the player's `MainHand` and on the goblin's `Weapon`; the per-frame line is gone.
- **Aimed swing (decision 2: yes).** `AttackDefinition2D.aim_weapon` (default false). While a swing with the flag runs, `Character2D._update_weapon_aim()` rotates `WeaponFacingPivot` so the authored right-facing arc is centred on the attack direction (the existing x mirror handles facing left); it returns to 0 when the swing ends, is cancelled or the character dies. `DefaultAttackDefinition.tres` (player) sets it to true; the goblin's does not, and the flag is ignored on rigs without a `WeaponFacingPivot`. Verify in-game: the arc is authored from -90 to +165 degrees, so check it looks right when aiming down and up, and that the sword sprite is not drawn behind the body at some angles.
- **Tests.** Section C now checks the flash runs on `ReactionAnim` while idle/run keeps playing. Slash lookups use `effect_children()` (children of `Effects`). Section O covers the scene structure, the enemy clip (no `:frame` tracks, shake returns to rest, sprite keeps animating), the shared material and flash, the Effects container, hit and death effects (spawned, positioned, self-freeing, none when the definition has no `hit_effect_scene`) and the source-level checks that groups and `z_index` are no longer set in code. Section P covers the aimed swing in eight directions, reset on finish/cancel/death, and `aim_weapon = false`.

## Phase 8: AI detection and HUD as scenes

Nothing here has been run in this environment (no Godot executable). Open the project once in Godot 4.7 (or run `godot --headless --import --path .`) so the new classes `EnemyBehaviorProfile` and `HealthBar` are registered and the new scenes/resources are imported, then run the smoke test (new sections Q and R).

**8a: AI**
- `BasicEnemy2D.tscn` has a `DetectionArea` (`Area2D`, layer 0, mask 1 = player, not monitorable) with a `CircleShape2D` (radius 180). `EnemyAIController2D` keeps the bodies that enter it (and are in `target_group`) as candidates through `body_entered` / `body_exited` and picks the nearest. The `get_nodes_in_group` scan and the refresh timer are gone.
- The disengage distance and the lost-target grace time are unchanged: a target already being chased is kept until it is farther than `disengage_radius` for `lost_target_grace_duration`; a new target can only come from inside the area.
- `EnemyBehaviorProfile` (`Characters/Controllers/EnemyBehaviorProfile.gd`, shipped as `GoblinBehaviorProfile.tres`) holds `detection_radius`, `disengage_radius`, `lost_target_grace_duration` and `home_stop_distance`. The controller's own exports for these are gone; it keeps `profile`, `detection_area` (NodePath, defaults to the child named `DetectionArea`) and `target_group`.
- `detection_radius` in the profile is **0 by default = use the circle exactly as drawn**, so the radius is changed by dragging the circle in the 2D view. A value above 0 overrides the circle for that profile (on a private copy of the shape, so other enemies are unaffected).
- Attack range comes from `AttackDefinition2D.ai_attack_range`. The controller's `attack_range` export is removed; a definition with `ai_attack_range = 0` falls back to the constant `EnemyAIController2D.FALLBACK_ATTACK_RANGE` (30 px).
- `behavior` is now the enum `EnemyAIController2D.Behavior { IDLE, CHASE, ATTACK, RETURN }` (`get_behavior_name()` for logging); `behavior_changed` carries enum values.
- Bodies that are already inside the area when the enemy spawns are reported by the physics server on the first physics frame, so the first target is chosen one frame after `_ready`.

**8b: HUD**
- `UI/HUD/HealthBar.tscn` + `HealthBar.gd` (`class_name HealthBar`) is the only bar. It is bound with the exported `health_source` NodePath to a `HealthComponent2D` (player: `../../Player/HealthComponent2D` in `Main.tscn`; goblin: `../HealthComponent2D`). Group lookup and `call_deferred` binding are gone. `bind(component)` can also be called from code.
- Feedback clips on the bar's `AnimationPlayer`: `intro`, `hit`, `heal` and a looping `critical` (pulses the fill's `self_modulate:a`). One AnimationPlayer plays one clip at a time, so `critical` is queued behind `hit` / `heal` and resumes afterwards; `hit` / `heal` never interrupt `intro` (they are queued behind it). The bar fill value, the damage trail and the number counter are still tweened in code.
- Look is data: `UI/HUD/Styles/*.tres` (panel, bar background, fill, damage fill, each with a `_compact` variant), `hud_font.tres` (`FontVariation`, Fredoka wght 700) and `health_gradient.tres` (constant `Gradient`: low / mid / high at 0 / 0.2501 / 0.5001, which keeps the old thresholds of 25 % and 50 %). `HealthBar.color_gradient`, `dead_color` and `critical_ratio` are exports.
- **Visual difference:** the fill style is now white and the whole `ProgressBar` is tinted with the gradient colour (`modulate`), so the fill no longer has a lighter 1 px border (it used to be `color.lightened(0.25)`). If you want it back, switch to three fill styles instead of one.
- `UI/HUD/EnemyHealthBar.tscn` is an inherited scene of `HealthBar.tscn`: a thin 28 x 5 bar showing only the fill bar and the damage trail bar (V6): the card panel is empty, the padding is 0, and the header, the on-bar number and the accent are hidden but still in the tree because `HealthBar.gd` finds them by path; `hide_until_damaged` and `hide_on_death` on. The first hit reveals the bar with `intro`, then `hit`. The intro and hit clips are shared, so the compact bar starts its intro at scale 0.92 and uses the player bar's hit squash (its hit colour flash has nothing to tint now that the card is empty).
- Deleted: `HealthBarStyle.gd`, `PlayerHealthBar.gd/.tscn`, `EnemyHealthBar2D.gd/.tscn` (and their `.uid` files).
- The Phase 4 `health` / `max_health` shims on `Character2D` are deleted: read `character.health_component.health` / `.max_health`. `Character2D.health_changed`, `damaged` and `died` stay. The `attack_definition` shim stays.
- Tests: section Q (detection area, profile override, enum, drag-to-resize) and R (bar bound by NodePath, value / counter / trail / colour / critical / heal / dead, enemy variant is inherited and reveals on the first hit). Older tests were updated to read `health_component.health`, and I18 / I19 use the enum and `FALLBACK_ATTACK_RANGE`. The new scripts' `.gd.uid` files are created by Godot the first time the project is opened.

## Phase 9: multiple attacks, combos, heavy attacks and weapons

Step notes for every sub-step are in `docs/phase9/` (`PLAN.md` holds the status table, the decisions and the expected smoke-test totals). Everything below follows section 8 and section 10.5 of `docs/Combat Architecture Review & Expansion Guide (Updated Oct 2026).md`: a weapon owns its attacks and its clips, and characters do not change per weapon.

**Attacks and input (9.0 to 9.3)**
- `AttackComponent2D.attacks` lists extra attacks next to the default `attack_definition`; every attack is started by id with `try_start_attack(id, direction)`. Helpers: `get_attack`, `has_attack`, `get_attack_ids`, `get_active_attack_id`, `set_attacks`. Bad entries (null, empty or duplicate id, missing clip) are skipped with a message naming the problem.
- `Character2D._get_attack_requested()` returns an attack id (empty = none). The input actions are `attack_light` (left mouse button) and `attack_heavy` (unbound).
- Enemies choose between weighted attacks: `EnemyBehaviorProfile.attack_choices` holds `AttackChoice2D` entries (attack and weight). The AI walks until it is inside the chosen attack's `ai_attack_range`. Every chosen attack must also be registered on the enemy's `AttackComponent2D`. The goblin picks between its slash (weight 3) and its lunge (weight 1).

**Combos (9.4, 9.6a, 9.6b, 9.R2)**
- A light attack chains when a request arrives inside its combo window, which a weapon clip opens and closes with `attack_event(&"combo_window_open")` and `attack_event(&"combo_window_close")` keys. Nothing chains by itself.
- What a chain plays: the attack's `combo_sequence` (a looping ordered list that starts with the attack itself), else its `next_attack`, else the same attack again. At the end of a chain a press inside the window restarts the combo's first attack. The shipped light combo is `player_light` -> `player_light2` -> `player_light` -> ...
- When the window closes with no press, the return clip of the attack performed last starts at once and cuts the rest of the weapon clip. During the return nothing can start, and a press is dropped (not buffered).
- Combo index, the combo's first attack and the charge clock are runtime state in `AttackComponent2D`, never stored in a resource. The combo resets when it ends, is interrupted, is cancelled or the character dies.

**Heavy attacks and charge (9.5a, 9.6c, 9.6d)**
- `AttackDefinition2D` has a **Charge** group: `charge_animation`, `release_mode` (`INPUT_RELEASE` or `THRESHOLD`) and `charge_threshold`. `begin_charge(id, direction)` and `release_charge(direction)` on the component start and release a charge; `is_charging()`, `get_charge_time()` and `get_charge_ratio()` (0 to 1, for a charge bar) read it. Charge changes timing only: damage and knockback stay fixed per attack.
- The player holds `attack_light` past `charge_start_time` (0.1 s) to begin a charge of the heavy attack. A press that is released earlier is a light attack. If the charge is refused (a swing or return is running), the release is a light attack, so a press held into a combo window still chains.
- The shipped attacks use the weapon's own clips: `player_light` (`sword_slash_1`, return `sword_slash_return_1`), `player_light2` (`sword_slash_2`, return `sword_slash_return_2`) and `player_heavy` (`sword_heavy_slash`, charge clip `sword_charge_heavy_slash`, return `sword_slash_return_1`).
- Each attack names which clip of its effect scene to play with `effect_animation` (default `slash`). `AttackSlash2D.tscn` also has a larger `heavy_slash` clip (hitbox sweep out to 80 px instead of 62), and `PlayerHeavyAttackDefinition.tres` uses it. A scene without the named clip is refused when the attack is registered or equipped, with a message naming the clip.
- The goblin's lunge (`goblin_lunge`, clip `lunge`) slows the goblin with `movement_multiplier` 0.3 but does not push it forward; a forward impulse needs a small addition to `MovementComponent2D`.

**Weapons (9.7)**
- `WeaponDefinition2D` is data only. `validate(animation_player)` reports every problem with the weapon named: empty id, no combo attack, empty or duplicate attack ids, links that leave the weapon, combo entries no chain reaches, and missing weapon, recovery or charge clips. `validate_scene()` checks the weapon's own scene.
- `Weapons/Sword.tscn` is the sword: root `MainHand` (a `Node2D`), the `weapon` sprite and a `HandAnim` `AnimationPlayer` with the eight sword clips. `player.tscn` holds one instance, `WeaponFacingPivot/MainHand`. The clips' `attack_event` method tracks use the path `../..`, so a weapon scene only works when it is mounted directly under `WeaponFacingPivot` (opened on its own, those tracks look invalid; that is expected).
- `CharacterContext2D.find_weapon_player(weapon_root)` finds a weapon's player (`HandAnim`, `WeaponAnimation`, else the first `AnimationPlayer` child); `bind_weapon(root)` points the context at a newly mounted weapon. `AttackComponent2D.rebind_weapon_player()` moves its `animation_finished` connection to the new player.
- `WeaponController2D` is an optional child of a character (the player has one, the goblin does not). `validate_equip(weapon)` and `can_equip(weapon)` change nothing. `equip(weapon)` is refused during a swing or charge, swaps the weapon scene when it differs from the mounted one (the new weapon takes the old one's name and position), sets the default attack and `attacks`, and puts the old weapon and attacks back if anything fails. It emits `weapon_equipped` or `equip_failed`. The cooldown keeps running through an equip. `starting_weapon` is equipped when the controller initializes; the player's is `SwordWeaponDefinition.tres`.
- `player.gd` takes its ids from the equipped weapon: `get_light_attack_id()` is the component's default attack (the weapon's first combo attack) and `get_heavy_attack_id()` is the weapon's `heavy_attack`. The `light_attack_id` and `heavy_attack_id` exports are empty by default and act as overrides.
- Weapons switch in play with `weapon_next` (Q, 11.4) through the weapon controller's `loadout`; there is still no pickup or inventory.

**Adding content now**
- A new attack: one clip in the weapon scene's `HandAnim` (with a `spawn_effect` key and, for combos, window keys), an effect scene (inherit `AttackSlash2D.tscn`), one `AttackDefinition2D` `.tres`, and an entry in the weapon's `basic_combo` or `heavy_attack`. Follow section 5 of the guide for the step-by-step.
- A new weapon: a weapon scene (a `Node2D` root, the sprite, an `AnimationPlayer` called `HandAnim`), its attack definitions, one `WeaponDefinition2D` `.tres`, then equip it. Run `validate()` first; the messages name the weapon, attack and clip.

**Not in Phase 9:** projectiles and a shared effect base class (the base class came in 10.2, projectiles in 11.1 to 11.3), `AttackSpawnPoint` (added in 10.5), active skills, passives and status effects (guide phases 3 to 5), a stagger state, and weapon switching in play (added in 11.4).

## Phase 13: active skills and HUD (13.0 to 13.4)

See `docs/phase13/`. `SkillDefinition2D` is data stored in a weapon's `active_skills` list (three slots). `SkillComponent2D` owns all runtime skill state: activation gating, mana cost, cast/interruption state, cooldown timers and skill signals. `ManaComponent2D` owns the mana pool and regeneration. Cooldowns are keyed by skill id and keep running when a weapon is switched; the HUD never creates its own cooldown timers.

### Skill behaviors and current weapon data

- **PROJECTILE:** `SkillComponent2D` spawns the skill's `AttackDefinition2D.effect_scene` (a `ProjectileEffect2D`, such as `Arrow.tscn`) at the attack origin. `max_range` becomes flight time; hits use the shared `AttackEffect2D` team, hit-once, status, crit and damage rules.
- **Projectile volleys (13.4.7):** `SkillDefinition2D.projectile_count` defaults to 1 and `spread_degrees` defaults to 0, preserving single-shot skills. Multi-shot creates three separate arrows evenly fanned across a 24-degree total angle; each arrow is non-piercing and can hit one target. Mana and cooldown are charged once for the skill activation.
- **AREA:** `AreaEffect2D` is configured from the skill's attack. `area_radius` sizes the circle. `AIM_DIRECTION` places it using `hitbox_offset`; `SELF` centres it on the character even when an `AttackSpawnPoint` is configured. Sword Spin is the equipped self-centred example; Ground Slam remains a valid definition but is not in the default weapon list.
- **DASH:** `DashComponent2D.start_skill_dash()` moves the caster by `max_range` at `dash_speed`; an optional area attack can follow the caster during the dash. Lunge is the sword's first skill.
- **BUFF:** a skill applies its `status_effect` to the caster through `StatusController2D`. Empowerment applies the 6-second damage multiplier status.
- **Current loadouts:** sword — Lunge (slot 1), Sword Spin (slot 2), Empowerment (slot 3); bow — Power Shot (slot 1), Multi-shot (slot 2), Empowerment (slot 3). The data resources use zero-based slot indices internally.

### Scene-based HUD (13.4)

- `UI/HUD/ManaBar.tscn` / `ManaBar.gd` binds through an exported `mana_source` path and uses a scene-defined `AnimationPlayer` for `intro`, `spend` and `restore`.
- `UI/HUD/SkillSlot.tscn` / `SkillSlot.gd` is a reusable scene for the icon, radial `TextureProgressBar` cooldown wipe, remaining-time label, hotkey and cost labels, and scene-defined ready / denied / started / unaffordable feedback animations.
- `UI/HUD/SkillBar.tscn` contains three `SkillSlot.tscn` instances. It binds to the player's `SkillComponent2D` and `ManaComponent2D` using exported node paths, rebuilds slot assignments on `skills_changed`, and derives labels from the `skill_1`–`skill_3` Input Map events. Rebinding an action updates the displayed label.
- `Main.tscn` hosts the health bar, mana bar and skill bar on the HUD `CanvasLayer`. The player scene contains its mana, skill and status components; `player.gd` routes keys 1–3 through `SkillComponent2D.try_use_slot()`.
- `SkillComponent2D` exposes `cooldown_started`, `cooldown_finished`, `skill_refused` and `skills_changed`, plus `get_cooldown_duration()` and `get_cast_progress()`. Those signals/data feed the HUD; the HUD does not own gameplay state.

### Verification status

The final Phase 13.4 smoke test is pending the user's run after the implementation is complete. The last confirmed summary before the later Phase 13.3.2–13.4 changes was `SUMMARY passes=776 failures=0` in Godot 4.7.2. This is historical, not a claim that the current source passes. The working environment used for these edits has no Godot executable, so only static file/reference checks were possible. See the current checklist in `docs/phase13/13.4.8-playtest-checklist.md` and progress notes in `docs/phase13/`.

## Phase 14: passives (14.0 to 14.3)

- `PassiveDefinition2D` (`Characters/Components/Passives/`) is data: id, trigger, `required_count`, `counter_window`, the status it grants and whether the next attack consumes it. `WeaponDefinition2D.passive_skills` lists a weapon's passives and validates them.
- `PassiveController2D` is the runtime owner of counters and rewards. It listens to the attack component, status controller and health component, grants rewards through `StatusController2D`, and `WeaponController2D.equip()` replaces its passives. The counter rules (misses, once per attack, no overlap, reward granted when the earning swing closes) are in `docs/phase14/14.0-notes.md`.
- The first passive, Rising Strikes, ships as data only and is not on any weapon. Status: written without running Godot; expected `SUMMARY passes=908 failures=0` (887 + 21).
- 14.3 adds event passives through `PassiveDefinition2D.effect`: heal on hit, a status on each target hit (bleed), and a damage bonus against low-health targets that `CombatResolver2D` multiplies in with the buff statuses. They act per target hit and are on no weapon yet. Expected after 14.3: `SUMMARY passes=920 failures=0` (908 + 12), not yet run.
