# Combat roadmap: what is not built yet, step by step

> **Status (Oct 27, 2026):** the single source of truth is `docs/STATUS.md`. Last automated result: `SUMMARY passes=1109 failures=0`, headless Godot 4.7.2, Oct 26. Per-step "expected N / 0" counts below are history; steps that say "not run separately" were verified by that one full run. The play-test and your own editor run are still open.

*Project-2D · Godot 4.7 · written October 24, 2026 from the code in the archive (Phase 9.8a) and the guide `Combat Architecture Review & Expansion Guide (Updated Oct 2026).md` in this folder. Nothing here was run in Godot.*

This continues `docs/phase9/PLAN.md`. Same rules as Phase 9: small steps, each leaves the game playable, each ends with a smoke-test run and a zip of only the changed and new files, and a step is done only when its SUMMARY line matches the expected number in its notes.

## How to read this plan

- **Phase V** is verification. Nothing else should start before it, because every step from 9.2 onward is unconfirmed in Godot.
- **Phases 10 to 14** are the missing systems, in dependency order: effect framework, projectiles and bow, damage resolver, skills, passives.
- **Track P** (presentation and data cleanup) is independent. Any P step can be done after Phase V, between other phases.
- **Track W** (weapon-owned content: one folder per weapon, generic attack names, a real goblin weapon) is planned in `docs/trackW/W0-plan.md` and **must be finished before P2**, because it changes where weapon files live and how the goblin gets its weapon.
- **Phase 15** is content and polish: more weapons, VFX, sound.
- Every step lists **Do**, **Tests** and **Done when**. New classes use the `2D` suffix and new folders are added only when a step needs them (guide 10.4 and 10.6).

## Status at a glance

