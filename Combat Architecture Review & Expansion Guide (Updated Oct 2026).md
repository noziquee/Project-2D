# Combat Architecture Review & Expansion Guide (Updated)

*Project-2D · Godot 4.7 · reviewed October 23, 2026 from the uploaded archive (git history through "Phase8"). This is a static read of the code and scenes. I could not run Godot, so anything marked **verify in-game** needs a play-test, and I have not run `tests/smoke_checks.gd`.*

## 1. Summary

The project has moved from "data-driven in theory" to "data-driven in practice". Since the last review you have finished Phases 0 to 8: an attack is now one `AttackDefinition2D` resource, weapon clips fire named events, health and hits are real components, teams and hit layers are data, and components, states, AI detection and the HUD are all nodes or resources you can edit in the Scene dock.

What is left is mostly **Phase 9 (multiple attacks and combos)** and a handful of places where a hard-coded node path, clip name or group still limits how freely you can add content.

**Top findings now, in order of impact:**

1. **A character can only own one attack.** There is one `attack_definition` export, one `attack` input action, and `try_start(requested: bool, ...)` takes no attack id. Everything you build in the editor is ready for a second attack, but nothing can select it yet.
2. **The effect scene has a rigid contract.** `AttackSlash2D.gd` looks up fixed node paths and the clip name `slash`, always spawns at the attacker's origin, and always sweeps a hitbox. Projectiles, area bursts and effects that follow the attacker are not expressible without script changes.
3. **Characters are discovered by node name.** `CharacterContext2D` finds the rig through hard-coded names (`LayeredRig`, `PlayerAnim`, `WeaponFacingPivot/MainHand/HandAnim`, `AnimatedSprite2D/Weapon/WeaponAnimation`). A new character that does not copy those names silently loses its weapon player.
4. **Hit and death presentation is subclass code with string clip names** (`take_damage`, `RESET`, `death`, `idle`, `run`), duplicated between `player.gd` and `BasicEnemy2D.gd`.
5. **Targeting still uses group names.** Hits need the group `damageable`; the AI targets the group `player` instead of comparing teams.
6. **Small leftovers:** legacy fallbacks (`attack_slash_scene`, `DEFAULT_*` preloads), a misleading tooltip on `hit_layers`, and two copies of the old guide in the project root.

## 2. What was fixed since the last review

These were findings in the previous version of this guide. I checked each one against the current code.

- **Cooldown bug (A): fixed.** `_finish_attack()` starts the cooldown when the recovery clip ends, so `cooldown_duration` is the real gap between swings. `interrupt()` also starts it.
- **Fragmented attack data (B): fixed.** `AttackDefinition2D` owns `id`, damage, timing, clip names, effect scene, hit effect scene, hitbox, hit layers, knockback, hit stun, aim flag and AI range.
- **One spawn per swing (C) and hard-coded two-phase attack (D): fixed.** The weapon clip calls `attack_event(&"spawn_effect")` as many times as you key it, and `recovery_animation` may be empty for a one-clip attack.
- **Aimed swing (E): done for the player.** `aim_weapon` rotates `WeaponFacingPivot` toward the attack direction. The goblin ignores it because its weapon is a child of the sprite.
- **Damage payload and teams (F): fixed.** `HitData` carries damage, source, direction, knockback and hit stun. Team is a `team` property on `Character2D`, and the hitbox mask comes from `hit_layers`.
- **Duplicated health (G): fixed.** One `HealthComponent2D` with invulnerability and healing.
- **No interrupts (H) and movement during attacks (I): fixed.** `interruptible`, `hit_stun`, `knockback` and `movement_multiplier` all exist.
- **Enemy hit feedback (J) and unused assets (K): fixed.** The enemy plays its authored `take_damage` clip, the player has a separate `ReactionAnim` player, and `HitEffect.tscn` and `DeathEffect.tscn` are used.
- **Components and states built in code: fixed.** They are child nodes in both scenes, and `Character2D` reports missing ones loudly.
- **AI and HUD in code: fixed.** The enemy uses a `DetectionArea` (Area2D + CircleShape2D) and an `EnemyBehaviorProfile` resource. The HUD is one `HealthBar.tscn` with an `AnimationPlayer`, `.tres` styles and a color `Gradient`.

## 3. How combat works today

### 3.1 Attack flow

