# Project-2D: Audit Verification and Improvement Roadmap (Track H)

Date: October 27, 2026. Basis: `Project-2D_Architecture_Audit_2026-10-26.pdf`, checked against the source in the archive, plus a real run in headless Godot 4.7.2 (`SUMMARY passes=1109 failures=0`, see `docs/trackW/W9-notes.md`).

Update, October 28, 2026: Phase H7 (display, input and touch controls) was added from `docs/Godot_Responsive_Display_and_Multi_Device_Input_Guide.pdf`. N5 is now in scope; decisions D9 to D12 are new. H0 to H6 are unchanged.

Nothing in this document changes game code. It is the plan. Every item says what it is, why, how big, and how you know it is done.

Legend: **S** = under 2 hours, **M** = half a day to a day, **L** = more than a day. "Verified" means I opened the file and the line is quoted; "Accepted" means the audit's reasoning is sound but I did not re-derive it from the code.

---

## 1. Verdict on the audit

### 1.1 Section 4 findings

| # | Audit claim | Verdict | Evidence / correction |
|---|---|---|---|
| A | Docs disagree on verification status | **Confirmed, and wider than stated** | The roadmap still says "not yet run" for W1 to W4, W6, "runtime smoke test still pending" for W8, "expected 1025 / 0" for W6, "awaiting the Phase 13.4 final smoke test" (13.4.7), "pending the user run" (13.4.8) and Phase 14 "not yet run". The architecture guide (status note and the section at line 373) still says W4 to W7 are not runtime-verified. The README and W9 are correct. |
| B | `BasicEnemy2D` has no `StatusController2D` | **Confirmed** | Only `player.tscn` contains one. `BasicEnemy2D.tscn` and `GoblinArcher.tscn` have none, so bleed and every other status silently do nothing to enemies. |
| C | Rig and weapon-player discovery rely on fallback names | **Confirmed** | `CharacterContext2D.gd` falls back to `HandAnim` / `WeaponAnimation` (line 26) and `MainHand` / `Weapon` (line 79). Partly mitigated: `WeaponController2D.equip()` already refuses to swap during a swing, charge or cast (lines 159 to 162). |
| D | Duck-typed property reads | **Confirmed, four sites** | `CombatResolver2D.gd` lines 55 and 65 (`status_controller`, `passive_controller`), `AttackEffect2D.gd` lines 132 and 133 (`team`), `PassiveController2D.gd` line 188. |
| E | No effect-scene validators | **Confirmed** | Scene validation exists only for weapons (`WeaponDefinition2D.validate_scene`) and for the slash clip (`AttackSlash2D.scene_lacks_animation`). Area and projectile effect scenes have none. |
| F | Goblin slash reuse changes hit-interrupt behavior | **Confirmed** | The goblin's basic combo is `Sword_Slash1` and `Sword_Slash2`. The only attacks with `interruptible = true` are `Bow_ArrowEnemy` and `GoblinSword_Lunge`. So a hit no longer interrupts the goblin's slash. |
| G | Roadmap mixes "not implemented / unverified / smoke-tested" | **Confirmed** | See A. |
| H | Archive contains `.git/` and `.godot/` | **Partly confirmed** | `.gitignore` already excludes `.godot/`; the cache is in the archive because the working folder was zipped. A packaging habit, not a repository problem. I did not measure the sizes. |

### 1.2 Section 9 findings

