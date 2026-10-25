# W4 - resource ids follow the file names

Written October 25, 2026 **without running Godot**. Q3 answered by you: ids follow the new file names. Rename of ids only: no file moves, no numbers, no clips. Two new checks. Expected: **`SUMMARY passes=988 failures=0`** (986 + 2). You will run one smoke test after Track W is finished; if the count is off then, find the first step whose notes do not match.

## Id renames (search-and-replace list)

| Old id | New id | File |
|---|---|---|
| `player_light` | `sword_slash1` | `Weapons/Sword/Attacks/Sword_Slash1.tres` |
| `player_light2` | `sword_slash2` | `Weapons/Sword/Attacks/Sword_Slash2.tres` |
| `player_heavy` | `sword_heavy_slash` | `Weapons/Sword/Attacks/Sword_HeavySlash.tres` |
| `arrow_shot` | `bow_arrow_shot` | `Weapons/Bow/Attacks/Bow_ArrowShot.tres` |
| `arrow_heavy` | `bow_arrow_heavy` | `Weapons/Bow/Attacks/Bow_ArrowHeavy.tres` |
| `goblin_arrow` | `bow_arrow_enemy` | `Weapons/Bow/Attacks/Bow_ArrowEnemy.tres` |
| `goblin_lunge` | `goblin_sword_lunge` | `Characters/Components/Combat/GoblinLungeAttackDefinition.tres` (the file moves and is renamed in W5) |

Kept on purpose:
- `goblin_slash` stays until W5, which deletes `GoblinAttackDefinition.tres` and uses `sword_slash1` instead.
- Skill ids (`lunge`, `sword_spin`, `ground_slam`, `empower`, `power_shot`, `multi_shot`) and the skill attack ids (`sword_spin_attack`, `multi_shot_attack`, ...) already carry no character name.
- Clip names (`sword_slash_1`, `bow_shoot`, ...) are unchanged. Nothing needed the standard names yet (the goblin shares the sword's attack only from W5), so none were added.

## What changed in the tests

Every old id in `tests/smoke_checks.gd` was replaced by its new id (about 150 lines). No assertion was loosened or removed; only the id text in checks, the messages and the `definition_variant(...)` calls changed. The AI profiles and the scripts do not name attack ids, so nothing else needed editing.

## New checks

- **WX1** scans every `.tres` in an `Attacks` or `Skills` folder under `Weapons/Sword` and `Weapons/Bow` and checks that no attack id, skill id or skill-attack id contains `player` or `goblin`.
- **WX2** checks that attack ids are unique across the sword, the bow and the two goblin knife attacks (those are added by path because they are not in a weapon folder until W5).

Difference from the W0 plan: WX1 scans only the sword and bow folders. The plan's id `goblin_sword_lunge` contains "goblin" by design (the goblin sword is its own weapon), so a scan that includes `GoblinSword/` would fail on it. W5 may extend WX1 to the `GoblinSword` folder with an exception for the `goblin_sword_` prefix.

## Files in the zip

Changed: `tests/smoke_checks.gd`, the six attack `.tres` files above, `Characters/Components/Combat/GoblinLungeAttackDefinition.tres`, `docs/Combat-Roadmap-Step-by-Step-Plan.md`, `docs/trackW/W0-plan.md`. New: `docs/trackW/W4-notes.md`. Nothing to delete.

## Next

W5: the `GoblinSword` weapon, `weapon_mount` on `WeaponController2D` and the goblin wired through it (expected 1002). It is the largest step in Track W, so I will build it in small increments.
