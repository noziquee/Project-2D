# Phase 9 implementation plan (living document)

Each step ends with a smoke-test run (`godot --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd`) and a zip of only the changed and new files. A step is only "done" once its SUMMARY line has been checked against the expected number in its notes.

## Status

| Step | What | Status | Expected SUMMARY | Confirmed in Godot |
|---|---|---|---|---|
| 9.0 | Test trust, parse error, path helper, quick wins | done (9.0 and 9.0b) | 244 / 0 (then 318 / 0) | yes (607 / 0, Oct 24) |
| 9.1 | `attacks` array and `try_start_attack(id)` | done | 264 / 0 | yes |
| 9.2 | Attack ids, `attack_light` / `attack_heavy` input | done (9.2a, 9.2b) | 266 / 23 | yes (23 later repaired) |
| 9.3 | Weighted AI attack choice | done | 279 / 23 | yes |
| 9.4 | Combos: `next_attack`, window events, chaining, shipped combo | done (9.4a–e) | 318 / 23 | yes (607 / 0, Oct 24) |
| 9.0b | Repair the 23 health-value checks | done | 318 / 0 | yes (607 / 0, Oct 24) |
| 9.5a | Player heavy attack (scene-authored) | done | 326 / 0 | yes (607 / 0, Oct 24) |
| 9.5b | Goblin lunge and weighted AI choice | data was missing from the archive; rebuilt in 9.5b (see 9.5b-notes) | see notes | yes (607 / 0, Oct 24) |
| 9.6a | Looping combo sequences, repeat when unlinked, reset | done (code and tests only) | 339 / 0 | yes (607 / 0, Oct 24) |
| 9.6b | Return on window close | done (code and tests only) | 343 / 0 | yes (607 / 0, Oct 24) |
| 9.6c | Heavy charge and release modes | done (component API and tests; player wiring in 9.6d) | 354 / 0 | yes (607 / 0, Oct 24) |
| 9.6d | Player wiring: press, hold, release | done | 361 / 0 | yes (607 / 0, Oct 24) |
| 9.R | Player attacks on the new `sword_*` clips, shipped light combo link | done (data and tests) | see 9.R-notes | yes (607 / 0, Oct 24) |
| 9.R2 | Combo restart at chain end, return-before-attack rule tested, heavy release flow tested, charge retry, `get_charge_ratio()` | done (code and tests) | see 9.R2-notes | yes (607 / 0, Oct 24) |
| 9.7a | `WeaponDefinition2D` resource, validation, shipped `SwordWeaponDefinition.tres` (data and tests only, nothing equips it) | done (data and tests) | baseline + 32 new checks (section II) | yes (607 / 0, Oct 24) |
| 9.7b | Sword as a weapon scene (`Weapons/Sword.tscn`), `CharacterContext2D` reads the weapon player from it | done (scene, code and tests) | baseline + 32 new checks (section JJ) | yes (607 / 0, Oct 24) |
| 9.7c-1 | `WeaponController2D` dry run: `validate_equip()` / `can_equip()`, changes nothing | done (code and tests) | previous total + 19 (section KK) | yes (607 / 0, Oct 24) |
| 9.7c-2 | `equip()` for the weapon already mounted: set default attack and `attacks`, roll back on failure, `weapon_equipped` / `equip_failed` | done (code and tests) | previous total + 20 (section LL) | yes (607 / 0, Oct 24) |
| 9.7c-3 | `equip()` swaps to another weapon scene (free old `MainHand`, mount, `bind_weapon`, rewire `animation_finished`), restores the old weapon on failure | done (code and tests) | previous total + 16 (section MM adds 19, section LL loses 3) | yes (607 / 0, Oct 24) |
| 9.7c-4 | `Character2D` resolves an optional `WeaponController2D`; `starting_weapon` equipped at initialize; node added to `player.tscn` in the editor with the sword as starting weapon | done (code and tests; needs the editor steps) | previous total + 8 (section NN) | yes (607 / 0, Oct 24) |
| 9.7c-4 (editor step) | `WeaponController2D` node added to `player.tscn` with the sword as starting weapon (done in text, `player.tscn` re-sent) | done | NN1a to NN3d now pass | yes (607 / 0, Oct 24) |
| 9.7d-1 | `player.gd` takes the light and heavy ids from the equipped weapon (`get_light_attack_id()`, `get_heavy_attack_id()`); the two exports become empty overrides | done (code and tests) | previous total + 12 (section OO) | yes (607 / 0, Oct 24) |
| 9.7d-2 | README controls and "add an attack or weapon", `IMPLEMENTATION_NOTES.md` for Phases 9.0 to 9.7 | done (docs only) | unchanged (no code or test change) | n/a |
| 9.7d-3 | Refresh stale notes and this plan, duplicate guide copies, leftover Threshold values on `DefaultAttackDefinition.tres` | done (docs only; the root guide copies were deleted in the Oct 24 cleanup) | unchanged | n/a |

