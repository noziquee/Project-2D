# Project-2D: Status

**Single source of truth.** If another document disagrees with this one, this one wins; fix the other.

| Item | Value |
|---|---|
| Last updated | October 27, 2026 |
| Godot | 4.7.2 (headless) |
| Import | Clean |
| Smoke suite | `SUMMARY passes=1198 failures=0` (October 27, 2026, your machine, headless Godot 4.7.2; all 34 parts; includes H2.1 to H4.7). Earlier green: 1109 / 0 on October 26 (`docs/trackW/W9-notes.md`) |
| First run of the H-track (October 27, 2026) | `1185 / 13`, then fixed: the player's `defense = 20` in `player.tscn` (kept as your balance value; `load_main()` pins it to 0 for tests) and the H3-22 weapon finder. Rerun: 1198 / 0. Then, with the error gate armed (October 27): `1198 / 0`, no `UNEXPECTED ERROR`; two full runs gave identical CHECK lines (H4.6 done). Still to do: commit `tests/expected_errors.txt` and push so CI runs (H4.7), then H4.5b (each part alone). |
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

D1 every combatant gets statuses · D2 goblin slash stays non-interruptible for now, goblin-owned `GoblinSword_Slash1/2` to be created · D3 skill `weapon_animation` = cast, then execute · D4 cooldowns character-wide by id · D5 status stacking stays additive (rename field) · D6 weapon definition owns attacks · D7 hide `channel_time` · D8 rename `max_range` per behavior.

## Rules on record (pinned by tests)

**Damage a character deals (D5, H4-6 to H4-15).** `multiplier = (1 + sum of (damage_multiplier - 1) x stacks over running statuses, never below 0) x (product of the wielder's passive multipliers that apply to the target)`. `damage = round(base x multiplier)`, at least 1 unless the multiplier is 0. A crit then multiplies that rounded damage; defense is subtracted last (minimum 1). Status bonuses add to each other, the passive multiplies the sum, and the product is rounded once. REFRESH keeps one stack and resets the timer, STACK adds one up to `max_stacks`, IGNORE leaves a running status alone. A status tick skips all of this.

**Cooldowns (D4, H4-16 to H4-19).** A cooldown belongs to the character and is keyed by skill id. It survives a weapon swap, keeps counting down while its skill is not equipped, ends and is announced even then, and is shared by every weapon that lists the same id, whatever slot it uses.

## Implemented and smoke-tested (automated pass only; no play-test yet)

- Combat core: attack components, combo/charge/heavy attacks, hit resolution, health, damage and crit.
- Weapons by folder (`Sword`, `Bow`, `GoblinSword`), weapon definitions, enemy Bow definition for the goblin archer, weapon switching with refusal during swing, charge and cast.
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
- `effect_animation` on area and projectile effects: still ignored by the effects, but a non-default value now earns a warning (H3.3). Equip logs weapon warnings; they never block it.

## Corrections to the audit

- N7 (slot collisions and duplicate skill ids are only runtime warnings) was partly wrong: `WeaponController2D.equip()` already refuses a weapon whose `validate()` reports them, and the old weapon stays. Only a direct `SkillComponent2D.set_skills()` call is lenient. H3.5 added four checks (H3-1 to H3-4) that pin both behaviors; no game code changed.

## Not implemented

- Channel skills (`channel_time` is hidden from the Inspector and must be 0, H2.3).
- Game over / respawn flow (not found in `player.gd` or `Main.tscn`; scope to be confirmed, N4).
- Gamepad bindings (scope to be confirmed, N5).
- Ground Slam is an example resource, not in any loadout.
- Dash-slash variant, fire staff and further weapons (Phase 15, after H0 to H4).

## Roadmap pointer

Plan: `Improvement-Roadmap-2026-10-27.md`. Current phase: **H0, H2.1, H2.2, H2.3, H2.4, H3.1 to H3.5, H4.1 to H4.4, H4.5a, H4.5c, H4.6 and H4.7 written, awaiting your copy-in and a `tools/run_checks.sh` run**; H2.3, H2.4 and all of H3 and H4.1 to H4.4 are written too; H4.5a and H4.5c written (suite split into 23 runnable parts, `docs/trackH/H4.5a-notes.md`, `H4.5c-notes.md`); H4.6 written (every random source seeded, global state reset before each part, `docs/trackH/H4.6-notes.md`); H4.7 written (GitHub Actions, `docs/trackH/H4.7-notes.md`); H2.2 written (a skill clip plays, then the skill executes, `docs/trackH/H2.2-notes.md`); next H2.6 (rename `max_range` by behavior, D8; migrates the `.tres` files) and H4.5b (run each part alone and compare with the full run), after you run the suite. H5 only once H3 and H4 are green.
