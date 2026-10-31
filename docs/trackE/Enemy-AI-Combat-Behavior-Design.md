# Enemy AI Combat Behavior and Weapon-Driven Decision Design

Project: Project-2D
Engine: Godot 4.7
Document type: Architecture review and implementation roadmap
**Status (October 30, 2026): first versions of Phases A to F are written in code. Nothing has been run in Godot yet, so no item below counts as verified. Phase G (regression run and encounter play-test) is not done.** Details: `E0-audit-and-status.md` and the per-step notes in this folder (`C3`, `DE1` to `DE3`, `E2` to `E4`).

---

## 1. Objective

Upgrade the current enemy AI from basic target pursuit and weighted attack selection into a tactical combat system that supports:

- Light-attack combos.
- Heavy attacks and configurable charge behavior.
- Weapon-defined active skills.
- Distinct enemy behavior patterns.
- Tactical positioning, repositioning, and recovery.
- Readable attack telegraphs and punishable openings.
- Reusable AI profiles that work across different enemies and weapons.

The system must preserve the project's existing combat architecture and avoid duplicating combat logic between players and enemies.

Core principle: Weapons define what an entity can do. AI behavior determines when, why, and how it uses those abilities.

## 2. Current AI Assessment

Original assessment, from the architecture review of "Project-2D(20261029-130406).zip". The "Now" column is the state on October 30, 2026.

### 2.1 Existing functionality (at the time of the review)

- `EnemyAIController2D.gd` handles target detection or selection, pursuit, attack requests, and returning toward the starting position when no target remains.
- `EnemyBehaviorProfile.gd` and `AttackChoice2D.gd` support weighted selection between registered attacks.
- The reviewed goblin profile favors `Sword_Slash1` over `GoblinSword_Lunge`.
- The AI supports a wind-up before requesting an attack.
- A warning lane is displayed for recognized heavy attacks.
- Weapon definitions support an `active_skills` collection, providing a potential source for available skills.

### 2.2 Identified limitations

| # | Limitation | Now |
|---|---|---|
| 1 | Light combos: attacks chosen individually, no combo step | Written: `preferred_combo_length`, `combo_recovery_pause`, `last_combo_decision` |
| 2 | Heavy attacks ignore openings, distance, likelihood of connecting | Written: `heavy_wait_for_opening`, opening reasons, hit prediction over the charge time (C3), fallback attack |
| 3 | Enemy skills not in the AI request path | Written: `skill_usage_priority`, dash, projectile, area and self-buff skills. Ally support and ground circles not possible yet |
| 4 | Weighted selection gives no behavior differences | Written: six profiles, `minimum_combat_range`, `preferred_combat_range`, target switching |
| 5 | Warning lane only for heavy attacks | Partly: `telegraph_all_attacks` for every attack, skill aim shapes via `skill_windup_duration`. Ground circle and dash strike circle not drawn |
| 6 | No action-commitment rules | Written: the AI is free to move only outside swing, cast, dash, charge, wind-up and stun; slots and target switching respect it |

These findings were verified by reading the code on October 30, 2026 (`E0-audit-and-status.md`), not by a run.

### 2.3 Overall assessment

The original AI was a target-chasing AI with weighted single-attack selection. The upgrade extends its decision-making instead of replacing the system, as recommended.

---

## 3. Design References

Inspirations for gameplay behavior, not claims about the games' internal AI.

| Game | Design principle | Application to Project-2D |
|---|---|---|
| Dead Cells | Telegraphs, committed attacks, combos, recovery openings | Readable wind-ups, intentional combo sequences, punishable recovery |
| Wizard of Legend | Spell variety and combinations of attack shapes | Casters that alternate projectiles, area attacks, and control skills |
| Wuthering Waves | Readable combat rhythm and punish opportunities | Deliberate attacks, clear danger windows, tactical recovery |
| Terraria | Reusable enemy AI patterns | Shared melee, ranged, charging, and other behavior archetypes |
| Albion Online | Weapon-driven combat identity | Weapons own their attack and skill definitions |
| Stardew Valley | Simple but recognizable enemy personalities | Low-cost profiles with distinct movement and attack tendencies |
| Battleheart Legacy | Distinct action-RPG roles | Frontline, ranged, support, and ability-focused enemies |
| Soul Knight | Recognizable projectile patterns and ranged threats | Projectile bursts, spreads, spacing, and elite variations |

Priority: (1) Dead Cells: commitment, telegraphs, combos, recovery. (2) Terraria: reusable archetypes. (3) Albion Online: weapon-owned abilities. (4) Battleheart Legacy: distinct roles. (5) Wizard of Legend, Wuthering Waves, Soul Knight, Stardew Valley: spell variety, readable rhythm, projectile patterns, recognizable personalities.

