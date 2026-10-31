extends Control
class_name ChargeBar
## RD6 step 6: the charge bar. AttackComponent2D owns the charge; this control only observes it. It shows the charge ratio
## (the same one that drives the reach, the stages and the release timing, so there is no second timer), a tick for each
## charge stage, the perfect-release window, and a short flash with the outcome when the charge is released.
## It stays hidden for attacks with no charge_threshold (the ratio never rises there, so a bar would only mislead).

const BAR_HEIGHT := 14.0
const FLASH_TIME := 0.3

## Path relative to this node to the AttackComponent2D being displayed.
@export var attack_source: NodePath
@export_group("Colors")
@export var background_color := Color(0.137255, 0.113725, 0.113725, 0.92)
@export var border_color := Color(0.180392, 0.141176, 0.137255, 1.0)
@export var fill_color := Color(0.96, 0.62, 0.2, 1.0)
@export var stage_color := Color(1.0, 0.85, 0.35, 1.0)
@export var window_color := Color(1.0, 0.9, 0.3, 0.35)
@export var early_color := Color(0.62, 0.62, 0.66, 1.0)
@export var perfect_color := Color(1.0, 0.9, 0.3, 1.0)
@export var late_color := Color(0.9, 0.35, 0.3, 1.0)

var _attack: AttackComponent2D
var _definition: AttackDefinition2D
var _flash_color := Color.WHITE
var _flash_left := 0.0
var _flash_ratio := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(maxf(custom_minimum_size.x, 120.0), BAR_HEIGHT + 4.0)
	visible = false
	if attack_source.is_empty():
		return
	var source := get_node_or_null(attack_source) as AttackComponent2D
	if source == null:
		push_warning("ChargeBar '%s': attack_source does not point to an AttackComponent2D." % name)
		return
	bind(source)

## Starts observing `component`. Called automatically for attack_source.
func bind(component: AttackComponent2D) -> void:
	_unbind()
	_attack = component
	component.charge_released.connect(_on_charge_released)
	component.tree_exiting.connect(_unbind)

func _unbind() -> void:
	if is_instance_valid(_attack):
		if _attack.charge_released.is_connected(_on_charge_released):
			_attack.charge_released.disconnect(_on_charge_released)
		if _attack.tree_exiting.is_connected(_unbind):
			_attack.tree_exiting.disconnect(_unbind)
	_attack = null
	_definition = null
	_flash_left = 0.0
	visible = false

func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
	var charging := is_instance_valid(_attack) and _attack.is_charging()
	if charging:
		_definition = _attack.get_charging_definition()
	var show_bar := (charging and _definition != null and _definition.charge_threshold > 0.0) or _flash_left > 0.0
	if show_bar != visible:
		visible = show_bar
	if visible:
		queue_redraw()

func _on_charge_released(timing: int) -> void:
	if _definition == null or _definition.charge_threshold <= 0.0:
		return
	# A release freezes the state at the ratio the component last reported; the flash keeps it on screen for a moment.
	_flash_ratio = _shown_ratio_now()
	_flash_color = _color_for_timing(timing)
	_flash_left = FLASH_TIME

## The ratio the bar is drawn at: live while charging, the released ratio during the flash, 0 otherwise.
func get_shown_ratio() -> float:
	if is_instance_valid(_attack) and _attack.is_charging():
		return _attack.get_charge_ratio()
	return _flash_ratio if _flash_left > 0.0 else 0.0

func _shown_ratio_now() -> float:
	return _attack.get_charge_ratio() if is_instance_valid(_attack) and _attack.is_charging() else _flash_ratio

## Charge ratios of the stage ticks of the attack in view (empty without stages).
func get_stage_marks() -> Array[float]:
	var marks: Array[float] = []
	if _definition != null:
		for stage in _definition.charge_stages:
			if stage != null:
				marks.append(stage.at_ratio)
	return marks

## The perfect-release window as Vector2(start, end), or Vector2.ZERO when the attack has none.
func get_release_window() -> Vector2:
	if _definition != null and _definition.has_release_window():
		return Vector2(_definition.perfect_window_start, _definition.perfect_window_end)
	return Vector2.ZERO

## The color the fill takes now: the outcome color while a window is set, the plain fill otherwise.
func get_fill_color() -> Color:
	if _flash_left > 0.0 and not (is_instance_valid(_attack) and _attack.is_charging()):
		return _flash_color
	if is_instance_valid(_attack) and _attack.is_charging() and _definition != null and _definition.has_release_window():
		return _color_for_timing(_attack.get_release_timing())
	return fill_color

func _color_for_timing(timing: int) -> Color:
	match timing:
		AttackDefinition2D.ReleaseTiming.EARLY:
			return early_color
		AttackDefinition2D.ReleaseTiming.PERFECT:
			return perfect_color
		AttackDefinition2D.ReleaseTiming.LATE:
			return late_color
	return fill_color

func _draw() -> void:
	var width := size.x
	var bar := Rect2(0.0, 2.0, width, BAR_HEIGHT)
	draw_rect(bar, background_color)
	var window := get_release_window()
	if window.y > window.x:
		draw_rect(Rect2(width * window.x, bar.position.y, width * (window.y - window.x), BAR_HEIGHT), window_color)
	var ratio := clampf(get_shown_ratio(), 0.0, 1.0)
	var inner := bar.grow(-2.0)
	var color := get_fill_color()
	if _flash_left > 0.0 and not (is_instance_valid(_attack) and _attack.is_charging()):
		color.a = _flash_left / FLASH_TIME
	draw_rect(Rect2(inner.position, Vector2(inner.size.x * ratio, inner.size.y)), color)
	for mark in get_stage_marks():
		var x := width * clampf(mark, 0.0, 1.0)
		draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), stage_color, 2.0)
	draw_rect(bar, border_color, false, 2.0)
