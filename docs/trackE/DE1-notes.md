# DE1: enemies use self buffs

Written October 30, 2026 **without running Godot**. Decision DE1 (buff and support skills in scope). 4 new checks, D2-1 to D2-4, in part `enemy_ai_skill`. Expected: the suite total from your last run + 4.

## What changed

- `EnemyAIController2D._skill_problem()`: a `BUFF` skill is no longer set aside. After `SkillComponent2D.can_use()` accepts it (cooldown, mana, state), it is used when the buff's `status_effect` is not already running on the enemy (`status_controller.has_status(id)`). A buff has no reach, so the reach and range tests do not apply to it. `NONE` skills are still ignored.
- It reuses the existing path: the `skill_usage_priority` roll once per usable skill, `try_use_skill()`, and `last_skill_decision` for the reason ("buff already running", "not enough mana ...").
- Doc comments updated in `EnemyAIController2D.gd` and `EnemyBehaviorProfile.gd`. No weapon data, skill component or status code changed.
- Tests: `goblin_skill_run()` takes optional `skill_path`, `mana_value` and `pre_applied`; existing calls are unchanged.

## Checks

| Check | Pins |
|---|---|
| D2-1 | priority 1, Sword Empower: cast once on the goblin itself while it has a target |
| D2-2 | status already running: not cast again; reason says "buff already running" |
| D2-3 | no mana: not cast; reason names mana |
| D2-4 | priority 0: never cast |

## Not done (support skills)

There is no ally-targeted skill behavior in `SkillDefinition2D` (behaviors are PROJECTILE, AREA, DASH, BUFF, NONE; targeting is AIM_DIRECTION or SELF), so "support" today means self buffs. Healing or buffing an ally needs a new skill behavior and target selection; that is a separate decision.

## Next

DE2, group attack slots (`docs/trackE/E0-audit-and-status.md`).
