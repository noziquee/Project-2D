# DE3: warning before an enemy skill

Written October 30, 2026 **without running Godot**. Phase F, first part (telegraphs beyond the attack lane). 5 new checks, D3-1 to D3-5, in part `enemy_ai_skill`.

## What changed

- `EnemyBehaviorProfile.skill_windup_duration` (0 = cast at once, the default, so nothing changes until you set it).
- `EnemyAIController2D`: after it chooses a skill, and while the skill stays usable, it shows the skill's own `aim_shape` as a warning for that long, then casts. If the skill stops being usable, the target is lost, the enemy is stunned or starts another action, the warning is dropped and nothing is cast. `get_skill_telegraph_outline()`, `is_skill_winding_up()` and `last_skill_decision` ("winding up 'x' (0.20 of 0.50 s)") give debug output.
- The warning is the skill's aim shape drawn at the skill's real reach (`with_reach(get_reach())`), the same geometry the player's aim preview uses, so it matches what the skill can hit. Fan, circle and line shapes work.
- `EnemyAttackTelegraph2D` gained `show_shape(points)` and `get_shape_points()`; `hide_lane()` clears it. The attack lane is unchanged.

## Checks

| Check | Pins |
|---|---|
| D3-1 | duration 0.5: a polygon warning of 3 or more points is shown before the cast |
| D3-2 | the first cast waits (frame 20 or later) |
| D3-3 | the skill is cast once the warning has run |
| D3-4 | the warning is gone after the cast |
| D3-5 | duration 0: cast at once, no warning |

## Not done

- A ground circle (placed shape) and skills with no aim shape (buffs) show no warning and cast at once: the placed centre the enemy would use is not defined for the AI yet, and a wrong warning is worse than none. Needs your decision on where an enemy places a ground circle.
- Dash skills show their line shape; their strike circle at the end is not drawn.
- Target switching rule and shipped-profile values (`skill_windup_duration` is 0 in all four) are still open.

## Decision DE4 (October 30, 2026): where an enemy puts a ground circle

On the target's position, held inside the shape's `max_range` (`GroundCircleAimShape2D.place_on(origin, target_position)`). **Not built yet, and it cannot be yet:** `SkillComponent2D` does not cast at a ground point today (`_place_effect` uses the attack origin; no shipped skill uses a ground circle; see `docs/trackH/H8.8b-notes.md`, "Hook a skill to it"). Once a skill can be cast at a point, the enemy path is: `get_skill_telegraph_outline()` returns `get_area_outline()` moved to the `place_on` centre, `_try_use_skill` passes that same centre to the cast, and the warning and the hit use one point. Until then a ground-circle skill shows no warning and an enemy does not use one (its reach rule would be wrong).
