# W1 - weapon scenes and definitions into their folders

**Naming correction (Oct 25):** the first draft used the placeholder names `scene.tscn`, `script.gd` and `weapon_definition.tres`. The shipped names carry the weapon's name: `Sword.tscn`, `Sword_WeaponDefinition.tres`, `Bow.tscn`, `bow.gd`, `Bow_WeaponDefinition.tres`. This file now lists those names; you had already renamed them in the editor.

Written October 25, 2026 **without running Godot**. Pure move: no script logic, no data value and no clip changed. No new checks. Expected: **`SUMMARY passes=986 failures=0`** (P10's number). The step is done only when your run prints 986 / 0.

## What moved

| Old path | New path |
|---|---|
| `Weapons/Sword.tscn` | `Weapons/Sword/Sword.tscn` |
| `Weapons/Bow.tscn` | `Weapons/Bow/Bow.tscn` |
| `Weapons/Bow.gd` (+ `.gd.uid`) | `Weapons/Bow/bow.gd` (+ `bow.gd.uid`) |
| `Data/Weapons/SwordWeaponDefinition.tres` | `Weapons/Sword/Sword_WeaponDefinition.tres` |
| `Data/Weapons/BowWeaponDefinition.tres` | `Weapons/Bow/Bow_WeaponDefinition.tres` |

`Data/Weapons/` (and `Data/`, which held nothing else) is gone. Every `uid="uid://..."` header and `ext_resource` uid is unchanged, so the editor still resolves each file by uid; only the text paths were rewritten.

## References rewritten

- `player.tscn`: sword scene, sword definition, bow definition.
- `Weapons/Sword/Sword_WeaponDefinition.tres` and `Weapons/Bow/Bow_WeaponDefinition.tres`: the weapon scene.
- `Weapons/Bow/Bow.tscn`: the script path (`Bow/bow.gd`).
- `tests/smoke_checks.gd`: the path constants and the strings in `II1e`, `JJ1a`, `JJ5a`, the sword path checks in the equip-cycle tests, `load(...)` calls at lines for EEE, the bow and sword scene checks. **No assertion changed**; only the path text (check names that said `Weapons/Sword.tscn` now say `Weapons/Sword/Sword.tscn`). A few check names still say "Bow.tscn" in prose (XX2, BC2); they do not read a path.
- Comments in `WeaponDefinition2D.gd` and `CharacterContext2D.gd`.
- Not touched on purpose: the older notes in `docs/phase*` (history).

A text search of all `.gd`, `.tscn`, `.tres` and `project.godot` files (outside `docs/` and `.godot/`) for `Weapons/Sword.tscn`, `Weapons/Bow.tscn`, `Weapons/Bow.gd` and `Data/Weapons` finds nothing.

## Files in the zip

Changed: `player.tscn`, `tests/smoke_checks.gd`, `Characters/Components/Weapons/WeaponDefinition2D.gd`, `Characters/Core/CharacterContext2D.gd`, `docs/Combat-Roadmap-Step-by-Step-Plan.md`, `docs/trackW/W0-plan.md`.
New: `Weapons/Sword/Sword.tscn`, `Weapons/Sword/Sword_WeaponDefinition.tres`, `Weapons/Bow/Bow.tscn`, `Weapons/Bow/bow.gd`, `Weapons/Bow/bow.gd.uid`, `Weapons/Bow/Bow_WeaponDefinition.tres`, `docs/trackW/W1-notes.md`.

**A zip cannot delete files. Delete these five yourself after unzipping** (or the project will have two copies and duplicate UIDs):
`Weapons/Sword.tscn`, `Weapons/Bow.tscn`, `Weapons/Bow.gd`, `Weapons/Bow.gd.uid`, and the folder `Data/Weapons/` (both `.tres` files in it).

## How to apply and check

1. Close Godot. Unzip over the project folder, then delete the five old items above.
2. Run `godot --headless --import --path .` and read the whole output for `invalid UID`, `Cannot open file` and `Failed loading resource`. If stale cache errors appear, delete the `.godot/` folder and import again (it is not in git).
3. Run `godot --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd`. Expected `SUMMARY passes=986 failures=0`.
4. Open `Main.tscn`: the player starts with the sword, `Q` switches to the bow and back, both draw and swing as before.
5. If you prefer to do the move inside the editor, move the files in the FileSystem dock instead; it rewrites references itself. Either way the end state must match the table.

## Next

W2 moves the attack, skill and arrow files into the folder of the weapon that created them (`Sword/Attacks`, `Sword/Skills`, `Bow/Attacks`, `Bow/Skills`, `Bow/Projectile`), names unchanged. Run W1 first so a failure points to one step.
