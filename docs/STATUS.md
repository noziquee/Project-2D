# Project-2D: Status

**Single source of truth.** If another document disagrees with this one, this one wins; fix the other.

| Item | Value |
|---|---|
| Last updated | October 29, 2026 |
| Godot | 4.7.2 (headless) |
| Import | Clean |
| Smoke suite | `SUMMARY passes=1648 failures=0` (October 29, 2026, headless Godot 4.7.2 on Linux, 50 parts, includes H2.1 to H9.6, H9.4.4 and the aim indicator style options: 16 new checks, H9-125 to H9-140, part `h8_indicator`; the run before them gave 1632 / 0 with H9-110 to H9-124 in part `h9_heavy`). The archive this run started from gave `1614 / 3` (H7-64, H7-75 and H9-27) because it lacked the H7-64/H7-75 test fixes and the heavy fan's `max_range = 100` (H9.2 decision); all three are now in. Before that: `1617 / 0`, same machine type, 49 parts. Your Windows run on October 29 before those fixes: `1615 / 2` (H7-64 and H7-75). Rerun on your machine and replace this line with your result. Earlier green: 1198 / 0 on October 27 (your machine); 1109 / 0 on October 26 (`docs/trackW/W9-notes.md`) |
| Track R run (October 29, 2026, headless Godot 4.7.2 on Linux, full suite) | R1 alone: `1658 / 7`. R1 + R2: `1676 / 2`. The two left are `UUU7` (arrow hit-once) and `H4-25` (one unexpected logged error: `Invalid polygon data, triangulation failed`, x185), both failing before Track R. The earlier `1648 / 0` line above does not match the current archive; rerun on your machine and replace it. Details: `docs/trackR/R1-notes.md`, `docs/trackR/R2-notes.md` |
| Fix run (October 31, 2026, headless Godot 4.7.2 on Linux, full suite) | `SUMMARY passes=1926 failures=0`. Your Windows run before it gave `1917 / 9` (EVT9, EVT10, BC34, BC35, C1-3, H8-130, H8-165, H9-114, SA30). Two were game bugs: C1-3 (an enemy's heavy charge always aimed right: `_begin_heavy_charge` read `get_aim_direction()` after setting `_heavy_charging`) and H9-114 (on arrival of a heavy approach the carried charge was lost: the reach at charge 0 is shorter, so the same frame's begin started a new walk; `_begin_approach_if_needed` now returns false while `_arrival_pending`). The other seven were tests that had not caught up: the sword's light reach is 30 now (EVT9, EVT10 use a 20 px gap), the bow heavy fixture's queue time is 0.6 s (BC34, BC35), a tap walks first when the goblin is out of reach (H8-130 moves the goblin away), the drawn aim shape is a copy at the charge's reach (H8-165), and Lunge costs no mana (SA30). Rerun on your machine and replace this line with your result. |
| First run of the H-track (October 27, 2026) | `1185 / 13`, then fixed: the player's `defense = 20` in `player.tscn` (kept as your balance value; `load_main()` pins it to 0 for tests) and the H3-22 weapon finder. Rerun: 1198 / 0. Then, with the error gate armed (October 27): `1198 / 0`, no `UNEXPECTED ERROR`; two full runs gave identical CHECK lines (H4.6 done). Still to do: commit `tests/expected_errors.txt` and push so CI runs (H4.7), then H4.5b (each part alone). |
| H9 first run (October 29, 2026) | `1615 / 2`. Cause: since H9.4 a key press with an enemy in view but out of reach walks to it first. H7-64 waited 60 frames after a light tap, which now starts its swing late (the walk comes first), so the skill was refused during the swing: the wait is now 120. H7-75 pressed skill 2 (`sword_spin`, reach 52) with the goblin 134 px away, so it started an approach instead of casting: `matrix_run` now frees the goblin before the skill loop. No game code changed. Result: `1617 / 0`. |
| `ERROR` lines in that green log | 66, almost all deliberate negative tests (see roadmap N1) |
| Play-test (checklist in `Improvement-Roadmap-2026-10-27.md`, section 5) | **Not done** |
| Your own run in the editor | **Not done** |

## Error gate (H4.4)

