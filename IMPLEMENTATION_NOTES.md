# Character System Integration

This project now combines the layered player rig and custom sword-slash effect from the working project with the component-oriented character architecture and goblin enemy form from `2D_RPG_Game`.

## Controls

- **WASD / Arrow keys:** Move
- **Left mouse button:** Attack toward the mouse cursor
- **Space:** Dash in the movement direction, or the last horizontal facing direction when standing still

## Implemented systems

- `Characters/Core/Character2D.gd`: shared character coordinator and controller hooks
- `Characters/Core/CharacterContext2D.gd`: scene-adapted references and shared action data
- `Characters/Components/Movement/MovementComponent2D.gd`: movement velocity and `move_and_slide()` authority
- `Characters/Components/Dash/DashComponent2D.gd`: dash duration, direction, cooldown, and signals
- `Characters/Components/Combat/AttackComponent2D.gd`: attack gating, animation lifecycle, cooldown, and spawning
- `Characters/Components/Combat/AttackDefinition2D.gd`: one resource per attack (damage, cooldown, movement multiplier, weapon/recovery clip names, effect scene, hitbox, AI swing range)
- `Characters/Components/Combat/AttackSlash2D.gd`: existing slash effect animation, hitbox sweep, friendly-fire checks, and once-per-swing hits
- `Characters/StateMachine/`: idle, move, dash, and attack presentation states
- `Characters/Components/Health/HealthComponent2D.gd`: health, damage, healing, death and an optional invulnerability window
- `Characters/Components/Combat/HitData.gd`: the hit payload (`damage`, `source`, `direction`, `knockback`, `hit_stun`)
- `player.gd`: player controls, hit reaction, and death presentation
- `Characters/Controllers/EnemyAIController2D.gd` and `Characters/Enemies/BasicEnemy2D.gd`: goblin target acquisition, chase, melee attacks, return-home behavior, and hit/death presentation

## Integration and improvements

The player's existing `MainHand/HandAnim` animations are preserved, with an added `attack_event(&"spawn_effect")` event in the swing animation. The enemy keeps the reference goblin art/scene and routes its existing weapon animation event to the shared character base.

The working project's slash scene now lives at `Characters/Components/Combat/AttackSlash2D.tscn` (moved from `sword_slash.tscn`). Its configurable hitbox origin is now separated from the animated forward sweep, so changing hitbox offset/size in an attack resource is not overwritten by the animation. The hitbox checks both player and enemy physics layers while enforcing team groups and one hit per target per swing.

Enemy hit feedback uses a tween instead of animating `AnimatedSprite2D.frame`, avoiding conflicts with its idle/run sprite animation. Target searches are throttled instead of scanning the scene tree every physics frame. Move, dash and attack properties are edited directly on the component nodes (changes take effect immediately).

## Tuning

Open `Characters/Components/Combat/DefaultAttackDefinition.tres` for player attack settings and `Characters/Components/Combat/GoblinAttackDefinition.tres` for goblin settings.

An attack is one `AttackDefinition2D` resource. Everything below can be changed from the `.tres` alone:

- `weapon_animation` / `recovery_animation`: clip names on the character's weapon `AnimationPlayer` (defaults `slash` / `sword_return`). Leave `recovery_animation` empty to end the attack when the weapon clip ends. A definition that names a missing clip is rejected with an error naming the clip, both at start-up and when swapped at runtime.
- `effect_scene`: the scene spawned by each `spawn_effect` event in the clip. When empty, the `AttackComponent2D`'s `attack_slash_scene` is used (deprecated, kept as a fallback).
- `movement_multiplier`: scales walking for the whole swing (1 = unchanged, 0 = rooted). Dashing is not affected.
- `ai_attack_range`: distance at which an AI starts the swing. `0` falls back to the controller's own `attack_range`. The goblin uses 60 px: its slash was measured to connect out to about 72 px centre to centre, and the old fallback (30 px) was well inside that.

`cooldown_duration` is the wait **after a swing finishes** before the next one can start (it begins when `sword_return` ends). Time between swing starts is therefore the weapon animation cycle (about 0.95 s for both characters, plus roughly 40 ms of animation hand-off) plus this value. Both shipped definitions use 0.05 s, which keeps the pre-Phase-1 attack rate; raise it to slow an attack. Move speed is on the character's `MovementComponent2D` node and the dash values are on its `DashComponent2D` node. Detection radius, disengage radius, attack range, and return-home distance are exposed on `EnemyAIController2D`.

## Validation note

The archive has been checked for referenced resource files and important animation callback/node paths. A Godot executable was not available in the editing environment, so the game still needs to be opened and run in Godot 4.7 to validate import and runtime behavior.

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
- Shared death handling lives in `Character2D` (emit `died`, clear velocity, cancel attack and dash). Subclasses only override two presentation hooks: `_on_damaged(hit)` (hit reaction; check `is_alive()` for the killing hit) and `_on_death()` (player: `death` clip and stop processing; goblin: `queue_free()`).
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
- `MovementComponent2D.move_speed`; `DashComponent2D.dash_speed` / `dash_duration` / `dash_cooldown`; `AttackComponent2D.attack_definition` / `attack_slash_scene`; `HealthComponent2D.max_health` / `invulnerability_duration`.
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
- `UI/HUD/EnemyHealthBar.tscn` is an inherited scene of `HealthBar.tscn`: compact styles and margins, header and accent hidden, the on-bar label shown, `hide_until_damaged` and `hide_on_death` on. The first hit reveals the bar with `intro`, then `hit`. The intro and hit clips are shared, so the compact bar now starts its intro at scale 0.92 (was 0.86) and uses the player bar's hit squash.
- Deleted: `HealthBarStyle.gd`, `PlayerHealthBar.gd/.tscn`, `EnemyHealthBar2D.gd/.tscn` (and their `.uid` files).
- The Phase 4 `health` / `max_health` shims on `Character2D` are deleted: read `character.health_component.health` / `.max_health`. `Character2D.health_changed`, `damaged` and `died` stay. The `attack_definition` shim stays.
- Tests: section Q (detection area, profile override, enum, drag-to-resize) and R (bar bound by NodePath, value / counter / trail / colour / critical / heal / dead, enemy variant is inherited and reveals on the first hit). Older tests were updated to read `health_component.health`, and I18 / I19 use the enum and `FALLBACK_ATTACK_RANGE`. The new scripts' `.gd.uid` files are created by Godot the first time the project is opened.
