# W7 - cross-weapon reference audit and clip validation

Written October 25, 2026. **Not run in Godot in this environment.** W6's source notes expected 1025 checks; W7 adds five WZ checks, so the expected combined result is **`SUMMARY passes=1030 failures=0`**, assuming the earlier unrun Track W changes pass.

## Audit results

- `Sword_Slash1.tres` and `Sword_Slash2.tres` are used by both `Sword_WeaponDefinition.tres` and `GoblinSword_WeaponDefinition.tres`. They remain under `Weapons/Sword/`, the folder of the first weapon that created them.
- `Sword_Empower.tres` is used by both the Sword and Bow definitions. It remains under `Weapons/Sword/`, the folder of the first weapon that created it. Its skill has no weapon animation clip dependency, so both weapon scenes remain valid.
- `Bow_ArrowEnemy.tres` is referenced by `Bow_EnemyWeaponDefinition.tres`, while the player Bow definition keeps its player-only arrow attacks.
- `Sword_GroundSlam.tres` was the only attack/skill resource in a weapon folder not referenced by a weapon definition. It remains available as an example, moved to `Data/Examples/WeaponSkills/Sword_GroundSlam.tres`; `tests/smoke_checks.gd` now loads it from that path. This keeps weapon folders limited to resources actually used by a weapon.
- Every remaining `.tres` in the weapon `Attacks/` and `Skills/` folders is checked for use by at least one weapon definition.

## Changes

- Added WZ1–WZ5 smoke checks for shared-resource identity and ownership, unused weapon-folder resources, shipped weapon-scene clip validation, and rejection of a weapon that tries to use a shared attack without the attack's required clip.
- No new class or combat system was introduced. `WeaponController2D.validate_equip()` already checks the weapon's own scene and reports the weapon, attack and missing clip; WZ5 locks this behavior in with a focused cross-weapon test.
- Updated the roadmap and Track W plan to record the audit and the Ground Slam example location.

## Files

Changed: `tests/smoke_checks.gd`, `docs/Combat-Roadmap-Step-by-Step-Plan.md`, `docs/trackW/W0-plan.md`.
New: `Data/Examples/WeaponSkills/Sword_GroundSlam.tres`, `docs/trackW/W7-notes.md`.
Moved/deleted old path: `Weapons/Sword/Skills/Sword_GroundSlam.tres` (delete the old file after extracting the ZIP; ZIP extraction does not remove obsolete files).

## Verification

Static source inspection only. Godot is not installed in this environment, so the full import and smoke suite have not run. Run `godot --headless --import --path .` and then `godot --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd`. Do not treat 1030 / 0 as a confirmed result until that command reports it.
