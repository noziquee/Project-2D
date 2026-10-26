# P5 - Hurtbox2D

Run in headless Godot 4.7.2 (Oct 26, 2026). Full suite: 1083 passes, 13 failures (the same 13 as in `P2-notes.md`); the 4 P5 checks pass.

## What changed

- New `Characters/Components/Health/Hurtbox2D.gd` (`class_name Hurtbox2D`, a `StaticBody2D`). It forwards `apply_hit` and `take_damage` to a `HealthComponent2D` (the exported one, or the child named `HealthComponent2D`) and re-emits `damaged` and `died`. It has a `team` like a character.
- It is a body, so attack hitboxes find it exactly as they find a character; no hitbox wiring changed. Give it a collision layer that the attack's `hit_layers` reach (the characters use layer 2) and a shape.
- `AttackEffect2D._try_hit` and `ProjectileEffect2D._touch` no longer ask for the `damageable` group. A target only needs `apply_hit` or `take_damage`. The projectile still stops on the world layer.
- Nothing in the shipped scenes changed. `player.tscn` and `BasicEnemy2D.tscn` still carry the `damageable` group (checks A6, A7, O9b, O9c assert it); no game code reads it any more, so it can be removed from the two scenes whenever you like (Inspector, Node tab, Groups).

## Checks (P5a to P5d)

Finds its health and is in no group; `apply_hit` forwards and `damaged` follows; `take_damage` kills, `died` fires once, a dead hurtbox takes nothing; a light arrow hurts a plain `Hurtbox2D` for 4 and is spent.

## Not done

- A ready-made crate scene: what a crate does when it breaks (effect, freeing, loot) is the scene's to wire to `died`; `ReactionComponent2D` only listens to characters.
- Hurtbox knockback and hit stun are ignored (it is static).

## Also fixed here

My earlier restore of `Bow_WeaponDefinition.tres` used a wrong UID for `Bow_ArrowShot.tres`; Godot fell back to the path with a warning. It now uses the file's real UID.
