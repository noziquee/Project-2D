# R2: strict validation and data (Track R, written October 29, 2026; run in headless Godot 4.7.2 on a copy of the project)

Result: R1 alone gave 1658 passes / 7 failures; with R2 1676 / 2. R2 adds 13 checks (R2-1 to R2-13, in
`tests/h8_aim_checks.gd`, part `h8_aim`), all passing. The 2 left are `UUU7` and `H4-25`, which failed before Track R and are
not about range. The five range failures (H3-6, H3-10, H3-22, H8-104, H8-107) are fixed by the data change below.

## What changed
- **Skills.** `SkillDefinition2D._aim_shape_warnings()` now compares a shape that follows the action's reach (fan, line,
  self circle) with `get_reach()` and warns when they differ by more than 1 px (`SHAPE_REACH_TOLERANCE_PX`). It replaces the
  25% rule (`SHAPE_RANGE_TOLERANCE`, removed), which let Lunge (148 vs 120) pass. The message names both numbers and says the
  shape's own value is ignored in game. A placed circle and the camera view are never compared. A skill with no known reach
  (0) is skipped.
- **Attacks.** `AttackDefinition2D.get_warnings()` gains the same check, for an attack that sets both `attack_range` and a
  shape. A heavy attack that leaves `attack_range` at 0 takes its reach from the shape and cannot disagree with it.
- **Data.** Power Shot's strip 150 to 300, Multi Shot's fan 150 to 300, Lunge's strip (120, the default) to 148. These are the
  numbers R1 already draws in game, so nothing changes on screen; the files now say the same thing.
- **Ground Slam** (`Data/Examples/WeaponSkills/Sword_GroundSlam.tres`, not on a shipped weapon) gets a line shape, 72 px long
  and 80 px wide: the area's 40 px radius centred 32 px ahead ends 72 px from the caster, and the strip covers its width.
- **Audit.** `tools/range_audit.py` prints each reach, lists every `MISMATCH` (a following shape more than 1 px from the reach, or
  a damage skill with no shape) and exits 1 if there is one. Before the data change it reported 4 (Ground Slam, Multi Shot,
  Power Shot, Lunge); now 0.

## Tests edited
- `H8-98` said a reach 20% off was inside the tolerance; it now expects a warning.
- `H8-95` builds an area skill with no attack, whose `get_reach()` is 0, so nothing was compared; it now gives the skill an
  attack.
- `EEE62` (`tests/smoke_checks.gd`) copies Ground Slam into a SELF skill. SELF needs a shape that ignores direction, so the
  copy now clears the shape, which is also what a real SELF variant would have to do.

## G8: `optional-heavy-reach-100/` is stale
It is byte-identical to the last committed `Sword_HeavySlash.tres` (`angle_degrees = 100`, `max_range = 100`), so it adds
nothing the shipped file did not already have. Your working copy sets the fan to 25 degrees, so copying the optional file in would
only undo that choice. Safe to delete: `git rm -r optional-heavy-reach-100`. Not deleted here.

## For R3
`Bow_MultiShot.tres`'s inner attack has `attack_range = 150` and `projectile_speed = 100`, while the skill's `max_range` is 300.
Skill projectiles take their travel from the skill, so this does not matter today, but R3 (attack projectile lifetime =
reach / speed) must not apply to attacks that belong to a skill, or Multi Shot would stop at 150.
