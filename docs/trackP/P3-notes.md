# P3.1 - locomotion clip names

Run in headless Godot 4.7.2 (Oct 26, 2026). Full suite: 1075 passes, 13 failures (the same 13 as in `P2-notes.md`); the 4 P3 checks pass.

## What changed

- `Character2D` has two new exports in the Rig group, `idle_clip` and `run_clip` (defaults `idle` and `run`). They are copied onto the `CharacterContext2D` as `idle_clip` and `run_clip`.
- `IdleState`, `MoveState`, `DashState`, `AttackState` and `BasicEnemy2D` play `context.idle_clip` / `context.run_clip` instead of the literal names. A missing clip behaves as before (nothing plays).
- Nothing in the shipped scenes changed.

## Left as is, on purpose

- The weapon's `RESET` clip (`AttackComponent2D`) and its `idle` rest-pose clip (`FacingComponent2D`) are a convention of each weapon scene, not of the character, so they are not exports on `Character2D`. `ReactionComponent2D` already exports its reset clip.
- No `CharacterAnimationSet` resource: two names did not justify one. If a third clip name (for example `walk` for a slow move) is ever needed by the states, that is the point to introduce it.

## Checks (P3a to P3d)

Defaults carried onto the context, shipped player and goblin idle on `idle`, a goblin told `idle_clip = run` starts on `run`, and its idle state keeps playing it.
