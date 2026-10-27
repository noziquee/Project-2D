# P6 - Stagger state

Run in headless Godot 4.7.2 (Oct 26, 2026). Full suite: 1090 passes, 13 failures (the same 13 as in `P2-notes.md`); the 7 P6 checks (P6a to P6g) pass.

## What changed

- New `Characters/StateMachine/States/StaggerState.gd`: an optional state with one export, `clip` (empty keeps the current clip). While `hit_stun_remaining > 0` it plays the clip; when the stun ends it goes to Idle.
- `Character2D._apply_hit_reaction`: after the knockback, stun and interrupts, a hit with `hit_stun > 0` enters `Stagger` when the character's state machine has that state. Without the node nothing changes: the stun still blocks attacks and dashes, it just shows nothing.
- A killing hit never staggers (the reaction is skipped for the dead), so the state cannot hold a dead character.
- Nothing in the shipped scenes changed; no character has a Stagger node yet.

## Add it to a character (Godot editor)

1. Open the character scene and select the `CharacterStateMachine` node.
2. Right-click it, **Add Child Node**, choose **Node**, name it exactly `Stagger`.
3. Drag `Characters/StateMachine/States/StaggerState.gd` from the FileSystem dock onto the node (or Inspector, Script, Load).
4. In the Inspector set **Clip** to the flinch clip name on the locomotion player or the sprite's frames.

## Checks

Only the goblin given the node has the state; a stunning hit enters it and plays the clip; a goblin without it is stunned as before; a hit with no stun does not extend it; it returns to Idle and the idle clip when the stun ends; a killing hit does not stagger and the goblin is freed as usual.

## Not done

- Movement is not blocked while staggered (hit stun never blocked movement; only attacks, dashes and skills). A war hammer that should root its target needs a decision: block movement on stun for everyone, or only while in `Stagger`.
- The dying test goblin is freed within a frame in the headless run, so the death clip is not observed there.
