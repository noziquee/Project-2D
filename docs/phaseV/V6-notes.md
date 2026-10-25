# V6 - Simple enemy health bar, and the final Phase 13.4 smoke run

Run in headless Godot 4.7.2 (`--import`, then `--fixed-fps 60 --script res://tests/smoke_checks.gd`). Before this step the run stopped at `SUMMARY passes=239 failures=1`; with only the test name fixed it gave 885 / 0 (the first full run of Phase 13.4); after this step: **`SUMMARY passes=887 failures=0`** (885 + 2 new checks, R27 and R28). The leak lines at exit are not failures.

## Why the smoke test stopped at 239
The enemy bar node in `BasicEnemy2D.tscn` is named `EnemyHealthBar` (it was `EnemyHealthBar2D`). Check `R22` still looked for the old name, got null, and `R23` crashed on it, so no later check ran. The test now uses `EnemyHealthBar`.

## Why the enemy bar looked big
`EnemyHealthBar.tscn` set `custom_minimum_size = (76, 18)` on its root. A Control cannot be smaller than its minimum size, so the 50 x 10 offsets set on the goblin were ignored: the bar was 76 x 18 world pixels (the goblin sprite is 16 x 16), and since its left edge was at x = -25 it sat to the right of the goblin. The height had a second floor: the bar row (10) plus margins (1 + 1) plus the 3 px border of `panel_compact.tres` on each side made 18. The camera zoom was never involved; it is untouched (`player.tscn`, zoom 2 x 2).

## What changed
- `UI/HUD/EnemyHealthBar.tscn`: minimum size and offsets 28 x 5; the card panel is a `StyleBoxEmpty`; padding margins 0; the header, the on-bar number and the accent are hidden; the bar row is 5 high. What shows is the fill bar and the damage trail bar.
- `UI/HUD/Styles/bar_background_compact.tres`, `bar_fill_compact.tres`, `damage_fill_compact.tres`: corner radius 1 (the old radii are bigger than a 5 px bar). Only the enemy bar uses these.
- `Characters/Enemies/BasicEnemy2D.tscn`: bar offsets (-13, -15) to (15, -10), centred on the sprite (its centre is at x = 1) with a gap above the head.
- `tests/smoke_checks.gd`: `R22` name fix; `R24` now checks the simple look; `R26` text; new `R27` (the bar is as large as its offsets, so no minimum size inflates it, and it is thin) and `R28` (fill and trail bars are shown).

## Decision
The card, padding, header, number and accent are hidden, **not deleted**: `HealthBar.gd` finds them by path (`$Card/Padding/Content/...`) and the player bar uses the same nodes, and an inherited scene cannot delete nodes of its base. Hidden and empty, they take no space and draw nothing.

`UI/HUD/Styles/panel_compact.tres` is no longer used by any scene. It can be deleted in the FileSystem dock (right-click, Delete) or kept.

## To tune it in the editor
Open `Characters/Enemies/BasicEnemy2D.tscn`, select `EnemyHealthBar`. Position and size: **Layout > Offsets** (left/right set the width, top/bottom the height and the gap above the head). If you make it larger than 28 x 5, also raise **Layout > Custom Minimum Size** only if you need a floor; a floor larger than the offsets is exactly what made it big before. Check `R27` still passes after tuning (its limits are 40 x 10).
