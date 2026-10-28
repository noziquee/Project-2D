extends Control
class_name VirtualStick
## H7.6: an on-screen stick. It never reads a device; it presses the four named input actions it is given, with the
## stick's push as their strength, exactly as a keyboard or a controller stick does. Gameplay code reads the actions
## (Input.get_vector) and cannot tell the difference.
##
## One finger at a time: the finger that lands inside the stick owns it until it lifts, wherever it drags. Other
## fingers (a button, the other stick) are ignored, so two thumbs work together.

## The stick's value changed (each drag step and each release). Length is 0 to 1.
signal value_changed(value: Vector2)

@export var action_left: StringName = &"move_left"
@export var action_right: StringName = &"move_right"
@export var action_up: StringName = &"move_up"
@export var action_down: StringName = &"move_down"

## A touch this much outside the circle (a fraction of its radius) still lands on the stick, so a thumb that is a
## little off is not dropped.
const HIT_SLOP := 1.25
@export_group("Visual Style")
@export var base_color := Color(1, 1, 1, 0.16):
	set(value):
		base_color = value
		queue_redraw()
@export var ring_color := Color(1, 1, 1, 0.45):
	set(value):
		ring_color = value
		queue_redraw()
@export var knob_color := Color(1, 1, 1, 0.5):
	set(value):
		knob_color = value
		queue_redraw()
@export_range(0.2, 0.6, 0.01) var knob_radius_ratio := 0.38
@export_range(1.0, 5.0, 0.5) var ring_width := 2.0

## Where the knob is, from -1 to 1 on each axis (length at most 1).
var value := Vector2.ZERO
var _finger := -1
## The actions this stick is holding down right now, so a release lets go of only those (never of a key the player
## is holding on another device).
var _pressed: Dictionary = {}

func _ready() -> void:
	# The stick reads touches itself in _input; it must not also swallow them as a GUI control.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func is_active() -> bool:
	return _finger != -1

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed and _finger == -1 and _contains(touch.position):
			_finger = touch.index
			_move_to(touch.position)
		elif not touch.pressed and touch.index == _finger:
			release()
		return
	var drag := event as InputEventScreenDrag
	if drag != null and drag.index == _finger:
		_move_to(drag.position)

## Lets go: the knob returns to the centre and every action this stick pressed is released.
func release() -> void:
	_finger = -1
	_set_value(Vector2.ZERO)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		release()
	elif what == NOTIFICATION_EXIT_TREE:
		release()

func _center() -> Vector2:
	return get_global_rect().get_center()

func _radius() -> float:
	return minf(size.x, size.y) * 0.5

func _contains(point: Vector2) -> bool:
	return point.distance_to(_center()) <= _radius() * HIT_SLOP

func _move_to(point: Vector2) -> void:
	var radius := _radius()
	if radius <= 0.0:
		return
	_set_value(((point - _center()) / radius).limit_length(1.0))

func _set_value(new_value: Vector2) -> void:
	value = new_value
	_drive(action_left, action_right, value.x)
	_drive(action_up, action_down, value.y)
	queue_redraw()
	value_changed.emit(value)

## Presses the action on the side the stick leans toward (strength = how far) and releases the other.
func _drive(negative: StringName, positive: StringName, axis: float) -> void:
	_hold(negative, maxf(-axis, 0.0))
	_hold(positive, maxf(axis, 0.0))

func _hold(action: StringName, strength: float) -> void:
	if strength > 0.0:
		if InputMap.has_action(action):
			Input.action_press(action, strength)
			_pressed[action] = true
	elif _pressed.has(action):
		Input.action_release(action)
		_pressed.erase(action)

func _draw() -> void:
	var radius := _radius()
	var middle := size * 0.5
	draw_circle(middle, radius, base_color)
	draw_arc(middle, radius, 0.0, TAU, 48, ring_color, ring_width)
	draw_circle(middle + value * radius * 0.55, radius * knob_radius_ratio, knob_color)
