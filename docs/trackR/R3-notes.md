# R3: attack projectiles and the melee reach gate (Track R, written October 29, 2026; NOT RUN: no Godot was available when this was written)

Status: written and unit-checked by reading only. Run `tools/run_checks.sh` (expect R2's 1676 / 2 plus 14 new checks, R3-1 to
R3-14, in `tests/h8_aim_checks.gd`, part `h8_aim`; `UUU7` and `H4-25` still fail as before). Replace this line with your result.

## What changed
- **Attack projectile lifetime (G4, RD2).** `ProjectileEffect2D._apply_reach_cap()`: when the attack hands over a reach and the
  projectile has a speed, `lifetime = min(scene lifetime, reach / speed)` (floor 0.05 s). `AttackComponent2D` already passed
  `get_reach()` to `configure()`, so no component change was needed. Basic shot (420, 120) now flies 120 px (was 504), heavy
  arrow (600, 150) 150 px (was 720), goblin arrow (200, 170) 170 px (was 240). Reach 0 or speed 0 keeps the scene's lifetime.
  `get_travel_distance()` reports speed x lifetime for tests.
- **Skills are untouched.** `SkillComponent2D` configures its projectile without a reach and sets its own lifetime from
  `max_range`, so Multi Shot's inner `attack_range = 150` / `speed = 100` cannot cut it off at 150 (check R3-8).
- **Melee reach gate (RD1).** `AttackSlash2D` computes a limit at start: `max(attack_range, starting leading edge) + 2 px`
  (`REACH_GATE_TOLERANCE_PX`). `_can_hit()` is false while `get_leading_edge()` is beyond it. A driven swing ends exactly at the
  reach, so this only bites when a clip moves the hitbox itself or the shape grows past the reach. No reach given (0): no gate.
- **Warnings.** `AttackDefinition2D._reach_cap_warnings()`: (RD3) a projectile attack with no reach; (RD1) a melee attack whose
  effect clip moves the hitbox by itself and whose static hit box ends more than 1 px short of `attack_range`.
  New helper `AttackSlash2D.scene_clip_moves_positions()`. Shipped attacks raise neither (R2-13 still holds).

## Things to watch when you run it
- The gate uses the live leading edge (current shape scale). If the heavy slash's scale overshoots its final 1.5 mid-window, the
  gate could reject a hit that used to land. H9-16 to H9-27 and the heavy-slash hit tests would show it.
- Enemy attacks with a projectile scene and no `attack_range` will now log the RD3 warning (warnings are never gated).
