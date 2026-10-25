# P1 - `ReactionComponent2D`

Written and run October 25, 2026 in headless Godot 4.7 (stable). 12 new checks (RC1 to RC11, RC4 runs twice). The archive's own run before this step gave `SUMMARY passes=920 failures=0` (so 14.1 to 14.3 are confirmed). After P1: 920 + 12 = **`SUMMARY passes=932 failures=0`**. No existing check was changed.

## What it does
`Characters/Components/Reaction/ReactionComponent2D.gd` is a node that listens to its `Character2D`'s `damaged` and `died` signals and plays the hit and death presentation from exported data:

| Field | Default | Meaning |
|---|---|---|
| `hit_player` | empty | AnimationPlayer that plays the hit flash |
| `hit_clip` | `take_damage` | clip played for every hit that deals damage and leaves the character alive |
| `reset_clip` | `RESET` | played on `hit_player` at death, after stopping it, so a flash never outlives the character |
| `death_player` | empty | AnimationPlayer that plays the death clip |
| `death_clip` | `death` | played once at death |
| `death_effect_scene` | empty | spawned in the effects container at the death position (`Effects2D`) |
| `free_on_death` | off | `queue_free()` on the character at death |

Every part is optional. An empty clip name, an unset player, a player that was freed or a clip the player does not have is skipped without an error. `play_hit()` is public if a script wants the same flash without a hit.

`Character2D` has a new optional `reaction_component` export. It is found by the child name `ReactionComponent2D` (like the other optional components) and gets `initialize(self)` in `_ready()`. `initialize()` can be called again or for another character; it moves the connections instead of doubling them.

## What moved out of the scripts
- `player.gd`: `_on_damaged()` is gone, and `_on_death()` no longer plays the `RESET` and `death` clips. It still clears the held-button state and calls `set_physics_process(false)`, because the player owns that input state. The two `AnimationPlayer` fields are gone.
- `BasicEnemy2D.gd`: `_on_damaged()`, `_on_death()`, `death_effect_scene` and the hit-player field are gone. The goblin script is now only the AI hookup.
- `player.tscn`: new `ReactionComponent2D` node, `hit_player = ReactionAnim`, `death_player = PlayerAnim`.
- `BasicEnemy2D.tscn`: new `ReactionComponent2D` node, `hit_player = AnimatedSprite2D/AnimationPlayer`, `death_effect_scene = DeathEffect`, `free_on_death` on. The old `death_effect_scene` line on the root is removed. `GoblinArcher.tscn` inherits it and needed no change.

## Behavior change to know about
The component reacts to the `died` signal, which `Character2D` emits at the start of its death handler, so on death the clip, the effect and the free now happen just before the shared cleanup (attack, dash and skill cancelled, velocity cleared) instead of just after it. Nothing reads those in between and `queue_free()` is deferred to the end of the frame, so the 920 existing checks (including O8 and K19) pass unchanged.

The goblin now also stops its flash and plays `RESET` at death, as the player always did. The goblin is freed in the same frame, so there is nothing to see.

## Tests (RC1 to RC11)
Scene wiring of both characters (RC1 to RC3); no clip names, effect spawning or `queue_free` left in `player.gd` and `BasicEnemy2D.gd`, and no `_on_damaged` / `_on_death` in the goblin script (RC4, RC5); a hit plays the clip (RC6); a missing clip, an empty name and an unset player are skipped (RC7); death plays the death clip, stops a running flash, keeps the player in the scene and still stops its physics (RC8); `initialize()` twice keeps one connection per signal (RC9); a component built in code with its own effect and `free_on_death` off spawns that effect and leaves the character (RC10); `initialize()` for another character moves the connections (RC11).

## Things to know
- **Node-typed exports in a `.tscn` need `node_paths=`.** The first version of the scenes listed `hit_player = NodePath(...)` without it, and the flash silently did nothing (5 existing checks failed, C2, C5, F5, O3b, O4c). The two scenes now carry `node_paths=PackedStringArray(...)` on the node header, as `player.tscn` already does for its components. If you add a component by hand in the editor, Godot writes this for you.
- **Run the import once** (`godot --headless --import --path .`) so the new `class_name` is in the class cache before the first run. `Character2D.gd` now names `ReactionComponent2D`.
- The hit clip also plays for status ticks (bleed), as it did before. If that flashes too often, a `react_to_periodic` flag on the component is the place for it; it is not added because nothing asks for it yet.
- Not changed: hit stun, knockback and swing interruption stay in `Character2D._apply_hit_reaction()` (gameplay, not presentation).

## Done when
A new enemy needs no presentation script: its scene gets a `ReactionComponent2D` node and sets the fields above. Met (RC5, RC10).

## Next
P2 (exported rig paths) or P3 (locomotion clip names), or Phase 15. Your own play-test of the flash and the death on a real run is still open.
