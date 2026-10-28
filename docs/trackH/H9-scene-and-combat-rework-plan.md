# H9: scene-driven visuals and combat rework (plan)

Written October 28, 2026. Nothing here has been run in the editor or the suite yet; every "delivered" item below is written and awaiting your run.

Source: the "code-driven elements that should become scenes" review, plus the five targets you set on October 28 (camera-view assist, real light-attack range, aim areas, auto-approach, replaceable HUD visuals).

**Rule that runs through all of it:** scenes own composition and presentation; code owns gameplay rules. Damage, target selection, movement, cooldowns, charge timing, state transitions, status stacks and passive triggers stay in code.

## 1. Targets

| # | Target |
|---|---|
| T1 | Assist range uses the camera view, not the weapon's range. Every visible damageable enemy or object that can be targeted shows an indicator. |
| T2 | The blue circle is the real light-attack range of the equipped weapon and updates when the weapon changes. |
| T3 | The circle stays visible while a heavy attack or skill is aimed. Each heavy attack and skill has its own configurable aim area, clipped to its own range circle (Mobile Legends style). Light attacks, heavy attacks and skills each use their own range, never one shared radius. |
| T4 | Attacking a target out of range moves toward it until in range, then attacks. Movement input cancels the approach at once and it does not resume until the next attack input. In range: face the target. Out of range: face the movement direction. |
| T5 | Every HUD visual is a replaceable placeholder, separate from gameplay logic: buttons, joystick, bars, skill icons and cooldowns, target marker, range and aim indicators, layout. |

Camera visibility is not permission to attack. A target can be visible and selected and still be out of the current attack's range.

## 2. Decisions on record (October 28, 2026, all as recommended)

| # | Decision |
|---|---|
| D18 | Merge `assist_range` and `ai_attack_range` into one `attack_range` per attack. It feeds the circle, the in-range check for auto-approach and the AI. |
| D19 | The sword's light `attack_range` is 70 (the real hitbox reach), not 96 (assist) or 60 (AI). |
| D20 | Camera-view targeting: the selected target gets the strong marker; other visible targets get a lighter one (can be switched off). |
| D21 | Keep the code fallback layout in `MobileControls` until the scene has been checked at the target resolutions, then drop it. |
| D22 | `effect_animation` on area and projectile effects is hidden from the Inspector; the H3.3 warning stays for old data. |

## 3. Delivered (written, not yet run)

Apply in this order. The `player.gd`, `smoke_checks.gd` and `h8_aim_checks.gd` in each zip are cumulative.

| Zip | What it does | Checks |
|---|---|---|
| `P1-aim-indicator-scenes` | `AimIndicator2D.tscn` and `AssistIndicator2D.tscn` hold z-order; colours and radii are `@export` properties; `player.gd` instantiates the scenes. | H8-239 to H8-242 |
| `P1b-indicator-editor-preview` | `@tool` sample drawing so the indicators show in the editor; style setters redraw. | none |
| `P2a-move-stick-in-scene` | `MoveStick` is a real `VirtualStick` in `MobileControls.tscn`; the runtime swap is removed. | H8-218 reworded |
| `P3a-keep-range-circle` | The blue circle stays visible while a heavy attack or skill is aimed; only the light marker is dropped then. | H8-243, H8-244 |
| `H9.1-attack-range` (H9.1a and H9.1b) | One `attack_range` per attack replaces `assist_range` and `ai_attack_range` (D18). Sword slashes 70 (D19), bow shot 240, enemy arrow 170, goblin lunge 75. `player.gd` and the AI read it. The circle already follows the equipped weapon. | H8-89 reworded, H8-245 to H8-247 |

Expected suite total: your last recorded total plus 6 new checks. Paste the `SUMMARY` line and date into `docs/STATUS.md` after the run.

## 4. Build order

**H9.1 Single attack range (T2, D18, D19).** Written: the field and the data migration (H9.1a) and the weapon-swap checks H8-245 to H8-247 (H9.1b). The planned warning for "`attack_range` differs a lot from the real hitbox reach" is dropped: the reach lives in the slash's position keyframes, and H9.2 removes those and moves the slash to `attack_range`, so the two can no longer disagree. Until H9.2 lands the sword's 70 is a hand-checked number.

