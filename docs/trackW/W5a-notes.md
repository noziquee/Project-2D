# W5a - `weapon_mount` on `WeaponController2D`

Written October 25, 2026 **without running Godot**. First increment of W5 (the goblin sword). Only the controller changes; the goblin scene, the `GoblinSword` files and the goblin's attacks are untouched, so the game plays as before. Six new checks: expected **`SUMMARY passes=994 failures=0`** (988 from W4 + 6). You will run one smoke test after Track W is finished; if the count is off then, find the first step whose notes do not match.

## What changed

`Characters/Components/Weapons/WeaponController2D.gd`:

- New export `weapon_mount: NodePath`, default empty. Empty means the character's `WeaponFacingPivot`, exactly today's behavior, so `player.tscn` needs no change.
- The path is resolved **relative to the controller** (the usual rule for exported node paths in the editor). For a goblin whose weapon hangs on its sprite and whose controller is a child of the goblin, the value is `../AnimatedSprite2D`.
- New `get_mount_root() -> Node2D`: the node at `weapon_mount`, or `WeaponFacingPivot` when the path is empty, or null when there is none.
- `validate_equip()`, `_mount_problems()`, `_swap_mount()` and `_restore_mount()` use `get_mount_root()` instead of `context.weapon_facing_root`. The refusal message for a character with no `WeaponFacingPivot` is unchanged (check `KK6` still matches it). A path that does not resolve gets its own message that names `weapon_mount`.

Difference from the W0 plan: the plan also gave `CharacterContext2D` a `weapon_mount_root`. It is not needed, because only the controller mounts weapons, and `context.weapon_facing_root` must stay the aim pivot that `FacingComponent2D` rotates (the goblin has none). So `CharacterContext2D.gd` is not touched.

## New checks (all in `run_weapon_mount_checks()`)

- **WM1** an empty `weapon_mount` means `WeaponFacingPivot`: the player can equip the bow; the goblin is still refused for lacking one.
- **WM2** `../AnimatedSprite2D` resolves to the sprite and the goblin can equip the sword.
- **WM3** an unresolved path refuses the weapon, names `weapon_mount`, and leaves the goblin's weapon and attacks unchanged.
- **WM4** equipping through the sprite mount mounts the sword under `AnimatedSprite2D`, named `Weapon`.
- **WM5** the goblin then has the sword's three attack ids with `sword_slash1` as default.
- **WM6** the goblin starts `sword_slash1` and plays `sword_slash_1`; no orphaned `#` nodes remain under its sprite.

These checks mount the sword on a goblin only inside the test arena; no shipped scene does it yet.

## Files in the zip

Changed: `Characters/Components/Weapons/WeaponController2D.gd`, `tests/smoke_checks.gd`, `docs/Combat-Roadmap-Step-by-Step-Plan.md`. New: `docs/trackW/W5a-notes.md`. Nothing to delete.

## Next

W5b: `Weapons/GoblinSword/GoblinSword.tscn` (the knife sprite and its clips copied from `BasicEnemy2D.tscn`) and `GoblinSword_WeaponDefinition.tres`, still not wired into the enemy. W5c: the goblin's lunge file. W5d: wire `BasicEnemy2D.tscn` through the controller and delete `GoblinAttackDefinition.tres`.