The suite listens to every error it logs (`tests/error_gate.gd`). An error passes when the running test declared it (`expect_error(...)` before, `check_expected_errors(...)` after) or when it is in `tests/expected_errors.txt`. Anything else fails the run as `UNEXPECTED ERROR`. **The gate is not armed until you record that file:** run `tools/run_checks.sh --record-errors` once, review `tests/expected_errors.txt` (these should be the deliberate negative tests) and commit it. Shutdown leaks (`ObjectDB instances leaked`) come after the script ends, so `run_checks.sh` counts them separately and does not gate them.

## Commands

```bash
tools/run_checks.sh                    # import + smoke suite, log in tools/logs/
tools/run_checks.sh --record-errors    # same, and rewrite tests/expected_errors.txt from this run
```

Run twice and compare (H4.6): `tools/run_checks.sh --twice` (a different CHECK or PART line between the two runs fails it).

Run only some parts (H4.5a): `tools/run_checks.sh --only=p3,h4_rules`. Part names: `godot --headless --path . --script res://tests/smoke_checks.gd -- --list`. A partial run is never the project total; it prints each part's own counts as `PART <name> passes=N failures=M`.

Or by hand:

```bash
godot --headless --import --path .
godot --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd
```

After any run, paste the new `SUMMARY` line and date into the table above.

## Decisions on record (October 27, 2026)

D1 every combatant gets statuses · D2 goblin slash stays non-interruptible for now, goblin-owned `GoblinSword_Slash1/2` to be created · D3 skill `weapon_animation` = cast, then execute · D4 cooldowns character-wide by id · D5 status stacking stays additive (rename field) · D6 weapon definition owns attacks · D7 hide `channel_time` · D8 rename `max_range` per behavior. D9 try the guide's display baseline (1280 x 720, `canvas_items`, `expand`) and keep `viewport` if the pixels shimmer · D10 landscape only for now · D11 touch aim is a right virtual stick · D12 keep the existing action names, add only `aim_*` (all decided October 28, 2026).

## Decisions on record (October 28, 2026): track H9

D18 one `attack_range` per attack (replaces `assist_range` and `ai_attack_range`) · D19 sword light `attack_range` = 70 (now 30 in `Sword_Slash1.tres`, October 2026 tuning) · D20 is superseded by D23 for marker behavior · D21 keep the code fallback layout in `MobileControls` until the scene is checked at target resolutions · D22 hide `effect_animation` for area and projectile effects · D23 exactly one target marker, no rings on other targets · D24 targets inside the 120-degree front cone rank first, nearest within that group; if none are in front, nearest visible target wins · D25 (decided October 29, 2026): option A. A heavy attack asked for out of reach keeps the charge reached, walks to the target and fires in reach; the player may let go of the input on the way and the heavy still fires on arrival (`docs/trackH/H9.4.4-notes.md`). Plan: `docs/trackH/H9-scene-and-combat-rework-plan.md`; H9.4 details: `docs/trackH/H9.4-plan.md`. H9.4.0 single-marker, H9.5 aim-area clipping, and H9.6 replaceable-art changes are written but **not yet run**. Priority 4 adds D22 Inspector hiding for `effect_animation` on area/projectile attack resources (legacy values remain stored and warn), authors `TouchSkillFace` nodes under all three skill buttons in `MobileControls.tscn` while preserving the code fallback, and registers H9-62 to H9-65. These changes are written but not yet run. H9.5 clips the displayed heavy/skill aim geometry to each action's own `aim_shape.max_range` using `Geometry2D.intersect_polygons`; ground-circle placement remains centred on its chosen point, and the light-attack range circle remains visible. Checks H9-55 to H9-61 were added. H9.6 adds optional ring/area/fan textures to `AimIndicator2D`, exports touch-control and skill-face styling, and exports HUD bar labels/accent colours; shared bar/slot styles remain `.tres` resources and control placement remains scene-authored. The archive's pre-existing unresolved merge markers in `tests/smoke_checks.gd` were removed while retaining the H7.4 check block. H9.1 to H9.6 have now been run (October 29, 2026): 1617 / 0, see the table above. Still open: H9.7 (what is left of it) and H9.8, and the play-test. H9.4.4 (heavy attacks with auto-approach, D25) is written and green in the suite.

## Decisions on record (October 29, 2026): shared weapon data and smart aim

