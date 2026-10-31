# R4: charge scaling (Track R, written October 29, 2026; NOT RUN: no Godot was available; builds on R3, which is also not run)

Run `tools/run_checks.sh`. Expect R3's total plus 9 new checks (R4-1 to R4-9, `tests/h8_aim_checks.gd`, part `h8_aim`).

## What changed (RD6)
- `AttackDefinition2D.charge_reach_min` (0 to 1, default 1 = fixed reach, so no existing data changes). `get_reach_at_charge(ratio)` =
  `get_reach() x lerp(charge_reach_min, 1, ratio)`; `charge_ratio_at(seconds)` = seconds / `charge_threshold` (0 with no threshold).
  `get_reach()` stays the full reach. Warning when `charge_reach_min < 1` and `charge_threshold` is 0.
- **Live while charging:** `player.gd` `_heavy_reach()` feeds the aim indicator's circle, the assist shape (through `with_reach()`)
  and the heavy auto-approach distance (reach at the charge carried so far, `_approach_charge`).
  `AttackComponent2D.get_charge_reach()` gives the live value.
- **Frozen at release:** `_commit_release()` computes the reach at the charge reached; `_start_swing()` stores it as `_active_reach`
  (`get_active_reach()`); `_spawn_effect()` passes it to the effect, so the slash's reach, the R3 gate and an attack projectile's flight all use it.
  Attacks that did not charge use `get_reach()` as before.

## To use it
The shipped heavies set no `charge_threshold` (INPUT_RELEASE, ratio always 0). To scale one, set `charge_threshold` (seconds for a
full charge) and `charge_reach_min`. With a threshold on an INPUT_RELEASE attack the threshold only scales the ratio; it does not
release by itself.

## Not covered by a test yet
The frozen-at-release path through a real AttackComponent2D (charge, release, read `get_active_reach()`) and the approach distance
are written but have no check; R5 should add them once a Godot run confirms R3.
