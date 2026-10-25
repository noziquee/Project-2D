# W5c - the goblin lunge on the goblin sword

Written October 25, 2026 **without running Godot**. Third increment of W5. One new attack file, registered on the goblin sword; nothing is wired into `BasicEnemy2D.tscn` yet, so the shipped goblin still plays as before. Three new checks: expected **`SUMMARY passes=1001 failures=0`** (998 from W5b + 3). You will run one smoke test after Track W is finished; if the count is off then, find the first step whose notes do not match.

## What changed

- New `Weapons/GoblinSword/Attacks/GoblinSword_Lunge.tres`, id `goblin_sword_lunge`. Your answer to Q1: it takes the sword Lunge's numbers, so **damage 3 to 5, knockback 180 to 200, hit stun 0.2 to 0.15**. Everything else is copied from `GoblinLungeAttackDefinition.tres`: the `lunge` clip, cooldown 0.4, movement multiplier 0.3, interruptible, hitbox 16 x 14 at offset (10, 0), AI range 75, the shared `AttackSlash2D` effect.
- `GoblinSword_WeaponDefinition.tres` now sets `heavy_attack` to the lunge. A weapon definition only accepts a combo, one heavy attack and skills, and a combo entry the chain cannot reach is a validation error, so `heavy_attack` is the one slot where a standalone attack can be registered without changing any script. The goblin AI picks attacks by id and never charges, so the name of the slot has no effect on play. Extra attacks on a weapon would be a code change; say so if you want that instead.
- The goblin sword's attack list is now `sword_slash1, sword_slash2, goblin_sword_lunge`.
- **Assertions changed on purpose** in the unrun W5b checks: GW2 no longer says "no heavy attack" and lists three ids, GW3 expects the three ids.

The old `GoblinLungeAttackDefinition.tres` stays until W5d, because `BasicEnemy2D.tscn` and `GoblinBehaviorProfile.tres` still point at it. Until then two files hold the id `goblin_sword_lunge`; WX2 only reads the old one, so it stays correct.

## New checks

- **GL1** the lunge has the sword Lunge's damage, knockback and hit stun (read from the skill file, so they cannot drift), the `lunge` clip and the 75 px AI range.
- **GL2** the lunge is the goblin sword's `heavy_attack` and the last of its extra attacks.
- **GL3** a goblin that equips the goblin sword (in a fresh arena) has the lunge, starts it by id and plays the `lunge` clip.

## Files in the zip

New: `Weapons/GoblinSword/Attacks/GoblinSword_Lunge.tres`, `docs/trackW/W5c-notes.md`. Changed: `Weapons/GoblinSword/GoblinSword_WeaponDefinition.tres`, `tests/smoke_checks.gd`, `docs/Combat-Roadmap-Step-by-Step-Plan.md`. Nothing to delete.

## Next

W5d: wire the enemy. `BasicEnemy2D.tscn` gets a `WeaponController2D` (`weapon_mount = ../AnimatedSprite2D`, `starting_weapon` = the goblin sword) and instances `GoblinSword.tscn` as `AnimatedSprite2D/Weapon` instead of the baked-in knife; `GoblinBehaviorProfile.tres` points at `sword_slash1` and the new lunge; `GoblinAttackDefinition.tres` and `GoblinLungeAttackDefinition.tres` are deleted. That is the gameplay change (goblin slash gets the sword's numbers), so it gets its own step and its own list of rewritten checks.
