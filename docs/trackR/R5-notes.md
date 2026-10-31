# R5: skill range tests (Track R, written October 29, 2026; NOT RUN: no Godot was available; R3 and R4 are not run either)

Run `tools/run_checks.sh`. Expect R4's total plus 15 new checks (R5-1 to R5-15, `tests/h8_aim_checks.gd`, part `h8_aim`).

## What changed
- Two small refactors in `SkillComponent2D` so the numbers can be tested without spawning anything; behavior is the same:
  `projectile_flight_time(skill, scene_speed)` (max_range / speed, the attack's speed or the scene's, floor 0.05 s, 0 = no limit
  asked) and `dash_duration(skill)` (max_range / dash_speed, floor 0.05 s). `_execute_projectile` and `_execute_dash` call them.
- Tests: Power Shot travels 300; Multi Shot travels its skill's 300, not its inner attack's 150; a linked attack's `attack_range`
  (40 or 900) never changes a skill projectile's travel; scene speed fallback; guards for no speed and a tiny range; Lunge dashes
  120 while its reach is 148 (strike radius 28); a dash with speed 0 stays finite; a placed area's reach is placement range plus
  radius, and changing one never changes the other; Sword Spin's circle, reach and radius are all 52.

## Not covered
Real flights and dashes in a running scene (distance travelled in physics frames) are not measured; the checks assert the numbers the
component hands to the projectile and the dash. A frame-stepped test is worth adding once the suite is green on your machine.
