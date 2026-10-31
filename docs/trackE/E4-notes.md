# E4: wiring Track E into a playable enemy

Written October 30, 2026 **without running Godot**. 4 new checks, E4-1 to E4-4, in part `enemy_ai_profiles`.

## Why

The Track E features are off by default, and the shipped goblin cannot show them: its profile never picks the heavy attack, it has no `SkillComponent2D`, and `skill_usage_priority`, `skill_windup_duration` and `heavy_wait_for_opening` are 0. The normal goblin and `Main.tscn` are unchanged.

## What was added

- `Characters/Enemies/GoblinElite.tscn`: inherits `BasicEnemy2D.tscn`, adds a `SkillComponent2D` (the goblin weapon's `Sword_Lunge` dash skill reaches it through `WeaponController2D`; it has no mana cost, so no `ManaComponent2D` is needed), and uses `GoblinEliteProfile`.
- `Profiles/GoblinEliteProfile.tres`: slash (weight 3) and the goblin lunge, which is the goblin weapon's heavy (weight 3); two-hit combos with a 0.5 s recovery pause; waits up to 1 s for a heavy opening; uses its skill every time it is usable, with a 0.6 s warning; switches to a clearly nearer target; 0.5 s wind-up lane.

## To see it

Drag `GoblinElite.tscn` into `Main.tscn` (or any arena). Expected: the red lane for the heavy charge, the skill's line shape for 0.6 s before the lunge dash, combos of two, and a pause after.

## Not wired

- `GoblinArcher` and the other profiles (Aggressive, Patient, Skirmisher, Caster, Simple) are not assigned to any scene yet. Assign one in the Inspector on an enemy's `EnemyAIController2D`.
- Ground-circle and ally-support skills are not possible yet (see `DE3-notes.md`, `DE1-notes.md`).

## Addendum: test arena (E5)

`TrackEArena.tscn` is a copy of `Main.tscn` (same player, HUD, walls) with six enemies, one per profile: `Elite` (heavy, skill, switching), `Aggressive` (three-hit combos), `Patient` (heavy waits for openings), two `Simple` goblins, and a `Skirmisher` archer (keeps its distance, circles). `Main.tscn` is unchanged and stays the main scene; open the arena with F6 (Run Current Scene). Checks E5-1 and E5-2 (part `enemy_ai_profiles`) confirm the arena loads and each enemy carries its profile.

Not in the arena: the Tactical Caster (needs a caster weapon), and attack slots or circling (`max_simultaneous_attackers` is 0 in every profile; set it on the two Simple goblins to test DE2).

## Addendum: warning before every attack (E6)

A plain attack (slash, lunge) has never shown a lane: `_show_telegraph()` only drew it for the weapon's heavy attack, so goblins with the shipped profile show no warning at all. New profile field `telegraph_all_attacks` (default false) draws the lane for every attack's wind-up. It is on in the Elite, Aggressive, Patient and Simple profiles, so the arena enemies warn before each swing; the shipped goblin profile is unchanged. It needs `attack_windup_duration` above 0. Checks E6-1 to E6-3.

Still true: the lane is drawn under the enemy sprite (`z_index = -1`), and the skill warning only appears when the enemy decides to cast (a dash skill is used to close a gap, so the target must be farther than the attack range but inside the skill's reach).
