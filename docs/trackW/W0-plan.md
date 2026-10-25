# Track W: weapon-owned content, one folder per weapon

*Project-2D · Godot 4.7 · plan written October 25, 2026 from the code in the archive (after P10, last confirmed `SUMMARY passes=986 failures=0`). **Decisions D1 to D6 were answered the same day (see "Decisions" below and the changes they caused). W1 to W3 are written, not yet run; you will run one smoke test after Track W is finished (`docs/trackW/W1-notes.md` to `W3-notes.md`).** The track must be finished before P2 starts.*

Same rules as Phase 9: small steps, each leaves the game playable, each ends with an import, a smoke-test run and a zip of only the changed and new files. A step is done only when its SUMMARY line matches the number in its notes.

## Goal

Attacks and skills belong to **weapons**, not to characters. Today the player's sword attacks are called `PlayerLight...`, the goblin's are `Goblin...`, and the goblin's weapon is painted into `BasicEnemy2D.tscn`. After Track W:

- every weapon has one folder holding its scene, definition, attacks, skills, projectile and effects;
- attack and skill resources have generic names (`slash1`, `slash2`, `lunge_attack`) and are shared between weapons when they behave the same;
- the goblin carries a real `GoblinSword` weapon definition and scene, like the player's Sword and Bow;
- adding a weapon later means adding a folder, not editing scripts.

## What I found in the archive (these shape the plan)

| # | Finding | Consequence |
|---|---|---|
| 1 | Weapon content is spread over four places: `Weapons/` (scenes), `Data/Weapons/` (definitions), `Characters/Components/Combat/` (11 attack `.tres`, `Arrow.tscn`) and `Characters/Components/Skills/` (6 skill `.tres`). Skill icons are in `UI/HUD/Icons/`. | The move table below. Scripts (`.gd`) stay where they are. |
| 2 | **The goblin has no weapon definition.** Its knife is a `Sprite2D` plus a `WeaponAnimation` player baked into `BasicEnemy2D.tscn` (node `AnimatedSprite2D/Weapon`), and attacks come from `AttackComponent2D.attack_definition` and the AI profile. There is no `WeaponController2D` on it. | Step W5 is a real change, not a rename. |
| 3 | **`WeaponController2D` only swaps weapons under `WeaponFacingPivot`** (the layered player rig, layout A). The goblin is layout B: the weapon is a child of the `AnimatedSprite2D` so the sprite flip mirrors it (`CharacterContext2D._init`). `validate_equip()` refuses a character with no `WeaponFacingPivot`. | The controller needs a **mount parent** that is `WeaponFacingPivot` for the player and `AnimatedSprite2D` for the goblin. This touches the same code as P2, so W5 adds only that one field and P2 stays afterwards. |
| 4 | The goblin slash and lunge `attack_event` keys use the path `../..`, exactly like `Sword.tscn`. Mounted under `AnimatedSprite2D` the path still reaches the character. | The `GoblinSword` scene can reuse the same key path. Confirm in W5. |
| 5 | Attack `.tres` files name weapon clips (`weapon_animation = &"sword_slash_1"`, `&"lunge"`, `&"bow_shoot"`). | **Two weapons can share an attack file only if their scenes have a clip of that name.** Sharing is a clip-name convention, see "Naming" below. |
| 6 | Several `ext_resource` lines have **no `uid`** (`Arrow.tscn`, `GoblinArrowAttackDefinition.tres`, `GoblinLungeAttackDefinition.tres`, `AreaEffect2D.tscn` references, `Passives/`). Others have both uid and path. | After a move, a path-only line breaks; a uid line still resolves in the editor but the text path is stale. Both must be rewritten. |
| 7 | `tests/smoke_checks.gd` has **38 lines** with the old paths (`SWORD_WEAPON_PATH`, `BOW_WEAPON_PATH`, `ARROW_*_PATH`, `POWER_SHOT_PATH` ...) and many checks use attack ids such as `player_light`, `goblin_slash`. | Moving files means editing path constants. Renaming **ids** changes check text, so ids are renamed in their own step (W4). |
| 8 | `EmpowerSkillDefinition.tres` is already used by **both** sword and bow; `HitEffect.tscn`, `AttackSlash2D.tscn` and `AreaEffect2D.tscn` are used by sword, goblin and skills. | These are the first "shared" resources. |
| 9 | The goblin archer (`GoblinArcher.tscn`) inherits `BasicEnemy2D.tscn` and overrides the weapon sprite and clips with its own `bow_shoot` / `bow_return`. | It is moved to a bow definition in W6, after the goblin sword works. |

