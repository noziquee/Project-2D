# P8 - `FacingComponent2D`

Written and run October 25, 2026 in headless Godot 4.7 (stable). 10 new checks (FC1 to FC10). Before P8 the run gave `SUMMARY passes=932 failures=0` (after P1); moving the code changed no result (932 / 0 again, so the existing facing checks D1, D2 and the aimed-swing checks P1 to P8 passed untouched). After P8: 932 + 10 = **`SUMMARY passes=942 failures=0`**. No existing check was changed.

## What it does
`Characters/Components/Facing/FacingComponent2D.gd` is the facing and weapon-aim code that lived in `Character2D._update_facing_direction()` and `_update_weapon_aim()`, moved out with the same behavior. `Character2D` calls `facing_component.update(_get_aim_direction())` every physics frame (the same two call sites as before) and `update_weapon_aim()` on death.

Each frame it:
1. remembers the last horizontal movement direction (`context.movement_facing_direction`);
2. picks the visible facing (`context.facing_direction`): that direction, or the side the attack points to while attacking;
3. sets `context.aim_direction`: the attack direction while attacking, otherwise the aim the character gives it;
4. mirrors the body (`context.visual_root`) and the weapon pivot (`context.weapon_facing_root`) on x;
5. rotates the weapon pivot toward the attack for attacks with `aim_weapon`.

The facing state stays on `CharacterContext2D`, because the dash, attack, skill and AI code read `context.facing_direction` directly.

## Fields (all new, defaults keep today's behavior)
| Field | Default | Meaning |
|---|---|---|
| `mirror_visual` | on | mirror the body rig when facing left (also keeps `AnimatedSprite2D.flip_h` off, as before) |
| `mirror_weapon` | on | mirror the weapon pivot when facing left |
| `art_faces_left` | off | for art drawn facing left: mirror when facing right instead. The weapon-aim angle follows the mirror, so aimed swings still line up |
| `rotate_weapon_to_aim` | on | off keeps the pivot unrotated even for `aim_weapon` attacks |

## What changed in the project
- New `Characters/Components/Facing/FacingComponent2D.gd`.
- `Character2D.gd`: new optional `facing_component` export, found by the child name `FacingComponent2D`. `_update_facing_direction()` is now a two-line hand-off and `_update_weapon_aim()` is gone. **A character with no such node gets a default component made in code**, silently, so a scene or a test that builds a character without one behaves exactly as before. The component is set up before the missing-components check, so a disabled character still resets its weapon pivot on death as it used to.
- `player.tscn` and `BasicEnemy2D.tscn` each carry a `FacingComponent2D` node with the defaults. `GoblinArcher.tscn` inherits it.

## Things to know
- The idle aim is now read every frame instead of only when not attacking (the old code evaluated it lazily). Both `player.gd` and the AI controller return it without side effects, so nothing observable changes.
- A new character layout, art drawn the other way round, or a character that should not mirror (a top-down sprite with no left and right art) is now a field change in the scene, with no code change.
- No node-typed exports on this component, so the `node_paths=` entry that P1 needed does not apply here.
- Run the import once (`godot --headless --import --path .`) so the new `class_name` is in the class cache; `Character2D.gd` now names `FacingComponent2D`.

## Tests (FC1 to FC10)
Both scenes carry and resolve the component (FC1); `Character2D.gd` has no `scale.x`, `atan2` or `flip_h` left (FC2); moving left faces and mirrors body and weapon and takes the idle aim (FC3); standing still keeps the facing (FC4); an attack aimed right faces right, uses the attack direction and keeps the movement facing (FC5); `mirror_visual` and `mirror_weapon` switch independently (FC6); `art_faces_left` (FC7); `rotate_weapon_to_aim` during a real aimed swing (FC8); the default component made in code mirrors the goblin sprite (FC9); a component with no context or no attack component does nothing harmful (FC10).

## Next
P2 (exported rig paths) is the natural neighbor: `CharacterContext2D._init` still finds `visual_root` and `weapon_facing_root` by name, which this component reads. P3, P4, P5, P6 and P7 are untouched. Your own play-test of left and right facing and the aimed swing is still open.
