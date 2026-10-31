# E3: simple common profile, target switching, attack pick report

Written October 30, 2026 **without running Godot**. Closes the Track E items that did not need a new skill behavior. 8 new checks, E3-1 to E3-8, in part `enemy_ai_profiles`.

## What changed

- `Profiles/SimpleCommonProfile.tres`: one swing at a time (wind-up 0.4 s, interval 1.5 s); no combo, heavy wait, skills, spacing or switching. Everything else stays at the defaults.
- `EnemyBehaviorProfile`: `target_switching` (`KEEP_CURRENT` default, `NEAREST`), `target_switch_margin` (40 px), `target_switch_min_interval` (2 s).
- `EnemyAIController2D._maybe_switch_target()`: with `NEAREST`, changes to a hostile at least the margin closer, at most once per interval, and only while the enemy is free to move and holds no attack slot. A swing, combo, charge, wind-up or slot is never dropped for a new target. `last_target_decision` says "switch 'a' -> 'b'" or why it kept the target.
- `_pick_attack()` now fills `last_attack_candidates`: one line per `attack_choices` entry ("candidate, weight 1.0", "rejected, weight 0", "rejected, charges (heavy skipped)", "rejected, not registered ...", "rejected, no attack set") and a final "picked: id". This is the rejected-candidate debug output the design doc asks for.

## Test fix

`run_enemy_ai_profiles_checks()` used `skirmisher` and `caster` in E2-5 before they were declared further down. GDScript treats that as a compile error, which would have stopped the whole suite from loading. E2-5 now sits after the declarations.

## Checks

| Check | Pins |
|---|---|
| E3-1..3 | the simple profile loads, keeps to one swing with no skills or spacing, and does not switch targets |
| E3-4, E3-5 | the pick report lists every entry, ends with the pick, and names why entries were rejected |
| E3-6 | `KEEP_CURRENT`: stays on the far target when a nearer one appears |
| E3-7, E3-8 | `NEAREST`: switches once to the clearly nearer target, and the reason says so |

## Not done

- **Support / commander profile**: needs an ally-targeted skill behavior (see `DE1-notes.md`). Left for a separate decision.
- Skills still do not take attack slots; shipped profiles do not set `target_switching`, `max_simultaneous_attackers` or `skill_windup_duration`.
- The rejected list covers attack picks only; skill rejections are still in `last_skill_decision`.
