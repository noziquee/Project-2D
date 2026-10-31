# R6: docs and the H2.6 handoff (Track R, written October 29, 2026)

Status of Track R: R0 to R2 done and run (1676 / 2). R3, R4 and R5 are written but NOT RUN (no Godot was available). The design
document is now `Attack-and-Skill-Range-Architecture-r4.docx`.

## Before H2.6 starts
1. Run `tools/run_checks.sh` and fix anything new from R3 to R5 (expected: R2's total plus 38 checks, `UUU7` and `H4-25` still failing).
2. `git rm -r optional-heavy-reach-100` (G8: identical to the committed `Sword_HeavySlash.tres`).

## What H2.6 must not break
Track R touches no field names. H2.6 renames `max_range` by behavior (decision D8). Places that read `max_range` or
`attack_range` in code: `player.gd`, `AimShape2D` and its five subclasses (`Line`, `Fan`, `CircleSelf`, `GroundCircle`, `View`),
`AimIndicator2D.gd`, `SkillComponent2D.gd` (`projectile_flight_time`, `dash_duration`), `SkillDefinition2D.gd` (`get_reach`, the
1 px warning), `ProjectileEffect2D.gd` (reach cap via `attack_range`), `AttackDefinition2D.gd` (`get_reach`, warnings), and 8
`.tres`/`.tscn` resources. `tools/range_audit.py` reads the same names.

## After H2.6
- Rename the fields, migrate the resources, then re-run `python3 tools/range_audit.py`: it must still say `MISMATCHES 0`.
- Update the audit script's field names if they changed.
- The R1 to R5 checks (`tests/h8_aim_checks.gd`) assert reach numbers, so they should pass unchanged; any that break are
  reading an old field name.
- The roadmap's H2.6 exit line asks for a test that measures real travel distance: R5 only checks the numbers handed to the
  projectile and the dash. A frame-stepped measurement belongs to H2.6.
