# R1: shapes follow the action's reach (Track R, written October 29, 2026; run in headless Godot 4.7.2 on a copy of the project)

Result: baseline full suite 1641 passes / 7 failures; with R1 1658 / 7. The same 7 checks fail before and after (listed
below); R1 adds 17 checks (R1-1 to R1-17, in `tests/h8_aim_checks.gd`, part `h8_aim`), all passing, and changes no
existing result.

## What was wrong
The aim indicator's circle used the action's `get_reach()`, but the strip or fan was the aim shape's own `max_range`, and the
target assist tested that same number. So Lunge drew a 120 px strip inside a 148 px circle (a 28 px gap), Power Shot 150
inside 300, Multi Shot's fan 150 inside 300, and the assist looked only as far as the shape.

## What changed
- `AimShape2D.with_reach(reach)`: returns the shape itself when it already has that reach, when no reach is given, or when
  the shape does not follow the action's reach. Otherwise it returns a copy with `max_range = reach`. The shared resource
  is never edited. Copies are kept per reach (at most 8) so the same reach gives the same object (the indicator and the
  tests compare shapes by identity), and each copy is refreshed from the shape on every call, so later edits are not missed.
- `AimShape2D.follows_action_reach()`: false by default. `FanAimShape2D`, `LineAimShape2D` and `CircleSelfAimShape2D`
  return true. `GroundCircleAimShape2D` (its range is only the cast distance) and the camera view keep their own values.
- `player.gd`: `_heavy_assist_shape()` and `_skill_assist_shape()` return the shape at the definition's `get_reach()`. The
  indicator, the target pick, the candidate rings and the cast direction all read these, so the picture and the assist agree.
- `tests/h8_aim_checks.gd`: H8-114 now expects the shape at the skill's reach (it compared by identity with the raw shape);
  17 new checks.

## Differs from the design doc
The doc proposed an optional reach argument on each shape method. A copy through `with_reach()` touches five scripts
instead of every method on six shapes (including `ViewAimShape2D`'s overrides) and leaves existing calls alone. R4 (charge
scaling) will call it every frame with a changing reach; the copy cache is capped at 8, so that stays cheap.

## Behaviour change to look at in play
The assist now looks as far as the real reach: Lunge out to 148 px (was 120), Power Shot and Multi Shot out to 300 px
(was 150). That is the intended fix, but it changes target picking for those three skills.

## Still failing (the same 7 before and after)
UUU7, H3-6, H3-10, H3-22, H8-104, H8-107 and H4-25. Five of them (H3-6, H3-10, H3-22, H8-104, H8-107) report the validation
warning that Power Shot's shape (150) differs from its `max_range` (300); R2 fixes that in data. UUU7 (an arrow hit-once
check) and H4-25 (an unexpected logged error) are not about range and were already failing in the archive.

## Not done here
Data and validation (R2), attack projectiles and the melee gate (R3), charge scaling (R4). No `.tres` file is touched.