D26 weapon data belongs to the weapon: the goblin archer equips `Bow_WeaponDefinition.tres` and uses `Bow_ArrowShot.tres`; `Bow_EnemyWeaponDefinition.tres` and `Bow_ArrowEnemy.tres` are removed. Enemy pacing is `EnemyBehaviorProfile.attack_interval` (archer 1.2 s), not a second attack. D27 (supersedes D24 and the H9-54 stability rule for the player) the target marker and PC attacks/skills with an aim shape choose the **nearest eligible target** the shape accepts, with no front-cone ranking and no stay-put bonus (`TargetingService2D.pick_nearest_target`, `resolve(..., prefer_nearest)`); the scored `pick_target` stays for other callers. D28 on PC (mouse aim) an aimed skill key or hotbar click opens an aim preview: left click casts toward the mouse (no snap to an enemy), Esc or dash cancels with no mana or cooldown; buffs, self skills and no-shape skills cast at once; touch and the right stick are unchanged (`player.skill_aim_preview` turns it off). D29 enemies wind up before a swing (`attack_windup_duration`, default 0.35 s) with a red lane (`EnemyAttackTelegraph2D`, generic forward lane: length = attack range, width = `hitbox_size.y`). Details: `docs/trackH/H10-smart-aim-notes.md`. **Written, not run, not play-tested.** The archer now fires `Bow_ArrowShot` (damage 4, speed 600, range 100, not interruptible) instead of the old enemy arrow (damage 1, speed 200, range 170, cooldown 1.2 s, interruptible).

## Rules on record (pinned by tests)

**Damage a character deals (D5, H4-6 to H4-15).** `multiplier = (1 + sum of (damage_multiplier - 1) x stacks over running statuses, never below 0) x (product of the wielder's passive multipliers that apply to the target)`. `damage = round(base x multiplier)`, at least 1 unless the multiplier is 0. A crit then multiplies that rounded damage; defense is subtracted last (minimum 1). Status bonuses add to each other, the passive multiplies the sum, and the product is rounded once. REFRESH keeps one stack and resets the timer, STACK adds one up to `max_stacks`, IGNORE leaves a running status alone. A status tick skips all of this.

**Cooldowns (D4, H4-16 to H4-19).** A cooldown belongs to the character and is keyed by skill id. It survives a weapon swap, keeps counting down while its skill is not equipped, ends and is announced even then, and is shared by every weapon that lists the same id, whatever slot it uses.

## Implemented and smoke-tested (automated pass only; no play-test yet)
- Track R (attack and skill reach, October 29, 2026; `docs/trackR/`): R0 audit, R1 shapes follow the action's reach (`AimShape2D.with_reach()`), R2 strict 1 px shape-vs-reach validation for skills and attacks, shipped shapes at their real reach (Power Shot 300, Multi Shot 300, Lunge 148), Ground Slam aim shape (line, 72 px). Checks R1-1 to R1-17 and R2-1 to R2-13 in `tests/h8_aim_checks.gd`. `tools/range_audit.py` now exits 1 on any mismatch. R3 (attack projectile lifetime = reach / speed, melee reach gate, two warnings; `docs/trackR/R3-notes.md`, checks R3-1 to R3-14) is written but NOT RUN. R4 (charge_reach_min, live while charging and frozen at release; `docs/trackR/R4-notes.md`, checks R4-1 to R4-9) is written but NOT RUN. R5 (skill range tests and two SkillComponent2D helpers; `docs/trackR/R5-notes.md`, checks R5-1 to R5-15) is written but NOT RUN. R6 (docs and H2.6 handoff, `docs/trackR/R6-notes.md`) is done. Track R's run status: R3 to R5 NOT RUN. (charge scaling), R5, R6. Needs a play-test of the assist change (Lunge, Power Shot, Multi Shot).

- Combat core: attack components, combo/charge/heavy attacks, hit resolution, health, damage and crit.
- Weapons by folder (`Sword`, `Bow`, `GoblinSword`), weapon definitions, the shared Bow definition equipped by both the player and the goblin archer (D26), weapon switching with refusal during swing, charge and cast.
- Bow draw, shot, heavy shot and return cycle (0.5 s draw).
- Skills: projectile, area, dash and buff behaviors; Sword Lunge, Spin, Empower; Bow Power Shot, Multi-shot, Empower; mana; cooldowns.
- Passives: Rising Strikes, heal on hit, bleed on hit, low-health bonus.
- Status framework (bleed, damage multiplier buffs) on the player.
- HUD: health and mana bars, skill bar with cooldown wipe, compact enemy health bar.

## Implemented, not verified