| # | Claim | Verdict | Evidence / correction |
|---|---|---|---|
| 9.1 | Attack ownership split between weapon and component | **Confirmed** | `AttackComponent2D` exports `attack_definition` (line 55) and `attacks` (line 61) and uses them at start-up (line 117). `WeaponController2D._set_attacks_from` overwrites both through `set_attack_definition()` and `set_attacks()`. |
| 9.2 | Skill `weapon_animation` validated but never played | **Confirmed** | The field is read only in `SkillDefinition2D.validate` (line 108) and `WeaponDefinition2D` (line 272). `SkillComponent2D` never reads it. |
| 9.3 | `channel_time` exposed but must be 0 | **Confirmed** | `SkillDefinition2D.gd` lines 43 and 96 to 97. |
| 9.4 | `effect_animation` ignored by area and projectile effects | **Confirmed** | Documented in `AreaEffect2D.gd` line 16 and `ProjectileEffect2D.gd` line 19. |
| 9.5, 9.6, 9.8, 9.11, 9.13 | Wide resources, skills reusing attack payloads, tagged-union skills, mixed status resource, large `AttackComponent2D` | **Accepted** | Sound design observations; none is a bug today. The audit's advice (add warnings first, split later) is right. |
| 9.7 | `max_range` means different things per behavior | **Confirmed** | Projectile: `lifetime = max_range / speed` (`SkillComponent2D` lines 335 to 338). Dash: `duration = max_range / dash_speed` (line 396). AREA does not use it. |
| 9.9 | Property-name lookups in the resolver | **Confirmed** | Same four sites as D. |
| 9.10 | Status multiplier is additive per stack | **Confirmed** | `StatusController2D.get_damage_multiplier()`: `bonus += (multiplier - 1.0) * stacks`, result `1.0 + bonus`. |
| 9.12 | Skill cooldown persistence across weapon swaps is implicit | **Confirmed, with two corrections** | (1) `set_skills()` clears `_skills` and `_slots` but not `_cooldowns`, so cooldowns already behave as character-wide, keyed by skill id; a smoke check (TTT9) covers sword/bow switch-back. The gap is that the rule is undocumented. (2) An in-progress cast cannot meet a swap, because equip is refused during a cast. |
| 9.14 | Resource existence does not prove scene compatibility | **Confirmed** | See E. |

### 1.3 Where the audit was wrong or incomplete
- **"Godot was not available, so the 1109/0 is unverified."** I ran it: import clean, `passes=1109 failures=0`. The audit's P0 "run import and smoke" is done for the delivered archive. The manual play-test is still open.
- **Skill slots are a field, not array order.** `SkillDefinition2D.slot` decides the slot; `set_skills()` ignores a skill whose slot is taken (with a warning only, lines 100 to 102). That is why the sword's array order does not matter and why two weapons sharing a skill (Empower) must agree on its slot. The audit does not mention this.
- **Equip already has guards** (swing, charge, cast). The audit's rollback-test advice stands, but the guard exists.

---

## 2. Additional findings (not in the audit)

| # | Finding | Why it matters |
|---|---|---|
| N1 | The green run prints **66 `ERROR` lines** (almost all deliberate negative tests) plus shutdown leak reports ("16 resources still in use", leaked RIDs). | A real new error is invisible in that noise. There is no list of expected errors, so the log cannot be diffed. |
| N2 | The test suite is **one file of about 7,000 lines** (`tests/smoke_checks.gd`, about 460 KB). | You cannot run one section, edits are slow to review, and a crash early on hides everything after it. |
| N3 | **No automated run on change** (no `.github/`, no script). The suite does return a non-zero exit code on failure (`quit(1)`), so it is ready for it. | The 1109/0 result decays the moment someone edits a file. |
| N4 | **No game-over or respawn flow** found in `player.gd` or `Main.tscn` (only a comment about clearing state on death). | Confirm it is intended; if not, a death in play-test ends the session. |
| N5 | **No gamepad bindings** and **no touch controls** in the project. **In scope as of October 28, 2026** (Phase H7). | The game is meant to run on PC, mobile and controller; today only keyboard and mouse can play it. |
| N9 | Aiming reads the mouse only: `player.gd` `_get_aim_direction()` uses `get_global_mouse_position()`. There is no aim action, so a stick or a finger cannot aim the bow. The display uses `stretch/mode="viewport"` with no base size, the camera zoom is 3, and `player.tscn` sets no camera limits. | These three decide how the game looks and plays on other screens and devices (Phase H7). |
| N6 | **98 Markdown files** under `docs/`, with status written inside roadmap table cells. | This is how the drift in A happened. A single status file would prevent it. |
| N7 | `skill.slot` collisions and duplicate skill ids are **warnings at runtime**, not hard validation errors at definition time. | A content mistake shows up as a skill that quietly does not appear. |
| N8 | The goblin's weapon definition **loads sword slash resources** (`GoblinSword_WeaponDefinition` uses `Sword_Slash1/2`). | Cross-weapon reuse is intended (W5), but the "weapon folder owns its content" rule now has a documented exception that nothing checks. |

