# Combat Architecture Review & Expansion Guide

*My 2D Game · Godot 4.7 · reviewed October 23, 2026 from the uploaded project archive (static review; I could not run Godot, so anything marked “verify in-game” needs a play-test).*

## 1. Summary

The foundation is good. You already have the right *shape* for a data-driven, component-based game: controllers express intent, components execute, a shared `CharacterContext2D` carries state, attacks have a Resource (`AttackDefinition2D`), and the slash effect is its own scene with its own animation. The smoke tests are a real asset.

The gap is that **the data-driven idea stops halfway**. An “attack” is currently spread across four places (the `.tres` definition, the slash scene assigned on the character, hard-coded animation names in `AttackComponent2D`, and the AI’s `attack_range`), and the components are created in code rather than living in the scene tree. That makes expanding combat (heavy attacks, combos, new enemies) harder than it needs to be.

**Top findings, in order of impact:**

1. **`cooldown_duration` currently does nothing.** Both attack definitions (0.35 s and 0.55 s) are shorter than the weapon animation cycle (player ≈ 0.96 s, goblin ≈ 0.95 s), and the code uses the larger of the two. Attack rate is really controlled by animation length.
2. **An attack is not one data package.** Slash scene lives on `Character2D`, animation names (`slash`, `sword_return`) are constants in code, and range lives on the AI controller.
3. **Only one attack per character**, with no combo, no multi-hit, and one spawn event per swing.
4. **Health/damage is duplicated** in `player.gd` and `BasicEnemy2D.gd` instead of being a component.
5. **Damage is a bare `int`** passed by `call("take_damage")`, with no source, direction, knockback or type. Team logic is hard-coded to group names inside the slash script.
6. **Components and states are built with `.new()` in `Character2D._ready()`**, so they are invisible and un-tweakable in the editor.
7. **Authored scene data is going unused** (enemy `take_damage` clip, three effect spritesheets, a stale duplicate scene).

## 2. What is already working well

- **Intent/execution split.** `EnemyAIController2D` and `player.gd` only answer “what do I want to do?” (`_get_movement_input`, `_get_attack_requested`…). `Character2D` and the components do it. This is exactly right and is what lets one base class serve player and goblin.
- **Single movement authority.** `MovementComponent2D` is the only thing that calls `move_and_slide()`; dash overrides velocity through context rather than moving the body itself.
- **The slash is a self-contained scene.** `AttackSlash2D.tscn` owns its sprite, animation, hitbox sweep and collision toggling. Changing `hitbox_size` duplicates the shape so scenes never share a mutated resource. Hit-once-per-target-per-swing is handled.
- **Authored events instead of timers.** The `spawn_slash` method track on the weapon animation means VFX timing is edited visually, not in code.
- **Fail loudly.** `CharacterContext2D` warns when a method track doesn’t resolve to the character, and `AttackComponent2D` refuses to initialize without the required clips. This will save you hours.
- **Signals exist** on components (`attack_started`, `attack_hit`, `attack_finished`, `dash_started`, `dash_ended`), which is the hook everything else should use.
- **Smoke tests** cover structure, attack, hit reaction, facing, dash, AI and death.

## 3. Combat review in detail

### 3.1 How an attack flows today

1. `Character2D._physics_process` asks the controller whether an attack was requested and in which direction.
2. `AttackComponent2D.try_start()` checks gating (initialized, not dashing/attacking, cooldown), stores direction in context, sets `is_attacking`, and plays the weapon clip `slash`.
3. A method track in `slash` (at 0.05 s) calls `spawn_slash()` on the character, which forwards to `AttackComponent2D.spawn_slash_from_animation()`.
4. The component instantiates the slash scene, calls `configure(...)` with damage, direction, hitbox size and offset, adds it to the current scene at the character’s position.
5. The slash’s own `AnimationPlayer` plays `slash`: sprite frames, travel, and a `CollisionShape2D:disabled` track that opens and closes the hit window.
6. `AttackSlash2D._try_hit` filters (self, `damageable` group, same-team groups, already-hit) and calls `take_damage(damage)`.
7. When `slash` finishes, `sword_return` plays; when that finishes, `is_attacking` clears and `attack_finished` fires.

### 3.2 Findings

**A. `cooldown_duration` is effectively dead (bug-level).** `try_start` sets `_cooldown_remaining = max(definition.cooldown_duration, weapon_cycle)`. The cycle is slash + return length divided by `speed_scale`. Player: 0.292 + 0.667 ≈ 0.96 s. Goblin: 0.30 + 0.65 ≈ 0.95 s. Since `is_attacking` also stays true for that entire cycle, the cooldown has expired by the time you could attack again. Until a definition value exceeds the animation length, editing it changes nothing. Decide what you want the number to mean (see 3.3).

**B. Attack data is fragmented.**

- Damage, hitbox size, hitbox offset, cooldown → `AttackDefinition2D`.
- Slash scene → `Character2D.attack_slash_scene` (separate export).
- Animation names → `const SLASH_ANIMATION / RETURN_ANIMATION` in `AttackComponent2D`.
- Reach / sweep distance → baked into the slash scene’s animation (hitbox travels 8 → 62 px).
- When the AI decides to swing → `EnemyAIController2D.attack_range` (30 px).