## Target structure (after the answers to D1 and D2: no `Shared/` folder)

A resource lives in the folder of **the first weapon that created it**, and later weapons point at it there. So everything the sword created (`slash1`, `slash2`, `heavy_slash`, the Empowerment skill ...) stays under `Weapons/Sword/`, even when the bow or the goblin sword also uses it.

```
Weapons/
├── Sword/
│   ├── Sword_WeaponDefinition.tres
│   ├── Sword.tscn                # was Weapons/Sword.tscn            (W1, done)
│   ├── Attacks/                  # Sword_Slash1.tres, Sword_Slash2.tres, Sword_HeavySlash.tres   (W2, W3 done)
│   └── Skills/                   # Sword_Lunge.tres, Sword_Spin.tres, Sword_GroundSlam.tres, Sword_Empower.tres (Empower is also used by the bow)
├── Bow/
│   ├── Bow_WeaponDefinition.tres
│   ├── Bow.tscn                  # was Weapons/Bow.tscn              (W1, done)
│   ├── bow.gd                    # was Weapons/Bow.gd                (W1, done)
│   ├── Attacks/                  # Bow_ArrowShot.tres, Bow_ArrowHeavy.tres, Bow_ArrowEnemy.tres
│   ├── Skills/                   # Bow_PowerShot.tres, Bow_MultiShot.tres
│   ├── Projectile/               # Bow_Arrow.tscn (extends ProjectileEffect2D; W2 and W3, done)
│   └── Effects/
└── GoblinSword/                  # new in W5
    ├── GoblinSword_WeaponDefinition.tres  # basic combo points at Sword/Attacks/Sword_Slash1.tres
    ├── GoblinSword.tscn          # knife sprite + clips taken from BasicEnemy2D.tscn
    └── Attacks/                  # GoblinSword_Lunge.tres (see W5)
```

**Stays where it is** (framework, not weapon content, and icons per D3): all `.gd` scripts under `Characters/Components/`, `AttackSlash2D.tscn`, `AreaEffect2D.tscn` and `ProjectileEffect2D.tscn` (base scenes that weapon effect scenes inherit from), `Characters/Effects/HitEffect.tscn`, `Characters/Components/Status/`, `Characters/Components/Passives/`, `UI/HUD/Icons/` (HUD textures, not weapon data; decision D3). `WeaponDefinition2D.gd` and `WeaponController2D.gd` stay in `Characters/Components/Weapons/`.

## Naming

- **Rule for weapon files (set by you, Oct 25):** every file carries its weapon's name; never a placeholder like `scene.tscn` or `weapon_definition.tres`. Scene `Sword.tscn`, `Bow.tscn`, `GoblinSword.tscn`; definition `Sword_WeaponDefinition.tres`, `Bow_WeaponDefinition.tres`, `GoblinSword_WeaponDefinition.tres`; a weapon script is lowercase, `bow.gd`.
- **Q2 answered (Oct 25): the weapon is in the file name** (`Sword_Slash1.tres`, `Bow_ArrowShot.tres`). W3 applies it.

