# W5b - the `GoblinSword` scene and weapon definition

Written October 25, 2026 **without running Godot**. Second increment of W5. Two new weapon files and four new checks; nothing is wired into `BasicEnemy2D.tscn` yet, so the shipped goblin still plays exactly as before. Expected: **`SUMMARY passes=998 failures=0`** (994 from W5a + 4). You will run one smoke test after Track W is finished; if the count is off then, find the first step whose notes do not match.

## New files

- `Weapons/GoblinSword/GoblinSword.tscn`: the goblin's knife as a weapon scene. The root is the knife `Sprite2D` itself (same position, offset, flip and `z_index` as the baked-in node) with the `WeaponAnimation` player as its child, so every clip still animates `.` and fires `attack_event` through `../..`. That path reaches the character when the scene is mounted under `AnimatedSprite2D`, as the old node did. Clips: the four the goblin has today (`RESET`, `slash`, `lunge`, `sword_return`, copied unchanged from `BasicEnemy2D.tscn`) plus `sword_slash_1` and `sword_slash_2`, which are copies of `slash`.
- `Weapons/GoblinSword/GoblinSword_WeaponDefinition.tres`: `weapon_id = goblin_sword`, `basic_combo = [Sword_Slash1, Sword_Slash2]` (the sword's own resources, decision D2), no heavy attack, no skills. Neither file has a `uid` yet; Godot adds one when you open and save them.

## Why `sword_slash_1` and `sword_slash_2` exist, and why slash2 is listed

Two findings from reading `WeaponDefinition2D`:

1. The sword's attacks name the clips `sword_slash_1` and `sword_slash_2`, and a weapon definition is invalid unless its scene has every clip its attacks name. So the goblin scene needs those names. They are copies of the knife's `slash`, which keeps the look.
2. `Sword_Slash1` links to `Sword_Slash2` through `next_attack`, and the validator refuses a link that leaves the weapon. So `sword_slash2` must be in the goblin's `basic_combo` too. Consequence for W5d: the goblin's attack list becomes `sword_slash1, sword_slash2` (it used to be one default plus the lunge), and the goblin AI must not chain into `sword_slash2` on its own. That is checked in W5d, and the existing check `S1` (the goblin lists one extra attack) is rewritten there on purpose.

## New checks

- **GW1** the scene is a knife `Sprite2D` with the six clips, and its attack clips fire `spawn_effect` through `../..`.
- **GW2** the weapon is valid (`validate()` and `validate_scene()` empty), lists the sword's own `sword_slash1` and `sword_slash2` (the same resource objects) and has no heavy attack.
- **GW3** a goblin equips it through `weapon_mount = ../AnimatedSprite2D`: the scene sits under `AnimatedSprite2D` as `Weapon`, and `sword_slash1` is the default attack.
- **GW4** that goblin swings `sword_slash1` and plays the knife's `sword_slash_1` clip.

GW3 and GW4 use a controller added by the test; the shipped enemy has none until W5d.

## Files in the zip

New: `Weapons/GoblinSword/GoblinSword.tscn`, `Weapons/GoblinSword/GoblinSword_WeaponDefinition.tres`, `docs/trackW/W5b-notes.md`. Changed: `tests/smoke_checks.gd`, `docs/Combat-Roadmap-Step-by-Step-Plan.md`. Nothing to delete.

## Next

W5c: the goblin's lunge as `GoblinSword/Attacks/GoblinSword_Lunge.tres` with the sword Lunge's damage, knockback and hit stun (your answer to Q1), registered on the goblin sword as its second attack. Still not wired into the enemy.