**H9.2 Slash rework (needs H9.1).** Root cause: the slash's reach lives in animation keyframes (`slash`: hitbox x 8 to 62, sprite 0 to 56; `heavy_slash`: hitbox 8 to 80, sprite 0 to 70), so no code can read it, and one swing has three different numbers (about 70 real, 96 assist, 60 AI).
- Remove the two position tracks from each clip: the sprite's `.:position` and `HitboxMotion:position`. Keep frame, scale, modulate and `disabled` (the hit window).
- `AttackSlash2D` moves the sprite and hitbox along x in code, from the start offset until the hitbox's leading edge reaches `attack_range` (half-width and scale included). Progress comes from the animation time up to the end of the hit window, so timing stays authored in the clip.
- It stays an `AttackSlash2D`, not a new projectile class (the slash has a timed hit window, hits each target once and does not stop on contact). `configure()` gains one parameter.
- Editor steps for the tracks: open `AttackSlash2D.tscn`, select `SlashEffectAnimSpritesheet/AnimationPlayer`, pick the `slash` clip, right-click each position track, Remove Track; repeat for `heavy_slash`.

**H9.3 Camera-view targeting (T1, D20).** A design change: eligible targets become damageable, alive, enemy-team nodes inside the camera rectangle, and range no longer decides who can be targeted. This touches `TargetingService2D`, the H8 checks and the H8 rule that a target must be inside the action's shape; record the change in `docs/STATUS.md`. The aim still scores candidates; the marker follows D20.

**H9.4 Interruptible auto-approach (T4).** First audit `MovementComponent2D`, `FacingComponent2D` and the states so it builds on them and adds no second movement controller.
- Attack input uses the selected target or acquires one. In range (including target size): face it and attack. Out of range: move toward it, facing the movement direction.
- Range and target validity are rechecked at the moment of attack, not when the button was pressed.
- Manual movement cancels the approach immediately; it does not resume until the next attack input.
- Tests: cancel, no auto-resume, target dies, weapon swap during the approach, cooldowns and costs.

**H9.5 Aim areas clipped to their own circle (T3).** Implemented in source, awaiting Godot verification. `AimIndicator2D` clips aimed polygons with `Geometry2D.intersect_polygons` against a circle whose radius is that action's own `aim_shape.max_range`; line/arrow overflow is constrained. Ground-circle placement remains centred on its selected point. The light-attack range circle stays visible. Checks H9-55 to H9-61 were added; run with the full H9 suite after the remaining steps.

**H9.6 Replaceable art (T5).** Implemented in source, awaiting Godot verification.
- `AimIndicator2D`: optional `ring_texture`, `area_texture`, and `fan_texture`; empty slots retain vector art. Assigned textures are tinted by the existing candidate/picked/fill colours, and aim texture polygons remain clipped to the action's reach. `texture_scale` controls UV coverage. For best results, use square white/grey PNGs with transparency; centre circles and rings, and author fan art pointing right.
- Touch controls: `TouchActionButton`, `VirtualStick`, and `TouchSkillFace` expose their primary colours and visual proportions in the Inspector instead of relying on script constants.
- HUD bars: health/mana icon text, title text, and accent colours are exported; bar fills, panels, fonts, and skill-slot panels were already shared `.tres` resources. Mobile control placement remains scene-authored, not rewritten in code. Target/candidate rings keep vector fallback when no `ring_texture` is assigned.
- No Godot import, smoke test, or editor/play test was run; the user requested testing only after all H9 work is complete.

**H9.7 Remaining review items.**
- Priority 2: `TouchSkillFace` becomes a scene child of each skill button; drop the code fallback layout once D21 is satisfied (this removes `_build_layout_in_code`, `_placements`, the size exports and checks H8-219 to H8-222).
- Priority 5: one test that loads every effect scene and asserts it has no problems.
- D22: hide `effect_animation` for area and projectile effects.
- Verify with a shipped skill that names a `weapon_animation` clip (STATUS notes none does yet); finish the rig child-name fallbacks beyond P2; set `AttackSpawnPoint` markers by hand on weapon-bearing characters.
- Deferred until needed: Priority 3 (area-effect visual scene, only if per-skill looks are wanted) and Priority 4 (`ReactionProfile.tres`; `ReactionComponent2D` already exports what is needed).

**H9.8 Regression.** Run the suite (`tools/run_checks.sh`) after every sub-step, then check weapon switching, target selection, attack recovery, skill costs and cooldowns, and manual interruption. Update `docs/STATUS.md` and add notes under `docs/trackH`. Then the play-test, which has never been done in the editor.

## 5. Risks
- Nothing is run yet; the first suite run after the four zips shows whether any check needs adjusting.
- The project's git state has unmerged entries (`README.md`, `BasicEnemy2D.tscn`, `smoke_checks.gd` and two docs). Resolve them before committing.
- H9.1 and H9.3 touch many data files and tests at once; deliver each in small sub-steps with a suite run between them.
