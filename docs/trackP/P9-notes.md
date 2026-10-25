# P9 - charge aim, sticky facing, bow rest pose and settle blend

Written and run October 25, 2026 in headless Godot 4.7 (stable). Before P9: `SUMMARY passes=942 failures=0`. After: **`SUMMARY passes=973 failures=0`** (31 new checks: CA0 to CA5, DZ1 to DZ5, SF1 to SF5, BR1, BR2, SB1 to SB11 with SB6a and SB7a). One existing check was changed on purpose: P3 now waits for the settle blend (12 frames) before it expects the pivot at 0. No new errors or warnings in the run output.

## What it fixes
1. **Aim while charging.** `Character2D` now hands the live aim to `AttackComponent2D.update_charge_direction()` every frame while a charge runs, so `attack_direction` and `aim_direction` follow the mouse; `FacingComponent2D` then rotates the pivot and flips the sprite on its own. The swing direction is still read once more at release and stays locked during the swing.
2. **Dead zone.** `FacingComponent2D.facing_dead_zone` (default 0.15, about 9 degrees from straight up or down): an attack aim with `|x|` below it keeps the side the character already shows, so a mouse hovering above or below the character does not flicker the sprite. 0 restores the old behavior (any `|x|` above 0.001 flips).
3. **Sticky facing.** `sticky_facing` (default on): after an attack the character keeps facing the side it attacked toward until it moves horizontally. Off restores the revert to the last movement direction. This changes `FC5`'s story slightly: `movement_facing_direction` is still not overwritten by an attack (still checked by FC5); the sticky side is a separate value inside the component.
4. **Bow rest pose.** `Weapons/Bow.tscn`: the `RESET` clip and the node's default rotation are now 0.0873 rad, the same as the `idle` clip and the end of `bow_return` (they were -0.785). A cancel or interrupt used to snap the bow by about 50 degrees.
5. **Settle blend.** `settle_time` (default 0.15 s, 0 = snap as before). When a swing finishes or is cancelled or interrupted, `AttackComponent2D` emits the new `swing_ended(cancelled)` signal (before it stops the weapon clip, so the poses are still the ones on screen). `FacingComponent2D` then blends, with a smoothstep ease:
   - the weapon pivot from its current angle to 0 by the shortest angle (`lerp_angle`);
   - the weapon hand (`context.weapon_pivot`) from its current position and rotation to the first keys of the weapon's own `idle` clip (the clip is only read; no code plays it). A weapon with no `idle` clip or tracks gets the old `RESET` snap.
   While a hand blend runs `context.hand_settling` is true; `AttackComponent2D.cancel()` (and a swing with no return clip) then calls `stop(true)` to keep the pose and skips its `RESET` snap. A new swing or charge ends the blend. Death calls `FacingComponent2D.snap_to_rest()`: pivot at 0 and hand at the idle pose at once.

## What changed in the project
- `AttackComponent2D.gd`: `swing_ended(cancelled)` signal, `update_charge_direction(direction)`, the `RESET` handling above.
- `CharacterContext2D.gd`: `hand_settling`.
- `Character2D.gd`: tracks the charge aim each frame; calls `snap_to_rest()` on death instead of `update_weapon_aim()`.
- `FacingComponent2D.gd`: the three fields, the dead zone, the sticky side, the blend, `snap_to_rest()`, `is_settling()`.
- `Weapons/Bow.tscn`: rest pose.
- `tests/smoke_checks.gd`: the new checks (`run_p9_checks()`), an `AimedPlayer` test class whose aim is a test value, and the P3 wait.

## Things to know
- What is not changed (step 4 of the plan, left for after you try this): the pivot still jumps to the aim on the first frame of a swing, and the weapon does not follow the mouse at rest.
- The blend is numerically smooth in the tests (largest pivot step 0.26 rad per frame for a 90 degree return, largest hand step 0.32 rad for a 110 degree return); whether 0.15 s feels right is only something you can judge in the game. It is one field on each `FacingComponent2D`.
- Sticky facing and the dead zone apply to goblins too, because they use the same component (their facing after a swing now stays toward the target).
- Run `godot --headless --import --path .` once after pulling, as for P8.