Result: to make a heavy attack you edit a resource, a scene, a character export, two animation clips, and possibly the AI. Also note the AI range (30) and the real reach (about 62 px of sweep plus hitbox width) are unrelated numbers, so they can silently disagree.

**C. One attack per character, one spawn per swing.** `spawn_slash_from_animation` frees any previous active slash before spawning a new one, so multi-hit attacks (flurry, spin) are impossible. There is no concept of combo step, charged attack, or a second attack slot.

**D. Hard-coded two-phase attack.** The component assumes exactly “slash then return”. A ranged attack, a lunge, a windup-only telegraph, or a one-clip attack cannot be expressed without editing `AttackComponent2D`.

**E. The sword swing doesn’t aim.** `WeaponFacingPivot` is only mirrored left/right (`scale.x`); nothing rotates it toward `aim_direction`. The slash *effect* rotates toward the mouse, but the sword *swing* always plays the same arc. Verify in-game; if you want 360° aimed attacks this is the first thing you’ll notice.

**F. Damage payload and team logic.**

- `take_damage(amount: int)` is called via `target.call(...)` after a `has_method` check. There’s no source, direction, knockback, hit-stun, damage type, or crit flag.
- Team rules are `is_in_group("player") and is_in_group("player")` in `AttackSlash2D`. Adding a third faction (neutral NPC, ally, destructible) means editing the slash script.
- The hit `Area2D` mask is fixed in the scene (`collision_mask = 3`: player + enemy), so it can’t hit the world layer (breakables, switches) without scene edits.

**G. Health and death are duplicated.** `player.gd` and `BasicEnemy2D.gd` each own `health`, `max_health`, `health_changed`, `died`, `take_damage`, and the “cancel attack + cancel dash on death” sequence. A `HealthComponent2D` would remove \~40 duplicated lines and give you invulnerability frames, healing, armor and resistances in one place.

**H. No interrupt rules.** Taking damage does not cancel an attack, and there’s no stagger. Fine for now, but you’ll want `interruptible` / `poise` fields on the definition once enemies have heavy attacks.

**I. Movement during attacks is not configurable.** `MovementComponent2D` always uses `movement_input`, so characters walk freely while swinging. If you want lunges, rooted heavy swings, or slowed attacks, that needs a `movement_multiplier` (and optionally `lock_facing`) per attack.

**J. Enemy hit feedback bypasses the authored clip.** `BasicEnemy2D.tscn` contains a `take_damage` animation (flash + shake) that nothing plays; `_play_hit_feedback()` re-creates the same effect with a tween. The reason is real (the clip has a `:frame` track that fights the sprite’s idle/run animation) but the fix is to remove that track and use the clip.

**K. Unused/stale assets.**

- `sword_slash.tscn` (project root) is an unreferenced duplicate of `AttackSlash2D.tscn`.
- `hit_effect_anim_spritesheet`, `explosion_anim_spritesheet` and `enemy_afterdead_explosion_anim_spritesheet` are imported but not used by any scene or script. The goblin currently just calls `queue_free()` on death.

### 3.3 Recommended target design for combat

Make **one `AttackDefinition2D` resource describe a complete attack**, so adding an attack is “create one `.tres`”. Suggested fields:

```gdscript
extends Resource
class_name AttackDefinition2D

@export var id: StringName = &"light"

@export_group("Damage")
@export var damage: int = 1
@export var knockback: float = 0.0
@export var hit_stun: float = 0.0

@export_group("Timing")
@export var cooldown_after_finish: float = 0.2   # starts when the attack ENDS
@export var movement_multiplier: float = 1.0
@export var interruptible: bool = true

@export_group("Animation")
@export var weapon_animation: StringName = &"slash"
@export var recovery_animation: StringName = &""   # optional

@export_group("Effect + Hitbox")
@export var effect_scene: PackedScene
@export var hitbox_size: Vector2 = Vector2(16, 16)
@export var hitbox_offset: Vector2 = Vector2.ZERO

@export_group("AI")
@export var ai_attack_range: float = 30.0
```

Then:

- `AttackComponent2D` exports `attacks: Array[AttackDefinition2D]` and a `current_attack`; `try_start(attack_id, direction)` picks one.
- Replace the hard-coded `spawn_slash` method name with a generic animation event (e.g. `attack_event(&"spawn_effect")`, `attack_event(&"combo_window_open")`) so a clip can fire several events.
- Make `cooldown_after_finish` start when the attack ends. That makes the number mean what it says.
- Send hits as a small `HitData` object/resource (`damage`, `source`, `direction`, `knockback`, `team`) to a `HealthComponent2D` instead of a bare `int`.
- Replace group-name team checks with collision layers set from a `team` value, or a `Hurtbox` area on each character.

## 4. Wider architecture review

**Components are created in code.** `Character2D._ready()` does `MovementComponentScript.new()` and `add_child()` for movement, dash, attack and the state machine, then mirrors exports (`move_speed`, `dash_*`, `attack_definition`) onto them through property setters. This is \~70 lines of plumbing and means none of it is visible in the Scene dock. Make them real child nodes in a base character scene and let each component own its exports; delete the forwarding setters.

