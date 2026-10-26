# P2.1 and P2.2 - exported rig paths

Written and run in headless Godot 4.7.2, October 25, 2026.

## What changed

- `Character2D` has a new **Rig** group of five `NodePath` exports: `visual_root_path`, `locomotion_player_path`, `animated_sprite_path`, `weapon_facing_root_path`, `weapon_pivot_path`. All are empty in the shipped scenes, so nothing in `player.tscn` or `BasicEnemy2D.tscn` changed.
- `CharacterContext2D._init` takes them as optional arguments (the existing `CharacterContext2D.new(body)` calls still work). A path that is set wins over the default name. Empty paths give exactly today's lookups (`LayeredRig`, `PlayerAnim`, `WeaponFacingPivot`, `WeaponFacingPivot/MainHand`, `AnimatedSprite2D`, `AnimatedSprite2D/Weapon`).
- A rig with a visual root (set, or named `LayeredRig`) gets the player-style defaults for the rest; any other rig gets the goblin-style ones. This is the same split as before, just not hard-wired to one node name.
- A set path that does not resolve warns (`rig path '...' does not resolve`) and leaves that reference empty. It never falls back to a default name.
- With no `weapon_pivot_path`, a player-style rig still searches the facing root for the first weapon scene, as before.
- `WeaponController2D` needed no change: its mount already follows `context.weapon_facing_root`.

## Checks (8, `run_p2_checks`, P2a to P2h)

Shipped player and goblin rigs unchanged (P2a to P2c), a third layout with none of the default names (P2d, P2e), an unresolved path does not fall back (P2f), the sprite layout with renamed nodes (P2g), and `Character2D` passing its exports to its context (P2h).

**Result: the 8 checks pass on their own (`SUMMARY passes=8 failures=0`).** Expected after the full suite is repaired: previous total + 8 (1030 + 8 = 1038).

## P2.2 - the last name lookup on the rig

`ReactionComponent2D`, `FacingComponent2D` and `WeaponController2D` already read the rig through the context, so nothing changed there. The one remaining rig name in game code was `BasicEnemy2D`'s `$AnimatedSprite2D`; it now uses `context.animated_sprite`, so a goblin whose sprite has another name works once `animated_sprite_path` is set. New check **P2i** renames the goblin's sprite to `Body` and wires it through `animated_sprite_path`, `weapon_pivot_path` and the controller's `weapon_mount`; it plays idle with no node-name lookup.

Left on names on purpose: component children (`EnemyAIController2D`, `DetectionArea`, `AttackSpawnPoint`), which already resolve by export-or-default-name, and are not rig nodes.

## Not yet

P2 is done: its "done when" (a layout that copies no default node name) is met by checks P2d, P2g and P2i. The weapon player has no path on purpose: it is read from whichever weapon is mounted.

## Not in P2.1

The weapon's `AnimationPlayer` has no path: it is read from whatever weapon is mounted. Next sub-steps: P2.2 point `ReactionComponent2D` / `FacingComponent2D` lookups at the same paths if any still use names; P2.3 a real third character scene as the "done when" proof.

## Track W repair: the first real run of the full suite (Oct 26)

Godot 4.7.2 headless, import clean. The first run of the code as uploaded stopped at 329 passes / 27 failures and aborted. After the repairs below the suite runs to the end: **1096 passes, 13 failures** after P2.2, P3.1, P4, P5, P6 and P7 (the 9 P2, 4 P3, 4 P4, 4 P5, 7 P6 and 6 P7 checks pass). Root causes, in the order found:

| Cause | Checks | Fix in this zip |
|---|---|---|
| The test mode `set_clip_returns(true)` renames the return clips on `Sword_Slash1/2`; the goblin now shares those, but its sword scene has no such clips, so its weapon was refused | ~25 goblin checks + the abort | Harness adds/removes those two clips on the GoblinSword library in memory (needs a held reference or the cache drops it) |
| `Sword_Slash1` had no `ai_attack_range`; the goblin's old slash had 60, so the AI fell back to its 30 default | I3, V2 | `ai_attack_range = 60` on `Sword_Slash1` (AI-only field, the Bow already does this; no effect on the player) |
| Goblin now has a weapon controller (W5d) | NN2a | Check now expects one |
| The goblin's slash is the sword's, which is not interruptible (the old goblin slash was); the lunge is | X11 | Check uses the lunge. **Gameplay change to confirm:** a hit no longer cancels the goblin's slash |
| `Bow_WeaponDefinition.tres` in the working tree had an inline copy of the arrow attack (id `arrow_shot`, made in the editor) instead of `Bow_ArrowShot.tres` (`bow_arrow_shot`) | XX5, XX7pre, YY5 | Restored the reference, removed the inline copy |
| `bow_draw` is 0.5 s in `Bow.tscn`; checks waited 40 frames or released the charge during the draw (the shot then follows the mouse) | XX7, XX9, XX10 | Longer waits; wait out the draw before releasing |
| Archer's `Weapon` is now the Bow scene root, not a sprite | ZZ4 (script error, ended the run) | Check compares the scene path |
| `load_main()` frees every `BasicEnemy2D`, which includes `GoblinArcher` | WA1 | New `fresh_with_archer()` for the W6 checks |
| The archer's exported `attack_definition` stays the slash it starts with; the live one is `.definition` | WA7 | Check reads `.definition` |
| Ground Slam is expected at `Data/Examples/WeaponSkills/` but only the old copy existed; the legacy goblin attack resources were still present | EEE51 (script error), WX1, WX2, GS13 | File added at the new path (delete the old one by hand); WX thresholds 12 to 11; legacy files removed (delete by hand) |

## Still failing: two decisions for you (13 checks)

1. **Sword skill loadout (9 checks: HHH2 to HHH5, TTT3, TTT4, TTT9, UUU3, WZ3).** `Sword_WeaponDefinition.tres` in the working tree lists Empower, Ground Slam, Lunge; the committed one (and every check) has Lunge, Spin, Empower. Ground Slam is documented as an example that is not in the default loadout. If the swap was intended, those checks need updating; if not, restore Spin.
2. **Bow draw time (4 checks: BC23, BC34, BC41, BC42).** `bow_draw` is 0.5 s (committed with Track W5c); `docs/bow-cycle-notes.md` and the cycle checks assume 0.167 s (four taps a quarter second apart giving four arrows, five arrows in 2 s). If 0.5 s is the feel you want, those checks need new timings; if not, set the clip length back.

Run it yourself: `godot --headless --import --path .` then `godot --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd`.
