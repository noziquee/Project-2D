# W2 - attacks, skills and the arrow into their weapon folders

Written October 25, 2026 **without running Godot**. Pure move: file names, resource ids, numbers and clips are unchanged, no new checks. Expected: **`SUMMARY passes=986 failures=0`**. Done only when your run prints that. W1 must be applied first (with your names: `Sword.tscn`, `Sword_WeaponDefinition.tres`, `Bow.tscn`, `bow.gd`, `Bow_WeaponDefinition.tres`).

## What moved (by decision D1: the folder of the first weapon that created it)

| Old path (under `Characters/Components/`) | New path |
|---|---|
| `Combat/DefaultAttackDefinition.tres` | `Weapons/Sword/Attacks/DefaultAttackDefinition.tres` |
| `Combat/PlayerLight2AttackDefinition.tres` | `Weapons/Sword/Attacks/PlayerLight2AttackDefinition.tres` |
| `Combat/PlayerHeavyAttackDefinition.tres` | `Weapons/Sword/Attacks/PlayerHeavyAttackDefinition.tres` |
| `Skills/LungeSkillDefinition.tres` | `Weapons/Sword/Skills/LungeSkillDefinition.tres` |
| `Skills/SpinSkillDefinition.tres` | `Weapons/Sword/Skills/SpinSkillDefinition.tres` |
| `Skills/GroundSlamSkillDefinition.tres` | `Weapons/Sword/Skills/GroundSlamSkillDefinition.tres` |
| `Skills/EmpowerSkillDefinition.tres` (the bow uses it too) | `Weapons/Sword/Skills/EmpowerSkillDefinition.tres` |
| `Combat/ArrowAttackDefinition.tres` | `Weapons/Bow/Attacks/ArrowAttackDefinition.tres` |
| `Combat/ArrowHeavyAttackDefinition.tres` | `Weapons/Bow/Attacks/ArrowHeavyAttackDefinition.tres` |
| `Combat/GoblinArrowAttackDefinition.tres` (the archer's, Bow folder by D5) | `Weapons/Bow/Attacks/GoblinArrowAttackDefinition.tres` |
| `Skills/PowerShotSkillDefinition.tres` | `Weapons/Bow/Skills/PowerShotSkillDefinition.tres` |
| `Skills/MultiShotSkillDefinition.tres` | `Weapons/Bow/Skills/MultiShotSkillDefinition.tres` |
| `Combat/Arrow.tscn` | `Weapons/Bow/Projectile/Arrow.tscn` |

All `uid="uid://..."` values are unchanged; only text paths were rewritten.

## Deliberately left where they are

- `GoblinAttackDefinition.tres` and `GoblinLungeAttackDefinition.tres` (the goblin's knife): W5 replaces the slash with the sword's `DefaultAttackDefinition` and decides the lunge (open question Q1), so moving them now would be wasted work.
- Framework scenes and scripts: `AttackSlash2D.tscn`, `AreaEffect2D.tscn`, `ProjectileEffect2D.tscn` and every `.gd`. `Characters/Components/Skills/` now holds only `SkillComponent2D.gd` and `SkillDefinition2D.gd`.
- Skill icons stay in `UI/HUD/Icons/` (D3).

## References rewritten

`player.tscn`, `Weapons/Sword/Sword_WeaponDefinition.tres`, `Weapons/Bow/Bow_WeaponDefinition.tres`, the five moved attack files and two skill files that reference each other or the arrow, `Characters/Enemies/GoblinArcher.tscn`, `Characters/Controllers/GoblinArcherBehaviorProfile.tres`, and the path constants and `load()` strings in `tests/smoke_checks.gd`. No assertion changed. A search for every old path in `.gd`, `.tscn`, `.tres` and `project.godot` (outside `docs/` and `.godot/`) finds nothing. No check scans these folders, so none depends on what a folder contains. Older notes in `docs/phase*` keep their historical paths; the README "Add an attack" paths are updated in W8.

## Files in the zip

Changed: `player.tscn`, `tests/smoke_checks.gd`, `Characters/Enemies/GoblinArcher.tscn`, `Characters/Controllers/GoblinArcherBehaviorProfile.tres`, `Weapons/Sword/Sword_WeaponDefinition.tres`, `Weapons/Bow/Bow_WeaponDefinition.tres`, the roadmap, `docs/trackW/W0-plan.md`, `docs/trackW/W1-notes.md`.
New (the moved files at their new paths): the 13 files in the table above, plus `docs/trackW/W2-notes.md`.

**Delete the 13 old files yourself** (a zip cannot delete): the ten `.tres` and the `Arrow.tscn` listed in the left column of the table, from `Characters/Components/Combat/` and `Characters/Components/Skills/`. If you use the FileSystem dock to move them instead, nothing needs deleting and you can skip the matching files from the zip.

## How to check

1. Close Godot, unzip over the project, delete the old files.
2. `godot --headless --import --path .` and read the output for `invalid UID`, `Cannot open file`, `Failed loading resource`.
3. `godot --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd`. Expected `SUMMARY passes=986 failures=0`.
4. In the game: all skills 1 to 3 on both weapons, the bow's arrow, the archer's arrows.

## Next

W3 renames the files to the generic names (`slash1`, `slash2`, `heavy_slash`, `arrow_shot` ...) with ids unchanged. Answer Q2 first if you want the weapon name in those file names.