**States are `RefCounted` objects registered in code.** Node-based states (`IdleState`, `MoveState`… as children of the state machine) can be seen, reordered, and extended per enemy (add a `StaggerState` node to the goblin only).

**Static typing is inconsistent.** Several scripts use `const X = preload(...)` aliases and `state_machine.call("transition_to", ...)` with string names, which silently disables type checking. Adding `class_name` to `CharacterContext2D`, `CharacterState` and `CharacterStateMachine`, and `extends Character2D` instead of `extends "res://…/Character2D.gd"` in `player.gd` and `BasicEnemy2D.gd`, lets the editor catch typos.

**One `AnimationPlayer` does locomotion and reactions on the player.** `PlayerAnim` plays `idle`, `run`, `take_damage`, `death` and `RESET`. Because `take_damage` resets sprite frames, locomotion states must re-assert their clip every frame, and `play_locomotion_animation` needs a special-case list of clips it must not interrupt. If reaction clips only touch the flash shader parameter (not `frame`/`position`) they can live on a **second** `AnimationPlayer` and play in parallel with no re-assert hack.

**AI is a string-keyed if/else.** `EnemyAIController2D` is clean for one enemy. For variety, move detection to an `Area2D` child (see section 6) and consider behaviour states or a `Resource` per enemy archetype (`detection_radius`, `attack_range`, `home_stop_distance` are already pure data).

**HUD duplication.** `PlayerHealthBar.gd` and `EnemyHealthBar2D.gd` are \~90% the same tween/bar logic, and `HealthBarStyle.gd` builds style boxes in code. See section 6.

**Housekeeping.**

- Two asset roots (`2D_RPG_Assets/` and `Assets/`); pick one.
- The zip contained the `.godot/` cache (including machine-specific D3D12 shader caches). Exclude it when sharing or committing.
- `Character2D._update_facing_direction()` sets `weapon_pivot.z_index = 1` every physics frame; set it once in the scene.
- `dash_speed = 150` on the goblin scene is unused because the goblin never requests a dash.

## 5. Step-by-step: expanding combat yourself

### Part A: Workflow that works with the code as it is today

Use this until you do the refactor in 3.3. Examples use a “Heavy Slash” for the player.

**Step 1: Create the attack definition**

1. In the FileSystem dock open `Characters/Components/Combat/`.
2. Right-click → *Create New* → *Resource…* → choose `AttackDefinition2D` → save as `HeavyAttackDefinition.tres`.
3. In the Inspector set `damage`, `hitbox_size`, `hitbox_offset`.
4. Set `cooldown_duration`, but remember finding A: it only matters if it is **longer** than the weapon animation cycle. To slow an attack today, lengthen the weapon clips or lower the weapon `AnimationPlayer`’s `speed_scale`.

**Step 2: Create the slash effect scene**

1. Right-click `AttackSlash2D.tscn` → *New Inherited Scene*. Save as `HeavySlash2D.tscn` in the same folder.
2. Keep these names and paths exactly, because `AttackSlash2D.gd` looks them up with `$`:
   - `SlashEffectAnimSpritesheet/AnimationPlayer` with a clip named **`slash`**
   - `HitboxOrigin/HitboxMotion/Area2D/CollisionShape2D`
3. Change the look: select `SlashEffectAnimSpritesheet`, swap `texture`, set `hframes`/`vframes`.
4. Edit the `slash` clip:
   - `frame` track → which sprite frame shows when.
   - `HitboxMotion:position` track → how far the hitbox travels (reach).
   - `CollisionShape2D:disabled` track → **the active hit window**. Put `false` where damage should start and `true` where it should end.
   - `modulate`, `scale`, `position` tracks → fade, stretch, travel of the visual.
5. Check the Area2D’s collision mask in the Inspector. At the moment it is 3 (player + enemy layers).
6. Enable *Debug → Visible Collision Shapes* when testing so you can see the active window.

**Step 3: Author the weapon swing animation**

1. Open the player scene, select `WeaponFacingPivot/MainHand/HandAnim` (goblin: `AnimatedSprite2D/Weapon/WeaponAnimation`).
2. The component requires clips named exactly **`slash`** and **`sword_return`**. Edit those (or, if you need two different swings today, make a second player scene or swap the clips per weapon).
3. In `slash`, keep a **method track** that calls `spawn_slash`. Its key time is when the effect appears.
4. The track’s path must resolve to the character root (`../..` from the pivot’s animation root). If it doesn’t, `CharacterContext2D` prints a warning at startup. Treat any warning in the Output panel as a to-do.

**Step 4: Assign everything to the character**

1. Select the character’s root node (Player, or the enemy scene root).
2. In the Inspector → *Attack* group set **Attack Definition** = `HeavyAttackDefinition.tres` and **Attack Slash Scene** = `HeavySlash2D.tscn`.
3. Enemies only: adjust `EnemyAIController2D.attack_range` so the AI swings from a distance that actually reaches (reach is roughly hitbox offset + sweep + half the hitbox width).

