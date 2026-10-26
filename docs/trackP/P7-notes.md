# P7 - forward impulse

Run in headless Godot 4.7.2 (Oct 26, 2026). Full suite: 1096 passes, 13 failures (the same 13 as in `P2-notes.md`); the 6 P7 checks (P7a to P7f) pass.

## What changed

- `AttackDefinition2D` has two new fields, **Forward Impulse** (speed in pixels per second along the attack direction, 0 = none) and **Impulse Duration** (seconds, default 0.15).
- `AttackComponent2D` starts the step when the attack's effect spawns (the `spawn_effect` event, so a clip needs no new key), fades it linearly to zero over the duration, and clears it when the swing is cancelled, interrupted or finished.
- `CharacterContext2D.impulse_velocity` carries it and `MovementComponent2D` adds it to the velocity, next to the knockback. It does not replace movement, so the lunge's `movement_multiplier` still applies.
- `GoblinSword_Lunge.tres` now has Forward Impulse 300 and Impulse Duration 0.15: the goblin steps about 13 px as the stab lands (measured 13.2 px). **This is a gameplay change you can tune:** open that file in the FileSystem dock and edit the two fields in the Inspector.
- No other attack has an impulse; the sword and its skills are unchanged.

## Checks (P7a to P7f)

The lunge has an impulse and the shared slash has none; the step has not begun before the effect spawns; it reaches close to its speed; it moves the goblin 8 to 40 px and is over by the end; cancelling clears it at once; an attack without one leaves it at zero.

## Not done

The player's Lunge skill is a skill, not an attack definition, and still uses its own movement; giving it an impulse would be a separate step.
