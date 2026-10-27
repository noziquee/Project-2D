# W6 - move GoblinArcher onto the Bow folder

Written October 25, 2026. **Not run in Godot in this environment.** W5d's source notes expect 1015 checks; this step adds WA1–WA10, so the expected combined result is **`SUMMARY passes=1025 failures=0`**, assuming the previous unrun Track W changes pass.

## What changed

- Added `Weapons/Bow/Bow_EnemyWeaponDefinition.tres`. It uses the same `Bow.tscn` visual/animation scene as the player but deliberately registers `Bow_ArrowEnemy.tres`, preserving the archer's enemy projectile settings and AI attack ID. The player-facing `Bow_WeaponDefinition.tres` remains unchanged.
- Simplified `Characters/Enemies/GoblinArcher.tscn` to inherit the base goblin, keep its archer AI profile and 12 health, and override the inherited `WeaponController2D` to equip the enemy Bow definition at `../AnimatedSprite2D`. The controller replaces the inherited GoblinSword mount with `Weapons/Bow/Bow.tscn` at initialization.
- Removed the archer-specific embedded bow animation tracks and direct bow texture override; bow visuals and attack clips now belong to the Bow scene.
- Added WA1–WA10 checks for controller setup, equipped definition, mounted scene, attack identity, AI choice, removed embedded animation data, and definition validation.

## Why there is an enemy Bow definition

The player's Bow definition uses player attacks (`Bow_ArrowShot` and `Bow_ArrowHeavy`). Equipping that exact definition on an enemy would replace the archer's enemy arrow with player attack data. The separate definition shares the Bow scene and Bow folder while retaining `Bow_ArrowEnemy` for the enemy. No combat scripts were changed.

## Verification

Static source inspection only; Godot runtime checks were not available here. Run the full smoke suite after W8 or when you next open the project in Godot.
