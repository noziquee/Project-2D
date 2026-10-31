# Track A: bow aim-follow (written October 29, 2026; NOT RUN: no Godot was available)

Run `tools/run_checks.sh`. Expect the previous total plus 35 new checks (A-1 to A-35, part `a_follow`, in `tests/smoke_checks.gd`), and no
change in any older check. Part alone: `tools/run_checks.sh --only=a_follow`.

## What changed
- **A1, data and component.** `AttackDefinition2D.aim_follow` (default off) and `aim_turn_speed` (degrees per second, 0 = instant).
  `AttackComponent2D.update_attack_direction(direction, delta)` turns the attack toward `direction`, capped by `aim_turn_speed`, and keeps
  `attack_direction` and `aim_direction` current. It acts from the start of the swing or draw until the first `spawn_effect`
  (`_effect_spawned`, cleared by every new swing and by `cancel()`), and for a heavy released while its draw is still playing
  (`_release_pending`; the draw's end then shoots along the followed `_charge_direction`). It does nothing for a held charge (that
  keeps following the live aim through `update_charge_direction()` as before), when idle, for a zero vector or for an attack with the
  flag off. Helpers: `is_aim_following()`, `is_release_pending()`. `cancel()`, `interrupt()` and the end of the attack end the follow.
- **A2, choosing the direction.** `Character2D._physics_process` calls `update_attack_direction(_get_attack_follow_direction(), delta)`
  every frame; the base returns zero, so enemies and every other controller are unchanged. `player.gd` overrides it:
  1. The activation (press of a light attack, release of a heavy) remembers the target it picked as a *candidate*
     (`_follow_candidate`). It becomes the *lock* only when an attack really starts (`attack_started`, or a release waiting for its
     draw). A click that is refused or queued during a running shot cannot take the lock away; a new attack always replaces it.
  2. Manual aim wins and stays for the rest of that shot (`_follow_manual`): a pushed stick, a touch drag (`_manual_aim`) or any mouse
     movement after the shot began.
  3. Else the direction from the player to the locked target (never re-picked).
  4. A locked target that dies or is freed ends the follow: zero is returned and the component keeps the last direction.
  5. No target and no manual aim: zero, the shot keeps its start direction (see the deviation below).
  All of it resets when the attack ends.
- **A3, heavy.** A heavy with `aim_follow` keeps following after release until the arrow spawns. Reach is untouched: `_release_reach` is
  still frozen in `_commit_release()` (R4); check A-26.
- **A4, data.** `Bow_ArrowShot.tres` and `Bow_ArrowHeavy.tres`: `aim_follow = true`, `aim_turn_speed = 600` (10 degrees a frame at 60 fps).
  The goblin archer uses `Bow_EnemyWeaponDefinition.tres` and its own attack, and its controller returns zero: unchanged (A-3, A-4).

## Deviation from the plan, please confirm
The plan said "else the live aim" when no target is locked. With a resting mouse that live aim is the same direction the shot started
with, but it is re-read from the pointer every frame, and the existing bow checks (`XX7`, `XX10`, which start a shot with a given
direction on the real player) would have had their arrows steered to wherever the headless mouse sits. So with no target and no manual
aim the shot now keeps its start direction; the first stick push, drag or mouse movement hands it the live aim (A-34, A-35). If you want
the pure live-aim fallback, change the last `return Vector2.ZERO` of `_get_attack_follow_direction()` in `player.gd` to
`return _get_aim_direction()` and expect `XX7` and `XX10` to need their arena pinned.

## Out-of-range decision (still to confirm)
Nothing was added for "target out of range at spawn": the arrow still leaves and stops at its `attack_range` (R3 cap), as the plan
recommends. No code was needed.

## Risks to watch in the first run
- **Spawn origin.** `context.get_attack_origin()` reads the `AttackSpawnPoint` marker; if it sits under the rotating weapon pivot, the
  arrow's start point shifts a little while the bow turns. Not measured.
- **Mouse flag.** Any `InputEventMouseMotion` during a shot counts as aiming by hand, including motion from a touchscreen emulating a
  mouse (`emulate_mouse_from_touch` is off in this project).
- **Not run.** The part was written without Godot; a parse or typing slip is possible. The checks that call `player.gd` members use an
  untyped `p`, as the H8 checks do.
- **Strafing targets** are not led (out of scope); at 600 px/s over the 120 px reach a sideways-moving target can still step out of the path.

## Not done (out of scope, as planned)
Skills (Power Shot, Multi Shot), predictive lead, enemy attacks.
