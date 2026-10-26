# P4 - team targeting

Run in headless Godot 4.7.2 (Oct 26, 2026). Full suite: 1079 passes, 13 failures (the same 13 as in `P2-notes.md`); the 4 P4 checks pass.

## What changed

- `EnemyAIController2D` no longer has `target_group`. A body becomes a candidate when it is a `Character2D` whose `team` is not empty and is not the enemy's own team (`_is_hostile`).
- Neutral characters (empty team), plain bodies, the enemy itself and its own team are never targets. A new faction needs only a new team name on the character, and the `DetectionArea` mask still filters by layer.
- The shipped scenes did not change: the player is team `player`, the goblins are team `enemy`.

## Checks (P4a to P4d)

No `target_group` left; the player and a third faction are hostile; the same team, a neutral character, a plain body and the enemy itself are not; and only hostile bodies entering the detection area become candidates.

## Left open

The `player` and `enemy` groups are still used by the HUD, and `damageable` is still the opt-in on a hit target (P5 removes that one).
