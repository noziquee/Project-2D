# R7: RD6 charge variety, steps 1 and 2 (written October 29, 2026; NOT RUN: no Godot was available)

Source: `RD6-Charge-Attack-Variety-Plan.docx`, implementation order steps 1 and 2. Run `tools/run_checks.sh`; expect the previous total plus 5 new
checks (R4-10 to R4-14, `tests/h8_aim_checks.gd`, part `h8_aim`).

## Step 1: the bow's heavy now expands
Finding: the shipped `Bow_ArrowHeavy.tres` set neither `charge_reach_min` nor `charge_threshold` (the plan says it set 0.5; it did not), so the
ratio stayed 0 and nothing expanded. It now sets `charge_reach_min = 0.5` and `charge_threshold = 1.0` (a full charge takes 1 s of holding; the count
starts after the 0.5 s `bow_draw`). Release mode stays INPUT_RELEASE, so the threshold only scales the ratio and never releases by itself. The reach
at release is frozen by the existing R4 path, so the arrow's flight, the R3 gate and the hit check all use it. The aim indicator and the target
assist already read `_heavy_reach()` live. A heavy released during its draw has ratio 0, so the arrow reaches half of `attack_range`.

Checks changed to match: `R4-9` (the bow heavy is now 0.5 / 1.0, the sword's stays fixed) and `XX9` (waits for a full charge, 96 frames, before release),
`A-26` (Track A: the reach frozen for a release during the draw is the minimum). New `R4-10`: the bow heavy's reach is 50, 75 and 100 percent of its full
reach at charge 0, 0.5 and 1.

## Step 2: optional easing
`AttackDefinition2D.charge_reach_ease` (a `Curve`, empty = linear, the default) and `eased_charge_ratio(ratio)`. `get_reach_at_charge()` feeds the
clamped ratio through the curve and clamps the result to 0 to 1, so the minimum and maximum reach cannot be pushed out of range; draw the curve from
(0, 0) to (1, 1) to keep both ends exactly. Below the diagonal is an ease-in, above it an ease-out. Nothing ships with a curve. Checks R4-11 to R4-14.

## Please check
- `R3-3` in `tests/h8_aim_checks.gd` expects the heavy arrow's full reach to be 150, but the data in this archive has `attack_range = 120`. That check
  looks stale (it predates this change); I left it alone.
- `XX9` places goblins at 120 and 240 px; the arrow is capped at its reach, so the far goblin may be out of reach whatever the charge. Run it before
  trusting its text.
- Play feel: a quick tap-release now shoots at about half reach (60 px). If that is too short, raise `charge_reach_min` in `Bow_ArrowHeavy.tres`
  or shorten `charge_threshold`.

## Step 3: charge stages (written October 29, 2026, NOT RUN)
Part `r7_stages`, checks S-1 to S-14 in `tests/smoke_checks.gd`.
- New resource `ChargeStage2D` (`Characters/Components/Combat/ChargeStage2D.gd`): `id`, `at_ratio` (0 to 1), `damage_multiplier`, `crit_chance_bonus`.
- `AttackDefinition2D.charge_stages` (empty = none, the default) and `get_charge_stage_index(ratio)`: the stage with the highest `at_ratio` reached, in
  any list order. A warning when stages are set but `charge_threshold` is 0.
- `AttackComponent2D` reads the stage from the same charge ratio as the reach (no second timer). Live: `get_charge_stage_index()`, `get_charge_stage()`
  and the signal `charge_stage_changed(index, stage)` for a charge bar. At release the stage is frozen next to the reach (`_release_stage`, taken by
  `_start_swing()` as `_active_stage`), and `_spawn_effect()` applies it: damage x `damage_multiplier` (rounded), crit chance + bonus (capped at 1).
  Cleared by `cancel()` and by the next swing. Reach, hitbox, pierce and targets are not touched by a stage.
- Nothing ships with stages, so no existing attack changes. To try it, add two `ChargeStage2D` entries to `Bow_ArrowHeavy.tres` (for example 0.5 x 2.0 and 1.0 x 3.0).
- Not built: a charge bar widget (no UI exists for charge yet); it can listen to `charge_stage_changed` and `get_charge_ratio()`. Projectile count and accuracy
  stages from the plan are not covered; only damage and crit.
- `ChargeStage2D` is a new global class: run the import step (`tools/run_checks.sh` does) before the suite.

## Step 4: timed release (written October 29, 2026, NOT RUN)
Part `r7_timed`, checks T-1 to T-14 in `tests/smoke_checks.gd`.
- `AttackDefinition2D` group "Timed release": `perfect_window_start` / `perfect_window_end` (a window on the charge ratio, off while end <= start, the
  default), `early_release_multiplier`, `perfect_release_multiplier`, `late_release_multiplier` (damage, 1 = unchanged) and `perfect_crit_bonus`.
  `get_release_timing(ratio)` gives NONE, EARLY, PERFECT or LATE (`ReleaseTiming`); both window ends count as perfect. Warnings: window with no
  `charge_threshold`; end not above start.
- It uses the same charge ratio as reach and stages (no second timer). `AttackComponent2D`: live `get_release_timing()` and signal
  `release_timing_changed(timing)` for a cue; signal `charge_released(timing)` at release; the timing is frozen at release with the reach and the stage.
  `_spawn_effect()` multiplies damage by stage x timing and adds the perfect crit bonus. A release during the draw has ratio 0, so it is EARLY.
- A window does not auto-release, and does not make the attack fail when missed: late and early only change the multipliers you set. Nothing ships
  with a window.
- No visual or audio cue is built; a cue can listen to `release_timing_changed`.
- T-14 allows a few pixels of slack because the exact frame of release depends on frame timing.

## Step 5: damage and area scaling (written October 29, 2026, NOT RUN)
Part `r7_scaling`, checks C-1 to C-12 in `tests/smoke_checks.gd`.
- `AttackDefinition2D.charge_damage_curve` and `charge_area_curve` (`Curve`, empty = none, the default). X is the charge ratio, Y is the multiplier
  itself, so set the curve's `min_value` / `max_value` (for example 1 to 3). `get_charge_damage_multiplier(ratio)` (never below 0) and
  `get_charge_area_multiplier(ratio)` (never below 0.1).
- Frozen at release with the reach, stage and timing. `_spawn_effect()` multiplies damage by curve x stage x timing; the area multiplier scales
  `hitbox_size` only when the spawned effect is an `AreaEffect2D` (its radius is half of `hitbox_size.x`). Reach, hitbox of any other effect, pierce
  and targets are untouched. Live reads for previews: `get_charge_damage_multiplier()` and `get_charge_area_multiplier()` on the component.
- Warnings: a curve with no `charge_threshold`; an area curve on an effect that is not an area effect.
- Not wired: the aim indicator does not yet draw the scaled area radius while charging; it still draws the attack's shape.
- C-12 temporarily swaps the bow heavy's effect scene for the area scene (restored at the end) to reach an area effect; no shipped attack uses an area curve.

## Not done (step 6 of the plan)
The charge bar (and its stage, timing and area/damage cues).

## Step 6: the charge bar (written October 29, 2026, NOT RUN)
Part `r7_bar`, checks B-1 to B-12 in `tests/smoke_checks.gd`.
- `UI/HUD/ChargeBar.gd` (`ChargeBar`, a Control drawn in code) is in `Main.tscn` as `HUD/PlayerChargeBar`, under the mana bar, with `attack_source` set to `Player/AttackComponent2D`. It only observes: each frame it reads `get_charge_ratio()`, so it has no timer of its own.
- It draws the charge ratio, a tick for each `charge_stages` entry, the perfect-release window, and colors the fill by `get_release_timing()` (early grey, perfect gold, late red) when the attack has a window. On `charge_released` it flashes the released outcome for 0.3 s, then hides.
- It stays hidden for attacks with no `charge_threshold` (the ratio never rises), so the sword's heavy shows no bar, and nothing else changes.
- New in `AttackComponent2D`: `get_charging_definition()` (read-only).
- Not built: an audio cue, a bar at the character in the world (it sits in the HUD), a per-stage label, and a damage/area preview. `ChargeBar.gd` has no `.uid` yet; the first import creates it.

## Charge starts during the draw (written October 29, 2026, NOT RUN)
Part `r7_draw`, checks D-1 to D-7 in `tests/smoke_checks.gd`.
- New `AttackDefinition2D.charge_counts_during_draw` (default off). When on, `AttackComponent2D` adds to the charge from the first frame, while `bow_draw` plays, instead of after it. `bow_draw` then hands off to `bow_charge` as before, and the bar, reach, stages and timing all read the same ratio.
- A release during the draw stops the count (`_release_pending`), so the shot fires when the draw ends at the ratio of the release (a tap shot is not stronger because it waited for the draw).
- `Bow_ArrowHeavy.tres` has it on. Full charge now arrives about one draw length (0.5 s) sooner; raise `charge_threshold` from 1.0 to 1.5 to keep the old total hold time.
- `reset_global_state()` turns it off on the heavy before each test part, because the older timing checks assume the charge starts after the draw.
