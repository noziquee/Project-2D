# Phase V2a: first real baseline, and the first batch of fixes

Not run after these edits (no Godot in the editing environment). Run the smoke test and paste the `SUMMARY` line and every `CHECK FAIL` line.

## The baseline (first real run, Godot 4.7.2, after Phase 10.5)

`SUMMARY passes=585 failures=22` (607 checks). Every earlier "expected" total in the notes was a prediction; this is the first real number. One `SCRIPT ERROR` also appeared before the checks (see fix 1).

The 22 failures: `H-player 6`, `H-player 7`, `L6`, `M3`, `O7`, `R19`, `S20`, `U14`, `U15`, `BB2`, `EE3`, `GG6`, `HH10`, `HH11`, `II12a`, `II12b`, `JJ1b`, `JJ4d`, `JJ5f`, `KK4d`, `PP2e`, `QQ4`.

## Plan for fixing them (three batches, by cause)

1. **V2a (this batch):** the harness error and the timing and input group.
2. **V2b:** the weapon scene and validation group (`JJ1b`, `JJ4d`, `JJ5f`, `KK4d`, `QQ4`, `II12a`, `II12b`).
3. **V2c:** the stale or mismatched ones (`M3`, `BB2`, `L6`, `O7`, `S20`), plus whatever V2a leaves.

## What changed in V2a

Two files: `tests/smoke_checks.gd` and `player.gd`. No scene, resource or other script changed.

### Fixes (cause known from the code)

| Item | Cause | Change |
|---|---|---|
| `SCRIPT ERROR` at `smoke_checks.gd:73` | `quiet_goblin_choices()` read `goblin._ai_controller`, an `@onready` variable. The very first `fresh()` runs from `_initialize()`, before the goblin's `_ready()` has run, so it was still null. | The helper finds the controller by node name (`EnemyAIController2D`) and returns quietly if it or its profile is missing. Test-only. |
| `U15` | Real game bug. `player.gd` `_on_death()` switches physics off, so `_sample_attack_input()` never runs again and a held attack button stayed "held" after death. | `_on_death()` clears `_light_held`, `_heavy_held`, `_press_charged`, `_charge_requested`, `_hold_elapsed` and the three pending requests. |
| `EE3` | Stale expectation. It wanted the cut at 0.2 to 0.28 s, written for an earlier clip. `sword_slash_1` closes its combo window at 0.4167 s of 0.5 s (check `AA1` says so). | The check reads the close key from the clip and expects the cut just before it, and before the clip's end. |
| `GG6` | Stale timing. It released the button after 12 frames, but the window opens at 0.25 s (15 frames), so the release was before any window existed. | The press is held until `is_combo_window_open()`, plus one frame, then released. The check itself is unchanged. |

### Diagnostics only (cause not yet known)

These checks keep their conditions. Only the failure text now says more, so the next run tells us the cause.

- `H-player 6`: also prints whether the first swing started, how long it lasted, and the cooldown of the active definition. In the first run the swing seemed to end after one frame, which points at the first `try_start` or at the swap of the definition for the player.
- `HH10` (and with it `HH11`): prints `attacking`, `cooldown`, `stunned` and `dashing` at the moment the new combo is refused.
- `U14`: prints the active id, the light id, cooldown, stun and charge state.
- `R19`: prints the clip name, whether it plays, the shown health and the critical flag. The first run reported the clip `hit` after a heal, which is odd.
- `PP2e`: lists the slash effects still alive and the clip each plays.

## Expected result of the next run

No check was added or removed, so the total stays 607. If the analysis above is right, `EE3`, `GG6` and `U15` pass and the `SCRIPT ERROR` is gone: **`SUMMARY passes=588 failures=19`**. The diagnostic checks should still fail, now with a longer message. If the number differs, paste the `CHECK FAIL` lines; that is the point of V2a.

One side effect to watch: the first `fresh()` now also gets the "quiet" goblin profile (no weighted lunge), like every other section. Sections A to G passed with it in other runs, so no change is expected.

## Not done

- V1 (open the project in the editor) and V3 (play-test) can only be done by you.
- The Threshold values on `DefaultAttackDefinition.tres` (decision V4) are untouched.
