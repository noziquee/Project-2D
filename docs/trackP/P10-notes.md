# P10 - code-driven return instead of return clips

Written and run October 25, 2026 in headless Godot 4.7 (stable). After P9: `SUMMARY passes=973 failures=0`. After P10: **`SUMMARY passes=986 failures=0`** (13 new checks, RT1 to RT12 with RT3b). No new errors or warnings in the run output.

## What it does
An attack can now end its swing with a **code-driven return**: `AttackDefinition2D.recovery_time` (seconds) with an optional `recovery_ease` (a `Curve` from 0 to 1, empty = smoothstep). It is used when `recovery_animation` is empty; a named return clip still wins, so the clip path is unchanged (the goblin archer still uses `bow_return`).

When the weapon clip ends, or the combo window closes with no press, `AttackComponent2D`:
1. emits the new `recovery_started(duration, ease)` signal (the poses are still those of the swing),
2. stops the weapon clip where it is (`stop(true)`, so the pose stays),
3. stays attacking for `recovery_time`: no attack, combo press or dash can start, and the cooldown starts when it ends, exactly as with a return clip,
4. `is_aiming_weapon()` is false during it, so the pivot can blend to 0.

`FacingComponent2D` blends the pivot (to 0, shortest angle) and the hand (to the first keys of the weapon's `idle` clip) over `recovery_time` with the curve. Its own `swing_ended(false)` at the end of the return is ignored, so there is no second blend. A cancel or interrupt during the return restarts a blend from the current pose over `settle_time` (no snap). Because the return starts from the pose the swing was actually in, cutting the swing at the combo window no longer jumps to the first key of a return clip.

## Shipped data
`DefaultAttackDefinition`, `PlayerLight2AttackDefinition`, `PlayerHeavyAttackDefinition`, `ArrowAttackDefinition` and `ArrowHeavyAttackDefinition` now have `recovery_animation = &""` and `recovery_time = 0.5` (the length of the clips they used, so attack timing is unchanged). The return clips (`sword_slash_return_1/2`, `bow_return`) are still in `Sword.tscn` and `Bow.tscn`, unused by the player; delete them once you are happy with how the interpolation feels.

## Tests
`set_clip_returns(true)` (in `smoke_checks.gd`) puts the old clip names back in memory at the start of the run, so every earlier check (I, BB, EE, HH, P9 ...) still exercises the clip path. `run_p10_checks()` switches to the shipped data and checks: shipped data (RT1), the recovery locks attacks for `recovery_time` and finishes once (RT2 to RT5), no frame jumps (RT6), ends at the idle pose without a second blend (RT7), cancel during the return (RT8), the ease curve (RT9), the cut at the combo window (RT10), and the bow (RT11, RT12).

## Things to know
- Feel is yours to judge: tune `recovery_time` and `recovery_ease` per attack in the `.tres`. A straight blend has no arc or overshoot; an ease curve is the lever for that.
- Position and rotation of the hand blend straight between the two poses; rotation takes the shortest way, so a swing that ends near 180 degrees from idle could turn the other way than a hand-authored return would. The sword and bow end poses (2.88 and -0.785 rad against 0.873 and 0.087) are well clear of that.
