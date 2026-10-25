# V5 - Phase 12 on the first full run: 661 / 65, then 710 / 16, then 726 / 0

Run in headless Godot 4.7.2 (`--import`, then `--fixed-fps 60 --script res://tests/smoke_checks.gd`). The first run on the Phase 12 archive gave 661 passes and 65 failures, the second (after the scene fixes below) 710 and 16. After this step: **`SUMMARY passes=726 failures=0`** (680 + 46 from Phase 12). New baseline.

## Causes (all editor tuning that the checks did not expect, none in the combat code)
1. `player.tscn`: the mounted sword instance was named `Sword`, not `MainHand`. `CharacterContext2D` and the tests look for `WeaponFacingPivot/MainHand`; with the wrong name the starting weapon was never equipped. Renamed back. (Fixed in the first zip.)
2. `defense = 5` on the player and `defense = 3` on the goblin. 12.2 ships every character at 0 (check BBB1) and the damage checks expect undiminished damage. Both set back to 0. Set defense in the editor when you play; the damage checks and BBB1 will then fail until it is back to 0.
3. `player.tscn` sets `charge_start_time = 0.5` (default 0.1). Every hold, charge, tap and threshold check is timed for 0.1 s: U3, U9, U10, BB3a/b, BB5, GG1 to GG3, GG5a, HH18 to HH20b, OO3c/d. These were the "sixteen unexplained" failures in the 12.1 notes. **Your 0.5 is kept.** `tests/smoke_checks.gd` `load_main()` now pins the player's `charge_start_time` to 0.1 for every test arena; the scene is not touched.
4. `Weapons/Sword.tscn`: the sprite offset was tuned to (5, -5). Check JJ1c pinned the old (8, -8). JJ1c now expects (5, -5).

## What changed
- `player.tscn`, `Characters/Enemies/BasicEnemy2D.tscn`: items 1 and 2.
- `tests/smoke_checks.gd`: `load_main()` pin (item 3), JJ1c expectation (item 4), U3 text.
- Roadmap and this note.

## Rule going forward
A value tuned in the editor must not decide a check. Either the check pins the value it needs (as `load_main()` does), or the value is left at its default. Run the smoke test after editor changes to a shipped scene.
