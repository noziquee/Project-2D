@tool
extends Control
class_name TouchActionButton
## H7.6 / H8.8: an on-screen button for one named input action. It never calls combat code: the player reads the same
## action a key or a controller button sets.
##
## Two modes:
## - PRESS: the action is held from touch-down to lift, so a tap is a press and a hold is a hold (the attack button:
##   attack_light charges while held). Also used for dash and weapon swap.
## - AIM_ON_RELEASE: an aimed skill. Nothing is pressed while the finger is down; the lift casts. A tap casts with
##   assistance, a drag aims by hand. A skill with no aim (a buff, a self skill) is asked of `aim_query` at touch-down
##   and behaves like PRESS: tap casts at once, no drag (D16).
##
## Dragging (when `drag_aim` or an aimed skill allows it) presses the existing aim_* actions, so player.gd stays the only
## aim reader: a drag is read exactly like a controller's right stick. The aim is where the finger is, seen from the
## button's centre. It starts only after the finger has moved `drag_threshold` from where it landed and has left a
## small dead zone around the centre, so a tap that wobbles never aims. Back inside the dead zone the manual aim is
## dropped again and the action returns to assistance.

## The drag's aim changed. Direction is a unit vector, or zero when there is none (not dragging, or in the dead zone).
signal aim_changed(direction: Vector2)

## How far out the drag reaches, 0 to 1 of the aim reach, or -1 when there is no manual aim (not dragging, or in the dead
## zone). A ground-circle skill puts its circle that fraction of its cast range away (H8.8). It changes together with
## aim_changed and drops back to -1 at the same moment the aim does.
signal pull_changed(pull: float)

## An aimed skill is waiting for the lift (true, from touch-down) or has stopped waiting (false: it was cast, or the
## touch was cancelled). The skill's aim indicator shows while this is true (H8.9). Never emitted for a PRESS button or
## for a skill with no aim.
signal cast_pending_changed(pending: bool)

enum Mode { PRESS, AIM_ON_RELEASE }

@export var action: StringName = &""
## Short text on the button.
@export var caption := "":
	set(value):
		caption = value
		queue_redraw()
@export var mode: Mode = Mode.PRESS
## A drag from this button aims. Always on for an AIM_ON_RELEASE button that has an aim; off for the rest unless set.
@export var drag_aim := false
## How far the finger must travel from where it landed before a drag counts (base viewport pixels, 1280 x 720).
@export var drag_threshold := 28.0
## Inside this fraction of the aim reach (measured from the button's centre) there is no manual aim.
@export_range(0.0, 0.9, 0.01) var aim_dead_zone := 0.25
## The aim reaches this many button radii from the centre; beyond that the direction no longer changes.
@export var aim_reach := 2.0

## AIM_ON_RELEASE only: returns true when the button's skill has an aim. Empty or invalid means it does.
var aim_query: Callable = Callable()

const HIT_SLOP := 1.1
## Physics frames an action stays pressed on a lift, and the aim after it, so the player's own per-frame read sees them.
const CAST_HOLD_FRAMES := 3
const AIM_ACTIONS := {
	&"left": &"aim_left", &"right": &"aim_right", &"up": &"aim_up", &"down": &"aim_down",
}
@export_group("Visual Style")
@export var idle_color := Color(1, 1, 1, 0.18):
	set(value):
		idle_color = value
		queue_redraw()
@export var held_color := Color(1, 1, 1, 0.42):
	set(value):
		held_color = value
		queue_redraw()
@export var ring_color := Color(1, 1, 1, 0.5):
	set(value):
		ring_color = value
		queue_redraw()
@export var text_color := Color(1, 1, 1, 0.85):
	set(value):
		text_color = value
		queue_redraw()
@export var aim_color := Color(1, 1, 1, 0.8):
	set(value):
		aim_color = value
		queue_redraw()
@export_range(0.1, 0.8, 0.01) var aim_dot_radius_ratio := 0.22
@export_range(0.3, 0.8, 0.01) var aim_dot_offset_ratio := 0.6
@export_range(0.3, 0.8, 0.01) var caption_size_ratio := 0.5
@export_range(1.0, 5.0, 0.5) var outline_width := 2.0

var _finger := -1
var _down_position := Vector2.ZERO
## This button has pressed its action (and has not released it yet).
var _holding := false
## The finger has passed the drag threshold: aim is being read from it.
var _dragging := false
## This touch is an AIM_ON_RELEASE touch with an aim (the cast waits for the lift).
var _casts_on_release := false
## The unit aim sent as aim_* right now, or zero.
var _aim := Vector2.ZERO
## How far out the drag reaches (0 to 1), or -1 with no manual aim.
var _pull := -1.0
var _aim_pressed: Dictionary = {}
## Bumped by every new touch and every forced release, so a pending delayed release can tell it is out of date.
var _generation := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func is_held() -> bool:
	return _finger != -1

## True while a drag is aiming (past the threshold; it may be inside the dead zone, see get_aim).
func is_dragging() -> bool:
	return _dragging

## The unit aim the drag is giving right now, or zero.
func get_aim() -> Vector2:
	return _aim

## How far out the drag reaches, 0 to 1 of the aim reach, or -1 with no manual aim.
func get_pull() -> float:
	return _pull

## True when this touch will cast on the lift instead of on touch-down (an aimed skill).
func casts_on_release() -> bool:
	return _casts_on_release