| 9.8a | Effect clip per attack: `effect_animation` on `AttackDefinition2D`, played by `AttackSlash2D`; the shipped heavy uses the scene's `heavy_slash` | done (code, data and tests) | previous total + 12 (section PP) | yes (607 / 0, Oct 24) |

**Baseline (Oct 24 2026, after V2b):** `SUMMARY passes=607 failures=0`. Every later step counts "previous total + N" from 607. The older Expected SUMMARY numbers in the table above were predictions made at the time; the run confirmed the final total, not each intermediate one.

**Run history:** first real run 585 / 22 (after Phase 10.5); V2a 590 / 17; V2b 607 / 0. Details in `docs/phaseV/`.

**Still not confirmed by playing:** the smoke test proves the code paths, not the feel. V3 (play-test) is still open.

## Decisions (recorded 2026-10-24)

1. **Light combo loop.** A light attack may have a `combo_sequence` (an ordered list of attacks). The combo index advances on each chain, wraps back to the first attack at the end of the sequence, and resets to the first attack when the combo ends. The combo ends when the window closes with no press, when a hit interrupts the chain, or when the character dies. It does not reset when a link finishes normally inside a chain.
2. **No sequence means repeat, or restart (changed in 9.R2).** A standalone attack with no link still repeats itself. At the end of a chain (the last link has no `next_attack`), a press inside its window starts the combo's first attack again. A self-link still means "repeat".
3. **Return on window close.** When the window closes without a press, the return clip of the attack that was last performed starts at once. It cuts the rest of the weapon clip. Attacks with no window keep today's behaviour (the return starts when the weapon clip ends).
4. **Heavy tap threshold.** A press shorter than 0.1 s that is released is a light attack. A press held longer than 0.1 s starts a heavy charge. (This replaces the current `heavy_hold_time` of 0.25 s as the charge start.)
5. **Threshold release.** In threshold mode the heavy fires when the charge reaches its threshold, even while the button is held. Releasing afterwards does nothing. The next press starts a new charge.
6. **Charge does not change numbers.** Charge changes timing and the release only. Damage and knockback stay fixed per attack for now.

## Steps

### 9.6a – light combo sequence (looping)
- `AttackDefinition2D.combo_sequence: Array[AttackDefinition2D]`, the ordered list of attacks a light combo runs through. Empty = repeat the attack itself (decision 2).
- `next_attack` stays as a shortcut for a two-attack link; it is equivalent to a sequence of one follow-up.
- `AttackComponent2D` keeps a runtime `_combo_index` (never stored in the resource). A chain uses the attack at the index and advances it; wrap at the end.
- Validation: every entry must be registered on the component, and entries are checked for clips like `attacks` (9.1). W4 changes on purpose (decision 2).
- Tests: a three-step sequence loops 1→2→3→1; no sequence repeats; the index resets when the combo ends (window closes with no press, interrupt, death); `next_attack` still works.
- Expected SUMMARY: to be set in the step notes (current 331 + new checks, minus W4 expectation changed in place).

### 9.6b – return on window close
- When `combo_window_close` fires and no request arrived, start the last performed attack's `recovery_animation` immediately (decision 3).
- If the attack has no recovery clip, finish it at once.
- The rest of the weapon clip is cut. Tests check the return starts at the close key, and that the attack with no window is unchanged.
- Expected SUMMARY: to be set in the step notes.

### 9.6c – heavy charge and release modes
- New fields on `AttackDefinition2D` (group "Charge"): `charge_animation` (plays while charging, may be empty), `charge_threshold` (seconds, 0 = no threshold), `release_mode` (enum: INPUT_RELEASE, THRESHOLD).
- Charge clock in `AttackComponent2D`: starts after the 0.1 s tap threshold (decision 4), holds the charge clip, and fires the heavy on release (INPUT_RELEASE) or at the threshold (THRESHOLD, decision 5).
- Tests: a tap under 0.1 s is light; INPUT_RELEASE fires on release; THRESHOLD fires at the threshold while still held; a second press after a threshold release starts a new charge.
- Expected SUMMARY: to be set in the step notes.

