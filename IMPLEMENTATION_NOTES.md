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
- `Characters/Components/Combat/AttackDefinition2D.gd`: reusable damage and hitbox configuration
- `Characters/Components/Combat/AttackSlash2D.gd`: existing slash effect animation, hitbox sweep, friendly-fire checks, and once-per-swing hits
- `Characters/StateMachine/`: idle, move, dash, and attack presentation states
- `player.gd`: player controls, health, hit reaction, and death
- `Characters/Controllers/EnemyAIController2D.gd` and `Characters/Enemies/BasicEnemy2D.gd`: goblin target acquisition, chase, melee attacks, return-home behavior, health, and death

## Integration and improvements

The player's existing `MainHand/HandAnim` animations are preserved, with an added `spawn_slash()` event in the swing animation. The enemy keeps the reference goblin art/scene and routes its existing weapon animation event to the shared character base.

The working project's slash scene now lives at `Characters/Components/Combat/AttackSlash2D.tscn` (moved from `sword_slash.tscn`). Its configurable hitbox origin is now separated from the animated forward sweep, so changing hitbox offset/size in an attack resource is not overwritten by the animation. The hitbox checks both player and enemy physics layers while enforcing team groups and one hit per target per swing.

Enemy hit feedback uses a tween instead of animating `AnimatedSprite2D.frame`, avoiding conflicts with its idle/run sprite animation. Target searches are throttled instead of scanning the scene tree every physics frame. Dash and attack properties can be adjusted at runtime and updates are forwarded to their components.

## Tuning

Open `Characters/Components/Combat/DefaultAttackDefinition.tres` for player attack settings and `Characters/Components/Combat/GoblinAttackDefinition.tres` for goblin settings. Character move speed and dash values are exposed on the character node. Detection radius, disengage radius, attack range, and return-home distance are exposed on `EnemyAIController2D`.

## Validation note

The archive has been checked for referenced resource files and important animation callback/node paths. A Godot executable was not available in the editing environment, so the game still needs to be opened and run in Godot 4.7 to validate import and runtime behavior.

## Review fixes (checked against `2D_RPG_Game`, verified in headless Godot 4.7.2)

- `player.tscn`: `weapon` and `HandAnim` pointed at a parent path that no longer existed, so Godot re-parented them to the player root. The swing animation moved the player body and `spawn_slash()` never reached the character. Both now sit under `WeaponFacingPivot/MainHand`.
- Player weapon clips renamed to `slash` / `sword_return` (same as the goblin and the reference), so `AttackComponent2D` no longer branches on animation names.
- `CharacterContext2D` resolves two explicit rig layouts and warns if the weapon player or a `spawn_slash` method track does not resolve; the recursive "search anywhere" fallbacks that hid the scene bug are gone.
- Idle/Move/Dash states re-assert their clip each frame, so idle/run resume after the `take_damage` -> `RESET` hit reaction.
- `player.gd`: `set_physics_process(false)` on death no longer depends on the AnimationPlayer existing.
- Static typing restored (preload-alias pattern from the reference) across Character2D, context, states, components and the AI controller.
- Ported `PlayerHealthBar` + HUD `CanvasLayer` into `Main.tscn`; named the physics layers (player / enemy / world); removed the hardcoded hitbox mask from `AttackSlash2D.gd`.

Smoke test: `godot --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd`
