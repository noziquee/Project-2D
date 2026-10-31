# E2: repositioning (preferred combat range)

Written October 30, 2026 **without running Godot**. Phase E. 5 new checks, E2-1 to E2-5, in part `enemy_ai_profiles`.

## What changed

- `EnemyBehaviorProfile.preferred_combat_range` (0 = off, the default). While an enemy is inside its attack range but cannot attack yet (reload, pacing interval, waiting), it walks sideways around its target, switching side every 1.5 s, and drifts toward this distance. The distance is held at most 95% of the attack's range, so the enemy can still shoot. `minimum_combat_range` still makes it back away when the target is closer than that, so the two together give a band: retreat below the minimum, hold the preferred distance, shoot up to the attack range.
- `EnemyAIController2D._reposition_intent()` and `_is_free_to_move()` (no swing, cast, dash, charge, wind-up or stun). The side is chosen once from the controller's seeded `rng`.
- `RangedSkirmisherProfile` now sets 85 (minimum 60) and `TacticalCasterProfile` 90 (minimum 80). No scene uses these profiles yet, so no enemy behaves differently until you assign one.

## Checks

| Check | Pins |
|---|---|
| E2-1 | a goblin that cannot attack yet ends within 12 px of the preferred distance |
| E2-2 | it walks at least 0.5 rad around the player meanwhile |
| E2-3 | it never leaves its attack range |
| E2-4 | preferred_combat_range 0: it stands still |
| E2-5 | skirmisher and caster prefer a distance above their retreat distance |

## Not done

- `maximum_combat_range` was not added: the attack's own range is the maximum an enemy attacks from, so a second number would have nothing to control.
- No avoidance of walls or other enemies while repositioning; no flee-when-low-health rule.
- The caster's attack range depends on its weapon; if that is short, the 95% cap pulls the preferred distance in.
