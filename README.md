# Project-2D

A top-down 2D action RPG in Godot 4.7. The player fights goblins (and a goblin archer) with a sword or bow. Basic and heavy attacks use weapon data; active skills, mana costs, cooldowns and the HUD are component-driven, with the HUD layout and animations authored as reusable scenes.

## Controls

- **WASD / Arrow keys:** move
- **Left mouse button, tap:** light attack toward the cursor. Tap again inside the swing's window to chain the combo.
- **Left mouse button, hold:** charge the heavy attack, release to swing
- **Space:** dash
- **Q:** switch weapon (sword, bow). Refused during a swing or charge. Bind other keys to `weapon_next` in the Input Map. Skill cooldowns continue while switching weapons.
- **1 / 2 / 3:** use the active skill in the matching slot for the equipped weapon. The slot labels are read from the Input Map and update if bindings change.
  - **Sword:** 1 Lunge, 2 Sword Spin, 3 Empowerment.
  - **Bow:** 1 Power Shot, 2 Multi-shot, 3 Empowerment.
- The HUD shows health, mana, skill icons, cooldown wipes and timers, hotkeys, and mana costs. Skills can be refused when their cost cannot be paid or the character is in a state that blocks skill use.
- `attack_heavy` is a separate heavy-attack action with no default key; bind one in Project Settings > Input Map if you want it.

## Running and testing

- Open the project in Godot 4.7 and run `Main.tscn`.
- After adding new scripts, run `godot --headless --import --path .` once so new classes are registered.
- Smoke test: `godot --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd`. It prints `SUMMARY passes=N failures=M`. The **last confirmed summary** is `SUMMARY passes=986 failures=0` (headless Godot 4.7 on Linux, Oct 25 2026, after Track P10, see `docs/trackP/P10-notes.md`; after P9 it was 973 / 0, after Track P8 942 / 0; the same run before P1 gave 920 / 0, so Phases 13.3.2 to 14.3 are confirmed, see `docs/trackP/P1-notes.md` and `docs/trackP/P8-notes.md`). It still needs to be repeated on your machine: run the import and smoke-test commands above and replace this line with your own output; do not use an expected count as a result.

## How it is organised

- `Characters/`: the shared `Character2D` base, components (movement, dash, health, attack, weapons), states, enemy AI and effects.
- `Characters/Components/Combat/`: `AttackDefinition2D` (one resource per attack), the attack component, `AttackEffect2D` (base class of effect scenes), the slash effect, the projectile effect and arrow (11.1, 11.2) and the shipped attack `.tres` files.
- `Characters/Components/Weapons/`: `WeaponDefinition2D` and `WeaponController2D`.
- `Weapons/` and `Data/Weapons/`: weapon scenes (sprite plus clips) and weapon definitions.
- `Characters/Components/Skills/` and `Characters/Components/Resources/`: skill definitions and `SkillComponent2D` / `ManaComponent2D`. Skill definitions live in `WeaponDefinition2D.active_skills`; projectile, area, dash and buff behaviors are implemented. Current equipped skills are Lunge, Sword Spin and Empowerment on the sword, and Power Shot, Multi-shot and Empowerment on the bow. Ground Slam remains available as a resource example but is not in the default sword loadout.
- `Characters/Components/Passives/`: `PassiveDefinition2D` and `PassiveController2D` (14.1). A weapon lists passives in `WeaponDefinition2D.passive_skills`; Rising Strikes (a counter passive), Vampiric Strikes, Serrated Edge and Executioner exist as data and are not on a weapon yet.
- `UI/HUD/`: scene-based health and mana bars, reusable skill slots and the three-slot skill bar, plus shared styles and placeholder skill icons. GDScript updates visuals; the scene tree defines layout and animations.
- `docs/`: the combat architecture guide, the roadmap for what is not built yet (`Combat-Roadmap-Step-by-Step-Plan.md`) and the Phase 9 step notes. `IMPLEMENTATION_NOTES.md` describes every system.

## Add an attack

1. In the weapon scene (`Weapons/Sword.tscn`, node `HandAnim`) add a clip with a Call Method key `attack_event("spawn_effect")` where the effect should appear. For combos, add `combo_window_open` and `combo_window_close` keys.
2. Make an effect scene: right-click `Characters/Components/Combat/AttackSlash2D.tscn` > New Inherited Scene. Keep the node names, or point the `Scene nodes` paths on the root at your own nodes. (Any scene whose root script extends `AttackEffect2D` works as an effect scene.) `AttackSlash2D.tscn` ships two clips, `slash` and `heavy_slash`; an attack picks one with `effect_animation`.
3. Create an `AttackDefinition2D` resource and fill in its id, damage, timing, clip names, effect scene (required) and hitbox.
4. Add it to the weapon: `basic_combo` (and link it from the previous attack with `next_attack` or `combo_sequence`) or `heavy_attack`.
5. Run the game and read the Output panel; every problem names the weapon, attack and clip. Then run the smoke test.

**A ranged attack** is the same recipe with a projectile as the effect: use `Characters/Components/Combat/Arrow.tscn` (or a scene whose root extends `ProjectileEffect2D`) as `effect_scene`, set `projectile_speed`, and use `pierce` / `max_targets` for the hit policy. `ArrowAttackDefinition.tres` and `Weapons/Bow.tscn` are the worked example.

**Optional: spawn the effect somewhere other than the character's origin.** Add a `Marker2D` named `AttackSpawnPoint` as a child of the character (or of the weapon pivot, so it follows the aim), or assign any marker to `Attack Spawn Point` on the character. Effects then appear at the marker.

## Add a weapon

1. Build a weapon scene: a `Node2D` root, the sprite, and an `AnimationPlayer` named `HandAnim` holding the clips and their `attack_event` keys. Mount it directly under `WeaponFacingPivot` (the keys use the path `../..`).
2. Create the weapon's attacks as above.
3. Create a `WeaponDefinition2D` resource: `weapon_id`, `display_name`, `weapon_scene`, `basic_combo`, `heavy_attack`.
4. Set it as **Starting Weapon** on the player's `WeaponController2D`, or call `equip()` from code. To make it switchable in play, add it to the controller's **Loadout** (the `weapon_next` key cycles through it). `validate_equip()` tells you why a weapon is refused.

See `docs/Combat Architecture Review & Expansion Guide (Updated Oct 2026).md` for the full step-by-step and the design behind it.
