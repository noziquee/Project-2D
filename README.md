# Project-2D

A top-down 2D action RPG in Godot 4.7. The player fights goblins with a sword: light attacks that chain into a combo, and a charged heavy attack. Characters are built from components and attacks, and weapons are data.

## Controls

- **WASD / Arrow keys:** move
- **Left mouse button, tap:** light attack toward the cursor. Tap again inside the swing's window to chain the combo.
- **Left mouse button, hold:** charge the heavy attack, release to swing
- **Space:** dash
- `attack_heavy` is a separate heavy-attack action with no default key; bind one in Project Settings > Input Map if you want it.

## Running and testing

- Open the project in Godot 4.7 and run `Main.tscn`.
- After adding new scripts, run `godot --headless --import --path .` once so new classes are registered.
- Smoke test: `godot --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd`. It prints `SUMMARY passes=N failures=M`. Compare it with the expected total in the newest note in `docs/phase9/`.

## How it is organised

- `Characters/`: the shared `Character2D` base, components (movement, dash, health, attack, weapons), states, enemy AI and effects.
- `Characters/Components/Combat/`: `AttackDefinition2D` (one resource per attack), the attack component, the slash effect and the shipped attack `.tres` files.
- `Characters/Components/Weapons/`: `WeaponDefinition2D` and `WeaponController2D`.
- `Weapons/` and `Data/Weapons/`: weapon scenes (sprite plus clips) and weapon definitions.
- `UI/HUD/`: the health bar scenes and styles.
- `docs/`: the combat architecture guide, the roadmap for what is not built yet (`Combat-Roadmap-Step-by-Step-Plan.md`) and the Phase 9 step notes. `IMPLEMENTATION_NOTES.md` describes every system.

## Add an attack

1. In the weapon scene (`Weapons/Sword.tscn`, node `HandAnim`) add a clip with a Call Method key `attack_event("spawn_effect")` where the effect should appear. For combos, add `combo_window_open` and `combo_window_close` keys.
2. Make an effect scene: right-click `Characters/Components/Combat/AttackSlash2D.tscn` > New Inherited Scene. Keep the node names. `AttackSlash2D.tscn` ships two clips, `slash` and `heavy_slash`; an attack picks one with `effect_animation`.
3. Create an `AttackDefinition2D` resource and fill in its id, damage, timing, clip names, effect scene and hitbox.
4. Add it to the weapon: `basic_combo` (and link it from the previous attack with `next_attack` or `combo_sequence`) or `heavy_attack`.
5. Run the game and read the Output panel; every problem names the weapon, attack and clip. Then run the smoke test.

## Add a weapon

1. Build a weapon scene: a `Node2D` root, the sprite, and an `AnimationPlayer` named `HandAnim` holding the clips and their `attack_event` keys. Mount it directly under `WeaponFacingPivot` (the keys use the path `../..`).
2. Create the weapon's attacks as above.
3. Create a `WeaponDefinition2D` resource: `weapon_id`, `display_name`, `weapon_scene`, `basic_combo`, `heavy_attack`.
4. Set it as **Starting Weapon** on the player's `WeaponController2D`, or call `equip()` from code. `validate_equip()` tells you why a weapon is refused.

See `docs/Combat Architecture Review & Expansion Guide (Updated Oct 2026).md` for the full step-by-step and the design behind it.