**Step 5: Test**

1. Run the game and swing. Watch the Output for warnings or errors.
2. Confirm: the effect spawns at the right frame, hits once per swing, doesn’t hit the attacker or same-team characters, and the swing finishes and returns to idle/run.
3. Run the headless smoke test: `godot --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd`
4. If you change the attack rate or damage, update the expectations in `tests/smoke_checks.gd` (section B asserts exactly 1 damage).

### Part B: Workflow after you do the refactor in 3.3

Once `AttackDefinition2D` owns the effect scene, animation names and range, adding an attack becomes:

1. **Animate** the weapon clip on the character’s weapon `AnimationPlayer` (any name), adding `attack_event` keys where things should happen.
2. **Build** the effect scene as an *Inherited Scene* of `AttackSlash2D.tscn` (or a projectile scene).
3. **Create** one `AttackDefinition2D` `.tres`: pick the clip name, effect scene, damage, knockback, hitbox, `ai_attack_range`.
4. **Add** it to the character’s `AttackComponent2D.attacks` array.
5. **Bind** it: map an input action (`attack_heavy`) for the player, or add it to the enemy’s weighted attack list.
6. **Test** with the smoke test plus one new check for the attack’s id.

No script edits. That is the data-driven goal.

### Part C: Suggested sequence for the refactor itself

Do these one at a time and run the smoke test after each.

1. Decide the meaning of cooldown (recommend: starts when the attack ends) and fix finding A.
2. Move `slash_scene`, animation names, and attack range into `AttackDefinition2D`.
3. Replace the `spawn_slash` method with a generic `attack_event(name)` and update both weapon clips.
4. Extract `HealthComponent2D` from `player.gd` and `BasicEnemy2D.gd`.
5. Introduce `HitData` and route `take_damage` through it.
6. Turn components and states into scene nodes (section 6, items 1–2).
7. Add `attacks: Array[AttackDefinition2D]`, then a second attack to prove it.

## 6. Code-driven elements that could be scenes or resources

Each item shows **what the code does now → what it could be**.

### Character and combat

1. **Components built with `.new()` in `Character2D._ready()`** (Movement, Dash, Attack) → child nodes in a base `Character2D.tscn`, with inherited scenes for Player and Goblin. Exports are edited in the Inspector per scene.
2. **State machine and four state objects registered in code** → `CharacterStateMachine` node with `IdleState`, `MoveState`, `DashState`, `AttackState` as child nodes.
3. **Facing flip** (`visual_root.scale.x`, `weapon_facing_root.scale.x`, set every physics frame) → a small `FacingComponent2D` node, or an `AnimationPlayer`/`AnimationTree` parameter.
4. **`weapon_pivot.z_index = 1` set every frame** → set `z_index` on `MainHand` in the scene. If it needs to change with direction, key it in the weapon animations.
5. **Slash spawn position** (`slash.global_position = character.global_position`) → a `Marker2D` named `AttackSpawnPoint` in the character scene, so each character defines where attacks originate.
6. **Where effects are parented** (`current_scene`, falling back to parent) → an `Effects` container node in `Main.tscn`, found through an exported `NodePath` or a group.
7. **Enemy hit feedback tween** (`_play_hit_feedback`) → the authored `take_damage` clip already in `BasicEnemy2D.tscn`, after removing its `:frame` track. Or a reusable `HitFlash` scene (a node plus its own `AnimationPlayer`) used by both player and enemy.
8. **Player reaction clips sharing the locomotion `AnimationPlayer`** → a second `AnimationPlayer` (e.g. `ReactionAnim`) that animates only the flash shader parameter, so it plays in parallel with idle/run.
9. **Animation name strings** (`"idle"`, `"run"`, `"take_damage"`, `"RESET"`, `"death"`, `"slash"`, `"sword_return"`) in several scripts → exported `StringName` fields or a `CharacterAnimationSet` resource so a new character can use different clip names.
10. **Death** (`queue_free()` immediately on the goblin) → a `DeathEffect` scene (you already have `enemy_afterdead_explosion_anim_spritesheet`) spawned by a `died` signal, with `queue_free()` at the end of its animation.
11. **Impact VFX** (`hit_effect_anim_spritesheet`, imported but unused) → a `HitEffect.tscn` spawned from the slash’s `hit_confirmed` signal at the contact point.
12. **Groups set in code** (`add_to_group("player")` etc.) → set in the Node dock → Groups tab on the scene root, so they’re visible and survive refactors.
13. **Hard-coded team checks** in `AttackSlash2D._try_hit` → collision layers/masks configured on the slash’s `Area2D`, or a `team` value on a `Hurtbox` node.
14. **Hit\_flash material duplicated four times** as sub-resources on the layer sprites in `player.tscn` → one shared `ShaderMaterial` `.tres` (or a `CanvasGroup` over `LayeredRig` with a single material).

### Enemy AI

