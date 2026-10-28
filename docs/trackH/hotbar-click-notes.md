# Hotbar: clickable skill slots with a toggle (October 28, 2026)

Status: written, not yet run (checks H7-18 to H7-27). Needs a play in the editor with a mouse.

## What it does

- A **left click on a skill slot** casts that slot's skill, the same request its key makes. `SkillComponent2D` still decides about cost, cooldown and refusal, so a refused click plays the slot's "denied" shake like a refused key.
- **Click-to-cast can be switched off and on** with the `H` key (action `toggle_click_cast`, change it in Input Map) or from code with `SkillBar.set_click_to_cast(bool)`; `SkillBar.click_to_cast` is an Inspector option for the starting state. When it is off, a click on a slot does nothing, and the number keys and controller buttons still cast. The cursor over a slot is a pointing hand when clicking casts and an arrow when it does not.
- A click on a slot **no longer also swings the weapon**, and while the cursor is over the hotbar the player **keeps its last aim** (otherwise a skill clicked on the hotbar would fire toward the hotbar).

## Files

`UI/HUD/SkillSlot.gd` and `SkillSlot.tscn` (the slot takes the click and reports it as `clicked`; everything inside it ignores the mouse; the slot is in the group `hud_pointer_block`), `UI/HUD/SkillBar.gd` (connects the slots, the toggle, `click_to_cast_changed`), `player.gd` (`_pointer_over_hud()`, the attack and aim guard), `project.godot` (action `toggle_click_cast`).

## Assumption

I read "can be toggled on and off" as the click-to-cast feature. If you meant that each skill can be switched off (disabled) from the hotbar, tell me and I will change it.

## Manual checks

Click each slot (casts, shows the cooldown wipe, no sword swing); click a refused skill (shake); press `H`, click (nothing), press a number key (casts); aim at an enemy, move the mouse down to the hotbar and click: the skill still goes toward the enemy.

## Notes

`gui_get_hovered_control()` returns nothing in a headless run, so the click-does-not-attack and aim-lock paths cannot be exercised by the automated suite; they are manual checks above. The on-screen skill buttons of H7.6 can reuse these slots.
