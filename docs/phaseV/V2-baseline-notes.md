# Phase V2: baseline confirmed

Run on Oct 24 2026 with Godot 4.7.2 (stable, win64).

## Result

- `godot --headless --import --path .` finished with no errors.
- `godot --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd` gave **`SUMMARY passes=607 failures=0`**. No `CHECK FAIL` line.
- 607 is the number V2b predicted, so its analysis was right: the extra goblins in `Main.tscn` and the stale checks were the whole cause.

The run does not say whether `DefaultAttackDefinition.tres` already had the V4 change (Threshold values cleared). It does not matter for the total: V4 adds and changes no check, and the section U checks that copy that attack hold for 22 frames at most.

## What in the log is expected, not a failure

- `ERROR:` and `WARNING:` lines with a GDScript backtrace from `AttackComponent2D`, `WeaponController2D`, `Character2D`, `AttackSlash2D` and `EnemyAIController2D`. They come from checks that feed a bad definition or weapon on purpose and then check the refusal (I15, I16, I27, M8, N11, S16, LL5, MM7, PP3, PP6, QQ3, QQ6, RR5, SS3, UU6 and others). Each is followed by a `CHECK PASS` for the refusal.
- The repeated warning `attack 'player_light' ... next_attack 'player_light2' is not registered` appears where a check replaces the player's attacks with its own list. The link is ignored by design there.
- After `SUMMARY`: `RID allocations ... leaked at exit`, `ObjectDB instances were leaked at exit` and `resources still in use at exit`. The headless test script quits while test scenes are still alive; the same kind of lines appear after the plain `--import` run. They are not failures. If you ever want a clean exit, the test could free its last scene before `quit()`, but that is cosmetic and not planned.

## What is now confirmed and what is not

Confirmed by the 607 checks: the combat system through Phase 10.5 (combos, return on window close, heavy charge and release, weapons and equip, effect base class, node paths, hit policy, spawn point).

Not confirmed:
- Opening and running `Main.tscn` in the editor and reading the Output panel (the headless import found no error, but the editor run was not reported).
- V3, the play-test. The checks prove behavior, not feel: hitbox reach, the heavy's look, aim up and down, the nine-goblin arena.

## Next

Phase 11.1 `ProjectileEffect2D` can start on this baseline: every later step counts from 607. If V3 turns up bugs, fix them first (roadmap rule).