- Anything that depends on feel or on-screen result: bow timing, goblin flinch, dash and lunge near walls, HUD readability. Covered by the play-test checklist only.
- Statuses on enemies (H2.1, written October 27): `BasicEnemy2D.tscn` now has a `StatusController2D` child, and `GoblinArcher.tscn` inherits it. Six new checks (H2-1 to H2-6) and four edited ones (DDD15, DDD16, EVT9, GGG1) cover it; **`SUMMARY passes=1198 failures=0` confirmed on October 27 after H2.1, H2.3, H2.4, H3.1 to H3.5, H4.1 to H4.4, H4.6 and H2.2 (6 + 9 + 4 + 19 + 10 + 4 + 6 + 14 + 7 + 2 + 6 new checks; H4.5a, H4.5c and H4.7 add none)**. Needs your run, then a play-test of bleed on a goblin.
- Automated run on every push and pull request (H4.7, written October 27): `.github/workflows/checks.yml` runs `tools/run_checks.sh` on GitHub with Godot 4.7.2. Never run yet: it needs the repository to contain this commit, and it will go red until the suite itself is green.
- Skill `weapon_animation` (H2.2, written October 27): a skill that names a clip plays it when it starts, then executes after its cast time; a cancelled cast stops it (`docs/trackH/H2.2-notes.md`, checks H2-7 to H2-12). No shipped skill names a clip yet, so nothing in the game plays differently until one does.
- Aim indicator style options (October 29, written, suite green, not yet seen in the editor or on a device): outline width, per-style strip width scale, range circle, circular gradient and pixelation on `AimIndicator2D` (`docs/trackH/aim-indicator-style-notes.md`, checks H9-125 to H9-140). Defaults keep the old look except that the range circle is on.
- `effect_animation` on area and projectile effects: still ignored by the effects, but a non-default value now earns a warning (H3.3). Equip logs weapon warnings; they never block it.

## Corrections to the audit

- N7 (slot collisions and duplicate skill ids are only runtime warnings) was partly wrong: `WeaponController2D.equip()` already refuses a weapon whose `validate()` reports them, and the old weapon stays. Only a direct `SkillComponent2D.set_skills()` call is lenient. H3.5 added four checks (H3-1 to H3-4) that pin both behaviors; no game code changed.

## Not implemented

- Channel skills (`channel_time` is hidden from the Inspector and must be 0, H2.3).
- Game over / respawn flow (not found in `player.gd` or `Main.tscn`; scope to be confirmed, N4).
- Gamepad bindings, touch controls, aim from a stick or finger, and responsive display settings: **in scope as of October 28, 2026**, planned as Phase H7 (source: `docs/Godot_Responsive_Display_and_Multi_Device_Input_Guide.pdf`). Today the display uses `viewport` stretch, the input map has keyboard and mouse only, and aiming reads the mouse. D9 to D12 were decided on October 28 as recommended (see below).
- Ground Slam is an example resource, not in any loadout.
- Dash-slash variant, fire staff and further weapons (Phase 15, after H0 to H4).

## Controller bindings and stick aim (H7.4, written October 28, 2026)

Written, not yet run. Expect `SUMMARY passes=1207 failures=0` after H7.4 alone, and `1237 / 0` once H7.2, H7.3, the hotbar work and H7.5 below are also in (1198 plus 9 checks H7-1 to H7-9, plus 8 checks H7-10 to H7-17, plus 10 checks H7-18 to H7-27, plus 12 checks H7-28 to H7-39; `U2`, `YY1` and `GGG3` were edited, not added). Xbox naming; Godot button numbers in brackets.

| Action | Controller |
|---|---|
| `move_*` | Left stick, and D-pad |
| `aim_*` (new) | Right stick (dead zone 0.25) |
| `attack_light` | Right trigger (dead zone 0.5). Hold it to charge, as holding the left mouse button does |
| `attack_heavy` | Right bumper (RB, 10). Charges the heavy attack directly |
| `dash` | A (0) |
| `weapon_next` | Left bumper (LB, 9) |
| `skill_1`, `skill_2`, `skill_3` | X (2), Y (3), B (1) |

Aim: the right stick takes over once pushed past its dead zone and keeps its last direction when released; any mouse movement or click hands the aim back to the mouse. Keyboard and mouse bindings are unchanged. Not done in H7.4: display settings (H7.2), camera limits (H7.3), last-used-device tracking (H7.5), touch controls (H7.6), prompts (H7.7). (H7.2, H7.3, H7.5 and H7.6 have since been written, see below.) Details: `docs/trackH/H7.4-notes.md`.

