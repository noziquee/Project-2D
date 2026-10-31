# Track E: Enemy AI combat behavior. E0 audit and status

Written October 30, 2026 from a read of the archive (branch `track-h`, uncommitted working tree). **Godot was not available, so none of the checks named here have been run.** The design document ("Enemy AI Combat Behavior and Weapon-Driven Decision Design", status "not implemented") is out of date: first versions of its Phases B to E are already in the code.

## Request paths (Phase A)

AI -> character -> shared combat. The AI never starts combat itself; it only publishes requests that `Character2D` consumes.

| Step | Where |
|---|---|
| Decide | `EnemyAIController2D.physics_update()` (`Characters/Controllers/`) |
| Publish | `consume_attack_request()`, `consume_charge_request()`, `consume_release_request()`, `get_attack_direction()`, `get_movement_intent()`; `BasicEnemy2D` forwards them to `Character2D` hooks |
| Execute attacks | `Character2D` calls `AttackComponent2D.try_start_attack / begin_charge / release_charge` (`Character2D.gd` ~184 to 205) |
| Execute skills | AI calls `SkillComponent2D.try_use_skill(id, dir)` directly, after `can_use(id)` |
| Combo state read | `AttackComponent2D.is_combo_window_open()`, `get_active_attack_id()`, `get_next_attack()` |
| Weapon data | the equipped weapon's attacks and `active_skills`; the profile only picks among registered attacks (`AttackChoice2D`, weighted) |
| Warning | `EnemyAttackTelegraph2D`, a generic forward lane (length = attack range, width = `hitbox_size.y`) |

No combat or damage logic is duplicated in the AI. Doc item: `AttackChoice2D` lives in `Controllers/`, not `Components/Combat/`.

## Status against the roadmap

| Phase | Status | In the code | Checks (part) |
|---|---|---|---|
| A Audit | Done by this file | see above | none |
| B Light combos | Mostly done | `preferred_combo_length`, `combo_recovery_pause`, `_wants_combo_continue()`, `last_combo_decision` | B2-1..4, B3-1..3 (`enemy_ai_combo`) |
| C Heavy attacks | Mostly done | `heavy_wait_for_opening`, `_opening_reason()`, hit prediction over the charge time (C3, written, not run; `C3-notes.md`), fallback attack, `last_heavy_decision`. No `heavy_attack_priority` | C1-1..3 (`enemy_ai_heavy`), C2-1..5, C3-1..2 (`enemy_ai_heavy_wait`) |
| D Skills | Partial | `skill_usage_priority`, `_try_use_skill()`, `_skill_problem()`; dash, projectile, area, and self buffs (DE1, written, not run; `DE1-notes.md`). Ally support needs a new skill behavior | D1-1..5, D2-1..4 (`enemy_ai_skill`) |
| E Profiles | Mostly done | `Profiles/` Aggressive, Patient, Ranged Skirmisher, Tactical Caster; `minimum_combat_range` retreat; `preferred_combat_range` repositioning (E2, written, not run; `E2-notes.md`) | E1-1..7, E2-1..5 (`enemy_ai_profiles`) |
| F Readability, groups | Partial | lane exists (D29); attack slots and circling while waiting (DE2, written, not run; `DE2-notes.md`). Skill warning shapes (DE3, written, not run; `DE3-notes.md`). Ground circle warning, target switching: not started | DE2-1..10 (`enemy_ai_slots`), D3-1..5 |
| G Regression | Not done | | full run needed |

## Acceptance checklist (design doc section 12)

- Equipped-weapon actions only: yes for skills and attacks (read from the components). Unverified by a run.
- Same resources for player and enemy: yes since D26 (archer uses `Bow_WeaponDefinition`).
- Combos stop when illegal: yes (B). Heavy respects range and state: partly (opening check only).
- Skills respect cooldown, cost: via `can_use`; target requirement and casting rules: not checked separately.
- Telegraph matches geometry: lane only, not other shapes or skills. Open.
- Profiles differ observably: E1 checks; confirm after a run.
- Reproducible randomness: `rng` is per controller and the suite seeds it (`_seed_added_node`).
- Debug output: last decision strings only; no rejected-candidate list for attacks. Open.

## Open work, in order

1. Run `tools/run_checks.sh`; record the result for the five `enemy_ai_*` parts and the new total in `STATUS.md`.
2. Commit this work (it is uncommitted).
3. C: range and hit-likelihood in the heavy decision; `heavy_attack_priority` only if tuning needs it.
4. D: use skill purpose metadata where definitions have it; decide on BUFF and support skills.
5. E: preferred and maximum range, repositioning instead of straight retreat; support and simple-common profiles only if wanted.
6. F: telegraph for skills and other shapes, attack slots for groups, target-switching rule.
7. G: encounter play-test.

## Decisions (October 30, 2026)

- DE4: an enemy places a ground circle on its target's position, held inside the shape's `max_range`. Waits for the skill component to cast at a point (your ground-circle track); see `DE3-notes.md`.
- DE1: buff and support skills are in scope for enemies. Step 4 gains: use BUFF skills when a fight starts or the buff is not running; support skills need a valid ally target.
- DE2: group attack slots are wanted now (Phase F first item). Plan: a small shared coordinator (group `enemy_attack_coordinator`) grants a limited number of simultaneous attack tokens per target; an enemy without a token keeps spacing instead of starting its wind-up; the token is released when its swing ends. Heavy attacks take a token of their own so they do not stack.

Order: run the suite first (step 1 above), then DE1, then DE2.