### 9.6d – player wiring
- `player.gd` sends press, hold and release to the component (charge start, release) rather than a one-shot request.
- `heavy_hold_time` is replaced by the charge start (0.1 s) and each heavy's own threshold.
- Tests U and BB are rewritten on purpose; their notes say which checks changed.
- Expected SUMMARY: to be set in the step notes.

## Phase 9.7 – weapons (guide section 10.5)

The updated guide builds the rest of Phase 9 as a weapon framework: a weapon owns its combo and heavy attack, and (from 9.7b) its own scene with the clips. Each step leaves the game playable and ends with a smoke-test run.

### 9.7a – WeaponDefinition2D (done)
- `Characters/Components/Weapons/WeaponDefinition2D.gd`: `weapon_id`, `display_name`, `weapon_scene` (optional until 9.7b), `basic_combo`, `heavy_attack`. Data only: no runtime state.
- `validate(animation_player = null)` returns messages naming the weapon and the problem: empty id, no combo attack, empty or duplicate ids, links that leave the weapon, unreachable combo entries, and (with an AnimationPlayer) missing weapon, recovery and charge clips.
- `Data/Weapons/SwordWeaponDefinition.tres`: the shipped sword (light, light2, heavy). Tests prove it matches what the player has registered today.
- No scene or character changes.

### 9.7b – sword as a weapon scene (done)
- `Weapons/Sword.tscn`: root `MainHand` (a Node2D with the pose the player's `MainHand` had), the `weapon` sprite and `HandAnim` with the eight clips that used to live in `player.tscn` (moved verbatim). `player.tscn` now holds one instance node, `WeaponFacingPivot/MainHand`, so every path the game and tests use is unchanged.
- `CharacterContext2D`: `find_weapon_player(weapon_root)` (static; `HandAnim`, `WeaponAnimation`, else the first `AnimationPlayer` child), a mounted weapon under any name on the player rig, and `bind_weapon(weapon_root)` for 9.7c. Both existing rig layouts keep working.
- `WeaponDefinition2D`: `instantiate_weapon()` and `validate_scene()`. `SwordWeaponDefinition.tres` sets `weapon_scene`.
- Risk handled: the `attack_event` method tracks (`../..`) resolve from the weapon root, so the weapon must be a child of `WeaponFacingPivot`. Tests JJ3a/JJ3b prove it for the shipped clips.

### 9.7c – WeaponController2D (built in four sub-steps, see the status table)
- `equip(weapon)`: validates against the weapon's AnimationPlayer, sets the default attack and `attacks` on `AttackComponent2D` (`set_attacks` already exists), swaps the weapon scene. A failed validation keeps the old weapon.
- Decisions assumed: equipping during a swing or charge is refused (not cancelled); the controller is an optional child, so the goblin is unaffected; only the player rig (`WeaponFacingPivot`) can swap weapons.
- Why `equip()` is more than a setter: `AttackComponent2D.initialize()` connects `animation_finished` to the weapon player once and `bind_weapon()` does not reconnect it; clip validation runs against the current weapon player, so bind first, then set attacks; combo, charge and cooldown state must be cleared; the old `MainHand` must be freed at once so the new one keeps its name.

### 9.7d – player wiring and docs
- Split into 9.7d-1 (`player.gd` ids from the equipped weapon, done), 9.7d-2 (README and IMPLEMENTATION_NOTES) and 9.7d-3 (stale notes, duplicate guides, leftovers).

Not in 9.7: projectiles, the effect base class, `AttackSpawnPoint`, skills, passives (guide phases 3 to 5).

## Risks
- **Unverified scene edits.** 9.4e, 9.5a and 9.5b edited `.tscn` and `.tres` as text. A Godot load error would make the whole chain of numbers meaningless. Open the project once before trusting any SUMMARY.
- **Animation timing.** Return-on-close (9.6b) changes how the light attack feels. Tune in play, not in tests.
- **Shared resources.** Combo indexes and charge clocks must live in the component. Storing them in a `.tres` would leak between characters.

## Open items outside Phase 9
- Done (Oct 24 cleanup): the two duplicate guide copies in the project root are deleted; the guide lives only in `docs/`.
- Done in V4: the leftover Threshold values on `DefaultAttackDefinition.tres` were cleared (see `docs/phaseV/V4-notes.md`).
- A forward movement impulse for the goblin lunge (needs `MovementComponent2D`).
- Projectiles, active skills and passives (guide phases 3 to 5): see `docs/Combat-Roadmap-Step-by-Step-Plan.md`.
