# Phase V2b: the extra goblins, stale checks, and the weapon scene root name

Not run after these edits (no Godot in the editing environment). Run the smoke test and paste the `SUMMARY` line and every `CHECK FAIL` line.

## Starting point

After V2a your run gave `SUMMARY passes=590 failures=17`. A run just before it gave 589 / 18, and `H-player 6`, `H-player 7` and `U14` failed in one run and passed in the other. Checks that pass in one run and fail in the next point to something random in the arena, not to a bug in the checked code.

Failures at the start of V2b: `L6`, `M3`, `O7`, `R19`, `S15`, `S20`, `BB2`, `HH10`, `HH11`, `II12a`, `II12b`, `JJ1b`, `JJ4d`, `JJ5f`, `KK4d`, `PP2e`, `QQ4`.

## The main finding: eight goblins the checks do not know about

`Main.tscn` is the playable arena and holds **nine** goblins (`BasicEnemy2D` to `BasicEnemy2D9`). The smoke test was written for one. It disables `BasicEnemy2D` and ignores the rest, and some of the others stand inside the 200 px detection range of the player. They chase and hit the player at random times (the AI picks its attack with a random weighted choice). The V2a failure texts show it:

- `HH10`: the player was **stunned** (a goblin had just hit it).
- `R19`: the bar showed 56 of 60, which is 4 damage, a goblin slash (1) plus a lunge (3). The clip was `hit` in one run and empty in the next.
- `O7`: six frames of impact effects with an attack that spawns none (a goblin hitting the player).
- `PP2e`: a leftover `slash` effect after the heavy swing (the goblin's).
- `L6`: the recorded hitbox mask was 3 for two of three layers, which is the goblin's default `hit_layers`, not the player's.
- `S15`, `HH11`: the same cause (a stunned player refuses to attack).

My V2a guesses for these (timing and cooldowns) were wrong, and the diagnostics I added did not find the cause. The text of the failure messages you pasted did.

### Fix
`tests/smoke_checks.gd`: a new `load_main()` helper instantiates `Main.tscn` and frees every `BasicEnemy2D` except the one named `BasicEnemy2D`, before the scene enters the tree. All four places that instantiated Main now call it. The game scene is unchanged: the arena keeps its nine goblins.

## Other fixes

| Check | Cause | Change |
|---|---|---|
| `JJ1b`, `JJ4d`, `JJ5f` | `Weapons/Sword.tscn` had its root node named `Sword`. The 9.7b notes and the checks expect `MainHand`. The player instance is named `MainHand` in `player.tscn`, so the game worked either way. | Root renamed to `MainHand` (one line in the scene file). |
| `QQ4` | Real gap in the dry run. `WeaponController2D.validate_equip()` did not report an attack with **no** `effect_scene`, although `AttackComponent2D` rejects it. A weapon with such an attack would pass the dry run and then fail inside `equip()`. | `validate_equip()` now reports it, naming the weapon and the attack. |
| `II12a`, `II12b` | The messages say `... has next_attack 'x', which is not part of this weapon`; the checks looked for `next_attack 'x' is not part of ...`. | The checks look for the real wording. |
| `KK4d` | The "valid weapon" used the shipped light attack, whose `next_attack` (`player_light2`) leaves a one-attack weapon, which is correctly reported. | The weapon uses a link-free variant of the light attack. |
| `S20` | Since 9.7c-4 the player's `WeaponController2D` equips the sword at startup and replaces `attacks`. | The test instance gets no starting weapon, because the check is about the component's own list. |
| `M3` | `player.tscn` sets `move_speed = 100` on purpose (check `I21` relies on it); `M3` still expected the script default 200. | `M3` expects 100. |
| `BB2` | It required the heavy attack to slow movement (`movement_multiplier < 1`), but `PlayerHeavyAttackDefinition.tres` sets none (1.0), and `BB3b` already expects 1.00. | `BB2` requires only that the heavy never moves the player faster than the light attack. |

## A design decision for you
`BB2` showed that the heavy attack does not slow the player while it swings, although the guide and the old check assumed it would. I kept the data as it is. If you want a slow heavy, set **Movement Multiplier** (for example 0.4) on `PlayerHeavyAttackDefinition.tres`; `BB2` and `BB3b` (which expects 1.00 today) would then need the number updated.

## Expected result
No check was added or removed: 607 checks. If the analysis is right, **`SUMMARY passes=607 failures=0`**. If something fails, paste its `CHECK FAIL` line. A check that fails only sometimes is no longer expected, because the random goblins are gone from the tests.

## Not done
- V1 (open the project) and V3 (play-test) are still yours. The play-test also covers the nine-goblin arena.
- When failures are 0 the total goes into `docs/phase9/PLAN.md` as the baseline (V2 "done when").
