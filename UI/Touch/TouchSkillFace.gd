extends Control
class_name TouchSkillFace
## H8.8d: what a touch skill button shows. It is a child of one skill TouchActionButton (skill_1 to skill_3) and takes the
## place of the hotbar slot on touch: the skill's icon, the cooldown sweep and seconds, the cast progress, the resource
## cost, and a dimmed icon when the skill cannot be afforded. It only draws; it never presses anything and it never takes
## a touch (the button under it reads the finger). SkillComponent2D stays the authority for cost, cooldown and casts, as
## it is for the hotbar's SkillSlot, which this mirrors.
##
## MobileControls.tscn authors one under each shipped skill button; MobileControls still creates one for code-built layouts.

@export_group("Visual Style")
@export var sweep_color := Color(0.05, 0.06, 0.08, 0.7)
@export var cast_color := Color(0.22, 0.62, 1.0, 0.9)
@export var text_color := Color(1, 1, 1, 1)
@export var text_outline_color := Color(0.055, 0.055, 0.07, 1)
@export var cost_color := Color(0.35, 0.72, 1.0, 1)
@export var unaffordable_cost_color := Color(1.0, 0.38, 0.32, 1)
@export var unaffordable_icon_tint := Color(0.48, 0.49, 0.53, 1)
@export var ready_flash_color := Color(0.56, 0.94, 0.67, 1)
@export_range(0.1, 1.0, 0.05) var flash_duration := 0.3
@export_range(16, 96, 4) var arc_points := 48
@export_range(0.1, 0.9, 0.01) var icon_size_ratio := 0.69
@export_range(0.3, 0.8, 0.01) var overlay_text_radius_ratio := 0.62
@export_range(0.2, 0.5, 0.01) var cost_text_radius_ratio := 0.3

var slot := 0

var _button: TouchActionButton
var _skill_component: SkillComponent2D
var _skill: SkillDefinition2D
var _default_caption := ""
var _flash := 0.0
var _last_cooldown_active := false

## Bound to `slot` of the player's SkillComponent2D. Safe to call again (the skills changed, or a new component).
func bind(button: TouchActionButton, skill_component: SkillComponent2D, slot_index: int) -> void:
	_unbind()
	_button = button
	slot = slot_index
	_default_caption = button.caption if _default_caption == "" else _default_caption
	_skill_component = skill_component
	if is_instance_valid(_skill_component) and not _skill_component.skills_changed.is_connected(_refresh_skill):
		_skill_component.skills_changed.connect(_refresh_skill)
	_refresh_skill()

func get_bound_skill() -> SkillDefinition2D:
	return _skill

func is_unaffordable() -> bool:
	return _is_unaffordable()

## 0 to 1: how much of the cooldown is left (0 when ready).
func get_cooldown_fraction() -> float:
	if _skill == null or not is_instance_valid(_skill_component):
		return 0.0
	var duration := _skill_component.get_cooldown_duration(_skill.id)
	var remaining := _skill_component.get_cooldown_remaining(_skill.id)
	return clampf(remaining / duration, 0.0, 1.0) if remaining > 0.0 and duration > 0.0 else 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

func _exit_tree() -> void:
	_unbind()

func _unbind() -> void:
	if is_instance_valid(_skill_component) and _skill_component.skills_changed.is_connected(_refresh_skill):
		_skill_component.skills_changed.disconnect(_refresh_skill)
	_skill_component = null

func _refresh_skill() -> void:
	_skill = _skill_component.get_skill_in_slot(slot) if is_instance_valid(_skill_component) else null
	# With a skill bound the icon is the label; an empty slot keeps the number the button had.
	if is_instance_valid(_button):
		_button.caption = "" if _skill != null else _default_caption
	_last_cooldown_active = false
	queue_redraw()

func _process(delta: float) -> void:
	if _skill == null or not is_instance_valid(_skill_component):
		return
	var cooling := get_cooldown_fraction() > 0.0
	if _last_cooldown_active and not cooling:
		_flash = flash_duration
	_last_cooldown_active = cooling
	_flash = maxf(_flash - delta, 0.0)
	queue_redraw()

func _is_unaffordable() -> bool:
	if _skill == null or not is_instance_valid(_skill_component):
		return false
	var reason := _skill_component.can_use(_skill.id)
	return reason.begins_with("not enough mana") or reason.begins_with("the character has no mana pool")

func _draw() -> void:
	if _skill == null or not is_instance_valid(_skill_component):
		return
	var radius := minf(size.x, size.y) * 0.5
	var middle := size * 0.5
	var unaffordable := _is_unaffordable()

	# The icon, in a square that sits inside the button's circle.
	if _skill.icon != null:
		var side := radius * (icon_size_ratio * 2.0)
		var tint := unaffordable_icon_tint if unaffordable else Color.WHITE
		draw_texture_rect(_skill.icon, Rect2(middle - Vector2(side, side) * 0.5, Vector2(side, side)), false, tint)

	# Cooldown: the part of the circle still to wait is shaded, with the seconds on top.
	var remaining := _skill_component.get_cooldown_remaining(_skill.id)
	var fraction := get_cooldown_fraction()
	if fraction > 0.0:
		_draw_sweep(middle, radius - 2.0, fraction, sweep_color)
		_draw_text(_format_seconds(remaining), middle, int(radius * overlay_text_radius_ratio), text_color)

	# Casting: a blue ring fills round the button, with the cast seconds left.
	var casting := _skill_component.get_casting_skill()
	if casting != null and casting.id == _skill.id:
		var progress := clampf(_skill_component.get_cast_progress(), 0.0, 1.0)
		draw_arc(middle, radius - 3.0, -PI * 0.5, -PI * 0.5 + TAU * progress, arc_points, cast_color, 5.0)
		_draw_text(_format_seconds(_skill_component.get_cast_remaining()), middle, int(radius * overlay_text_radius_ratio), text_color)

	# Ready again: a short green ring.
	if _flash > 0.0:
		var flash_color := ready_flash_color
		flash_color.a = _flash / flash_duration
		draw_arc(middle, radius - 2.0, 0.0, TAU, arc_points, flash_color, 4.0)

	# The cost, under the icon.
	if _skill.cost_resource != SkillDefinition2D.CostResource.NONE and _skill.cost_amount > 0.0:
		var cost_size := maxi(int(radius * cost_text_radius_ratio), 10)
		_draw_text("◆ " + _format_cost(_skill.cost_amount), Vector2(middle.x, middle.y + radius * 0.66), cost_size, unaffordable_cost_color if unaffordable else cost_color)

## Shades `fraction` of the circle, starting at the top and running clockwise.
func _draw_sweep(center: Vector2, radius: float, fraction: float, color: Color) -> void:
	var start := -PI * 0.5
	var end := start + TAU * fraction
	var points := PackedVector2Array([center])
	var steps := maxi(int(arc_points * fraction), 2)
	for i in range(steps + 1):
		var angle := lerpf(start, end, float(i) / float(steps))
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)

## Centred text with an outline so it reads on any icon.
func _draw_text(text: String, center: Vector2, font_size: int, color: Color) -> void:
	var font := get_theme_default_font()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var origin := Vector2(center.x - text_size.x * 0.5, center.y + font.get_ascent(font_size) * 0.5 - 2.0)
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(font_size / 4, 2), text_outline_color)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _format_seconds(seconds: float) -> String:
	if seconds < 10.0:
		return "%.1f" % maxf(seconds, 0.0)
	return "%d" % ceili(seconds)

func _format_cost(amount: float) -> String:
	if is_equal_approx(amount, roundf(amount)):
		return "%d" % roundi(amount)
	return "%.1f" % amount
