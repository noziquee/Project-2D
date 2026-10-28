# H8: Assisted aiming and touch combat controls (plan, October 28, 2026)

Status: **plan only, nothing implemented. Awaiting your review.**
Source: `Godot_Mobile_Controls_and_Aim_Assist_Design.pdf`, plus your decisions of October 28.
This supersedes D11 (touch aim is a right virtual stick) and the aim stick built in H7.6.

## Decisions to record (proposed D13 to D17)

| # | Decision |
|---|---|
| D13 | No standalone aim stick on touch. D11 is superseded. |
| D14 | Light attack = a tap on the attack button. Aimed by assist only (no drag, no shape). |
| D15 | Heavy attack = hold the attack button; drag from it to aim, like a skill. Hold without drag: assist inside the heavy attack's aim shape, else last aim. |
| D16 | Aim shapes apply to heavy attacks and damage skills only. Buff skills have none: tap casts, no indicator, no drag. |
| D17 | Aim shapes vary (fan, line, arrow, circle on self, ground circle), Mobile Legends as the reference. A shape guides aiming and targeting only; the real hitbox and damage rules do not change. |

## Rules (from the PDF)

- Eligible target: alive, damageable, in range, valid for the action. Only registered damageables; no scenery.
- Score: closeness to the intended direction first, distance second.
- Stability: choose once at activation (tap, or charge release); do not re-pick every frame. Re-pick only if the target dies, leaves range or becomes invalid.
- Fallback: no target -> `last_aim_direction` -> last non-zero facing.
- Manual aim (drag) overrides assist for that one action only; the next action returns to assist.
- Keyboard/mouse and controller use the same targeting service. Mouse and right stick stay the aim input there (H7.4 unchanged).

## Steps

| Step | Work | Size | Done when |
|---|---|---|---|
| H8.1 | Audit (read-only): how damageables are found today (`Hurtbox2D`, hit layers), where `context.aim_direction` is consumed (`AttackComponent2D`, `SkillComponent2D`, projectile direction), heavy-charge aim update while charging. Write findings to `H8.1-notes.md`. | S | Notes list every aim read and the hook point. |
| H8.2 | `AimShape2D` base resource (`contains`, `score`, `max_range`, indicator kind) plus Fan, Line (also used for arrow) and CircleSelf. Ground circle is declared but deferred to H8.8. Smoke checks for each shape. | M | Shape checks green; no gameplay change. |
| H8.3 | `TargetingService2D`: collect candidates, filter, score, sticky choice, fallback. Takes origin, direction, range and an optional shape. Smoke checks: behind the player, several enemies, a damageable object, scenery ignored, target dies, no target. | M | Checks green; nothing calls it yet. |
| H8.4 | Persistent aim state (`last_aim_direction`, last facing) and a per-action manual override. `player.gd::_get_aim_direction()` gains the assist step; stick and mouse rules unchanged on desktop and controller. | M | Desktop and controller behave as before; no-target attack goes to a predictable direction. |
| H8.5 | Light-attack assist: one project-wide arc (about 120 degrees in front, an export), sword first, then bow. | S | Light tap hits the best nearby target; sword arc and hitbox unchanged. |
| H8.6 | `aim_shape` export on heavy attack and `SkillDefinition2D`. Empty = no aim. Validation (range and cross-field rules) and the section 6 definition-of-done checks. Assign shapes to the shipped skills (buffs none). | M | Every damage skill and heavy attack has a shape or a stated reason not to. |
| H8.7 | Heavy attack and skill assist: pick direction/target at charge release or cast; no retargeting mid-animation. Bow heavy accepts aim changes while charging within the shape. | M | Heavy and skill aim use shapes; cooldown, mana and combo rules intact. |
| H8.8 | Touch controls: drag-capable `TouchActionButton` (tap, hold, drag with a drag threshold and its own dead zone); remove the aim stick from `MobileControls`; new right-side layout (large attack button, dodge/swap and 3 skill buttons around it). Drag presses the existing `aim_*` actions, so `player.gd` stays the only aim reader. Ground-circle drag-to-place for skills that need it. | L | Tap = light; hold = charge; hold+drag = aimed heavy; skill tap = assist; skill drag = manual; no accidental heavy from a drag. |
| H8.9 | Aim indicators drawn from the same shape resource (fan, line, arrow, circle, ground circle). Optional highlight of enemies inside the shape (open question). | M | Indicator matches what assist uses. |
| H8.10 | Tests and docs: touch actions reach the same gameplay methods; aim priority; drag vs hold timing; buff skills show no indicator; device matrix (section 5b); STATUS and roadmap updated, D11 marked superseded. | M | Checks in the suite and green; matrix filled in. |

Order: H8.1 to H8.4 can start now and change no gameplay. H8.8 is the riskiest step; build it only after H8.7 is play-tested with mouse and controller.

## Risks

- A drag read as a hold fires an accidental heavy attack: needs a drag threshold, tested on a real phone.
- Assist that ignores player intent feels wrong: keep arcs modest and keep manual override absolute.
- `emulate_mouse_from_touch` stays off (H7.6), so the hotbar stays display-only on touch.
- Shapes must not drift from the real hitboxes: shape = aim guide, hitbox = unchanged.

## Open questions

1. Light-attack arc: one project-wide value (proposed) or per weapon?
2. Highlight enemies inside the aim shape, or a plain indicator?
3. Keep the aim stick behind an option during play-testing, or remove it at H8.8? (Proposed: remove, per D13.)