- **Files:** generic action names, no character name: `slash1`, `slash2`, `heavy_slash`, `lunge_attack`, `arrow_shot`, `arrow_heavy`. A file lives in the `Attacks/` folder of the first weapon that created it, even when other weapons use it (D1).
- **Rename map (applied in W3; weapon name in the file name, your answer to Q2):**

| Today (after W2) | New name (W3) | Folder |
|---|---|---|
| `DefaultAttackDefinition.tres` (id `player_light`) | `Sword_Slash1.tres` | `Sword/Attacks/` (the goblin slash reuses it in W5, D2) |
| `PlayerLight2AttackDefinition.tres` (`player_light2`) | `Sword_Slash2.tres` | `Sword/Attacks/` |
| `PlayerHeavyAttackDefinition.tres` (`player_heavy`) | `Sword_HeavySlash.tres` | `Sword/Attacks/` |
| `LungeSkillDefinition.tres`, `SpinSkillDefinition.tres`, `GroundSlamSkillDefinition.tres` | `Sword_Lunge.tres`, `Sword_Spin.tres`, `Sword_GroundSlam.tres` | `Sword/Skills/` |
| `EmpowerSkillDefinition.tres` | `Sword_Empower.tres` (the bow points at it, D1) | `Sword/Skills/` |
| `ArrowAttackDefinition.tres` (`arrow_shot`) | `Bow_ArrowShot.tres` | `Bow/Attacks/` |
| `ArrowHeavyAttackDefinition.tres` (`arrow_heavy`) | `Bow_ArrowHeavy.tres` | `Bow/Attacks/` |
| `GoblinArrowAttackDefinition.tres` (`goblin_arrow`) | `Bow_ArrowEnemy.tres` (slower, 1 damage; numbers unchanged) | `Bow/Attacks/` |
| `PowerShotSkillDefinition.tres`, `MultiShotSkillDefinition.tres` | `Bow_PowerShot.tres`, `Bow_MultiShot.tres` | `Bow/Skills/` |
| `Arrow.tscn` | `Bow_Arrow.tscn` | `Bow/Projectile/` |
| `GoblinAttackDefinition.tres` (`goblin_slash`) | **removed in W5**, replaced by `Sword_Slash1.tres` (D2) | n/a |
| `GoblinLungeAttackDefinition.tres` (`goblin_lunge`) | `GoblinSword_Lunge.tres`, numbers from the sword's Lunge (Q1, see W5) | `GoblinSword/Attacks/` |

- **Resource ids** (`id = &"player_light"`) are renamed in W4, never in a move step. An attack id shows up in tests, the AI profile and error messages. Proposed ids: `sword_slash1`, `sword_slash2`, `sword_heavy_slash`, `bow_arrow_shot`, `bow_arrow_heavy`, `bow_arrow_enemy`, `goblin_sword_lunge` (final list in the W4 notes).
- **Clip-name convention for sharing.** A cross-weapon attack names a clip every weapon that uses it has. Proposed standard clips for melee weapons: `slash_1`, `slash_2`, `heavy_slash`, `lunge`. The sword scene keeps `sword_slash_1` etc. as aliases until W4 renames both sides; the goblin sword scene uses the standard names from the start.

## Decisions (answered October 25, 2026)

