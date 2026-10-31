# H10: shared bow, smart aim, skill preview, enemy wind-up

**Status: written, not run.** No Godot was available when this was made. Run `tools/run_checks.sh --twice` and compare with your baseline, then play-test.

## Part A: shared weapon data (D26)
- `GoblinArcher.tscn` equips `Weapons/Bow/Bow_WeaponDefinition.tres`; `GoblinArcherBehaviorProfile.tres` chooses `Weapons/Bow/Attacks/Bow_ArrowShot.tres`.
- Removed `Bow_EnemyWeaponDefinition.tres` and `Bow_ArrowEnemy.tres`. `.godot/uid_cache.bin` and `global_script_class_cache.cfg` were deleted so Godot rebuilds them on import.
- The archer now has the player's arrow values. To keep it playable, `EnemyBehaviorProfile.attack_interval` (new, default 0) paces it: the archer profile uses 1.2 s, the old cooldown.
- The archer's `AttackComponent2D` also registers `Bow_ArrowHeavy`; the AI never picks it. The weapon's skills are ignored (enemies have no `SkillComponent2D`).

## Part B
- `EnemyBehaviorProfile.attack_windup_duration` (0.35 s default). `EnemyAIController2D` runs the wind-up and cancels it when the swing starts, the enemy is stunned or dead, the target leaves range or is lost. 0 attacks at once.
- `Characters/Enemies/EnemyAttackTelegraph2D.gd`: the lane. The controller finds the child by name or makes it on first use, so no scene needed editing.
- `TargetingService2D.pick_nearest_target()`; `pick_marked_target()` uses it; `resolve()` takes `prefer_nearest` (the player passes true).
- `player.gd`: `request_skill_cast(slot)`, `_pending_cast_slot`, `_update_pending_cast()`, `skill_aim_preview`. `SkillBar._on_slot_clicked` calls `request_skill_cast` on the player.
- Dash while previewing cancels and is swallowed (`_dash_cancel_frame`). The confirming click does not also start a light attack.

## Tests
- New part `smart_aim` (SA1 to SA35). Older tests: `load_main()` sets `skill_aim_preview = false` and `reset_global_state()` sets the goblin and archer profiles' wind-up to 0, so they keep their timing.
- Changed: WA3 to WA10 (+WA11, WA12), ZZ2/ZZ5/ZZ7/ZZ9/ZZ10 (archer now 100 px range, 4 damage), W7/WZ, H3-10, A-3 (+A-3b), H8-89, R3-1 to R3-4, H9-53, H9-54.
- R3-2 and R3-3 now compare against each attack's own `get_reach()` (they asserted 120, but the shot is `attack_range = 100` and the heavy 200).

## Open
- The lane is a generic forward rectangle (the archer's is 8 px wide). Per-attack telegraph shapes remain the follow-up from the spec.
- Pure nearest can make the marker flip between two equidistant enemies. No tie-break was added.
