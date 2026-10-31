# Aim indicator style options

Status: written October 29, 2026. Suite `1648 / 0` (headless Godot 4.7.2, Linux). Not yet seen in the editor or on a device. Checks H9-125 to H9-140 (part `h8_indicator`).

## What changed

All options are exports on `AimIndicator2D` (Inspector groups in this order). Shapes stay data and geometry only; nothing here changes targeting, hitboxes or damage.

| Option | Group | Default | Effect |
|---|---|---|---|
| `outline_width` | Outline | 2.0 | Thickness of every indicator outline (aim area, arrow head, range circle, placed circle). 0 = none. Pixelated: whole cells, at least one. |
| `rectangle_width_scale`, `arrow_width_scale` | Strip Width | 1.0 / 1.0 | Drawn width of a strip = the shape's `width` x the scale for its style. Range still sets only the length. The arrow head is as long as the drawn strip is wide. |
| `show_range_circle`, `range_fill_color` | Range Circle | on, white 6 % | A circle on the caster with radius = the action's reach, beneath the aim shape. Outline colour is the existing `range_color`. Skipped for a self-circle that already is that circle. A placed circle's cast-range ring is now this circle. |
| `circle_gradient`, `gradient_center_color`, `gradient_edge_color`, `gradient_steps` | Circle Gradient | off | Fills circular shapes (self-circle, placed ground circle) from the centre out. Outline uses `edge_color` and `outline_width`. `gradient_steps` is the number of flat bands when pixelated. Replaceable-art textures win over it. |
| `pixelate`, `pixel_size` | Pixelation | off, 4 | Fills, outlines, the placed-circle guide line and target rings are drawn as square cells. |

`LineAimShape2D` gains `get_outline_at_width` and `get_head_outline_at_width`; `get_outline` and `get_head_outline` call them with the shape's own width, so existing callers and checks are unchanged.

## Decisions taken while writing this (change them if wrong)

- Presentation settings live on the indicator, not on the shapes. A width scale therefore changes the picture only; `contains` and `score` keep the shape's `width`. For a skill that should be wider for targeting too, change `width` on that skill's `LineAimShape2D`.
- The scales are global per style (all arrows, all rectangles), not per skill.
- The range circle is drawn by `AimIndicator2D` (above characters, faint), not on the ground layer under them like the light-attack circle from `AssistIndicator2D`.
- The gradient applies to circular shapes only, not fans or strips. The range circle is a flat fill.
- Target rings keep their own width (2 and 3); they follow `pixelate` but not `outline_width`.

## Try it in the editor

1. FileSystem dock: double-click `Characters/Components/Aim/AimIndicator2D.tscn`.
2. Select the root node `AimIndicator2D`. The 2D view shows a sample range circle, fan, rings and (with the gradient on) a sample circle.
3. Inspector: change values under Outline, Strip Width, Range Circle, Circle Gradient and Pixelation. Save the scene (Ctrl+S); the player builds the indicator from this scene, so saved values are what the game uses.
4. In game: hold a heavy attack (bow or sword) or press and hold an aimed skill to see it.