---

## 3. Decisions to make first (these unblock everything else)

| # | Decision | Options | My recommended default |
|---|---|---|---|
| D1 | Do all combatants support statuses? | Yes, add `StatusController2D` to every enemy / Optional, flag it in validation | **Yes.** Add it to `BasicEnemy2D.tscn`. Cheap, and it makes bleed work. |
| D2 | Should the goblin's slash be interruptible? | Keep (shared slash) / New `GoblinSword_Slash1/2` that reuse the clip and effect but set `interruptible = true` | **Decide after the play-test**; if goblins should flinch, make goblin-specific attack resources, not a second framework. |
| D3 | What does a skill's `weapon_animation` do? | Play it then execute / Wait for an animation event / Remove the field | **Cast-then-execute** for skills that name a clip; none for those that do not. |
| D4 | Skill cooldown rule across weapon swaps | Character-wide by id (current) / Per weapon / Reset on equip | **Character-wide by id**, now written down and tested. |
| D5 | Status stacking maths | Additive (current) / Multiplicative | **Keep additive**, rename the field to describe it, add tests. |
| D6 | Who owns a weapon character's attacks? | The weapon definition only / Both (current) | **Weapon definition only**; the component gets a normalized attack set. |
| D7 | `channel_time` | Hide until built / Keep with a "reserved" label | **Hide the export** until channel skills exist. |
| D8 | Rename `max_range` by behavior? | `projectile_range`, `dash_distance`, `target_range` / Keep | **Rename**, with a migration for the existing `.tres` files. |
| D9 | Display scaling | Guide baseline: base size 1280 x 720, `canvas_items`, aspect `expand` / Keep `viewport` (fixed pixel look) | **Try the guide baseline** and check that pixels stay crisp (nearest filter is already the default). Keep `viewport` if the art shimmers. | (decided October 28: recommended default)
| D10 | Portrait / tall screens | Supported (UI and encounters tested) / Landscape only | **Landscape only for now.** A portrait phone shows about three times more world vertically than 16:9 at zoom 3. | (decided October 28: recommended default)
| D11 | How a touch player aims the bow | Right virtual stick / Drag anywhere / Auto-aim nearest enemy | **Right virtual stick** (same code path as a controller's right stick). | (decided October 28: recommended default)
| D12 | Action names | Keep the existing names (`attack_light`, `attack_heavy`, `dash`, `move_*`) / Rename to the guide's | **Keep.** About 63 test lines use them; the guide's table is an example, not a requirement. Add only `aim_*` actions. | (decided October 28: recommended default)

---

## 4. The roadmap

Order matters: truth first, then decisions, then fixes, then validation and tests, then restructuring, then new content. Each phase ends with a smoke run whose result is recorded in `docs/STATUS.md`.

### Phase H0: Make the status truthful (S, no game code)
| Step | Work | Done when |
|---|---|---|
| H0.1 | Create `docs/STATUS.md`: Godot version, exact commands, date, summary line, and three labelled lists: not implemented / implemented, not verified / implemented and smoke-tested. | One file answers "what is the state?" |
| H0.2 | Update the roadmap rows and the guide's status note to match W9 (all the rows listed under A). Keep "automated pass" and "play-test done" as separate columns. | `grep -n "not yet run"` finds only things that really are unrun. |
| H0.3 | Add `tools/run_checks.sh` that runs import then the smoke suite and saves the log. | One command reproduces the result. |
| H0.4 | Add a packaging note to the README: exclude `.godot/`; say whether `.git/` is included. | Archive habits written down. |

### Phase H1: Play-test and decide (M, you)
| Step | Work | Done when |
|---|---|---|
| H1.1 | Run the play-test checklist in section 5 and note what you see. | Each item is marked pass / fail / unsure. |
| H1.2 | Answer D1 to D8 (section 3). | Each decision is written in the roadmap. |
| H1.3 | Confirm N4 (game over / respawn) is in or out of scope. N5 (gamepad and touch) is answered: **in scope**, see H7. | One yes/no answer (N4). |

### Phase H2: Contract fixes (M to L, code)
| Step | Work | Size | Done when |
|---|---|---|---|
| H2.1 | Add `StatusController2D` to `BasicEnemy2D.tscn` (D1); test bleed and a damage buff on the goblin and the archer. | S | Bleed ticks on every enemy variant, with checks. |
| H2.2 | Skill animation (D3): implement the chosen policy in `SkillComponent2D._execute()`, or remove the field and its validation. | M | A skill with a clip plays it; a missing clip fails validation. |
| H2.3 | Hide `channel_time` (D7). | S | Not in the Inspector; validation message kept for old data. |
| H2.4 | Combatant accessors: one helper each for team, status controller, passive controller, health; replace the four `get("...")` sites. | M | No `get("status_controller")`, `get("team")` left outside the helpers; tests for character, projectile, null and non-character sources. |
| H2.5 | Goblin interruptibility (D2), if you want it. | S | Goblin flinch behavior matches the decision, with a check. |
| H2.6 | Range naming (D8): rename the fields and migrate the resources. | M | Each behavior has one clearly named distance; a test measures real travel distance. |

### Phase H3: Validation (M to L)
| Step | Work | Size | Done when |
|---|---|---|---|
| H3.1 | One loadout report: weapon definition → scene root → mount → animation player → attack clips → method tracks → effect scene nodes and clips → skills (including slot collisions and duplicate ids) → passive and status references. Lists every problem in one pass. | L | A deliberately broken weapon prints all its problems at once. |
| H3.2 | `validate_scene()` on each effect type (slash, area, projectile): required nodes, hitbox shape, clips. | M | Wrong effect scene for a behavior is caught before the game starts. |
| H3.3 | Subtype-aware warnings for ignored fields (`effect_animation` on area and projectile, charge fields without a charge clip, status tick fields on a buff). | M | Warnings, not silent acceptance. |
| H3.4 | Table-driven skill validation test, one row per behavior (required fields, forbidden fields, required components). | M | Adding a behavior without a row fails a check. |
| H3.5 | Make skill slot collisions and duplicate ids definition-time errors (N7). | S | A bad loadout fails to equip with a clear message. |

### Phase H4: Test quality (M to L)
| Step | Work | Size | Done when |
|---|---|---|---|
| H4.1 | Equip as a transaction: rollback after an invalid scene, missing clip, rejected attack list, failed bind; assert the old weapon, attacks, skills, passives and animation connection all remain valid. | M | Four failure paths each have a check. |
| H4.2 | Status maths tests (D5): two buffs, several stacks, refresh / ignore, with passives and critical hits. | S | The formula is pinned by tests. |
| H4.3 | Cooldown rule tests (D4): swap away and back, shared ids, removed skill. | S | The rule is written and tested. |
| H4.4 | Expected-error allowlist (N1): tests declare the errors they expect; the runner fails on any other `ERROR`. Report shutdown leaks separately. | M | A new unexpected error turns the run red. |
| H4.5 | Split `smoke_checks.gd` into suites (combat, weapons, skills, passives, UI, bow cycle) with a filter argument (N2). | L | You can run one suite; the total stays 1109 (or higher). |
| H4.6 | Seed crit RNG and isolate global state. | S | Two runs give identical output. |
| H4.7 | Run the suite on every change (N3). | S | A change that breaks a check is flagged without you running it. |

### Phase H5: Restructuring (L, only after H3 and H4 are green)
| Step | Work | Done when |
|---|---|---|
| H5.1 | Single attack-set source (D6): a normalized attack set from the weapon definition; migrate scenes and tests; then remove the legacy exports. | One authoring path; the player and goblin pass unchanged. |
| H5.2 | Shared combat payload resource (damage, crit, statuses, hit layers) used by attacks and skills. **Only if** skill and attack definitions keep drifting. | Skills reference a payload, not a whole attack. |
| H5.3 | `AttackAnimationDriver` extracted from `AttackComponent2D`. **Only if** that class becomes hard to change; keep one source of truth for "is an attack active". | Same behavior, smaller class, tests unchanged. |

### Phase H6: Back to content (Phase 15)
Start the fire staff and further weapons only when H0 to H4 are done. Each new weapon then ships with: a folder from a template, an attack and a skill template, one validation test, one hit test, and a play-test line (section 6).
Do H7.1 to H7.5 before the fire staff, because every new weapon is aimed and triggered through the actions they set up. H7.6 onward can run alongside content.

### Phase H7: Display and multi-device input (platform layer)
Done early, outside the step list: clickable hotbar slots with a click-to-cast toggle (`docs/trackH/hotbar-click-notes.md`). H7.6's on-screen skill buttons can reuse the same slots.
Source: `docs/Godot_Responsive_Display_and_Multi_Device_Input_Guide.pdf`. Principle from the guide: gameplay and combat stay shared; a small platform layer handles display, input and HUD presentation. Weapons, attacks and skills never read a device directly, only named actions. Confirm each property name in the Godot 4.7 editor before relying on it (the guide says so too).

| Step | Work | Size | Done when |
|---|---|---|---|
| H7.1 | Answer D9 to D12. | you | **Done, October 28, 2026: all four as recommended** (D9 try the guide baseline, D10 landscape only, D11 right virtual stick for touch aim, D12 keep the existing action names). |
| H7.2 | **Written October 28, 2026 (`docs/trackH/H7.2-H7.3-notes.md`), awaiting your run and a look at the pixels.** Display: set the base viewport to 1280 x 720, stretch mode `canvas_items`, aspect `expand` (per D9), landscape orientation (per D10). Today it is `viewport` with no base size. | S | Resizing the window at 16:9, 21:9 and 4:3 keeps the game undistorted and the pixels crisp; the camera zoom stays 3. |
| H7.3 | **Written October 28, 2026 (same notes): `World/CameraBounds2D.gd` limits the camera to the arena floor.** Camera and world: keep `zoom = 3` and do not zoom to fill. Visible world is the viewport divided by the zoom (about 427 x 240 px at 16:9, wider on ultrawide). `player.tscn` sets no camera limits, so add limits (or a test) so no ratio shows beyond the level edge or an unfinished area. | M | At each target ratio the camera shows no out-of-bounds area, and enemies still appear as intended. |
| H7.4 | **Written October 28, 2026 (`docs/trackH/H7.4-notes.md`), awaiting your run.** InputMap foundation: keep the existing actions (`move_*`, `attack_light`, `attack_heavy`, `dash`, `weapon_next`, `skill_1` to `skill_3`) and add controller bindings to each (left stick and D-pad for move, triggers or face buttons for attacks and dash, a shoulder button for `weapon_next`, buttons for skills). Add `aim_left/right/up/down` for the right stick and change `_get_aim_direction()` to take the stick when it is past its dead zone, otherwise the mouse (or touch aim), otherwise the facing direction. | M | A controller plays the whole combat set; the right stick aims the bow; keyboard and mouse behave exactly as before. |
| H7.5 | **Written October 28, 2026 (`docs/trackH/H7.5-notes.md`), awaiting your run.** Input-mode manager (an autoload or a Main child): tracks the last-used device (keyboard/mouse, controller, touch), starts as touch on Android and iOS, emits a `device_changed` signal, and does not assume a connected controller is the active device. | M | Switching devices updates the active mode; a test drives each device and checks the mode. |
| H7.6 | **Written October 28, 2026 (`docs/trackH/H7.6-notes.md`), awaiting your run.** Mobile controls: a `MobileControls` group in the HUD (`Main.tscn` CanvasLayer) with a move stick, an aim stick (D11), and buttons for `attack_light`, `attack_heavy` (hold), `dash`, `weapon_next` and `skill_1` to `skill_3`. Buttons trigger the same input actions (a `TouchScreenButton` has an `action` property), never a separate combat path. Anchors and containers, not fixed pixel positions. Shown on touch devices only; a debug toggle forces it on for testing. | L | On touch, every combat action works; on desktop the overlay is hidden; keyboard and controller still trigger the same actions. |
| H7.7 | **Written October 28, 2026 (`docs/trackH/H7.7-notes.md`), awaiting your run.** HUD layout and prompts: skill bar, health and mana stay readable and clear of the touch controls at every target ratio and keep their anchors; optional `DesktopControls` and controller prompts follow `device_changed`. | M | No overlap with combat information at 16:9, 21:9 and 4:3; prompts change with the active device. |
| H7.8 | **Written October 28, 2026 (`docs/trackH/H7.8-notes.md`), awaiting your run.** Tests: a table that fires each action from each device and checks the same gameplay method runs; aim source priority; heavy-attack hold timing from a held button; all three skill slots; mobile controls visible only when intended. Then the device matrix in section 5b. | M | The checks are in the suite and green; the matrix is filled in. |
| H7.9 | Docs: link this phase from `docs/STATUS.md`; add the new-weapon rule in section 6. | S | STATUS shows H7 progress. |


---

## 5. Play-test checklist (H1.1)
- Bow: draw (0.5 s), shot, return; four quick taps; hold for the heavy shot; click during the heavy shot.
- Switch sword and bow during a cooldown, just after a cast, and during a swing (it should refuse).
- Goblin hit during its slash (D2).
- Bleed on the goblin and the archer (expect nothing until H2.1).
- Rising Strikes, heal on hit, bleed on hit, low-health bonus.
- Dash and lunge near walls and enemies.
- Compact enemy health bar; skill bar cooldown wipe after switching back.
- Player death: what happens (N4).

## 5b. Device checklist (H7.8, from the guide)
- Landscape 16:9 phone or emulator.
- Portrait or tall ratio, if supported (D10).
- Resizable desktop window.
- Ultrawide display or an equivalent test viewport.
- Touch controls appear only when intended.
- Keyboard/mouse and controller trigger the same gameplay actions.
- UI stays readable and does not cover important combat information.
- Camera limits, enemy visibility and level boundaries stay correct.
- Bow aiming, charged attacks, dash and all three skill slots work on every supported device.

## 6. Definition of Done for any new exported field (from audit 9.15)
Which function reads it? Does it apply to every behavior or only one? Is it duplicated elsewhere? Is the unit clear (seconds, pixels, multiplier, bonus)? Does validation check range and cross-field rules? What happens if it is wrong or changed at runtime? Is there a check proving it changes behavior? A field that fails the first question is removed, or marked reserved.

## 7. Suggested order and effort
H0 (S) → H1 (you) → H2.1, H2.3, H2.4 (quick wins) → H3 → H4 → H2.2 and H2.6 (they need decisions) → H7.1 to H7.5 → H5 → H6 (with H7.6 to H7.9 alongside). H0 to H4 together are roughly one to two weeks of part-time work; H5 is optional.

A new weapon, attack or skill also reads only named input actions (never a device or the mouse directly), so it works on keyboard/mouse, controller and touch without extra code.