15. **Target search** (`get_nodes_in_group` every 0.2 s plus distance math) → a `DetectionArea` `Area2D` + `CollisionShape2D` child; visible in the editor, resizable by dragging, filtered by physics layers.
16. **AI tuning numbers** (`detection_radius`, `disengage_radius`, `attack_range`, `home_stop_distance`) → an `EnemyBehaviorProfile` `.tres` shared by enemy variants.
17. **Behavior names as strings** (`"Idle"`, `"Chase"`, `"Attack"`, `"Return"`) → behavior state nodes, or at least an enum.

### HUD

18. **Style boxes built in `HealthBarStyle.gd`** (panel, bar background, fill, damage trail) → `StyleBoxFlat` `.tres` files or one `Theme` resource applied to the bar scene.
19. **Font setup in code** (`FontVariation` with `wght` axis) → a `FontVariation` `.tres` referenced from the Theme.
20. **Health colours by ratio** (`COLOR_HEALTH_HIGH/MID/LOW` thresholds in script) → a `Gradient` or small `HealthBarStyle` resource.
21. **Five tweens per bar** (intro, hit pulse, heal pulse, critical pulse loop, counter) → `AnimationPlayer` clips (`intro`, `hit`, `heal`, `critical`) inside the health bar scene. Only the number-counter tween really needs code.
22. **Two near-identical bar scripts** → one `HealthBar.tscn` base with a compact variant (inherited scene) for enemies.
23. **Binding by group lookup** (`get_first_node_in_group("player")`, `call_deferred`) → an exported `NodePath` or a `HealthComponent2D` reference assigned in the editor.

### Already good (keep as is)

- Slash effect animation, hitbox sweep and active window (scene + AnimationPlayer).
- Player rig, locomotion and weapon swing clips (AnimationPlayer).
- Goblin `SpriteFrames` (idle/run).
- Arena walls and layers in `Main.tscn`, physics layer names in `project.godot`.

## 7. Cleanup checklist

- Delete `sword_slash.tscn` at the project root (unreferenced; the real one is `Characters/Components/Combat/AttackSlash2D.tscn`).
- Pick one asset folder and move the other into it.
- Exclude `.godot/` from archives and version control.
- Remove the unused `dash_speed` override on the goblin, or give the goblin a dash intentionally.
- Add `class_name` to `CharacterContext2D`, `CharacterState`, `CharacterStateMachine`, and switch `player.gd` / `BasicEnemy2D.gd` to `extends Character2D`.
- After changing attack timing, update `tests/smoke_checks.gd`, and add a test that asserts effective attack rate so finding A can’t regress.

## 8. Implementation Plan

This turns the findings above into an ordered plan. It replaces the short sequence in Part C of section 5. Each phase is small enough to finish in one sitting, leaves the game playable, and ends with the smoke test green. Effort figures are rough estimates for one person working in the Godot editor.

### Ground rules

- **Branch and tag.** Work on a branch, commit per phase, and tag `phase-N-done` so you can roll back one phase without losing the rest.
- **Smoke test first and after every step.** Run `godot --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd`. Save the baseline output before you touch anything.
- **Move and rename in Godot’s FileSystem dock**, never in the OS file browser, so UIDs and scene references update.
- **Shims before deletions.** When an API changes, keep the old one as a thin forwarding function until the phase that migrates its last caller, then delete it.
- **One behaviour change at a time.** Refactor steps keep gameplay identical. Anything that changes how the game feels (cooldowns, knockback) is its own step with its own test.
- **Every phase adds tests.** The smoke test is your safety net; extend it as you go.

### Decisions to make before starting

1. **What should cooldown mean?** Recommended: it starts when the attack *ends*, so the number in the resource is the real gap between attacks.
2. **Should the sword swing aim toward the mouse?** If yes, do the optional step at the end of Phase 7.
3. **Team rule.** Recommended: a `team` value on the character (groups stay only for targeting). Alternative: collision layers only.
4. **Fate of `attack_slash_scene` on `Character2D`.** Recommended: the attack definition owns the effect scene; keep the character export only as a temporary fallback.

### Overview

- **Phase 0:** Baseline and cleanup (\~½ day)
- **Phase 1:** Fix attack timing (\~½ day)
- **Phase 2:** One resource per attack (\~1–1.5 days)
- **Phase 3:** Generic animation events and multi-hit (\~1 day)
- **Phase 4:** `HealthComponent2D` and `HitData` (\~1.5 days)
- **Phase 5:** Teams, hit layers, knockback, interrupts (\~1 day)
- **Phase 6:** Components and states become scene nodes (\~1.5–2 days)
- **Phase 7:** Scene-driven feedback and VFX (\~1.5 days)
- **Phase 8:** AI detection and HUD as scenes (\~1.5–2 days)
- **Phase 9:** Multiple attacks and combos (\~1–2 days)

Total: roughly 11–14 focused days. Dependencies: 2 → 3 → 9; 4 → 5 → 7; 6 and 8 can happen any time after 4. After Phase 5 the *combat* is fully data-driven; Phases 6–8 are the scene-driven work, and can be reordered if you would rather see visible results sooner.

### Milestones

- **M1 (Phases 0–2):** an attack is one resource.
- **M2 (Phases 3–5):** events, health and hits are proper systems.
- **M3 (Phases 6–8):** the editor shows and controls everything.
- **M4 (Phase 9):** a new attack is purely a content task, with no script edits.

