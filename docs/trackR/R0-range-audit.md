# R0: range audit (Track R, written October 29, 2026; no game code changed)

Source: every attack and skill `.tres` under `Weapons/` and `Data/`, read by `tools/range_audit.py`, plus the code paths
named below. "Indicator circle" is the radius `player.gd` passes to the aim indicator (`get_reach()`). "Strip / fan drawn"
is the aim shape's own `max_range`, which is what the indicator outlines before clipping it to the circle. A **gap** is
the part of the circle the shape does not fill; a **clip** is the part of the shape cut off by the circle. Nothing was
run in Godot for this audit; the numbers are computed from the resources with the same rules as `get_reach()`.

## Attacks

| Attack | Effect | attack_range | Shape (max_range) | get_reach | Real reach in game | Indicator verdict |
|---|---|---|---|---|---|---|
| `bow_arrow_enemy` | Bow_Arrow | 170 | none | 170 | projectile travels 240 px (speed 200 x 1.2 s scene lifetime), no range cap | light circle = attack_range |
| `bow_arrow_heavy` | Bow_Arrow | 0 | Line (150) | 150 | projectile travels 720 px (speed 600 x 1.2 s scene lifetime), no range cap | matches |
| `bow_arrow_shot` | Bow_Arrow | 120 | none | 120 | projectile travels 504 px (speed 420 x 1.2 s scene lifetime), no range cap | light circle = attack_range |
| `goblin_sword_lunge` | AttackSlash2D | 75 | none | 75 | slash driven to 75 px (H9.2) | light circle = attack_range |
| `sword_heavy_slash` | AttackSlash2D | 0 | Fan (100) | 100 | slash driven to 100 px (H9.2) | matches |
| `sword_slash1` | AttackSlash2D | 70 | none | 70 | slash driven to 70 px (H9.2) | light circle = attack_range |
| `sword_slash2` | AttackSlash2D | 70 | none | 70 | slash driven to 70 px (H9.2) | light circle = attack_range |

## Skills

| Skill | Behavior | max_range | area_radius | Shape (max_range) | get_reach | Real reach in game | Indicator verdict |
|---|---|---|---|---|---|---|---|
| `ground_slam` | AREA | 0 | 40 | none | 72 | circle radius 40 px, centre 32 px ahead | **no aim_shape, no indicator** |
| `multi_shot` | PROJECTILE | 300 | 0 | Fan (150) | 300 | projectile flies 300 px (lifetime = max_range / speed) | **gap 150 px** |
| `power_shot` | PROJECTILE | 300 | 0 | Line (150) | 300 | projectile flies 300 px (lifetime = max_range / speed) | **gap 150 px** |
| `empower` | BUFF | 0 | 0 | none | 0 | no area, no travel | no indicator (by design) |
| `lunge` | DASH | 120 | 0 | Line (120) | 148 | dash travels 120 px; strike radius 28 px | **gap 28 px** |
| `sword_spin` | AREA | 0 | 52 | CircleSelf (52) | 52 | circle of radius 52 px centred on the caster | matches |

## What the audit shows

1. **The arrow gap you reported is data plus a rule, not a drawing bug.** The indicator circle is `get_reach()`, but the
   strip is the shape's own `max_range`. Lunge: reach 148 (dash 120 + strike radius 28) against a 120 px strip, so a
   28 px gap. Power Shot: circle 300, strip 150, a 150 px gap. Multi Shot's fan is 150 inside the same 300 circle.
   Validation only warns beyond 25% (`SHAPE_RANGE_TOLERANCE`), and Lunge sits inside that tolerance, so nothing warns.
2. **Ordinary attack arrows are uncapped.** `Bow_Arrow.tscn` has lifetime 1.2 s, so a basic shot (speed 420,
   `attack_range` 120) flies about 504 px, the heavy arrow (speed 600, shape 150) about 720 px, the goblin's arrow
   (speed 200, `attack_range` 170) about 240 px. Only skill projectiles derive lifetime from `max_range`.
3. **Melee is already tied to reach.** H9.2 drives the slash's leading edge to `attack_range` (or `get_reach()` for the
   heavy). So the first version of the design doc was wrong to list light-melee reach as an open gap.
4. **Ground Slam has no `aim_shape`**, so it draws no aim indicator, although `wants_aim_shape()` says an AREA skill with
   an attack should have one. Its real reach is 72 px (32 offset + 40 radius).
5. **`optional-heavy-reach-100/`** differs from the shipped `Sword_HeavySlash.tres` only in `angle_degrees` (100 vs 25).
   The shipped fan is already `max_range = 100`, so the optional file no longer does what its notes describe and looks
   stale; check before copying it in.
6. **Overlap with the roadmap.** H2.6 (D8) already plans renaming `max_range` by behavior with a `.tres` migration. Track
   R should not rename fields; it should land before or alongside H2.6 and leave the rename to it.

## Not covered by this audit
Enemy `.tres` behaviour profiles and any resource outside `Weapons/` and `Data/`; `Bow_ArrowEnemy` and the goblin lunge
are listed but their AI use (`get_effective_attack_range`) is not measured. Scenes that override a projectile's lifetime
beyond `Bow_Arrow.tscn` were not found.