---

## 4. Target Architecture

### 4.1 EnemyAIController2D
Acquires and validates targets, evaluates the situation, chooses an action, requests movement, attacks and skills, manages decision timing, and reassesses after an action. It does not own attack definitions, skill implementations or damage logic.

### 4.2 EnemyBehaviorProfile
The enemy's combat personality: aggression, preferred distance, combo length, heavy and skill priority, repositioning, recovery patience, target switching. It influences decisions but does not redefine weapon attacks or skills.

### 4.3 Equipped weapon and definitions
The weapon provides light attacks and combo links, heavy attacks, active skills, projectiles and effects. An enemy and a player use the same weapon assets.

### 4.4 Shared combat execution
The AI requests actions through `AttackComponent2D`, `SkillComponent2D`, `WeaponController2D`, the combat state machine, animation and effect systems, and hit detection. Verified in code: the AI publishes requests that `Character2D` consumes; skills go through `SkillComponent2D.try_use_skill` after `can_use`.

---

## 5. Combat Decision Loop

Hybrid of a lightweight state machine and utility-based selection:

1. Acquire or validate the target.
2. With no valid target, idle, patrol or return.
3. If an action is committed, let its animation, hit timing and recovery finish.
4. Gather available attacks and skills from the equipped weapon.
5. Filter out illegal actions.
6. Evaluate the rest against tactical conditions and the profile.
7. Request the best action through the existing combat pipeline.
8. Reassess after it completes.

Hard legality checks (target validity, range, target type, cooldown, resources, state and commitment, line of sight if supported, cast/charge/combo-window requirements) always come first. Randomness never bypasses them.

*Status:* the written code is a state-driven priority loop with weighted and rolled choices, not a scored utility evaluation. Target type, line of sight and casting rules are not checked separately by the AI.

---

## 6. Light-Attack Combo System

Light attacks are sequences. The AI reads the weapon's combo links, tracks the step, respects the continuation window, considers whether the next attack can connect, lets profiles prefer shorter or longer combos, stops when continuation is no longer appropriate, and preserves existing animation, hit and recovery logic. It never invents combo steps.

*Status:* written (B2, B3 checks).

---

## 7. Heavy-Attack Decision System

Heavy attacks are chosen for tactical openings, not cooldown alone: effective range, target vulnerable or committed, wind-up length, likelihood the target leaves the area, area or control effect, profile risk preference. Charge style stays in the attack definition. The warning matches the attack's shape, range, width, direction and active window, and the attack may miss naturally.

*Status:* openings, hit prediction, charge from the definition and a fallback attack are written (C1 to C3). `heavy_attack_priority` was not added (nothing needed it). The lane uses the attack's reach, width and aim direction.

---

## 8. Weapon-Skill Decision System

Enemies use the active skills of the equipped weapon: discovered through the weapon's collection, cooldown and cost checked, target and range validated, casting and state respected, executed through `SkillComponent2D`, not cast just because ready, chosen by purpose, with a fallback.

*Status:* written for dash, projectile, area and self-buff skills, with an optional warning shape before the cast (D1, D2, D3). Not done: ally support (needs a new skill behavior), ground circles (the skill component cannot cast at a point), and choosing by skill-purpose metadata.

---

## 9. Reusable Enemy Behavior Profiles

Data-driven and reusable.

| Profile | Design intent | Status |
|---|---|---|
| 9.1 Aggressive combo fighter | persistent, longer combos, clear recovery windows | `AggressiveMeleeProfile.tres` |
| 9.2 Patient duelist | waits for openings, short combos, heavy on vulnerable targets | `PatientMeleeProfile.tres` |
| 9.3 Ranged skirmisher | holds distance, circles, repositions | `RangedSkirmisherProfile.tres` |
| 9.4 Tactical caster | alternates projectiles and area skills, repositions | `TacticalCasterProfile.tres` (no caster weapon exists yet) |
| 9.5 Support or commander | support skills for allies, safe position | not built: needs an ally skill behavior |
| 9.6 Simple common enemy | inexpensive logic, limited moves | `SimpleCommonProfile.tres` |
| Elite example | heavy, skill warning, switching | `GoblinEliteProfile.tres` with `GoblinElite.tscn` |

Profile fields that exist: `preferred_combo_length`, `combo_recovery_pause`, `heavy_wait_for_opening`, `skill_usage_priority`, `skill_windup_duration`, `minimum_combat_range`, `preferred_combat_range`, `max_simultaneous_attackers`, `max_simultaneous_heavies`, `circle_while_waiting`, `target_switching` (with margin and interval), `telegraph_all_attacks`, plus the originals (`attack_windup_duration`, `attack_interval`, detection and disengage radii).