## Phase 0: Baseline and cleanup (\~½ day)

**Goal:** a clean starting point with zero behaviour change.

1. Create a branch, run the smoke test, and save the output as the baseline (all `CHECK PASS`).
2. Delete `sword_slash.tscn` at the project root (unreferenced). Merge `Assets/` and `2D_RPG_Assets/` into one folder using the FileSystem dock.
3. Add `class_name` to `CharacterContext2D`, `CharacterState` and `CharacterStateMachine`. In every script that has `const X = preload(...)` of the same name, delete that const in the same edit, because it would shadow the global class.
4. Change `extends "res://Characters/Core/Character2D.gd"` to `extends Character2D` in `player.gd` and `BasicEnemy2D.gd`. Type `CharacterState.state_machine` as `CharacterStateMachine` and replace the `.call("transition_to", ...)` string calls with direct calls.
5. Confirm `.gitignore` excludes `.godot/`.

**Done when:** the smoke test output matches the baseline and the Output panel shows no new warnings.

## Phase 1: Make attack timing mean what it says (\~½ day)

**Goal:** fix finding A. This is the only phase that intentionally changes game feel.

1. In `AttackComponent2D.try_start`, remove `maxf(definition.cooldown_duration, _weapon_cycle_duration())`. The cooldown should not start with the swing.
2. Start it when the swing ends:

```gdscript
# AttackComponent2D._on_weapon_animation_finished
elif animation_name == RETURN_ANIMATION:
	context.is_attacking = false
	_cooldown_remaining = definition.cooldown_duration
	_active_slash = null
	attack_finished.emit()
```

3. Retune the two `.tres` files. The values now *add* to the \~0.95 s animation cycle. To keep today’s feel, set both to about 0.0–0.1; otherwise pick the gap you actually want.
4. Keep `_weapon_cycle_duration()` only if something still uses it (for example an AI telegraph); otherwise delete it.

**Tests to add:** after an attack finishes, `is_on_cooldown()` is true for about `cooldown_duration` and then false; the period between two attacks equals cycle length plus cooldown within one physics frame.

**Done when:** editing `cooldown_duration` visibly changes attack rate for both player and goblin.

## Phase 2: One resource per attack (\~1–1.5 days)

**Goal:** `AttackDefinition2D` describes a complete attack (see the field list in 3.3). Defaults reproduce today’s behaviour, so nothing breaks as fields are added.

1. Add fields to `AttackDefinition2D`: `id`, `effect_scene`, `weapon_animation` (default `slash`), `recovery_animation` (default `sword_return`; empty means the attack ends when the weapon clip ends), `ai_attack_range`, `movement_multiplier`. Keep the name `cooldown_duration` so existing `.tres` values survive.
2. In `AttackComponent2D`, replace the two animation constants with the definition’s names. Validate that the clips exist in `initialize()` **and** in `set_attack_definition()` (today it only validates at start-up, so swapping definitions at runtime can reference a missing clip).
3. Effect scene: use `definition.effect_scene` when set, else fall back to the character’s `attack_slash_scene`. Mark that export deprecated in a comment.
4. AI: read the swing distance from `attack_component.definition.ai_attack_range` when it is above zero, else from the controller’s own `attack_range`. Fill in the goblin’s value so it matches the slash’s real reach.
5. Movement multiplier: add `move_multiplier := 1.0` to `CharacterContext2D`. `AttackComponent2D` sets it from the definition when an attack starts and resets it to 1.0 when it finishes or is cancelled. `MovementComponent2D` multiplies normal (non-dash) movement by it.
6. Update `DefaultAttackDefinition.tres` and `GoblinAttackDefinition.tres`.

**Tests to add:** a definition with different clip names plays correctly; a definition with a missing clip logs an error that names the clip; the AI uses the definition’s range; `move_multiplier` returns to 1.0 after an attack.

**Done when:** you can change an attack’s animation, effect, range and speed using only the `.tres`.

## Phase 3: Generic animation events and multi-hit (\~1 day)

**Goal:** a weapon clip can fire several named events, not one hard-coded `spawn_slash`.

1. Add `Character2D.attack_event(event: StringName)` that forwards to `AttackComponent2D.handle_event(event)`.
2. `handle_event(&"spawn_effect")` runs the existing spawn logic. Keep `spawn_slash()` as an alias that calls `attack_event(&"spawn_effect")`, so the current clips keep working.
3. Update `CharacterContext2D._validate_spawn_slash_tracks` to accept either method name.
4. Replace `_active_slash` with `_active_effects: Array[AttackSlash2D]`. Remove entries when they leave the tree, and have `cancel()` free all of them. Stop freeing the previous slash when a new one spawns.
5. Migrate the player and goblin weapon clips to call `attack_event` with the argument `spawn_effect`. Once both work, delete the `spawn_slash()` alias.
6. Reserve the event names `combo_window_open` and `combo_window_close` for Phase 9.

**Tests to add:** a clip with two `spawn_effect` events creates two slashes; `cancel()` frees all of them.

