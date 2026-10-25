# Bow animation cycle

Light shot: `bow_draw` > `bow_shoot`. Heavy shot: `bow_draw` > `bow_charge` (loops) > `bow_heavy_shoot`.
Every transition happens by itself when the previous clip ends; nothing waits for input except the heavy release.

## What changed

| File | Change |
| --- | --- |
| `Weapons/Bow.tscn` | New `Arrow` sprite (the nocked arrow), new `bow_draw` clip, arrow tracks in `bow_charge`, `bow_shoot`, `bow_heavy_shoot` (shown at the start, hidden on the SAME key as `spawn_effect`), hidden in `idle`, `RESET`, `bow_return`. `bow_shoot` is 0.417 s now; its combo window is 0.125 s to 0.375 s. |
| `Weapons/Bow.gd` (new) | Hides the arrow when an attack is cancelled (a hit, death). |
| `AttackDefinition2D.gd` | `draw_animation` (clip played before the swing, or before the charge) and `input_queue_time` (how long a click made during the attack is remembered). Both default to "off", so sword and goblin attacks are unchanged. |
| `AttackComponent2D.gd` | Plays the draw first and hands over to the weapon or charge clip by itself. A release during the draw fires the shot when the draw ends. The charge only counts after the draw. Queued clicks chain at the combo window, when the clip ends, or after the return. |
| `Character2D.gd` | Asks `take_queued_attack()` when nothing new was pressed, so a click made during the return still plays. |
| `WeaponDefinition2D.gd` | Weapon validation also checks the `draw_animation` clip. |
| `ArrowAttackDefinition.tres` | `draw_animation = bow_draw`, `input_queue_time = 0.45`, `recovery_time` 0.5 > 0.3. |
| `ArrowHeavyAttackDefinition.tres` | `draw_animation = bow_draw`, `input_queue_time = 0.6`. |
| `tests/smoke_checks.gd` | `WW11` clears the new draw/queue fields on its sword-clip variant; new section `BC1` to `BC43`. |

## Tuning

- Draw speed: length of `bow_draw` (0.167 s).
- How early a click may come: `input_queue_time` on the arrow definitions.
- When the next shot can chain: `combo_window_open` / `combo_window_close` keys in `bow_shoot`.
- Time back to idle after the last shot: `recovery_time` on `ArrowAttackDefinition.tres`.
- Arrow placement: the `Arrow` node's position (8.5, -0.5) and the `Arrow:position` tracks of the clips.

## Verified

`godot --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd` gives `SUMMARY passes=1031 failures=0`
(Godot 4.7, before the change: 986 / 0). The engine warning and error lines of the run are identical to the run before.