func _input(event: InputEvent) -> void:
	# This script is @tool so the button draws in the scene editor; it must never react to the editor's own input.
	if Engine.is_editor_hint() or not is_visible_in_tree():
		return
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed and _finger == -1 and _contains(touch.position):
			_begin(touch)
		elif not touch.pressed and touch.index == _finger:
			_lift()
		return
	var drag := event as InputEventScreenDrag
	if drag != null and drag.index == _finger and _can_drag():
		_drag_to(drag.position)

func _begin(touch: InputEventScreenTouch) -> void:
	_generation += 1
	_finger = touch.index
	_down_position = touch.position
	_dragging = false
	_set_aim(Vector2.ZERO)
	_casts_on_release = mode == Mode.AIM_ON_RELEASE and (not aim_query.is_valid() or bool(aim_query.call()))
	if not _casts_on_release:
		_set_held(true)
	else:
		cast_pending_changed.emit(true)
	queue_redraw()

## The finger lifted. The action is let go now (an attack) or pressed now (an aimed skill's cast), and the aim stays down
## for a few physics frames longer, so the player still reads the drag when it starts or releases the action.
func _lift() -> void:
	var generation := _generation
	_finger = -1
	if _casts_on_release:
		_casts_on_release = false
		cast_pending_changed.emit(false)
		_set_held(true)
		_finish_cast_later(generation)
	else:
		_set_held(false)
		_release_aim_later(generation, CAST_HOLD_FRAMES)
	_dragging = false
	queue_redraw()

func _finish_cast_later(generation: int) -> void:
	await _wait_physics_frames(CAST_HOLD_FRAMES)
	if generation != _generation:
		return
	_set_held(false)
	await _wait_physics_frames(1)
	if generation != _generation:
		return
	_set_aim(Vector2.ZERO)

func _release_aim_later(generation: int, frames: int) -> void:
	await _wait_physics_frames(frames)
	if generation != _generation:
		return
	_set_aim(Vector2.ZERO)

func _wait_physics_frames(frames: int) -> void:
	for i in frames:
		if not is_inside_tree():
			return
		await get_tree().physics_frame

## Lets go of everything at once (the buttons were hidden or removed while held). Not delayed.
func release() -> void:
	_generation += 1
	_finger = -1
	_dragging = false
	if _casts_on_release:
		_casts_on_release = false
		cast_pending_changed.emit(false)
	_set_held(false)
	_set_aim(Vector2.ZERO)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		release()
	elif what == NOTIFICATION_EXIT_TREE:
		release()

func _can_drag() -> bool:
	return drag_aim or _casts_on_release

func _radius() -> float:
	return minf(size.x, size.y) * 0.5

func _center() -> Vector2:
	return get_global_rect().get_center()

func _contains(point: Vector2) -> bool:
	return point.distance_to(_center()) <= _radius() * HIT_SLOP

func _drag_to(point: Vector2) -> void:
	if not _dragging:
		if point.distance_to(_down_position) < drag_threshold:
			return
		_dragging = true
	var offset := point - _center()
	var reach := _radius() * aim_reach
	if reach <= 0.0 or offset.length() < reach * aim_dead_zone:
		_set_aim(Vector2.ZERO)
	else:
		_set_aim(offset.normalized(), clampf(offset.length() / reach, 0.0, 1.0))
	queue_redraw()

## Sends `direction` (a unit vector or zero) as the four aim actions, the way a stick pushed that way would. `pull` is how
## far out the finger is (0 to 1); it is only meaningful with a direction, and is -1 without one.
func _set_aim(direction: Vector2, pull: float = 1.0) -> void:
	var new_pull := pull if direction != Vector2.ZERO else -1.0
	var aim_same := direction == _aim and (direction != Vector2.ZERO or _aim_pressed.is_empty())
	if aim_same and is_equal_approx(new_pull, _pull):
		return
	var pull_moved := not is_equal_approx(new_pull, _pull)
	_pull = new_pull
	if aim_same:
		# Only how far out the finger is has changed: the direction (and so the aim actions) stay as they are.
		pull_changed.emit(_pull)
		return
	_aim = direction
	_hold_aim(&"left", maxf(-direction.x, 0.0))
	_hold_aim(&"right", maxf(direction.x, 0.0))
	_hold_aim(&"up", maxf(-direction.y, 0.0))
	_hold_aim(&"down", maxf(direction.y, 0.0))
	queue_redraw()
	if pull_moved:
		pull_changed.emit(_pull)
	aim_changed.emit(direction)

func _hold_aim(side: StringName, strength: float) -> void:
	var aim_action: StringName = AIM_ACTIONS[side]
	if strength > 0.0:
		if InputMap.has_action(aim_action):
			Input.action_press(aim_action, strength)
			_aim_pressed[aim_action] = true
	elif _aim_pressed.has(aim_action):
		Input.action_release(aim_action)
		_aim_pressed.erase(aim_action)

func _set_held(held: bool) -> void:
	if held and not _holding and InputMap.has_action(action):
		Input.action_press(action)
		_holding = true
	elif not held and _holding:
		Input.action_release(action)
		_holding = false
	queue_redraw()

func _draw() -> void:
	var radius := _radius()
	var middle := size * 0.5
	draw_circle(middle, radius, held_color if is_held() else idle_color)
	draw_arc(middle, radius, 0.0, TAU, 48, ring_color, outline_width)
	if _aim != Vector2.ZERO:
		draw_circle(middle + _aim * radius * aim_dot_offset_ratio, radius * aim_dot_radius_ratio, aim_color)
	if caption != "":
		var font := get_theme_default_font()
		var font_size := maxi(int(radius * caption_size_ratio), 10)
		var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, Vector2(middle.x - text_size.x * 0.5, middle.y + font.get_ascent(font_size) * 0.5 - 2.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