**Done when:** a flurry attack is possible by adding keys to an animation and nothing else.

## Phase 4: HealthComponent2D and HitData (\~1.5 days)

**Goal:** remove the duplicated health code and replace the bare `int` damage.

1. Create `HitData` (a `RefCounted`): `damage`, `source`, `direction`, `knockback`, `hit_stun`.
2. Create `HealthComponent2D` (a `Node`): `max_health`, `health`, signals `health_changed(current, maximum)`, `damaged(hit)` and `died`, plus `apply_hit(hit)`, `heal(amount)`, `is_alive()` and an optional invulnerability window.
3. Add it as a child node to `player.tscn` (max 5) and `BasicEnemy2D.tscn` (max 3), matching today’s values.
4. In `Character2D`: expose `health_component`; add `apply_hit(hit)`; keep `take_damage(amount)` as a shim that wraps a `HitData`; add `health` and `max_health` getters that forward; re-emit `health_changed` and `died`. The HUD and the smoke tests read all of these, so the shims keep them working until Phase 8.
5. Move the shared death logic (cancel attack, cancel dash) into one handler in `Character2D`. `player.gd` and `BasicEnemy2D.gd` keep only presentation (the `death` clip, `queue_free()`).
6. `AttackSlash2D` builds a `HitData` (direction = slash direction) and calls `apply_hit` when the target has it, falling back to `take_damage` otherwise.
7. Delete the duplicated health variables, signals and `take_damage` bodies from `player.gd` and `BasicEnemy2D.gd`.

**Tests to add:** existing B, C, F and G must pass unchanged; new checks for healing clamped to max, overkill damage, and the invulnerability window ignoring a second hit.

**Done when:** health, damage and death live in one component and both characters use it.

## Phase 5: Teams, hit layers, knockback, interrupts (\~1 day)

**Goal:** combat rules become data and general.

1. Add `team: StringName` to `Character2D` (`player`, `enemy`). `AttackSlash2D._try_hit` compares `source.team` with `target.team`. Groups stay only for target searches.
2. Add `hit_layers` (`@export_flags_2d_physics`, default 3 to match today) to `AttackDefinition2D` and apply it to the hitbox `Area2D` mask in `configure()`. This also lets an attack hit the world layer later (breakables, switches).
3. Knockback: add `knockback_velocity` to the context, decaying each physics frame; `MovementComponent2D` adds it; apply `hit.direction * hit.knockback` from the `damaged` signal.
4. Interrupts: add `knockback`, `hit_stun` and `interruptible` to the definition. If a hit lands on a character whose current attack is `interruptible`, call `attack_component.cancel()`. `hit_stun` briefly blocks `try_start`.

**Tests to add:** same-team hit does nothing; a third team is damaged; knockback moves the target; an interruptible swing is cancelled. Keep B4 (the swinging player doesn’t move) passing.

**Done when:** a new faction or a breakable object needs no script change.

## Phase 6: Components and states become scene nodes (\~1.5–2 days)

**Goal:** everything you tune is visible in the Scene dock.

**6a. Components**

1. In `player.tscn` and `BasicEnemy2D.tscn` add child nodes `MovementComponent2D`, `DashComponent2D` and `AttackComponent2D` (and keep `HealthComponent2D`). The scripts are already `Node` with `class_name`.
2. In `Character2D._ready()` replace `.new()` plus `add_child()` with typed `@export` references (with a `get_node_or_null` fallback). Keep calling `initialize(context)`, and `push_error` if a required component is missing.
3. Move `move_speed` to `MovementComponent2D` and the dash values to `DashComponent2D`; delete the forwarding setters. **Re-enter per-scene overrides on the components**: the goblin’s `move_speed = 50` and `dash_speed = 150` live on the root node today and will otherwise be lost.
4. Move the `attack_definition` / `attack_slash_scene` exports onto `AttackComponent2D`.

**6b. States**

1. Make `CharacterState` extend `Node`; keep `setup`, `enter`, `physics_update` and `exit`.
2. Add `Idle`, `Move`, `Dash` and `Attack` nodes under the `CharacterStateMachine` node in each scene. The machine registers its children by node name in `_ready()` and has an `initial_state` export.
3. Delete the `register_state(...)` block from `Character2D`.

**Watch out:** child `_ready()` runs before the parent’s, so components must not touch `context` in `_ready()`. They don’t today; keep it that way. Do 6a and 6b as separate commits.

**Tests to update:** the structure checks (section A) assert that the nodes exist in the scene without runtime creation.

**Done when:** you can select a component in the Scene dock and edit its exports per character. Optional afterwards: make a `Character2D.tscn` base scene and inherit Player and Goblin from it.

## Phase 7: Scene-driven feedback and VFX (\~1.5 days)

**Goal:** presentation is authored in scenes and animation clips, not tweens and per-frame code.

