# Phase V4: leftovers, static check, and the V3 play-test sheet

Not run (no Godot in the editing environment). V1, the V2 run and V3 are still yours. This step adds **no checks and changes none**, so the expected total is unchanged: **`SUMMARY passes=607 failures=0`** if V2b's analysis is right.

## What changed

| File | Change |
|---|---|
| `Characters/Components/Combat/DefaultAttackDefinition.tres` | Removed `release_mode = 1` and `charge_threshold = 2.0`. The player's light attack is Input Release with no threshold again (the field defaults). |
| `IMPLEMENTATION_NOTES.md` | The validation note states the real Phase V status. |
| `docs/phase9/PLAN.md`, `docs/Combat-Roadmap-Step-by-Step-Plan.md` | The V4 decision is recorded; V rows say what is still yours. |

## The Threshold decision (V4)

Decided: **cleared**. The values sat on the light attack, which is never charged, so they did nothing in the game. I checked the smoke test before removing them:

- No check reads the shipped light attack's `release_mode` or `charge_threshold`.
- The checks that copy it with `definition_variant()` and then charge (section U, `U6` to `U15`) hold the button for 22 frames at most, far under the old 2.0 s (120 frames), so they behaved as input release before and after.
- Every check about THRESHOLD release (`FF`, `GG`, `HH`, `KK4f`) sets its own mode and number on its own variant. `HH15` and `HH15b` use the shipped heavy, which has no threshold.

If you wanted a heavy that fires by itself, set Release Mode = Threshold and a Charge Threshold on `PlayerHeavyAttackDefinition.tres`, not on the light attack. `HH15` expects the shipped heavy to still be charging after 2.5 s, so it would need updating.

## Static check done in place of V1

I cannot open Godot, so I read all 28 `.tscn` and `.tres` files with a script and checked:

- every `ext_resource` path exists, and its `uid` matches the `.uid`, `.import` or scene header of that file;
- every `ExtResource("id")` and `SubResource("id")` has a matching definition, and `load_steps` matches the count;
- every node's `parent` exists earlier in the file;
- every `load("res://...")` and `preload` path in the `.gd` files exists.

Result: **no broken reference.** The only line the script flagged, in `UI/HUD/EnemyHealthBar.tscn`, is an inherited scene editing nodes of `HealthBar.tscn`; those nodes exist in the base scene, so it is not a problem.

This does not replace V1. It cannot see property type errors, a bad `AnimationLibrary` track path, or a script parse error. Open the project and read the Output panel.

## V3: play-test sheet

Run `Main.tscn` (nine goblins). Tick each line or write what felt wrong. Turn on Debug > Visible Collision Shapes for the hitbox lines.

- [ ] **Start:** the Output panel is empty and the player holds the sword.
- [ ] **Light combo:** tap light, then light again inside the window: light, light2, light. Stop tapping: the swing ends and the weapon returns at once. After a goblin hits you mid-combo, the next tap is light 1 again.
- [ ] **Tap or hold:** a tap under 0.1 s is a light attack. Holding starts the charge pose. Releasing swings the heavy once. Holding for 3 s and more does not swing by itself.
- [ ] **Heavy reach:** the `heavy_slash` hitbox matches what the animation shows. Say whether you want the heavy to slow you while it swings (it does not now; see V2b notes, `BB2`).
- [ ] **Aim:** swing toward the cursor straight up and straight down, and to the left. The arc is centred on the cursor and the sprite flips correctly.
- [ ] **Goblins:** a goblin uses both its slash and its lunge over a few fights. It starts the swing close enough to connect, not from too far.
- [ ] **Hit during a swing:** the goblin's hit cancels its own swing if it is interruptible, and the player's swing is not cancelled (the light attack is not interruptible). Both return to idle or run.
- [ ] **Death:** killing a goblin plays the death effect and frees it. Dying as the player stops all input without errors.
- [ ] **Nine goblins:** walk through the arena. Note frame rate, goblins stuck on walls, and goblins that never return home.
- [ ] **Dash:** Space dashes, and a dash cancels nothing it should not.

## Still open (yours)

1. V1: `godot --headless --import --path .`, then open the project and run `Main.tscn`. Paste any Output text.
2. V2: `godot --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd`. Paste the `SUMMARY` line and every `CHECK FAIL` line. At 607 / 0, the total goes into `docs/phase9/PLAN.md` as the baseline.
3. V3: the sheet above.

Phase 11 starts after those pass, or earlier if you accept building on an unconfirmed baseline.
