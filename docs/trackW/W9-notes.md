# W9 - Track W run and the two decisions

Run in headless Godot 4.7.2, October 26, 2026. Import clean. **`SUMMARY passes=1109 failures=0`.**

## Decisions (from you)
1. **Sword loadout: keep what is in the files.** `Sword_WeaponDefinition.tres` in this archive lists Empower, Spin and Lunge. The checks HHH2 to HHH5, TTT3, TTT4, TTT9, UUU3 and WZ3 pass against it unchanged, so no check was edited for this. Ground Slam stays an example in `Data/Examples/WeaponSkills/` and is not equipped.
2. **Bow draw time: keep 0.5 s** (`bow_draw` in `Bow.tscn`).

## Checks retimed for the 0.5 s draw (only `tests/smoke_checks.gd` changed)
A cycle is now the 0.5 s draw plus the shot, about 0.9 s. The assertions are not loosened; the waits match the feel.

| Check | Was | Now |
|---|---|---|
| BC23 | click every frame for 2 s, at least 5 arrows (got 3) | same rule over 5 s (300 frames), at least 5 arrows, 0 returns |
| BC34 | the recording starts 25 frames into the draw, so the clip list opens with `bow_draw` | expects `bow_draw`, `bow_heavy_shoot`, `bow_draw`, `bow_shoot` and 2 arrows |
| BC41, BC42 | four taps 15 frames apart, record 200 frames | four taps 45 frames (0.75 s) apart, record 300 frames; each tap lands in the previous shot's combo window; still four arrows as draw > shoot x4, and the bow returns only after the last shot |

## Still open
- The goblin's slash is the sword's slash, so a hit no longer cancels it (it did with the old goblin slash). Confirm in play.
- Bleed does nothing to goblins until `BasicEnemy2D.tscn` gets a `StatusController2D` child (see `docs/phase14/14.3-notes.md`).
- Ground Slam is not in any loadout.
- The V3 play-test and your own editor run.