1. **Enemy hit feedback.** Delete the `:frame` tracks from the enemy’s `take_damage` and `RESET` clips. Play `take_damage` from the `damaged` handler and delete the `_play_hit_feedback` tween. Check that idle/run keep animating during the flash.
2. **Player reactions.** Add a second `AnimationPlayer` (`ReactionAnim`) with a `take_damage` clip that only animates `material:shader_parameter/enabled`. Remove the frame and position tracks from `PlayerAnim`’s `take_damage`, then remove the `take_damage`/`RESET` special case from `play_locomotion_animation` (keep `death`). Replace the four duplicated shader sub-resources with one shared `ShaderMaterial` `.tres`.
3. **Effects container.** Add an `Effects` `Node2D` to `Main.tscn` (in a group such as `effects_root`) and have attack effects and VFX spawn there instead of `current_scene`.
4. **Hit effect.** Build `HitEffect.tscn` from `hit_effect_anim_spritesheet` with an `AnimationPlayer` that frees the scene at the end. Spawn it at the contact point from `hit_confirmed`.
5. **Death effect.** Build `DeathEffect.tscn` from `enemy_afterdead_explosion_anim_spritesheet`, spawned at the enemy’s position when `died` fires.
6. **Static properties out of code.** Set `z_index` on `MainHand` in the scene and groups in the Node dock; delete the per-frame `z_index` line and the `add_to_group` calls.
7. **Optional (decision 2): aimed swing.** Rotate `WeaponFacingPivot` toward `aim_direction` at attack start, behind an `aim_weapon` flag on the definition. Treat it as its own small spike, because the left/right mirroring and the authored arc both interact with it.

**Tests to add:** the reaction clip plays without interrupting run; a death effect appears in the `Effects` container.

**Done when:** hit flash, hit impact and death all play from scenes and clips you can edit visually.

## Phase 8: AI detection and HUD as scenes (\~1.5–2 days)

**8a. AI**

1. Add a `DetectionArea` (`Area2D` with a `CircleShape2D`) to the enemy scene. Track candidates through `body_entered` / `body_exited`, filtered by physics layer, and keep the disengage-distance and grace-time logic. Delete the `get_nodes_in_group` scan.
2. Create an `EnemyBehaviorProfile` resource (`detection_radius`, `disengage_radius`, `lost_target_grace_duration`, `home_stop_distance`; attack range now comes from the attack definition). Replace the behaviour strings with an enum.

**8b. HUD**

1. Build one `HealthBar.tscn` with an `AnimationPlayer` holding `intro`, `hit`, `heal` and `critical` clips. Keep only the number-counter tween in code.
2. Move the style boxes to `StyleBoxFlat` `.tres` files (or one `Theme`), and the `FontVariation` to a `.tres`. Use a `Gradient` for the high/mid/low colours.
3. Use the same scene for player and enemy, with an inherited compact variant for enemies.
4. Bind through an exported `NodePath` to the `HealthComponent2D` signals. Remove the group lookup and `call_deferred` binding, then delete `HealthBarStyle.gd` and the duplicate bar script. This is also when you can delete the Phase 4 `health` / `max_health` shims.

**Tests to add:** an enemy outside the detection area ignores the player and chases once inside; a bar’s value follows `health_changed`.

**Done when:** you can resize a detection radius by dragging it in the 2D view, and restyle a health bar without opening a script.

## Phase 9: Multiple attacks and combos (\~1–2 days)

**Goal:** prove the system. Adding attacks should now be content work.

1. `AttackComponent2D.attacks: Array[AttackDefinition2D]`; `try_start(attack_id, direction)`; track a `current_attack`. `Character2D._get_attack_requested()` returns an id (empty for none).
2. Add input actions `attack_light` and `attack_heavy` for the player. For enemies, pick an attack from a simple weighted list on the AI profile.
3. Combos: add `next_attack: AttackDefinition2D` to the definition. The `combo_window_open` / `combo_window_close` events (reserved in Phase 3) set a flag; an attack request during the window starts the next attack immediately, bypassing the cooldown.
4. Proof of success: add `HeavyAttackDefinition.tres` with `HeavySlash2D.tscn` for the player, and a goblin lunge that uses `movement_multiplier`, using **only** the editor. If a script edit is needed, note what was missing and feed it back into the definition.

**Tests to add:** heavy attack selected by id; a combo chains within the window and not outside it; the goblin uses its second attack.

**Done when:** a new attack is one animation clip, one effect scene, one `.tres` and one array entry.

## Risks and how to handle them

- **Method-track paths break when nodes move** (Phases 6 and 7). `CharacterContext2D` already warns about unresolved tracks; treat any warning as a blocker for that phase.
- **Renaming resource fields silently resets saved values.** Prefer adding fields over renaming; if you rename, resave the `.tres` in the editor and check the values.
- **Smoke-test timing.** Tests wait a fixed number of physics frames. Phases 1 and 5 change timing, so update waits deliberately rather than loosening assertions.
- **Initialisation order.** Moving components to nodes (Phase 6) changes when `_ready()` runs. Keep components free of `context` access until `initialize()`.
- **HDR flash values.** The enemy flash clip uses very bright modulate values (about 18.9). Check it visually after Phase 7 rather than assuming it looks the same as the tween.

## Recommended first session

Do Phase 0 and Phase 1 together: they are small, low-risk, and fix the one real bug (cooldown) before you build on top of it.