| # | Decision | Answer | What changes in the plan |
|---|---|---|---|
| D1 | Folder for resources used by 2+ weapons | **No `Shared/` folder.** A resource stays in the folder of the first weapon that created it. | The sword created `slash1`, `slash2`, `heavy_slash` and the Empowerment skill, so they live in `Weapons/Sword/`. The bow and the goblin sword reference them there. The W7 audit now checks cross-folder references instead of moving files. |
| D2 | Goblin slash numbers vs the sword's | **Use the same effect and numbers as the sword for now.** | No `slash_small.tres`. The goblin's basic attack is `Weapons/Sword/Attacks/Sword_Slash1.tres`. **This is a gameplay change** (goblin damage, hitbox and range become the sword's), so the goblin checks that name `goblin_slash` numbers are updated in W5, and the exact changes are listed in W5's notes. The goblin lunge: the sword has no lunge attack, so it stays its own `lunge_attack.tres` in `GoblinSword/Attacks/` unless you want it replaced as well (open question Q1). |
| D3 | Skill icons into weapon folders | **No.** You will make your own folder in `2D_RPG_Assets` later. | Icons stay in `UI/HUD/Icons/` for now. Skill files keep pointing there until you create the new folder. |
| D4 | Enemy mount point | **Yes: a `weapon_mount` field on `WeaponController2D`** (default `WeaponFacingPivot`; the goblin sets `AnimatedSprite2D`). | W5 as written. P2 stays afterwards. |
| D5 | Goblin archer | **Yes: it uses the Bow folder** with `Bow_ArrowEnemy.tres`. | W6 as written. |
| D6 | Redirect for old paths | **Not answered; the recommendation stands: no redirect.** | Clean move, every reference rewritten. Tell me if you want one. |

**Q1 answered (Oct 25): yes, the goblin lunge also uses the sword's numbers.** The sword's Lunge skill (`Sword_Lunge.tres`) carries its attack as an embedded resource: damage 5, knockback 200, hit stun 0.15, a 56x56 area burst. The goblin's AI picks attack files, not skills, so W5 makes `GoblinSword_Lunge.tres` and copies **damage, knockback and hit stun** from it. It keeps the goblin's `lunge` clip, movement multiplier, cooldown and AI range, and its melee effect scene and hitbox shape, because the sword's 56x56 burst is an area effect, not a forward thrust. Say so if you want the burst too. 

**Q3 answered Oct 25: yes, ids follow the file names (applied in W4, `W4-notes.md`).** Original question: resource ids follow the file names in snake case (`sword_slash1`, `bow_arrow_shot`). That changes ids that tests, AI profiles and messages use, which is why it is its own step. Tell me if you would rather keep the current ids (`player_light`, `goblin_slash` ...) and rename only the files.

## Steps

Each step lists **Do**, **Tests** and **Done when**. Every step starts with `git status` clean and ends with `godot --headless --import --path .` then the smoke test.

### W0. This plan (done when you read it)
- **Do:** this document and the roadmap update. No game file changes.
- **Done when:** you have answered D1 to D6 or accepted the recommendations.

### W1. Weapon scenes and definitions into their folders (pure move) - written, awaiting your run, see `docs/trackW/W1-notes.md`
- **Do:** create `Weapons/Sword/` and `Weapons/Bow/`; move `Weapons/Sword.tscn` to `Sword/Sword.tscn`, `Weapons/Bow.tscn` to `Bow/Bow.tscn`, `Bow.gd` to `Bow/bow.gd`, and the two `Data/Weapons/*.tres` to `<Weapon>_WeaponDefinition.tres`. Move each `.uid` and `.import` file with its source file. Rewrite every `res://` path in `player.tscn`, the weapon definitions, `Bow.tscn` (script path), `project.godot` if present, `smoke_checks.gd` (constants only) and docs. Delete the empty `Data/Weapons/`.
- **Tests:** no new checks. `SWORD_WEAPON_PATH`, `BOW_WEAPON_PATH` and `BOW_SCENE_PATH` change, nothing else.
- **Done when:** `SUMMARY passes=986 failures=0` and the Output panel shows no "file not found" or "invalid UID" lines.

### W2. Attacks, skills and the arrow into their weapon folders (pure move, old names kept) - written, awaiting your run, see `docs/trackW/W2-notes.md`
- **Do:** move the attack, skill and `Arrow.tscn` files to the folders in the table, **keeping file names and ids for now**. Sword attacks (`Default`, `PlayerLight2`, `PlayerHeavy`) go to `Weapons/Sword/Attacks/`; `Lunge`, `Spin`, `GroundSlam` and `Empower` skills to `Weapons/Sword/Skills/`; the arrow attacks and `GoblinArrow` to `Weapons/Bow/Attacks/`; `PowerShot` and `MultiShot` to `Weapons/Bow/Skills/`; `Arrow.tscn` to `Weapons/Bow/Projectile/`. The two goblin knife attacks (`GoblinAttack`, `GoblinLunge`) stay where they are until W5 replaces them. Rewrite paths in the weapon definitions, the skills, `GoblinArcher.tscn`, the AI profile of the archer, `Arrow.tscn` references and `smoke_checks.gd` constants.
- **Tests:** none new; path constants only.
- **Done when:** 986 / 0 and a text search for the old folders finds nothing outside this doc and old notes.

### W3. File names with the weapon in the name (rename only, ids unchanged) - written, awaiting your run, see `docs/trackW/W3-notes.md`
- **Do:** rename the files per the table (`Sword_Slash1.tres`, `Sword_Slash2.tres` ...) and rewrite references. Ids stay `player_light` etc.
- **Done when:** 986 / 0.

### W4. Resource ids and clip names
- **Do:** rename the ids to the proposed ids, update every test that names them, the AI profiles, error-message checks and the notes. Rename the sword scene clips to the standard names only if D-sharing needs it; otherwise add the standard names as additional clips. One search-and-replace list goes into the notes.
- **Tests:** a new check that no shipped attack or skill id contains `player` or `goblin` (WX1), and that attack ids are unique across the three weapon folders (WX2). Expected: **986 + 2 = 988**.
- **Done when:** 988 / 0.

### W5. `GoblinSword` weapon, definition and enemy wiring
- **Do:**
  1. `WeaponController2D`: add `weapon_mount: NodePath` (empty = `WeaponFacingPivot`, today's behavior). `_mount_problems()` and `_swap_mount()` use it. The context gets a `weapon_mount_root`. Keep `validate_equip()` messages in the same form.
  2. `Weapons/GoblinSword/GoblinSword.tscn`: the knife `Sprite2D` and the `AnimationPlayer` clips (`RESET`, `lunge`, `slash`, `sword_return`) moved out of `BasicEnemy2D.tscn`, keeping the `attack_event` keys (`../..`).
  3. `Weapons/GoblinSword/GoblinSword_WeaponDefinition.tres`: `basic_combo` = `Weapons/Sword/Attacks/Sword_Slash1.tres` (D2: the sword's effect and numbers), `heavy_attack` empty, no skills. `GoblinAttackDefinition.tres` is deleted. The goblin's lunge becomes `GoblinSword/Attacks/GoblinSword_Lunge.tres` with the sword Lunge's damage, knockback and hit stun (Q1). `Sword_Slash1` chains into `Sword_Slash2` through `next_attack`; check in W5 that the goblin AI does not start the combo (it only chains on a second request).
  4. `BasicEnemy2D.tscn`: add a `WeaponController2D` child with `weapon_mount = AnimatedSprite2D` and `starting_weapon = GoblinSword definition`; remove the baked-in `Weapon` and `WeaponAnimation` nodes. `attack_definition` on its `AttackComponent2D` is then set by `equip()`.
  5. The goblin AI profile keeps picking from `GoblinBehaviorProfile.tres` (slash weight 3, lunge); the lunge is `GoblinSword_Lunge.tres` in `GoblinSword/Attacks/`.
- **Tests (expected +14, 988 + 14 = 1002):** `validate_equip` for the goblin sword has no problems (GS1); the goblin carries and initializes a `WeaponController2D` (GS2); it ends up with the same two attacks as before (GS3); the knife is mounted under `AnimatedSprite2D` and flips with it (GS4); a slash and a lunge still hit a target at the old reach (GS5, GS6); the existing goblin checks (I, M, EE ..., AI range checks) pass untouched (GS7); the sword is still refused on a character with no mount (GS8); the player's sword and bow swap unchanged (GS9, GS10); the goblin archer is untouched at this point (GS11); no node named `Weapon` remains in the base scene's own tree except the mounted one (GS12 to GS14, final list in the notes).
- **Gameplay change:** the goblin's slash now has the sword's damage, hitbox, knockback and range. Every existing check that reads `goblin_slash` numbers or `ai_attack_range = 60` is listed and updated in the W5 notes; assertions are changed on purpose, not loosened.
- **Risks:** nine goblins are in `Main.tscn` and the checks control only one of them (V2b); a changed mount touches all nine. `FacingComponent2D` mirrors the weapon through the sprite flip, so check `FC9`. Check the hit flash shader on the knife after the mount change.
- **Done when:** 1002 / 0, and in the editor a goblin walks, slashes and lunges with the same look as before.

### W6. Goblin archer onto the Bow folder
- **Do:** `GoblinArcher.tscn` uses `Weapons/Bow/Bow.tscn` through the same `weapon_mount`, with a `Weapons/Bow/BowEnemy_WeaponDefinition.tres` holding only `Bow_ArrowEnemy.tres` (D5). Remove its private `bow_shoot`/`bow_return` clip library if the Bow scene clips are used.
- **Tests:** the archer fires an arrow through the same effect scene as the player; `goblin_arrow`'s numbers are unchanged.
- **Done when:** the shipped archer shoots exactly as before.

### W7. Cross-weapon reference audit and validation
- **Do:** list every attack and skill used by two or more weapons (the goblin sword and `slash1`, the bow and `empower`), confirm each lives in the folder of the first weapon that created it (D1), and add a check that a weapon using another weapon's attack has the clip that attack names (extends `validate_equip()` messages, no new class).
- **Tests:** an attack on a weapon whose scene lacks its clip is refused with a message naming the weapon, attack and clip.
- **Done when:** the SUMMARY matches the notes and no weapon folder contains a resource that no weapon uses.

### W8. Docs
- **Do:** update the README sections "How it is organised", "Add an attack" and "Add a weapon" with the folder rule; `IMPLEMENTATION_NOTES.md`; the architecture guide's file-layout section; the roadmap status line.
- **Done when:** a text search finds no old path in README, notes or guide except inside historical `docs/phase*/` notes (those stay as written).

## Safety rules for every move step

1. **Move in the editor's FileSystem dock when you can.** It rewrites uids and references itself. If files are moved as text (as I would do), move the `.uid` and `.import` files with them, rewrite `path="..."` **and** check each `uid="..."` still belongs to the moved file.
2. After each step run `godot --headless --import --path .` and read the whole Output for `invalid UID`, `Cannot open file` and `Failed loading resource`.
3. Delete `.godot/` only if the import log shows stale cache errors (it is not in git).
4. One step per commit. If a step fails, `git revert` that commit; do not patch forward over a broken move.
5. Search for the old path text (`grep -rn "Data/Weapons"` and the old file names) before calling a step done. `docs/phase*` notes are history and stay unchanged.
6. Do not change attack numbers, timings or clip contents in a move or rename step.

## What this plan does not change

`AttackComponent2D`, `SkillComponent2D`, `CombatResolver2D`, the HUD, the passives and every `.gd` file other than `WeaponController2D.gd` (W5) and `smoke_checks.gd` (path constants, ids, new checks). No system is rewritten.

## Effect on the rest of the roadmap

- **P2 (exported rig paths) starts after W8**, not before. W5 already adds the one mount field the goblin needs; P2 then covers `visual_root`, locomotion player, weapon player and weapon pivot, and can build on `weapon_mount`.
- **P3 to P7 and Phase 15** are unchanged. Phase 15 weapons (fire staff, war hammer, dual daggers, spear) become "add a folder under `Weapons/`", which is the point of this track.
- The `13.3.5` channel skill and the Phase 14 passives are untouched. Passives stay in `Components/Passives/`; a weapon only lists them.