Proposed names deliberately not added: `maximum_combat_range` (the attack's range is the maximum), `heavy_attack_priority`, `aggression`, `light_combo_probability`, `reposition_probability`, `decision_cooldown`, `randomness`. Add one only when tuning shows a measurable need.

---

## 10. Group Combat and Fairness

Safeguards and their status:

- Attack-slot coordination: written (`max_simultaneous_attackers`, heavy limit; slots stored on the target). Off by default.
- Avoid synchronized heavies: `max_simultaneous_heavies`.
- Room for ranged enemies: repositioning (E2). No wall or enemy avoidance yet.
- No pointless target switching: `target_switching` is off by default, with a margin, a minimum interval, and never during a swing or while holding a slot.
- Action commitment and recovery: preserved.
- Attacks can miss: preserved.
- Complex coordination for elites and bosses: not started.

---

## 11. Implementation Roadmap and Status

| Phase | Scope | Status |
|---|---|---|
| A Audit and contracts | request paths documented | Done: `E0-audit-and-status.md` |
| B Combo-aware light attacks | combo steps, continuation | Written, not run |
| C Tactical heavy attacks | openings, prediction, charge | Written, not run |
| D Enemy skill integration | discover and request weapon skills | Written for self buffs, dash, projectile and area; support and ground circle open |
| E Behavior profiles | aggressive, patient, skirmisher, caster | Written, plus simple and elite; not run |
| F Readability and positioning | telegraphs, recovery, repositioning, groups | Partly written: all-attack lane, skill shapes, slots, circling, switching. Ground circle and dash strike circle open |
| G Regression testing and tuning | automated and encounter tests | Not done. The suite has about 70 Track E checks written; none run. Play-test arena: `TrackEArena.tscn` |

Exit criteria for each phase are unchanged from the original design; none is met until the suite and play-test have run.

---

## 12. Acceptance Criteria

"In code" means written, not run.

- [~] Enemies use only attacks and skills of their equipped weapon (in code).
- [~] Players and enemies reference the same weapon, attack and skill resources (in code; the archer uses the player's bow).
- [~] Light combos progress through valid links and stop when illegal (in code).
- [~] Heavy attacks respect range, target, state, charge and timing (in code).
- [~] Skills respect cooldowns, costs, target requirements and casting rules (cooldown and cost via `can_use`; target requirements and casting rules not separate).
- [~] No overlapping actions during forbidden states or committed attacks (in code).
- [ ] Telegraphs match the attack's effective geometry and direction (lane and skill shapes only; ground circle and dash strike circle open).
- [~] Attacks can miss naturally (unchanged behavior).
- [~] Profiles produce observable differences (in code; confirm in the arena).
- [~] Random selection reproducible (seeded per controller).
- [ ] Existing player combat and enemy behavior remain functional (needs the full run).
- [~] Debug output identifies the action, rejected candidates, combo step and reasons: `last_combo_decision`, `last_heavy_decision`, `last_skill_decision`, `last_slot_decision`, `last_target_decision`, `last_attack_candidates` (attack picks only; skill rejections are in `last_skill_decision`).

---

## 13. Implementation Safeguards

1. Do not bypass `AttackComponent2D`, `SkillComponent2D`, or the state machine.
2. Do not duplicate player weapon data into enemy-specific definitions.
3. Do not hardcode skills or attack sequences into enemy scripts.
4. Do not allow randomness to bypass legality checks.
5. Do not add every proposed profile parameter without validating its usefulness.
6. Preserve existing public interfaces where possible.
7. Keep debug instrumentation for action selection and rejected decisions.
8. Make incremental changes and run regression tests after each phase.
9. Treat the weapon definition as the source of available actions.
10. Profiles hold personality and preferences, not attack execution.

All new profile fields default to the old behavior, so the shipped goblin and `Main.tscn` are unchanged.

---

## 14. Final Recommendation and Next Steps

Implement a hybrid state-driven enemy AI with profile-based decisions: the state machine says what is legal, the decision layer chooses, the profile sets personality, and the weapon provides the actions. This is the shape of the code now.

Next:

1. Run `tools/run_checks.sh` and record the result (Track E parts: `enemy_ai_combo`, `enemy_ai_heavy`, `enemy_ai_heavy_wait`, `enemy_ai_skill`, `enemy_ai_profiles`, `enemy_ai_slots`).
2. Play-test `TrackEArena.tscn`; tune values.
3. Decide on ally support skills, ground-circle casting (DE4) and a caster weapon.
4. Commit.