## Display, camera and hotbar (written October 28, 2026, not yet run)

- **H7.2:** base viewport 1280 x 720, stretch `canvas_items`, aspect `expand`, landscape orientation (D9, D10). The window opens larger than before (it was the default 1152 x 648) and the visible world at zoom 3 is about 427 x 240 px. If the pixel art shimmers, set `window/stretch/mode` back to `viewport` (D9's fallback).
- **H7.3:** `World/CameraBounds2D.gd` (a `CameraBounds` node in `Main.tscn`) limits the player's camera to the arena floor (1000 x 640). Zoom stays 3. At 16:9, 21:9, 32:9, 16:10, 4:3, 5:4 and 1:1 the view fits; a 9:16 portrait window would not (D10).
- **Hotbar:** a left click on a skill slot casts it like its key; `H` (action `toggle_click_cast`) switches click-to-cast off and on, and the keys still work when it is off. A click on a slot no longer also swings the weapon, and the aim does not turn toward the hotbar. Notes: `docs/trackH/H7.2-H7.3-notes.md`, `docs/trackH/hotbar-click-notes.md`.

## Active input device (H7.5, written October 28, 2026, not yet run)

`Platform/InputModeManager.gd` (a node named `InputModeManager` in `Main.tscn`) tracks whether the player is on keyboard and mouse, a controller or touch, and emits `device_changed(device)`. It starts as touch on Android and iOS and as keyboard and mouse elsewhere; a connected controller does not become the active device until it is used. A key press or real mouse input, a controller button or a stick pushed past 0.4, and a touch each switch the mode; a resting stick, releases and mouse events made from touches do not. Unplugging the last controller falls back to the start mode. Find it with the group `input_mode_manager`. Nothing uses it yet: HUD prompts (H7.7) and touch controls (H7.6) will. Notes: `docs/trackH/H7.5-notes.md`.

## Touch controls (H7.6, written October 28, 2026, not yet run)

`UI/Touch/MobileControls.gd` (a `MobileControls` node under `HUD` in `Main.tscn`) shows a move stick on the left and, on the right, a grid of buttons beside an aim stick (D11). It is visible only while `InputModeManager` reports touch, and every control presses an existing named action (`move_*`, `aim_*`, `attack_light`, `attack_heavy`, `dash`, `weapon_next`, `skill_1` to `skill_3`); there is no combat code in it. `project.godot` now sets `input_devices/pointing/emulate_mouse_from_touch=false`, because a touch would otherwise also arrive as a left mouse click and swing the weapon (`attack_light` is bound to it). Expect `SUMMARY passes=1275 failures=0` with H7.2 to H7.6 all in (28 new checks, H7-40 to H7-67, part `h7_touch`). Not done: HUD prompts and layout work at every ratio (H7.7), the device matrix (H7.8). Needs a try on a phone or with the debug switch. Notes: `docs/trackH/H7.6-notes.md`.

## Prompts follow the device (H7.7, written October 28, 2026, not yet run)

`UI/HUD/SkillBar.gd` listens to `InputModeManager.device_changed`: the slot labels show the number keys on keyboard and mouse, the controller button (X, Y, B) when a controller is in use, and nothing on touch (the overlay's buttons carry their own captions). The layout part of H7.7 is already covered by H7-66 and H7-67 (corner anchors, right cluster clear of the skill bar at the 1280 base width). Expect `SUMMARY passes=1275 failures=0` (4 new checks, H7-68 to H7-71, part `h7_prompts`). Notes: `docs/trackH/H7.7-notes.md`.

## Same gameplay from every source (H7.8, written October 28, 2026, not yet run)

Part `h7_matrix` (checks H7-72 to H7-77) runs dash, a light tap, a heavy hold and all three skill slots once through an action press (what a key or controller button does) and once through the touch overlay's buttons, and requires identical results; it also pins the aim priority (touch stick, then mouse). Expect `SUMMARY passes=1275 failures=0` with H7.2 to H7.8 all in. The device matrix to fill in by hand is in `docs/trackH/H7.8-notes.md`. Phase H7 is then complete apart from your own runs.

- Track A (bow aim-follow, October 29, 2026; `docs/trackA/A-notes.md`): A1 to A5 written, NOT RUN (no Godot was available). `AttackDefinition2D.aim_follow` / `aim_turn_speed`, `AttackComponent2D.update_attack_direction()`, a `_get_attack_follow_direction()` hook in `Character2D` and the player's target lock; the two player arrow attacks follow at 600 deg/s, the goblin archer does not. Checks A-1 to A-35, part `a_follow`. One deviation from the plan (no target and no manual aim keeps the start direction) needs your confirmation.

- R7 (RD6 charge variety steps 1 and 2, October 29, 2026; `docs/trackR/R7-notes.md`): written, NOT RUN. The bow's heavy now sets `charge_reach_min = 0.5` and `charge_threshold = 1.0` (it set neither), plus an optional `charge_reach_ease` curve (default linear). Checks R4-10 to R4-14; R4-9, XX9 and A-26 updated. Step 3 (charge stages: `ChargeStage2D`, `charge_stages`, signal `charge_stage_changed`; checks S-1 to S-14, part `r7_stages`) is written, NOT RUN. Step 4 (timed release: `perfect_window_*`, release multipliers, signals `release_timing_changed` / `charge_released`; checks T-1 to T-14, part `r7_timed`) is written, NOT RUN. Step 5 (`charge_damage_curve`, `charge_area_curve`; checks C-1 to C-12, part `r7_scaling`) is written, NOT RUN. Step 6 (charge bar) not started.

- Track E (enemy AI combat behavior, first versions written October 29, 2026, audit October 30; `docs/trackE/E0-audit-and-status.md`): combo length and recovery pause (B2, B3), heavy-attack opening wait (C1, C2), skill use (D1), self buffs (DE1, D2-1 to D2-4, `docs/trackE/DE1-notes.md`), four profiles and minimum-range retreat (E1); parts `enemy_ai_combo`, `enemy_ai_heavy`, `enemy_ai_heavy_wait`, `enemy_ai_skill`, `enemy_ai_profiles`. **NOT RUN, uncommitted.** Phases F (telegraphs for all actions, group coordination) and G not started. Next: run the suite and record the result here, group attack slots (DE2, `max_simultaneous_attackers`, checks DE2-1 to DE2-10, part `enemy_ai_slots`, with `circle_while_waiting`, `docs/trackE/DE2-notes.md`) are also written, NOT RUN. DE3 (warning shape before an enemy skill, `skill_windup_duration`, checks D3-1 to D3-5, `docs/trackE/DE3-notes.md`) is written, NOT RUN. C3 (heavy attack judged by where the target will be at the end of the charge, checks C3-1 and C3-2, `docs/trackE/C3-notes.md`) is written, NOT RUN. E2 (repositioning to `preferred_combat_range`, checks E2-1 to E2-5, `docs/trackE/E2-notes.md`) is written, NOT RUN. E3 (simple common profile, target switching, attack pick report `last_attack_candidates`, checks E3-1 to E3-8, `docs/trackE/E3-notes.md`) is written, NOT RUN; it also fixes E2-5 in `tests/smoke_checks.gd`, which used two variables before their declaration. Support / commander profile still needs an ally skill behavior. E4 (`GoblinElite.tscn` with `GoblinEliteProfile.tres`: heavy choice, `SkillComponent2D`, skill warning, target switching; checks E4-1 to E4-4; `docs/trackE/E4-notes.md`) is written, NOT RUN; the normal goblin and `Main.tscn` are unchanged. E5 (`TrackEArena.tscn`, six enemies with one profile each, checks E5-1 and E5-2) is written, NOT RUN.

## Roadmap pointer

Plan: `Improvement-Roadmap-2026-10-27.md`. Current phase: **H0, H2.1, H2.2, H2.3, H2.4, H3.1 to H3.5, H4.1 to H4.4, H4.5a, H4.5c, H4.6 and H4.7 written, awaiting your copy-in and a `tools/run_checks.sh` run**; H2.3, H2.4 and all of H3 and H4.1 to H4.4 are written too; H4.5a and H4.5c written (suite split into 23 runnable parts, `docs/trackH/H4.5a-notes.md`, `H4.5c-notes.md`); H4.6 written (every random source seeded, global state reset before each part, `docs/trackH/H4.6-notes.md`); H4.7 written (GitHub Actions, `docs/trackH/H4.7-notes.md`); H2.2 written (a skill clip plays, then the skill executes, `docs/trackH/H2.2-notes.md`); next H2.6 (rename `max_range` by behavior, D8; migrates the `.tres` files) and H4.5b (run each part alone and compare with the full run), after you run the suite. H5 only once H3 and H4 are green.
