# W3 - file names with the weapon in the name

Written October 25, 2026 **without running Godot**. Rename only: ids, numbers, clips and folders are unchanged, no new checks. Expected: **`SUMMARY passes=986 failures=0`**. You will run one smoke test after Track W is finished; if the count is off then, find the first step whose notes do not match. Answers used: Q2 (the weapon is in the file name).

## Renames

| Old file (after W2) | New file |
|---|---|
| `Weapons/Sword/Attacks/DefaultAttackDefinition.tres` (id `player_light`) | `Weapons/Sword/Attacks/Sword_Slash1.tres` |
| `Weapons/Sword/Attacks/PlayerLight2AttackDefinition.tres` (`player_light2`) | `Weapons/Sword/Attacks/Sword_Slash2.tres` |
| `Weapons/Sword/Attacks/PlayerHeavyAttackDefinition.tres` (`player_heavy`) | `Weapons/Sword/Attacks/Sword_HeavySlash.tres` |
| `Weapons/Sword/Skills/LungeSkillDefinition.tres` | `Weapons/Sword/Skills/Sword_Lunge.tres` |
| `Weapons/Sword/Skills/SpinSkillDefinition.tres` | `Weapons/Sword/Skills/Sword_Spin.tres` |
| `Weapons/Sword/Skills/GroundSlamSkillDefinition.tres` | `Weapons/Sword/Skills/Sword_GroundSlam.tres` |
| `Weapons/Sword/Skills/EmpowerSkillDefinition.tres` | `Weapons/Sword/Skills/Sword_Empower.tres` |
| `Weapons/Bow/Attacks/ArrowAttackDefinition.tres` (`arrow_shot`) | `Weapons/Bow/Attacks/Bow_ArrowShot.tres` |
| `Weapons/Bow/Attacks/ArrowHeavyAttackDefinition.tres` (`arrow_heavy`) | `Weapons/Bow/Attacks/Bow_ArrowHeavy.tres` |
| `Weapons/Bow/Attacks/GoblinArrowAttackDefinition.tres` (`goblin_arrow`) | `Weapons/Bow/Attacks/Bow_ArrowEnemy.tres` |
| `Weapons/Bow/Skills/PowerShotSkillDefinition.tres` | `Weapons/Bow/Skills/Bow_PowerShot.tres` |
| `Weapons/Bow/Skills/MultiShotSkillDefinition.tres` | `Weapons/Bow/Skills/Bow_MultiShot.tres` |
| `Weapons/Bow/Projectile/Arrow.tscn` | `Weapons/Bow/Projectile/Bow_Arrow.tscn` |

Every `uid="uid://..."` is unchanged. Not renamed: the two goblin knife attacks (W5) and the framework scenes.

## References rewritten

`player.tscn`, `Weapons/Sword/Sword_WeaponDefinition.tres`, `Weapons/Bow/Bow_WeaponDefinition.tres`, `Weapons/Sword/Attacks/Sword_Slash1.tres` (its `next_attack`), the three bow attack files and two bow skill files (the arrow scene and each other), `Characters/Enemies/GoblinArcher.tscn`, `Characters/Controllers/GoblinArcherBehaviorProfile.tres`, and the path constants and `load()` strings in `tests/smoke_checks.gd`. No assertion changed. Checked: no check reads a file name (the `get_file()` uses in the tests read scene and script names that did not change), and no old path is left in any `.gd`, `.tscn`, `.tres` or `project.godot` outside `docs/` and `.godot/`.

## Files in the zip

Changed: `player.tscn`, `tests/smoke_checks.gd`, `Characters/Enemies/GoblinArcher.tscn`, `Characters/Controllers/GoblinArcherBehaviorProfile.tres`, the two weapon definitions, `docs/Combat-Roadmap-Step-by-Step-Plan.md`, `docs/trackW/W0-plan.md`, and the notes. New: the 13 renamed files at their new names (all of them, so the zip alone is enough).

**Delete the 13 old file names yourself** (the left column above) after unzipping, or rename them in the FileSystem dock instead (then take only the changed files from the zip). Leaving the old names gives two copies of each resource with the same `uid`.

## Next

W4: resource ids and standard clip names, 2 new checks (expected 988). Q3 in `W0-plan.md` asks whether ids follow the new file names or stay as they are.
