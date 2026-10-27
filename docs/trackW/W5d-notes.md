# W5d - wire the GoblinSword into BasicEnemy2D

Implemented October 25, 2026. **Not run in Godot in this environment.** This completes the source changes for W5; run the combined smoke suite after Track W is finished. The previous W5c notes expected 1001 checks. W5d adds 14 new GS checks, so the expected total from that baseline is **1015 passes, 0 failures**, assuming all previous unrun Track W checks pass.

## Changes

- `BasicEnemy2D.tscn` now instances `Weapons/GoblinSword/GoblinSword.tscn` under `AnimatedSprite2D/Weapon`, and adds `WeaponController2D` with `weapon_mount = ../AnimatedSprite2D` and `starting_weapon = GoblinSword_WeaponDefinition.tres`.
- The attack component starts with the shared `Sword_Slash1` resource so it can initialize before the controller equips the weapon. Its extras are `Sword_Slash2` and `GoblinSword_Lunge`; the controller then applies the weapon definition as normal.
- `GoblinBehaviorProfile.tres` chooses `Sword_Slash1` and `GoblinSword_Lunge`, not the combo follow-up. This keeps the AI from independently choosing `sword_slash2`; it only becomes available as the registered combo link.
- Removed `GoblinAttackDefinition.tres` and `GoblinLungeAttackDefinition.tres`, plus stale `.uid` sidecars if present. Replaced references in smoke checks.
- Updated `Character2D.gd`'s component comment to reflect that the goblin now has a weapon controller.

## New checks

GS1–GS14 cover controller presence and initialization, mount configuration, mounted scene, default attack and attack IDs, resource identity, slash data, lunge values, AI choices, absence of the old character-owned resources, and removal of embedded weapon animation data from `BasicEnemy2D.tscn`. The existing S1 check now expects the goblin's two extra attacks: `sword_slash2` and `goblin_sword_lunge`.

## Gameplay change

The goblin's basic slash now uses the sword's shared `Sword_Slash1` numbers and hit effect. Its lunge keeps its weapon-specific values.

## Files

Changed: `Characters/Enemies/BasicEnemy2D.tscn`, `Characters/Controllers/GoblinBehaviorProfile.tres`, `Characters/Core/Character2D.gd`, `tests/smoke_checks.gd`, `docs/Combat-Roadmap-Step-by-Step-Plan.md`.
New: `docs/trackW/W5d-notes.md`.
Deleted: `Characters/Components/Combat/GoblinAttackDefinition.tres`, `Characters/Components/Combat/GoblinLungeAttackDefinition.tres` and their `.uid` sidecars if present.
