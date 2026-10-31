# C3: heavy attacks judged by where the target will be

Written October 30, 2026 **without running Godot**. Phase C. 2 new checks, C3-1 and C3-2, in part `enemy_ai_heavy_wait`.

## What changed

- `EnemyAIController2D._opening_reason()` now has a fourth reason after "stunned", "committed to a swing" and "nearly still": `_predicted_hit_reason()`. It moves the target by its velocity over the attack's `charge_threshold`, and the heavy goes ahead when that spot is inside the lane the attack will cover (from the enemy along its aim, up to the attack's `get_reach()`, `hitbox_size.y` wide plus 8 px for the target's body). A target walking along the lane or toward the enemy is therefore hit; one that would end outside the reach or off to the side is not.
- It only matters when `heavy_wait_for_opening` is above 0 (at 0 the heavy always starts, as before). No new profile field: the charge time, reach and width come from the attack definition, so the weapon still owns the heavy's behavior.
- `last_heavy_decision` names the prediction ("target predicted inside the lane (45 of 60 px along, 0 px across)").

## Checks

| Check | Pins |
|---|---|
| C3-1 | target walking along the lane (ends 45 px away, reach 60): heavy charged, reason names the prediction |
| C3-2 | target predicted to end 75 px away (reach 60): no heavy, the other attack is used after the wait |

C2-1 to C2-5 are unchanged; a target moving sideways at 200 px/s still gets no heavy (it ends far off the lane).

## Not done

- `heavy_attack_priority` was not added: nothing in the checks needs it. Add it when tuning shows enemies using heavies too rarely or too often.
- The prediction assumes constant velocity and ignores walls and the target's own dodges; the lane is the current aim, not a re-aim during the charge.
