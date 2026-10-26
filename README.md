# Project-2D

A top-down 2D action RPG built with Godot 4.7. The player and enemies use data-driven weapons, attacks, projectiles, skills, and combat components. Weapon-specific content is organized under `Weapons/<WeaponName>/`; runtime systems remain under `Characters/Components/`.

## Controls

- **WASD / Arrow keys:** move.
- **Left mouse button, tap:** light attack toward the cursor; tap again during the combo window to chain.
- **Left mouse button, hold:** charge the equipped weapon's heavy attack, then release to swing when configured for input release.
- **Space:** dash.
- **Q:** switch between the player's Sword and Bow loadout. Switching is refused during a swing or charge; skill cooldowns continue while switching.
- **1 / 2 / 3:** use the active skill in that slot.
  - **Sword:** Lunge, Sword Spin, Empowerment.
  - **Bow:** Power Shot, Multi-shot, Empowerment.
- **`attack_heavy`:** a separate heavy-attack action with no default key; bind it in Project Settings > Input Map if desired.

The HUD displays health, mana, skill icons, cooldowns, hotkeys, and mana costs. Skill use can be refused when its cost cannot be paid or the character is in a state that blocks skill use.

## Run and test

1. Open the project in Godot 4.7 and run `Main.tscn`.
2. After adding scripts or changing global classes, run an import:

   ```bash
   godot --headless --import --path .
   ```

3. Run the smoke suite:

   ```bash
   godot --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd
   ```

The last **confirmed** result is `SUMMARY passes=1109 failures=0` (headless Godot 4.7.2, October 26, 2026; import clean; see `docs/trackW/W9-notes.md`). It covers Track W, P2 to P7 and the retimed bow-cycle checks. The V3 play-test and your own run in the editor are still open.

## Project structure

```text
Weapons/
├── Sword/
│   ├── Sword.tscn
│   ├── Sword_WeaponDefinition.tres
│   ├── Attacks/       # Sword_Slash1, Sword_Slash2, Sword_HeavySlash
│   └── Skills/        # Sword_Lunge, Sword_Spin, Sword_Empower
├── Bow/
│   ├── Bow.tscn
│   ├── Bow_WeaponDefinition.tres
│   ├── Bow_EnemyWeaponDefinition.tres
│   ├── bow.gd
│   ├── Attacks/       # player and enemy arrow attacks
│   ├── Skills/        # Bow_PowerShot, Bow_MultiShot
│   └── Projectile/    # Bow_Arrow.tscn
└── GoblinSword/
    ├── GoblinSword.tscn
    ├── GoblinSword_WeaponDefinition.tres
    └── Attacks/       # GoblinSword_Lunge

Characters/
├── Core/              # Character2D and CharacterContext2D
├── Components/        # reusable movement, combat, health, skills, status, passives, weapons
├── Controllers/       # enemy AI and attack selection
└── Enemies/           # enemy scenes and behavior profiles
UI/HUD/                # health/mana bars, skill slots, icons and HUD scenes
tests/smoke_checks.gd  # headless smoke checks
docs/                  # roadmap, architecture guide, and phase/track notes
Data/Examples/         # un-equipped example resources
```

### Ownership rules

- Weapon scenes, definitions, attack resources, skills, and weapon-specific projectiles live under the folder of the weapon that first introduced them.
- There is deliberately **no `Weapons/Shared/` folder**. When another weapon reuses a resource, it references the original resource in its owning weapon folder.
- Every weapon-related file includes its weapon name, e.g. `Sword_Slash1.tres`, `Bow_ArrowShot.tres`, and `GoblinSword_Lunge.tres`.
- Enemy loadouts may use a separate weapon definition while sharing the weapon scene. For example, `Bow_EnemyWeaponDefinition.tres` preserves the goblin archer's enemy arrow settings rather than equipping the player's attacks.
- Framework scripts and reusable effect base scenes stay in `Characters/Components/`; they are not duplicated per weapon.
- `Sword_GroundSlam.tres` is an example skill, not in the default loadout. The canonical example copy is `Data/Examples/WeaponSkills/Sword_GroundSlam.tres`.

## Add an attack

1. Open the owning weapon scene under `Weapons/<WeaponName>/` and add the required clip to its `HandAnim` animation player. Include the `attack_event(&"spawn_effect")` call at the effect spawn point; add combo-window events for combo attacks.
2. Create or reuse an effect scene. `Characters/Components/Combat/AttackSlash2D.tscn` is the melee base example; projectile effects can inherit from `ProjectileEffect2D`.
3. Create an `AttackDefinition2D` resource in that weapon's `Attacks/` folder. Name the file with the weapon prefix and configure its id, damage, timing, clip names, effect scene, hitbox and targeting policy.
4. Reference the resource from the weapon's `WeaponDefinition2D` in `basic_combo` or `heavy_attack`, or from the relevant skill definition.
5. Ensure the weapon scene contains every animation clip named by its attack resources. Run the project and the smoke suite; validation should identify the weapon, attack and missing clip when a clip is absent.

A cross-weapon shared attack is valid only when each consuming weapon scene provides the required clip name. Shared resources stay in the folder of the weapon that originally owns them.

## Add a weapon

1. Create `Weapons/<WeaponName>/` with a weapon scene, a `<WeaponName>_WeaponDefinition.tres`, and `Attacks/` and/or `Skills/` folders as needed.
2. Put the weapon sprite and animation player in the scene; author all clips referenced by its attacks. Add a projectile folder when it owns a projectile scene.
3. Create the attack and skill resources with weapon-prefixed filenames. Reuse an existing resource by reference only when its behavior and required animation-clip contract match.
4. Configure `weapon_scene`, `basic_combo`, `heavy_attack`, active skills and passives on the weapon definition. For enemy variants, create a separate definition if they need different attack data while reusing the same visual weapon scene.
5. Equip it through the character's `WeaponController2D`, add it to the player's loadout if it should be switchable, then import and run smoke tests.

## Documentation

- `IMPLEMENTATION_NOTES.md`: system behavior and implementation details. Earlier phase sections may describe the paths that existed at the time; the current Track W ownership layout above is authoritative for weapon content.
- `docs/Combat Architecture Review & Expansion Guide (Updated Oct 2026).md`: architecture review and authoring guidance.
- `docs/Combat-Roadmap-Step-by-Step-Plan.md`: implementation order and completion status.
- `docs/trackW/`: decisions and step notes for the weapon-folder migration.