| Phase | What | Status |
|---|---|---|
| V | Verify and stabilize Phase 9 | **V6 (Oct 25): simple enemy health bar; the smoke test stopped at R22 because the bar node was renamed; now `SUMMARY passes=887 failures=0` in headless Godot 4.7.2 (`docs/phaseV/V6-notes.md`).** V5 (Oct 25): Phase 12 run, 726 / 0, new baseline. V1 import and V2 smoke test done: **`SUMMARY passes=607 failures=0`** (baseline, `docs/phaseV/V2-baseline-notes.md`). V4 done. Open and only you can do them: opening and playing `Main.tscn` in the editor (rest of V1) and the V3 play-test |
| 10 | Effect framework (base class, spawn point, hit policy, legacy cleanup) | 10.1 to 10.5 done and confirmed by the 607 / 0 run |
| 11 | Projectiles and the bow | **Phase 11 done** (11.1 to 11.5), run in headless Godot 4.7.2: **`SUMMARY passes=680 failures=0`** (11.1 alone gave 623 / 0, 11.4 gave 669). Notes in `docs/phase11/` |
| 12 | Combat resolver (defense, crits, status effects) | **Phase 12 done** (12.1 to 12.4, 46 new checks). Full run after V5 in headless Godot 4.7.2: **`SUMMARY passes=726 failures=0`**. Notes in `docs/phase12/`; the first run's failures were editor-tuned values, see `docs/phaseV/V5-notes.md` |
| 13 | Active skills | 13.0 decisions, 13.1 `SkillDefinition2D` and 13.2 `SkillComponent2D` / `ManaComponent2D` done, run in headless Godot 4.7.2: **`SUMMARY passes=760 failures=0`** (726 + 34). **13.3.1 projectile skill done (Oct 25), run in headless Godot 4.7.2: `SUMMARY passes=776 failures=0`** (760 + 16, `docs/phase13/13.3.1-notes.md`). **13.3.2 area skill written (Oct 25), not run separately; covered by the full run of Oct 26 (`SUMMARY passes=1109 failures=0`)** (776 + 15, `docs/phase13/13.3.2-notes.md`). **13.3.3 dash skill written (Oct 25), not run separately; covered by the full run of Oct 26 (`SUMMARY passes=1109 failures=0`)** (791 + 13, `docs/phase13/13.3.3-notes.md`). **13.3.4 buff skill written (Oct 25), not run separately; covered by the full run of Oct 26 (`SUMMARY passes=1109 failures=0`)** (804 + 11, `docs/phase13/13.3.4-notes.md`). 13.3.5 channel (only if a weapon needs it) not started. **13.4 (input, HUD and the first playable skills; the old 13.4 and 13.5 are merged) is planned in 8 segments, 13.4.1 to 13.4.8 (`docs/phase13/13.4-plan.md`). 13.4.1 (skill signals and HUD read API) source present, runtime verified by the V6 and Oct 26 headless runs; play-test open (`docs/phase13/13.4.1-notes.md`); 13.4.2 (the player gets the skill components and the skill keys) source integration completed during 13.4.6, runtime verified by the V6 and Oct 26 headless runs; play-test open (`docs/phase13/13.4.2-notes.md`); 13.4.3 (the shipped skills on the sword and bow) source data present, with slot 1 upgraded to Spin and Multi-shot in 13.4.7; runtime verified by the V6 and Oct 26 headless runs; play-test open (`docs/phase13/13.4.3-notes.md`); 13.4.4 (scene-based mana bar) implemented; covered by the V6 and Oct 26 headless runs, play-test open (`docs/phase13/13.4.4-notes.md`); **13.4.5 (reusable scene-based SkillSlot with cooldown wipe and feedback animations) implemented; covered by the V6 and Oct 26 headless runs, play-test open (`docs/phase13/13.4.5-notes.md`, checks SSS1–SSS11); 13.4.6 (three-slot SkillBar, weapon switching, Input Map labels, and missing player input/component integration) implemented; covered by the V6 and Oct 26 headless runs, play-test open (`docs/phase13/13.4.6-notes.md`, checks TTT1–TTT11); 13.4.7 (Spin, Multi-shot volley fields, weapon data and tests) implemented; covered by the V6 and Oct 26 headless runs, play-test open (`docs/phase13/13.4.7-notes.md`, checks UUU1–UUU7); 13.4.8 documentation/checklist done. The final Phase 13.4 smoke run was done headless in V6: 885 / 0, then 887 / 0 (see `docs/phaseV/V6-notes.md`); it still needs your own run and the play-test checklist.** Notes in `docs/phase13/` |
| 14 | Passives | **14.0 rules, 14.1 `PassiveDefinition2D` / `PassiveController2D` and 14.2 first passive (Rising Strikes) written (Oct 25), not run separately; covered by the full run of Oct 26 (`SUMMARY passes=1109 failures=0`)** (887 + 21, `docs/phase14/`). **14.3 event passives written (Oct 25), not run separately; covered by the full run of Oct 26 (`SUMMARY passes=1109 failures=0`)** (908 + 12, `docs/phase14/14.3-notes.md`) |
| W | Weapon folders and shared attack data (before P2) | **W0–W9 done (W9 = the first real run).** W1–W3 organize weapon scenes, definitions, attacks, skills and projectiles; W4 renames ids; W5 adds `GoblinSword` and wires the goblin; W6 gives `GoblinArcher` an enemy-specific Bow definition; W7 audits shared references and animation clips; W8 aligns the README, implementation notes, architecture guide and roadmap. No `Shared/` folder: shared resources stay in the first weapon's folder. See `docs/trackW/W0-plan.md` and `W1`–`W8` notes. **Runtime status:** **First real run (Oct 26, headless Godot 4.7.2): import clean; after the repairs in `docs/trackP/P2-notes.md` the suite ran to the end with 1096 passes / 13 failures. Decisions made (keep the sword loadout as it is in the files; keep the 0.5 s bow draw); the 4 bow-cycle checks were retimed: `SUMMARY passes=1109 failures=0` (`docs/trackW/W9-notes.md`). Track W is now runtime-verified in headless Godot.** ||
| P | Presentation and data cleanup (reactions, stagger, rig paths, hurtbox, team targeting) | **P1 `ReactionComponent2D` done (Oct 25), run in headless Godot 4.7: `SUMMARY passes=932 failures=0`** (the archive's 920 + 12, `docs/trackP/P1-notes.md`). **P8 `FacingComponent2D` done (Oct 25), run in headless Godot 4.7: `SUMMARY passes=942 failures=0`** (932 + 10, `docs/trackP/P8-notes.md`). **P9 charge aim, sticky facing, bow rest pose and settle blend done (Oct 25), 973 / 0** (`docs/trackP/P9-notes.md`). **P10 code-driven return done (Oct 25), `SUMMARY passes=986 failures=0`** (`docs/trackP/P10-notes.md`). **P2.1 and P2.2 exported rig paths done (Oct 25 to 26), 9 new checks pass** (`docs/trackP/P2-notes.md`); P3 to P7 not started |
| 15 | More weapons, VFX, sound, polish | not started |

## Decisions to make before the phase that needs them

| Decision | Needed by | Starting recommendation |
|---|---|---|
| Characters with no `attack_definition`: refuse attacks with an error, or keep one marked default | 10.1 | **Decided: refuse with a clear error.** `player.tscn` now sets its own definition. |
| Hit-once rule: per effect (today) or per swing | 10.4 | **Decided: per effect** (melee and, later, per projectile) |
| Resource for skill costs: stamina, mana, or none | 13.0 | **Decided: optional per skill, NONE or MANA** (`ManaComponent2D`), see `docs/phase13/13.0-notes.md` |
| Number of skill slots: fixed (3 or 4) or per weapon | 13.0 | **Decided: 3 slots per weapon**, skills live on `WeaponDefinition2D` |
| Passive counter rules: do misses count, multi-target counts once per target or per attack, can stacks overlap | 14.0 | **Decided: misses do not count, once per attack, rewards do not overlap**; full table in `docs/phase14/14.0-notes.md` |
| Threshold release values left on `DefaultAttackDefinition.tres` | V4 | **Decided: cleared** (inert, no check reads them) |
| Weapon content layout: one folder per weapon, `Weapons/Shared/` for resources used by two or more weapons, attacks named by action not by character | W1 | **Decided Oct 25 (`docs/trackW/W0-plan.md`): no `Shared/` folder, a resource stays in the folder of the first weapon that created it; the goblin uses the sword's slash effect and numbers for now; skill icons stay in `UI/HUD/Icons/` until you make your own folder in `2D_RPG_Assets`; `weapon_mount` on `WeaponController2D`; the goblin archer uses the Bow folder; no redirect for old paths. Q1 answered: the goblin lunge also takes the sword's damage, knockback and hit stun. Q2 answered: the weapon is in the file name. Q3 answered: resource ids follow the new file names (W4)** |
| Skill keys, radial wipe approach, multi-shot fields, HUD signals | 13.4 | **Decided in `docs/phase13/13.4-plan.md`**: keys 1 to 3, a `TextureProgressBar` wipe, `projectile_count` and `spread_degrees`, new `SkillComponent2D` signals. Change them before the segment that needs them |

---

## Phase V: verify and stabilize Phase 9

### V1. Open the project once
- **Do:** Run `godot --headless --import --path .`, then open the project in Godot 4.7 and run `Main.tscn`. Read the whole Output panel. Several `.tscn` and `.tres` files were edited as text (9.4e, 9.5a, 9.5b, 9.7b, 9.7c-4), so a load error is possible.
- **Done when:** the project opens and the game starts with no errors, or every error is fixed or reported with its text.

### V2. Smoke test and baseline
- **Do:** Run `godot --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd`. Paste the `SUMMARY passes=N failures=M` line and every `CHECK FAIL` line.
- **Expected in the log, not failures:** the rejected-definition errors and the `no_such_effect_clip` messages named in `docs/phase9/9.8a-notes.md`.
- **Done when:** failures are 0 (or each failure is fixed), and the real total is written into `docs/phase9/PLAN.md` as the new baseline. Every later "previous total + N" is counted from it.
- **Done (Oct 24 2026):** `SUMMARY passes=607 failures=0`, written into `docs/phase9/PLAN.md`. The leak lines at exit are not failures (see `docs/phaseV/V2-baseline-notes.md`).
- **Progress:** the first real run gave `SUMMARY passes=585 failures=22`; after V2a 590 / 17. V2b found the cause of most of the rest: `Main.tscn` holds nine goblins and the checks only controlled one. Notes in `docs/phaseV/`. The final total goes into `docs/phase9/PLAN.md` when failures reach 0.

### V3. Play-test checklist
Check each in the running game and note what feels wrong:
- Light combo: tap chains light, light2, back to light; stops when the window closes; resets after an interrupt.
- Heavy: a tap (under 0.1 s) is light; a hold charges; release swings. Check the charge clip and the `heavy_slash` look and reach (use Debug > Visible Collision Shapes).
- Weapon: the sword is equipped at start; swapping or a refused equip leaves the old weapon working.
- Aim: swing toward the mouse straight up and straight down (guide finding G).
- Goblin: it picks its second attack (the lunge) and the swing distance matches the real reach.
- Interrupt: a hit during a swing cancels it and the character returns to idle or run.
- **Done when:** each item passes or is logged as a bug. Fix bugs before Phase 10.

### V4. Small decisions and leftovers
- Decide the leftover Threshold values on `DefaultAttackDefinition.tres`. **Done (V4):** cleared.
- Update the validation note in `IMPLEMENTATION_NOTES.md` with the confirmed results. **Done:** it states the 607 / 0 baseline.
- **Done when:** both are written down.

---

## Phase 10: effect framework (guide finding B and I, phase 3 groundwork)

Goal: a new attack kind (arrow, burst, follow-up effect) is a new scene and script with the same `configure(...)` signature, so `AttackComponent2D` never needs to know which one it spawned.

### 10.1. Remove the legacy slash fallbacks (done, see `docs/phase10/10.1-notes.md`)
- **Do:** In `AttackComponent2D.gd` remove `attack_slash_scene`, `slash_scene`, `set_slash_scene()` and `DEFAULT_SLASH`, and make `_spawn_effect` use only the definition's `effect_scene`. Apply the decision above for `DEFAULT_ATTACK` (in `AttackComponent2D.gd` and the `Character2D.attack_definition` setter). Remove the deprecated wording in `AttackDefinition2D.gd` and `IMPLEMENTATION_NOTES.md`. Every shipped `.tres` already sets `effect_scene`, so game content does not change.
- **Why it is a step and not part of the cleanup zip:** test `I27` checks the legacy fallback on purpose, so removing it means rewriting that test, and the baseline has not been run yet.
- **Tests:** rewrite `I26` and `I27` on purpose (a definition with no `effect_scene` is rejected with an error naming the attack). `M6` stays. Say in the notes which checks changed.
- **Done when:** no `slash_scene` or `DEFAULT_SLASH` is left in the code, and the SUMMARY matches the notes.

### 10.2. `AttackEffect2D` base class (done, see `docs/phase10/10.2-notes.md`)
- **Do:** Add `Characters/Components/Combat/AttackEffect2D.gd` (a `Node2D` base) holding the shared parts: `configure(...)` with the current signature, the `hit_contact` and `hit_confirmed` signals, the target filter (not the attacker, `apply_hit`, not the same team) and hit-once tracking. `AttackSlash2D` extends it and keeps its behavior.
- **Tests:** the existing hit, friendly-fire and hit-once checks pass unchanged; add one check that `AttackSlash2D` is an `AttackEffect2D`.
- **Done when:** no behavior change and the SUMMARY is the previous total + the new checks.

### 10.3. Exported node paths and clip names on `AttackSlash2D` (done, see `docs/phase10/10.3-notes.md`)
- **Do:** Replace the fixed `@onready` paths (`$SlashEffectAnimSpritesheet/AnimationPlayer`, `$HitboxOrigin/...`) with exported `NodePath`s that default to today's names. `effect_animation` is already on the definition (9.8a).
- **Tests:** a scene that renames a node and sets the path still works; the shipped scene is untouched.
- **Done when:** a differently built effect scene works without editing the script.

### 10.4. Hit policy: pierce and max targets (done, see `docs/phase10/10.4-notes.md`)
- **Do:** Add `max_targets` (0 = unlimited) and `pierce: bool` to `AttackDefinition2D` and pass them through `configure(...)` (new last arguments with defaults). Decide per-effect or per-swing hit-once as in the decisions table.
- **Tests:** an effect with `max_targets = 1` hits only one of two targets; the default still hits both; the same target is hit once per effect.
- **Done when:** the policy is data on the definition and the defaults keep today's behavior.

### 10.5. `AttackSpawnPoint` (done, see `docs/phase10/10.5-notes.md`)
- **Do:** Add an optional `Marker2D` named `AttackSpawnPoint` to the character scenes and an exported path on `Character2D` (or `CharacterContext2D`). `_spawn_effect` uses it when present and falls back to `character.global_position`.
- **Tests:** with a marker, the effect spawns at its position; without one, at the attacker's origin as today.
- **Done when:** both shipped characters still behave the same and an attack can originate from a hand or a staff tip.

---

## Phase 11: projectiles and the bow (guide phase 3)

Build the bow only after Phase 10. Its job is to prove that a different weapon type needs no changes to `AttackComponent2D`.

### 11.1. `ProjectileEffect2D` (done and confirmed, 623 / 0, see `docs/phase11/11.1-notes.md`)
- **Do:** Add a script and scene that extends `AttackEffect2D`: velocity along the attack direction, a collision mask from `hit_layers`, a lifetime, and an impact. Hits go through `HitData` and `HealthComponent2D.apply_hit()`; the impact spawns the definition's `hit_effect_scene`. Respect `pierce` and `max_targets` from 10.4. It frees itself on impact, expiry or hitting the world layer.
- **Tests:** it travels, hits an enemy, stops on a wall (world layer value 4), expires after its lifetime, never hits the shooter or the same team, and pierce works.
- **Done when:** a test spawns an arrow and it damages a goblin through the normal damage path.

### 11.2. Arrow attack definition (done, see `docs/phase11/11.2-notes.md`)
- **Do:** `ArrowAttackDefinition.tres` with `effect_scene = Arrow.tscn`, damage, knockback, and a projectile speed field (a new `projectile_speed` on `AttackDefinition2D`, ignored by melee effects).
- **Done when:** the validation messages name the attack and clip as for melee.

### 11.3. Bow weapon scene and definition (done, see `docs/phase11/11.3-notes.md`)
- **Do:** `Weapons/Bow.tscn` (sprite plus `AnimationPlayer` with draw, release and return clips, and an `attack_event(&"spawn_effect")` key at release). `Data/Weapons/BowWeaponDefinition.tres` with `basic_combo` (one shot) and `heavy_attack` (a charged piercing shot using the Phase 9.6c charge fields).
- **Done when:** `validate_equip()` for the bow returns no problems.

### 11.4. Weapon switching input (done, see `docs/phase11/11.4-notes.md`)
- **Do:** Add a `weapon_next` input action and wire it to `WeaponController2D.equip()` in `player.gd`. Equip is already refused during a swing or charge.
- **Tests:** swap sword to bow to sword; a failed equip rolls back; the light and heavy ids come from the equipped weapon (9.7d-1).
- **Done when:** you can play with both weapons and switch freely.

### 11.5. Goblin archer (optional proof; done, see `docs/phase11/11.5-notes.md`)
- **Do:** An enemy using the bow definition with a ranged `ai_attack_range`. If AI needs a ranged behavior, add it as its own small step and leave `EnemyAIController2D`'s `Behavior` enum alone until then (guide section 6, item 9).

---

## Phase 12: combat resolver (guide phase 3 to 5 groundwork)

Goal: one place calculates final damage for melee, projectiles, skills and passives. `HitData` and `HealthComponent2D.apply_hit()` stay the foundation.

### 12.1. Route all damage through one function (done, see `docs/phase12/12.1-notes.md`)
- **Do:** Add `CombatResolver2D` (a static helper or a small node) with `resolve(hit: HitData, target) -> HitData`, doing nothing yet. `apply_hit` calls it first.
- **Tests:** results are identical to today; all damage sources (melee, projectile) pass through it.
- **Done when:** there is a single place to extend and no behavior change.

### 12.2. Defense (done, see `docs/phase12/12.2-notes.md`)
- **Do:** A `defense` value on the target (on `HealthComponent2D` or a small stats resource) and a damage-reduction formula in the resolver. Write the formula in the notes.
- **Tests:** zero defense changes nothing; defense lowers damage; damage never drops below a minimum.

### 12.3. Critical hits (done, see `docs/phase12/12.3-notes.md`)
- **Do:** `crit_chance` and `crit_multiplier` (on the attacker's stats or the definition). Use a seedable random source so tests are deterministic.
- **Tests:** chance 0 never crits, chance 1 always crits, the multiplier is applied once.

### 12.4. Status effect framework (done, see `docs/phase12/12.4-notes.md`)
- **Do:** `StatusEffectDefinition2D` (resource: id, duration, tick interval, stack rule, tick damage or modifier) and `StatusController2D` (runtime node: apply, refresh, stack, expire, remove). Runtime state lives in the controller, never in the `.tres`.
- **Tests:** a bleed ticks damage on schedule, expires, refreshes on reapply, stacks per its rule, and clears on death.
- **Done when:** a definition can apply a status on hit with no new script.

---

## Phase 13: active skills (guide phase 4)

### 13.0. Decisions (done, see `docs/phase13/13.0-notes.md`)
- Settle the slot count and cost resource from the decisions table. Write them in the notes.

### 13.1. `SkillDefinition2D` (done, see `docs/phase13/13.1-notes.md`)
- **Do:** A resource with id, name, icon, slot, cooldown, cost, cast or channel time, targeting, range, area shape, animation and effect references, and a behavior type. Add the commented-out `active_skills` array on `WeaponDefinition2D` and validate it like attacks (clips, ids, duplicates).

### 13.2. `SkillComponent2D` executor (done, see `docs/phase13/13.2-notes.md`)
- **Do:** Validate (cooldown, cost, not dashing, not stunned), start the cast, run the behavior, start the cooldown. Reuse `AttackComponent2D` gating rules instead of writing new ones. Cooldowns live in the component.
- **Tests:** cooldown blocks a second use; a failed cost refuses cleanly; an interrupt cancels a cast.

### 13.3. Reusable behaviors, one at a time
1. Projectile skill (uses `ProjectileEffect2D`). **13.3.1 done, see `docs/phase13/13.3.1-notes.md`.**
2. Area skill (an area effect scene, a new `AttackEffect2D` subclass). **13.3.2 written; covered by the Oct 26 full run (1109 / 0), see `docs/phase13/13.3.2-notes.md`.**
3. Dash skill (reuse `DashComponent2D` for movement). **13.3.3 written; covered by the Oct 26 full run (1109 / 0), see `docs/phase13/13.3.3-notes.md`.**
4. Buff skill (uses the status framework from 12.4). **13.3.4 written; covered by the Oct 26 full run (1109 / 0), see `docs/phase13/13.3.4-notes.md`.** It adds `damage_multiplier` to statuses and applies it in `CombatResolver2D`.
5. Channel skill (last, only if a weapon needs it).
- **Done when:** each behavior has one shipped skill and one test.

### 13.4. Input, HUD and the first playable skills (planned in 8 segments; the old 13.5 is merged in)
Why merged: a skill HUD with empty slots cannot be play-tested, so the first skills go on the sword and the bow inside this phase. The full plan, with the decisions, tests and risks, is in `docs/phase13/13.4-plan.md`. The addon `game-components-addon` (cooldown and ability systems) is used as a visual and behavior reference only; the HUD is built as scenes with an `AnimationPlayer`, as the health bar is, and `SkillComponent2D` stays the only owner of cooldowns and costs.

**Gate:** passed (covered by the Oct 26 full run, 1109 / 0).

| Segment | What | Playable after it |
|---|---|---|
| 13.4.1 | **Source present; runtime verification deferred to the final Phase 13.4 smoke test.** `SkillComponent2D` signals for the HUD (`cooldown_started`, `cooldown_finished`, `skill_refused`, `skills_changed`) and `get_cooldown_duration()`, `get_cast_progress()` | no visible change |
| 13.4.2 | **Prerequisite source integration completed during 13.4.6; runtime verification deferred to the final Phase 13.4 smoke test.** Player gets `ManaComponent2D`, `SkillComponent2D`, `StatusController2D`; input actions `skill_1` to `skill_3` (keys 1 to 3) and the `player.gd` hook | keys activate equipped skills |
| 13.4.3 | **Source data present; runtime verification deferred to the final Phase 13.4 smoke test.** Current loadouts: sword Lunge, Spin, Empowerment; bow Power Shot, Multi-shot, Empowerment; placeholder icons | skills work by key, no HUD |
| 13.4.4 | **Implemented; headless-verified (V6 and Oct 26 runs), play-test open; see `docs/phase13/13.4.4-notes.md`.** Scene-based `ManaBar.tscn` and `ManaBar.gd`, blue `.tres` fill, intro/spend/restore clips, bound to the player mana component | mana visible (headless-verified; play-test open) |
| 13.4.5 | **Implemented; headless-verified (V6 and Oct 26 runs), play-test open; see `docs/phase13/13.4.5-notes.md`.** Reusable `SkillSlot.tscn`: icon, radial wipe, seconds, hotkey, cost, cast progress, and ready / denied / started / unaffordable clips | one slot in a test scene (headless-verified; play-test open) |
| 13.4.6 | **Implemented; headless-verified (V6 and Oct 26 runs), play-test open; see `docs/phase13/13.4.6-notes.md`.** Three-slot `SkillBar.tscn` in `Main.tscn`, follows weapon switches, Input Map hotkeys update on rebind; missing player component/input prerequisites were added | full HUD |
| 13.4.7 | **Implemented; headless-verified (V6 and Oct 26 runs), play-test open; see `docs/phase13/13.4.7-notes.md`.** Sword Spin, bow Multi-shot volley, data validation, centered SELF area placement and weapon loadouts; dash-slash variant deferred pending play-test feedback | full first skill set |
| 13.4.8 | **Documentation and checklist done; headless summary recorded (see `docs/STATUS.md`); manual play-test observations still open.** README, implementation notes, roadmap status and play-test checklist updated | ready for final smoke test |

- **Done when:** the sword and the bow each have three skills, the bar shows them with working cooldown wipes, the mana bar moves as you cast, and the final SUMMARY is in the README.

---

## Phase 14: passives (guide phase 5)

### 14.0. Write the counter rules (done, see `docs/phase14/14.0-notes.md`)
- Do misses count, how counters reset, once per target or once per attack, whether stacks overlap. Put the answers in the step notes before any code.

### 14.1. `PassiveDefinition2D` and `PassiveController2D` (written; headless-verified Oct 26, see `docs/phase14/14.1-notes.md`)
- **Do:** A resource describing trigger event, condition, counter and effect, and a runtime controller that connects to `attack_started`, `attack_hit`, `attack_finished`, `damaged`, `died` (all already emitted) and tracks stacks. Add the commented-out `passive_skills` array to `WeaponDefinition2D`.

### 14.2. First passive as the test (written; headless-verified Oct 26, see `docs/phase14/14.2-notes.md`)
- **Do:** The guide's example: three qualifying hits grant an empowered state that the next attack consumes for bonus damage.
- **Tests:** counts only the hits your rules allow, resets as written, the empowered state is consumed once.

### 14.3. Event passives (written; headless-verified Oct 26, see `docs/phase14/14.3-notes.md`)
- Heal on hit, bonus damage below a health threshold, bleed on hit (uses 12.4). One test each.

---

## Track W: weapon-owned content (before P2; full plan in `docs/trackW/W0-plan.md`)

Why: attacks and skills are spread over `Weapons/`, `Data/Weapons/`, `Characters/Components/Combat/` and `Characters/Components/Skills/`, they carry character names (`PlayerLight...`, `Goblin...`), and the goblin's knife is baked into `BasicEnemy2D.tscn` with no weapon definition. Goal: one folder per weapon (`Weapons/Sword`, `Weapons/Bow`, `Weapons/GoblinSword`; a resource lives in the folder of the first weapon that created it, no `Shared/`), weapon-named files (`Sword_Slash1`, `Sword_Slash2`, `GoblinSword_Lunge`), shared attack and skill resources where behavior matches, and a goblin that uses its own weapon definition and scene.

Rules: preserve behavior, move before rename, rename before changing ids, one step per commit, every step ends with the import and the smoke test. No `.gd` system is rewritten; only `WeaponController2D` gets one new field (`weapon_mount`, W5) and `smoke_checks.gd` gets path and id updates.

| Step | What | Expected SUMMARY |
|---|---|---|
| W0 | The plan, the decisions and this roadmap update (**done, documents only**) | 986 / 0 unchanged |
| W1 | Move weapon scenes and weapon definitions into `Weapons/Sword/` and `Weapons/Bow/` (**written Oct 25; verified in the Oct 26 full run**, `docs/trackW/W1-notes.md`) | 986 / 0 |
| W2 | Move attack, skill and arrow files into the folder of the weapon that created them (old names kept) (**written Oct 25; verified in the Oct 26 full run**, `docs/trackW/W2-notes.md`) | 986 / 0 |
| W3 | Rename files with the weapon in the name, e.g. `Sword_Slash1.tres`, `Bow_ArrowShot.tres` (ids unchanged) (**written Oct 25; verified in the Oct 26 full run**, `docs/trackW/W3-notes.md`) | 986 / 0 |
| W4 | Rename ids to follow the file names (Q3 answered: yes); 2 new checks (**written Oct 25; verified in the Oct 26 full run**, `docs/trackW/W4-notes.md`) | 988 / 0 |
| W5 | `GoblinSword` scene and definition, `weapon_mount` on `WeaponController2D`, goblin wired through it; 14 new checks. Built in increments: W5a `weapon_mount` (**written Oct 25; verified in the Oct 26 full run**, 6 checks, 994 at the time, `docs/trackW/W5a-notes.md`), W5b the `GoblinSword` scene and definition (**written Oct 25; verified in the Oct 26 full run**, 4 checks, 998 at the time, `docs/trackW/W5b-notes.md`), W5c the goblin lunge on the goblin sword (**written Oct 25; verified in the Oct 26 full run**, 3 checks, 1001 at the time, `docs/trackW/W5c-notes.md`), then the enemy wiring | 1002 / 0 at the end |
| W6 | Goblin archer onto the Bow folder (**written Oct 25; verified in the Oct 26 full run**, `docs/trackW/W6-notes.md`) | 1025 expected at the time; final result 1109 / 0 (W9) |
| W7 | Cross-weapon reference audit and clip validation (**source changes written Oct 25; verified in the Oct 26 full run**, `docs/trackW/W7-notes.md`) | 1030 expected at the time; final result 1109 / 0 (W9) |
| W8 | README, implementation notes, guide and roadmap docs (**documentation updated**) | no code change; runtime verified in W9 (1109 / 0) |

- **Source/docs done when:** a new weapon is a new folder under `Weapons/`, the goblin and player use the same kinds of resources, no weapon-specific content remains in the framework folders, and docs match the current layout. **Runtime done when:** Godot import and smoke checks pass and the actual SUMMARY is recorded in the README. Track W's runtime gate was passed in W9 (headless, Oct 26); the play-test is still open.

---

## Track P: presentation and data cleanup (any time after Phase V)

Each of these removes a place where adding content still needs a script change. Do them when the next new character or weapon needs them, not all at once. Order below is by value (guide section 6).

- **P1. `ReactionComponent2D` (done, 932 / 0, see `docs/trackP/P1-notes.md`).** Listens to `damaged` and `died` and plays exported clip names and effect scenes. Moves the hard-coded `take_damage`, `RESET` and `death` strings out of `player.gd` and `BasicEnemy2D.gd`. *Done when:* a new enemy needs no presentation script.
- **P2. Exported rig paths (done: five exported paths on `Character2D`, `BasicEnemy2D` reads its sprite from the context, 9 checks pass; see `docs/trackP/P2-notes.md`).** Exported `NodePath`s on `Character2D` for the visual root, locomotion player, weapon player and weapon pivot, defaulting to today's names, replacing the name lookups in `CharacterContext2D._init`. *Done when:* a third character layout works without copying node names.
- **P3. Locomotion clip names (P3.1 done: `idle_clip` and `run_clip` exports on `Character2D`, 4 checks pass; see `docs/trackP/P3-notes.md`).** Exported `StringName`s on the states, or one `CharacterAnimationSet` resource, for `idle`, `run` and the `RESET` clip used in `AttackComponent2D`.
- **P4. Team targeting (done: `_is_hostile` replaces `target_group`, 4 checks pass; see `docs/trackP/P4-notes.md`).** `EnemyAIController2D` targets any character on a different team instead of the `player` group; the `DetectionArea` mask still filters. *Done when:* `target_group` is gone.
- **P5. `Hurtbox` component (done: `Hurtbox2D`, the `damageable` group check is gone from the hit rules, 4 checks pass; see `docs/trackP/P5-notes.md`).** An `Area2D` that forwards hits to `HealthComponent2D`, so crates and switches take hits without joining the `damageable` group by hand (this also removes the group check in `AttackSlash2D`).
- **P6. `Stagger` state (done: optional `StaggerState` node, 7 checks pass; no character has one yet; see `docs/trackP/P6-notes.md`).** A state node plus a reaction clip, added only to characters that should flinch when hit stun applies.
- **P7. Goblin lunge impulse (done: `forward_impulse` and `impulse_duration` on `AttackDefinition2D`, 6 checks pass; see `docs/trackP/P7-notes.md`).** A forward movement impulse in `MovementComponent2D` for the lunge (listed as open in `docs/phase9/PLAN.md`).
- **P8. `FacingComponent2D` (done, 942 / 0, see `docs/trackP/P8-notes.md`).** Moved the facing flip and weapon aim out of `Character2D`, with mirroring, art direction and weapon aim as fields.

---

## Phase 15: more weapons and polish (guide phase 6)

- One weapon at a time, each as content only: scene, clips, effect scenes, attack `.tres` files, one `WeaponDefinition2D`, and one new smoke check per attack. Suggested order: fire staff (projectile plus burn), war hammer (slam and stagger, needs P6), dual daggers (fast combo plus bleed), spear.
- VFX: slash and projectile trails, charge-up visuals and release effects, weapon-specific impacts.
- Sound: swing, hit, block and skill cues, configured on attack and weapon resources, never hard-coded in player or enemy scripts.
- Feedback for crits, status effects and skill activation.
- Debug tools and resource validation extended to skills, passives and statuses.
- Balancing pass.

## Housekeeping that stays open

- Keep exactly one copy of the guide, in `docs/` (done in this cleanup).
- Keep `.godot/` out of archives (it is in `.gitignore`).
- Treat any `CharacterContext2D` warning as a blocker (guide section 9).
- Prefer adding fields to resources; renaming silently resets saved values.
- After any timing change, update the smoke-test waits deliberately; do not loosen assertions.