1. `Character2D._physics_process` asks its controller (`player.gd` or the enemy AI) for movement, dash and attack intent.
2. `AttackComponent2D.try_start()` checks gating (initialized, not attacking, not dashing, no hit stun, no cooldown), picks a direction, sets `context.is_attacking`, applies the definition's `movement_multiplier`, and plays `weapon_animation` on the weapon `AnimationPlayer`.
3. The weapon clip contains a method track calling `attack_event(&"spawn_effect")`. `Character2D.attack_event()` forwards it to `AttackComponent2D.handle_event()`.
4. `_spawn_effect()` instantiates the definition's `effect_scene`, calls `AttackSlash2D.configure(...)` with damage, direction, hitbox size, offset, hit layers, knockback and stun, and adds it to the `Effects` node (group `effects_root`) at the attacker's position.
5. The effect scene's own `slash` clip plays the sprite, the hitbox sweep and the `CollisionShape2D:disabled` track (the active hit window).
6. `AttackSlash2D._try_hit` filters: not the attacker, in group `damageable`, has `apply_hit`, not on the same non-empty team, and not already hit by this effect. It builds a `HitData`, calls `apply_hit`, then emits `hit_contact` (spawns the definition's `hit_effect_scene`) and `hit_confirmed`.
7. `HealthComponent2D.apply_hit` reduces health and emits `health_changed`, `damaged` and (if lethal) `died`. `Character2D` applies knockback and hit stun, calls `interrupt()` on the victim's attack, and runs the subclass `_on_damaged` or `_on_death` hooks.
8. When the weapon clip ends, `recovery_animation` plays; when that ends, `_finish_attack()` clears `is_attacking`, restores `move_multiplier`, starts the cooldown and emits `attack_finished`.

### 3.2 Where each piece of an attack lives

This is the answer to "what do I edit to change X?" and the reason the workflow in section 5 works.

- **Damage, knockback, hit stun, interruptible, cooldown, movement during the swing:** the `AttackDefinition2D` `.tres`.
- **Which clips play:** `weapon_animation` and `recovery_animation` in the `.tres`, with the clips themselves on the character's weapon `AnimationPlayer`.
- **When the effect appears (and how many times):** the `attack_event(&"spawn_effect")` keys inside the weapon clip.
- **How the effect looks, how far it reaches, when it can hit:** the effect scene (sprite, `slash` clip, `HitboxMotion:position` track, `CollisionShape2D:disabled` track).
- **Hitbox size and where its sweep starts:** `hitbox_size` and `hitbox_offset` in the `.tres`.
- **Who can be hit:** `hit_layers` in the `.tres`, plus `team` on each character and the `damageable` group on the target.
- **Impact visual:** `hit_effect_scene` in the `.tres`.
- **When the AI swings:** `ai_attack_range` in the `.tres` (0 falls back to 30 px).
- **Character stats:** `HealthComponent2D.max_health`, `MovementComponent2D.move_speed`, `DashComponent2D` values, `knockback_friction` on the character root.
- **Enemy behavior:** `EnemyBehaviorProfile` (`disengage_radius`, `lost_target_grace_duration`, `home_stop_distance`, optional `detection_radius`) and the drawn `DetectionArea` circle.

## 4. Architecture review

### 4.1 What is working well (keep it)

- **Intent/execution split.** Controllers only answer "what do I want?" and `Character2D` plus components execute. One base class serves the player and the goblin.
- **Single movement authority.** Only `MovementComponent2D` calls `move_and_slide()`; dash velocity, knockback and `move_multiplier` all flow through it.
- **Validation that names the problem.** `validate_definition()` reports the exact missing clip, and `CharacterContext2D` warns about method tracks that do not resolve or fire unknown events. Treat every warning in the Output panel as a to-do.
- **A swing is isolated from definition swaps.** `_active_definition` is captured at swing start, so changing `definition` mid-swing cannot strand the running attack.
- **Effects outlive the swing safely.** The effect list is tracked, `cancel()` frees live ones, and hit effect scenes are bound to the attack that spawned them.
- **Signals everywhere you need them:** `attack_started`, `attack_hit`, `attack_finished`, `dash_started`, `dash_ended`, `health_changed`, `damaged`, `died`, `behavior_changed`, `state_changed`.
- **Smoke tests** (about 1,100 lines) cover structure, attack rate, hits, facing, dash, AI and death.

### 4.2 Findings and recommendations

**A. One attack per character (Phase 9 not started).** `combo_window_open` and `combo_window_close` are accepted and ignored, and there is no `next_attack`. The fix is small and mostly data: an `attacks` array on `AttackComponent2D`, an id passed to `try_start`, and a second input action. See section 8.

**B. The effect scene contract is rigid.**

- `AttackSlash2D` uses `@onready` lookups with fixed paths (`$SlashEffectAnimSpritesheet/AnimationPlayer`, `$HitboxOrigin/HitboxMotion/Area2D/...`) and requires a clip called exactly `slash`; it frees itself when that clip ends.
- The effect always spawns at `character.global_position` and rotates to the attack direction.
- Hit-once tracking is per effect, so a flurry that spawns three effects can hit the same target up to three times. That is probably what you want, but decide on purpose.
- Recommendation: make the clip name an `@export`, and add an `AttackSpawnPoint` `Marker2D` per character. For ranged attacks, later add a second effect script (a projectile) that shares the same `configure(...)` signature, so the definition does not care which one it spawns.

**C. Rig discovery by node name.** `CharacterContext2D._init` knows exactly two layouts. A third character type (a mage with a staff, a boss with two weapons) must copy the names or the character logs "Attacks are disabled". Recommendation: exported `NodePath`s on `Character2D` (visual root, locomotion player, weapon player, weapon pivot) with the current names as defaults.

**D. Presentation lives in subclasses with string clip names.** `player.gd` and `BasicEnemy2D.gd` both override `_on_damaged` and `_on_death` and hard-code `take_damage`, `RESET` and `death`. `IdleState`, `MoveState` and `AttackState` hard-code `idle` and `run`. Recommendation: exported `StringName` fields, or a small `ReactionComponent2D` that listens to `damaged` and `died` and plays configured clips and effect scenes. Then a new enemy needs no script.

**E. Targeting still uses group strings.** `AttackSlash2D._try_hit` requires the group `damageable`, and `EnemyAIController2D.target_group` is `player`. Team is already a property, so the AI should target any character whose team differs, with the `DetectionArea` mask limiting what it sees. A `Hurtbox` `Area2D` component would also let crates and switches take hits without joining groups by hand.

**F. Hit stun has no presentation.** `hit_stun` blocks attack and dash starts, but there is no stagger state or clip. Add a `Stagger` state node (and a reaction clip) when you want enemies to visibly flinch. The state machine already supports extra state nodes per character.

**G. `aim_weapon` is player-only.** This is documented in the resource, but a designer filling in the goblin's definition may expect it to work. Verify in-game that the left/right mirroring and the authored arc look right at extreme angles (straight up and straight down).

**H. AI is single-attack.** It reads one range from the active definition and requests one attack. With multiple attacks it needs a selector: a weighted list on `EnemyBehaviorProfile`, each entry an `AttackDefinition2D`, and the swing distance taken from whichever is chosen.

**I. Legacy fallbacks are now dead weight.** Both shipped definitions set `effect_scene`, so `AttackComponent2D.attack_slash_scene`, `set_slash_scene()`, `DEFAULT_SLASH` and the `DEFAULT_ATTACK` fallback only matter for characters with no definition. Remove them once every definition sets its own effect scene, or keep one clearly marked default.

**J. Two small data traps.**

- `AttackDefinition2D.cooldown_duration` defaults to 0.4 in the script, but both shipped `.tres` files use 0.05. A brand-new definition therefore feels much slower than the existing ones. Pick one default.
- The `hit_layers` tooltip says "add the world layer (4)". The project's layers are player = 1, enemy = 2, world = 3; the flag **value** for world is 4. Reword the tooltip to avoid the mix-up.

**K. Housekeeping.**

- The project root contains two copies of the old guide (one with a mangled `#U2013` file name). Keep one, ideally under a `docs/` folder.
- `IMPLEMENTATION_NOTES.md` still says the project was never opened in Godot. Update it after you run the game and the smoke test.
- The goblin carries a `DashComponent2D` it never uses. That is harmless; keep it if you plan a dash enemy.

## 5. Step-by-step: add a new attack yourself

This workflow uses only the editor, no script edits. The example is a **Heavy Slash** for the player. Until Phase 9 a character holds one active attack (see Part B), so the steps end by assigning the definition to a character.

### Step 0: Decide the attack on paper

Write down: an id (`player_heavy`), damage, how it should feel (wind-up, active time, recovery), reach, whether it should root the character, knockback and stun, and for AI users the distance it should start from.

### Step 1: Author the weapon clip

1. Open the character scene. The weapon `AnimationPlayer` is `WeaponFacingPivot/MainHand/HandAnim` on the player and `AnimatedSprite2D/Weapon/WeaponAnimation` on the goblin.
2. In the Animation panel, duplicate `slash` as `heavy_slash`. Duplicate `sword_return` as `heavy_return`, or skip the recovery clip entirely if the attack should end when `heavy_slash` ends.
3. Edit the keys: longer wind-up, bigger arc, different timing.
4. Make sure the clip has a **Call Method** track that targets the character root and calls `attack_event` with the single argument `spawn_effect`. The key time is when the effect appears. Add more keys for a flurry.
5. Reopen the scene or run the game and read the Output panel. `CharacterContext2D` warns if a track does not resolve to the character, calls a missing method, or fires an unknown event name.

### Step 2: Build the effect scene

1. Right-click `Characters/Components/Combat/AttackSlash2D.tscn` and choose **New Inherited Scene**. Save it as `HeavySlash2D.tscn` in the same folder.
2. Keep these names and the root script exactly as they are, because `AttackSlash2D.gd` looks them up:
   - `SlashEffectAnimSpritesheet` with a child `AnimationPlayer` holding a clip called `slash`
   - `HitboxOrigin/HitboxMotion/Area2D/CollisionShape2D` using a `RectangleShape2D`
3. To change the look, select `SlashEffectAnimSpritesheet`, swap `texture`, and set `hframes` and `vframes`.
4. Edit the `slash` clip:
   - the `frame`, `position`, `scale` and `modulate` tracks control the visual
   - the `HitboxMotion:position` track controls how far the hitbox travels (reach)
   - the `CollisionShape2D` **disabled** track is the **active hit window**. Hits only land while it is `false`, because the script starts with the shape disabled.
5. Do not set the `Area2D` mask here. It comes from `hit_layers` in the definition (the scene's mask of 3 is only a fallback).
6. The effect frees itself when its `slash` clip ends, so make the clip as long as the effect should live.

### Step 3: Optional impact effect

1. Open `Characters/Effects/HitEffect.tscn`. It is a root-script-free `Node2D` with an `AnimationPlayer` that frees the scene at the end.
2. Make an inherited scene (`HeavyHit.tscn`) and change the sprite or frames.
3. Keep a method track that calls `queue_free` on the root at the end of the clip, so impacts never pile up.

### Step 4: Create the attack definition

1. In the FileSystem dock open `Characters/Components/Combat/`.
2. Right-click, **Create New**, **Resource**, choose `AttackDefinition2D`, save as `HeavyAttackDefinition.tres`.
3. Fill the Inspector group by group:
   - **Id:** `player_heavy` (shows up in logs and tests).
   - **Damage:** the hit value.
   - **Timing:** `cooldown_duration` is the wait **after the swing ends**. Time between swing starts is the animation length plus this value. Set it explicitly: the script default is 0.4, while the shipped attacks use 0.05. `movement_multiplier` of 1 is normal, 0 roots the character for the swing, and 0.3 is a slow wade. `interruptible` lets a hit cancel the swing.
   - **Animation:** `weapon_animation` = `heavy_slash`, `recovery_animation` = `heavy_return` (or empty). `aim_weapon` is on for the player so the arc points at the mouse; the goblin ignores it.
   - **Hit:** `hit_layers` 3 hits the player and enemy layers; add the world layer (flag value 4) for breakables. `knockback` is a starting speed in px/s that decays with the target's `knockback_friction`. `hit_stun` blocks the target's attacks and dashes for that many seconds.
   - **Effect + Hitbox:** `effect_scene` = `HeavySlash2D.tscn`, `hit_effect_scene` = your impact scene, `hitbox_size` and `hitbox_offset` to match the visual.
   - **AI:** `ai_attack_range`. Leave 0 for the player.

### Step 5: Assign it to a character

1. Open the character scene, select the **AttackComponent2D** node (not the root).
2. Drag `HeavyAttackDefinition.tres` into **Attack Definition**.
3. If the clip names are wrong, the game logs an error that names the missing clip and refuses to initialize attacks, instead of failing silently.

### Step 6: Set the AI range (enemies only)

The swing must start from a distance at which it can really connect. A good estimate is `hitbox_offset` plus the furthest value of the `HitboxMotion:position` track plus half of `hitbox_size.x`. The goblin uses 60 px for a slash that connects out to about 72 px centre to centre. Keep `ai_attack_range` at or below the real reach so the enemy does not swing at nothing, and turn on **Debug, Visible Collision Shapes** to see the active hitbox.

### Step 7: Test

1. Run the game and swing. Watch the Output for warnings or errors.
2. Check: the effect appears on the right key, hits once per effect, does not hit the attacker or same-team characters, applies knockback and stun, and the character returns to idle or run.
3. Run the headless smoke test: `godot --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd`.
4. Add one check for your new attack (assert damage dealt and the attack rate), and update existing expectations if you changed timing. Update waits deliberately; do not loosen assertions.

### Step 8: The tuning loop

- **Too fast or too slow:** `cooldown_duration`, or the clip length or the weapon `AnimationPlayer` speed.
- **Hits too early, late or not at all:** the `CollisionShape2D:disabled` track and the `spawn_effect` key time.
- **Wrong reach:** `HitboxMotion:position` track, `hitbox_offset`, `hitbox_size`.
- **Hits the wrong things:** `hit_layers`, `team` on the characters, and the `damageable` group on the target.
- **Enemy swings from too far or too close:** `ai_attack_range`.
- **Feels weightless:** raise `knockback` and `hit_stun`, add a `hit_effect_scene`, shorten the cooldown.

### Part B: Using two attacks before Phase 9

Until the `attacks` array exists, pick one of these:

- Build a second character scene (an inherited scene of the player or `BasicEnemy2D.tscn`) whose `AttackComponent2D` points at the other definition.
- Swap at runtime with `character.attack_definition = load("res://.../HeavyAttackDefinition.tres")`. The setter validates the clips and keeps the old attack if any are missing.

### Part C: Add a new enemy variant

1. Right-click `Characters/Enemies/BasicEnemy2D.tscn`, **New Inherited Scene**, save it (for example `Brute.tscn`).
2. On the root: `team` (must differ from the player's), `death_effect_scene`.
3. On the components: `HealthComponent2D.max_health`, `MovementComponent2D.move_speed`, `AttackComponent2D.attack_definition`.
4. On `EnemyAIController2D`: assign a new `EnemyBehaviorProfile` `.tres`. Resize the circle on `DetectionArea` in the 2D view, or set `detection_radius` in the profile to override it. Make the `DetectionArea` collision mask include the layers of your targets.
5. For a different art style: swap the `SpriteFrames` (needs `idle` and `run`), and keep the weapon node names or use the exported paths once recommendation C in section 4.2 is done.
6. Drop it into `Main.tscn` and run the smoke test.

## 6. Code-driven elements that can become scenes or resources

### Already scene or resource driven (keep as is)

Components and states as child nodes; `AttackDefinition2D` and `EnemyBehaviorProfile` resources; the slash effect scene with its animated hit window; `DetectionArea` with a resizable circle; the `HitEffect` and `DeathEffect` scenes; the `Effects` container; the separate player `ReactionAnim` player and the enemy `take_damage` clip; the HUD scene with its `AnimationPlayer`, `.tres` styles and color gradient; physics layer names and arena walls.

### Remaining candidates, highest value first

1. **Attack list and selection** (`attack_definition` single export, `attack` input, `try_start(bool)`) becomes `attacks: Array[AttackDefinition2D]`, an attack id on input actions and AI profiles, and `next_attack` on the definition for combos.
2. **Effect spawn origin** (`character.global_position` in `_spawn_effect`) becomes an `AttackSpawnPoint` `Marker2D` in each character scene.
3. **Hit and death presentation** (`_on_damaged` and `_on_death` overrides with clip-name strings in two scripts) becomes a `ReactionComponent2D` node with exported clip names and effect scenes, listening to `damaged` and `died`. This removes most of `player.gd` and `BasicEnemy2D.gd`.
4. **Hittable objects** (the `damageable` group plus duck typing) becomes a `Hurtbox` `Area2D` component that forwards to `HealthComponent2D`. Crates, switches and bosses with multiple hurtboxes get free.
5. **Targeting by group string** (`target_group`) becomes a team comparison with the `DetectionArea` mask doing the filtering.
6. **Rig discovery by node name** (`CharacterContext2D._init`) becomes exported `NodePath`s on `Character2D`, with the current names as defaults.
7. **Locomotion clip names** (`idle`, `run` in the state scripts, `death` and `RESET` in the characters) become exported `StringName`s on the states, or one `CharacterAnimationSet` resource shared by characters.
8. **Effect scene clip name and node paths** (`slash` and the `$` lookups in `AttackSlash2D`) become exported fields, so a differently built effect scene works.
9. **Extra enemy behaviors** (the `Behavior` enum and branching in `EnemyAIController2D`) become behavior state nodes once you add ranged, fleeing or patrol enemies. Do not do this before you need it.
10. **Stagger** (hit stun with no visual) becomes a `Stagger` state node plus a clip, added only to characters that should flinch.
11. **Facing flip every physics frame** (`scale.x` mirroring in `_update_facing_direction`) can become a small `FacingComponent2D`. Low priority; it works.
12. **Health bar value tweens** (bar fill, damage trail, number counter) are the only HUD motion still in code. They animate changing values, which is a good fit for tweens, so leave them unless you want pixel-exact control.

### Do not convert

Attack timing, cooldown, gating rules, the hit filter, knockback decay and the state transitions are logic, not content. Keeping them in small, tested scripts is correct; the goal is that **content** (attacks, enemies, effects) is data.

## 7. Cleanup checklist

- Remove the duplicate guide in the project root (keep one, under `docs/`).
- Change the `cooldown_duration` script default to match your shipped value, or set it on every new `.tres`.
- Reword the `hit_layers` tooltip: layers are numbered 1 to 3, and the flag value for world is 4.
- Remove `attack_slash_scene`, `set_slash_scene()` and the `DEFAULT_*` preloads once every definition sets `effect_scene` and every character sets `attack_definition`.
- Run the game and the smoke test in Godot 4.7, then update the validation note in `IMPLEMENTATION_NOTES.md`.
- Update `README.md` (it still says only "Hack and Slash") with controls and how to add an attack.
- Keep `.godot/` out of archives. It is already in `.gitignore`.

## 8. Suggested next steps: Phase 9 (multiple attacks and combos)

Do these in order, running the smoke test after each. Each step leaves the game playable.

1. **Quick wins first (about an hour):** fix the tooltip, align the cooldown default, delete the duplicate guide.
2. **`attacks` array.** On `AttackComponent2D` add `@export var attacks: Array[AttackDefinition2D]`. Keep `attack_definition` as the default entry so existing scenes keep working. Add `try_start_attack(id: StringName, direction: Vector2)` that selects an entry and then runs the existing logic.
3. **Input.** Add `attack_light` and `attack_heavy` input actions. Change `Character2D._get_attack_requested()` to return an attack id (empty for none), and update `player.gd`. The enemy returns its chosen id.
4. **AI selection.** Add a weighted list to `EnemyBehaviorProfile` (definition plus weight), pick one when the cooldown ends, and use that definition's `ai_attack_range` for the swing distance.
5. **Combos.** Add `next_attack: AttackDefinition2D` to the definition. In `handle_event`, set a flag on `combo_window_open`, clear it on `combo_window_close`, and if an attack request arrives inside the window start `next_attack` immediately, bypassing the cooldown.
6. **Prove it, editor-only.** Add `HeavyAttackDefinition.tres` with `HeavySlash2D.tscn` for the player and a goblin lunge using `movement_multiplier`, following section 5 exactly. If you had to edit a script to finish, note what was missing and move it into the definition.

**Tests to add:** the heavy attack is selected by id; a combo chains inside the window and not outside it; the goblin picks its second attack; `move_multiplier` is back to 1.0 after every attack.

**Done when:** a new attack is one animation clip, one effect scene, one `.tres` and one array entry.

## 9. Risks

- **Method-track paths break when nodes move.** Treat any `CharacterContext2D` warning as a blocker.
- **Renaming resource fields silently resets saved values.** Prefer adding fields; if you rename, resave the `.tres` and check it.
- **Smoke-test timing.** Tests wait a fixed number of physics frames, so update waits deliberately when you change timing.
- **Init order.** Components must not read `context` in `_ready()`; they receive it in `initialize()`.
- **HDR flash values.** The enemy flash clip uses very bright modulate values; check it visually after changing it.

## 10. Design structure: Albion-inspired weapon system

This section brings in your *Weapon System Design Guide* and maps it onto the code you have today. The guide is a design target, not a rewrite order. Its own rule is to inspect the existing project and adapt, and the project is already close to its core idea: **Resources describe data, reusable scripts execute behavior, scenes hold visuals and projectiles.** Where the two differ, this section says which one to follow. It also changes how Phase 9 in section 8 should be built (see 10.5).

*The guide describes an Albion-inspired design, not Albion Online's exact abilities or balance. The weapon examples are proposed archetypes for your game.*

### 10.1 The design in one page

- **Weapon-centred combat.** The equipped weapon decides the basic attack pattern, the heavy attack, the projectiles and effects, the active skills and the passives. Player and enemy code do not change per weapon.
- **Five kinds of combat content.** Basic attacks (repeatable, combo-capable), heavy or empowered attacks, active skills (cooldown, cost, cast, targeting), passive skills (persistent or event-triggered bonuses) and combat feedback (animation, trails, impacts, sound, numbers).
- **Hybrid architecture.** `.tres` Resources for data, reusable scripts for execution, scenes for projectiles, hitboxes and VFX.
- **Shared attack lifecycle.** Request, wind-up, active, impact, recovery, driven by animation events rather than scattered timers.
- **Event-driven passives.** Passives listen to combat events (`attack_started`, `attack_hit`, `damage_received`, `skill_activated`, `enemy_defeated`) instead of polling.
- **Explicit animation ownership.** Movement picks idle or run, combat picks the weapon action, and no two systems write the same properties.

### 10.2 Example weapon matrix (for your own game)

- **Sword:** quick melee slash combo; overhead strike with stagger as the heavy; dash slash, spin and finisher as skills; combo stacks and short blade trails.
- **Bow:** arrow projectile; charged piercing shot; multi-shot, explosive arrow and arrow rain; consecutive-hit bonus and arrow trails.
- **Fire staff:** small fire projectile; charged firebolt or blast; fire wave, burning ground and meteor; burn or spell-chain bonus, embers and flame trails.
- **War hammer:** slow blunt hit; ground slam with shockwave; charge, knockback and stun strike; stagger buildup, dust and ground cracks.
- **Dual daggers:** rapid alternating hits; lunge or two-blade finisher; backstep, bleed and execution; bleed stacks or wounded-target bonus.
- **Spear:** long-reach thrust; piercing thrust or short charge; impale, sweep, throw and pull; momentum or precision stacks.

### 10.3 Guide components mapped to your project

Each line shows the guide's component, what you have now, and what is missing.

- **WeaponDefinition** (identity, base stats, combo, heavy attack, skills, passives, clip references). *Now:* nothing. The closest thing is `AttackComponent2D.attack_definition` plus clips that live on the character's weapon `AnimationPlayer`. *Gap:* the whole weapon concept.
- **AttackDefinition** (type, multiplier, timings, effects, hitbox, knockback). *Now:* `AttackDefinition2D`, which already has damage, cooldown, movement multiplier, interruptible, clip names, aim flag, hit layers, knockback, hit stun, effect and hit-effect scenes, hitbox and AI range. *Gap:* no attack type, no combo link (`next_attack`), no pierce or max-targets policy.
- **WeaponController** (owns the equipped weapon, routes input). *Now:* nothing; `Character2D` asks `player.gd` for a single attack request. *Gap:* weapon equip and switch, and input routing to light, heavy and skill slots.
- **AttackExecutor** (phases, combo progression, hit timing, interruption). *Now:* `AttackComponent2D`. It already handles gating, the clip lifecycle, `attack_event`, interruption and cooldown. *Gap:* combo progression (the combo events are reserved but ignored) and a heavy or charged path.
- **SkillExecutor** (validation, targeting, cost, cooldown, cast, channel). *Now:* nothing. *Gap:* all of it.
- **Projectile**. *Now:* nothing; `AttackSlash2D` is a melee sweep only. *Gap:* a projectile effect with velocity, collision filter, lifetime and impact.
- **Hitbox** (who can be hit, during which frames). *Now:* the `Area2D` in the effect scene, with frames set by the `CollisionShape2D:disabled` track and targets set by `hit_layers`, `team` and hit-once tracking. *Gap:* an area (non-sweeping) hitbox and an explicit pierce policy.
- **CombatResolver** (damage, defense, crits, status, hit reactions). *Now:* `HitData` plus `HealthComponent2D.apply_hit`, with knockback, hit stun and interrupt applied in `Character2D`. *Gap:* defense, crit, status effects and a single place to put them.
- **PassiveController** (tracks events, counters, triggers). *Now:* nothing, but the signals it needs exist: `attack_started`, `attack_hit`, `attack_finished`, `damaged`, `died`. *Gap:* the controller and passive resources.
- **VFX/SFX system.** *Now:* `Effects2D` (spawns into the `Effects` container), `hit_effect_scene`, `HitEffect.tscn`, `DeathEffect.tscn`. *Gap:* trails and charge effects, and any audio.
- **AnimationController.** *Now:* `CharacterContext2D.play_locomotion_animation` for idle and run, a separate `ReactionAnim` on the player, and the weapon `AnimationPlayer` for attacks. Ownership is already separated. *Gap:* the weapon player is found by a fixed node path, which blocks per-weapon animation sets.

### 10.4 Where to follow your code instead of the guide

- **Timing comes from animation clips, not number fields.** The guide's `windup_time`, `active_time` and `recovery_time` would duplicate what your weapon clip and the effect's hit-window track already define, and the guide itself recommends animation events. Keep your approach. Add timing fields only for things a clip cannot express (charge hold time, for example).
- **Keep the existing names.** `AttackDefinition2D`, `AttackComponent2D` and `HealthComponent2D` already work and are tested. Use `WeaponDefinition2D`, `WeaponController2D` and the same `2D` suffix for new classes. Do not rename working classes to match the guide.
- **Do not move files.** Put new weapon code in a new folder beside `Characters/Components/Combat/` and leave the rest in place.
- **Do not add `attack_type` and a match statement.** The guide's type enum is fine as documentation, but the project's cleaner version is a base class for effect scenes. Each effect type (melee sweep, projectile, area) is its own script with the same `configure(...)` signature, so `AttackComponent2D` never needs to know which one it spawned. This also fixes the rigid effect contract in finding B.
- **Runtime state stays out of Resources.** The guide's rule matches what you already do (`_cooldown_remaining` and `_active_definition` live in the component). Keep combo index, charge time, skill cooldowns and passive stacks in runtime objects, never in a shared `.tres`.

### 10.5 How this changes the Phase 9 plan

Section 8 plans a flat `attacks: Array[AttackDefinition2D]`. The weapon design gives that array a better home. Build it as a weapon instead:

1. **Add `WeaponDefinition2D`** (a Resource). Fields: `weapon_id`, `display_name`, `weapon_scene` (see below), `basic_combo: Array[AttackDefinition2D]`, `heavy_attack: AttackDefinition2D`, and later `active_skills` and `passive_skills`. Keep `attack_definition` on `AttackComponent2D` as a fallback so existing scenes still load.
2. **Make the weapon a scene.** One scene per weapon holding its sprite and its own `AnimationPlayer` with the `slash`, return and heavy clips and their `attack_event` keys. The character instances it under `MainHand`, and `CharacterContext2D` reads `weapon_animation_player` from the equipped weapon scene. This removes the fixed-path rig problem for weapons and is what makes weapon switching possible.
3. **Add combo progression to `AttackComponent2D`.** `next_attack` (or index into `basic_combo`) plus the `combo_window_open` and `combo_window_close` events already reserved. Reset the combo index after a timeout or on interruption.
4. **Add a heavy path.** A second input action (`attack_heavy`) and `heavy_attack`. Decide hold-to-charge versus a plain button (see 10.7) before building.
5. **Do the sword completely before anything else.** Then add the bow to prove projectiles.

A small sketch of the new resource, following your conventions:

```gdscript
extends Resource
class_name WeaponDefinition2D

@export var weapon_id: StringName
@export var display_name: String
## Sprite + AnimationPlayer with this weapon's clips and attack_event keys.
@export var weapon_scene: PackedScene
@export var basic_combo: Array[AttackDefinition2D]
@export var heavy_attack: AttackDefinition2D
# Added in later phases:
# @export var active_skills: Array[SkillDefinition2D]
# @export var passive_skills: Array[PassiveDefinition2D]
```

Validate it the way `validate_definition()` already does: check that every attack's clips exist on the weapon scene's `AnimationPlayer`, and name the weapon and the missing clip in the error.

### 10.6 Proposed folder layout (added, not reorganized)

```
res://
├── Characters/Components/Combat/         (existing: attack component, definition, slash, HitData)
├── Characters/Components/Weapons/        (new)
│   ├── WeaponDefinition2D.gd
│   ├── WeaponController2D.gd
│   └── Skills/ and Passives/             (later phases)
├── Combat/Effects/                       (new: projectile and area effect scripts, shared base)
├── Data/Weapons/                         (sword.tres, bow.tres, ...)
├── Data/Attacks/                         (one AttackDefinition2D .tres per attack)
└── Weapons/                              (one scene per weapon: sprite + AnimationPlayer + clips)
```

This is the guide's structure adapted to what exists. Create folders only as each phase needs them.

### 10.7 Decisions to finalize

The guide leaves four choices open. A starting recommendation for each, based on your current code:

- **Basic and heavy input.** Dedicated actions (`attack_light`, `attack_heavy`) are the smallest change from today. Hold-to-charge needs a charge timer and a charged variant of the attack. Start with dedicated buttons and add charging later if the feel calls for it.
- **Aiming.** Mouse direction with left/right sprite flipping is what you have, and `aim_weapon` already rotates the weapon toward it for the player. Keep it. Lock-on would be a new targeting system.
- **Active skill slots.** Decide before building the skill UI: three, four, or a count set on each weapon. A count per weapon costs nothing extra if skills live on `WeaponDefinition2D`.
- **Authoring approach.** Hybrid, as the guide recommends. This is already the shape of your project.

### 10.8 Later phases: skills, passives and projectiles

**Projectiles.** Add a base class for effect scenes, then a projectile script that owns velocity, collision mask (from `hit_layers`), lifetime and impact. Route damage through `HitData` and `apply_hit`, the same way `AttackSlash2D` does, and spawn the definition's `hit_effect_scene` on impact. The weapon decides which projectile scene is used; the projectile does not hard-code its impact effect or damage.

**Active skills.** Reusable behavior types configured by resources, not one big match on skill names: projectile skill, area skill, dash skill (reuse `DashComponent2D` for the movement), channel skill and buff skill. A skill definition holds name, icon, slot, cooldown, cost, cast or channel timing, targeting, range, area shape, and its animation, audio and VFX references.

**Passives and status effects.** Passives respond to events. `Character2D` already re-emits `damaged`, `died` and `health_changed`, and `AttackComponent2D` emits `attack_started`, `attack_hit` and `attack_finished`; a `PassiveController` can connect to those. Before building any passive, write down the counter rules: do misses count, how counters reset, whether a multi-target attack counts once per target or once per attack, and whether stacks can overlap. The guide's example (Heroic Momentum: three qualifying hits grant an empowered state that the next attack consumes for bonus damage) is a good first test.

**Combat resolver.** When defense, crits and statuses arrive, extend what `HealthComponent2D.apply_hit` and `HitData` carry rather than adding a second damage path. Every source of damage should end in the same call.

### 10.9 Guide roadmap against your phases

- **Guide Phase 1, foundation** (resources, attack executor, sword hit detection, damage resolution, hit-once). *Mostly done:* your Phases 1 to 8. Remaining: the weapon resource, equip and switch.
- **Guide Phase 2, heavy attacks and animation ownership.** This is your Phase 9 (combo and heavy), built as 10.5 describes. Animation ownership for idle, run and reactions is already separated.
- **Guide Phase 3, projectile framework and a bow.** Not started. Needs the effect base class and a projectile script.
- **Guide Phase 4, active skills.** Not started.
- **Guide Phase 5, passives and status effects.** Not started; the signals it needs exist.
- **Guide Phase 6, expand and polish.** Fire staff, hammer, daggers, distinct effects, sound, debug tools and resource validation. By then each new weapon should be content only.

### 10.10 Design rules, checked against your code

- **Do not duplicate the player controller or damage system per weapon.** Followed: one `Character2D`, one `HealthComponent2D`.
- **Keep definitions separate from runtime state.** Followed so far; keep it that way for combos, charge, cooldowns and stacks.
- **Route all damage through one resolver.** Followed through `HitData` and `apply_hit`; keep new damage sources on that path.
- **Use dedicated behavior classes for different attack types.** Not yet; needed when you add projectiles and areas (see 10.4).
- **Use animation events for hit and release timing.** Followed: `attack_event(&"spawn_effect")` and the hit-window track. Add events for arrow release and charge.
- **Give each attack a hit-once or multi-hit policy and a target filter.** Partly: hit-once is per effect and targets are filtered by team and layers. Add an explicit pierce or max-targets setting before projectiles.
- **Build one complete sword, then one complete bow.** This is the recommended order.
- **Inspect before moving files.** Followed in this guide: nothing needs to be moved.
- **Use explicit typing and validate exported resources.** Mostly followed (`validate_definition`); extend the same validation to weapons, skills and passives.

### 10.11 Adding a weapon once this exists

After the weapon framework is in place, a new weapon is content work:

1. Build the weapon scene: sprite, `AnimationPlayer`, light, heavy and return clips, and `attack_event` keys.
2. Build or inherit the effect scenes (slash, projectile, area) and impact scenes.
3. Create one `AttackDefinition2D` `.tres` per attack, following section 5.
4. Create one `WeaponDefinition2D` `.tres`, then fill `weapon_scene`, `basic_combo` and `heavy_attack`.
5. Equip it on the player and test with the smoke test, plus one new check per attack.

*Reference note: for any exact Albion Online ability or balance detail, verify against current official game information.*
