# W8 — documentation alignment

Prepared October 25, 2026. Documentation-only step; no GDScript, scenes, resources, or smoke-test logic changed.

## Updated files

- `README.md`: current weapon-folder tree, ownership conventions, adding attacks/weapons, commands for import and smoke tests, and explicit distinction between the last confirmed 986 / 0 baseline and Track W's unconfirmed expected 1030 / 0.
- `IMPLEMENTATION_NOTES.md`: added an authoritative current Track W layout section and corrected current references to the Bow, Sword and arrow resources. Earlier phase descriptions are identified as historical snapshots where paths may differ.
- `docs/Combat Architecture Review & Expansion Guide (Updated Oct 2026).md`: replaced the proposed pre-migration layout and obsolete "not started" statements with the current Track W layout and implementation status.
- `docs/Combat-Roadmap-Step-by-Step-Plan.md`: marked the W8 documentation pass complete and clarified that the Track W runtime verification gate is still pending.

## Current ownership rules documented

- Sword content lives in `Weapons/Sword/`.
- Bow content, including the enemy Bow definition and arrow projectile, lives in `Weapons/Bow/`.
- GoblinSword content lives in `Weapons/GoblinSword/`.
- Cross-weapon resources remain in the folder of the weapon that first created them; no `Shared/` folder is used.
- The goblin archer uses `Bow_EnemyWeaponDefinition.tres` so enemy arrow behavior is preserved while sharing the Bow scene.
- `Data/Examples/WeaponSkills/Sword_GroundSlam.tres` is the canonical example resource and is not part of the default skill loadout.

## Verification

Static documentation and path review only. Godot was not run. The last confirmed smoke result remains `SUMMARY passes=986 failures=0` from Track P10. Track W's expected combined result is `SUMMARY passes=1030 failures=0`, but it is not confirmed until the user runs the import and smoke-test commands in the README.
