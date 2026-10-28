# H9 first real run: `passes=1597 failures=20`, and the fixes

Run on your machine, headless Godot 4.7.2, October 29, 2026. Fixes below are written but **not re-run**; run `tools/run_checks.sh` and paste the new SUMMARY line into `docs/STATUS.md`.

| Failing checks | Cause | Fix |
|---|---|---|
| HHH8, HHH9, H7-27, H7-64, H7-75, H8-138 (skill keys / buttons, Empower) | Real bug. `_begin_approach_if_needed()` never checked rule 4 (reach 0 = no approach). `is_in_reach()` is false for reach 0, so a self buff with an enemy on screen started an approach instead of casting. | `player.gd`: return false when `_reach_for(...) <= 0`. |
| H9-54, H9-35 (marker flips between two near-equal enemies) | Real bug. The marker used the stateless `pick_target()`, so the stay-put bonus never applied to it. | `TargetingService2D.pick_marked_target()` remembers the marked target and gives it `STICKY_BONUS`; `player.gd` uses it. `clear()` forgets it. |
| T4, T7, U5, U7 | Test predates auto-approach: enemy 200 px away and in view, light reach 70, so the tap walked instead of swinging. | Tests put the enemy off screen (5000 px). |
| V12 | Test predates D19: default attack range is now 70, enemy was placed at exactly 70. | Enemy placed at 76 px (beyond 70, inside v_long's 80). |
| H9-47 to H9-52 | Test bug: stubs from earlier checks stayed alive and won the picks. | Earlier stubs are set aside for H9-50..52, `far_visible` revived for H9-47. |
| H4-25 (2 unexpected errors, `Can't free a RefCounted object`) | Test bug in `h9_visuals`: `.free()` on `AttackDefinition2D` resources. | Removed the three `.free()` calls. |

The `RID` / "resources still in use" lines at exit are shutdown leaks the runner already counts separately.
