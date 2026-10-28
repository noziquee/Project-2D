@tool
extends Node2D
class_name AssistIndicator2D
## The assist view: a blue circle on the ground round the player (how far a light tap looks for a target, the light
## attack's attack_range) and a ring under the enemy the next tap will go for, like a mobile MOBA's range circle and
## target mark. It is a passive drawer: the player tells it what to show every physics frame (show_state) and when to
## stop (clear). It never decides a target and changes nothing in combat; the swing's real hitbox is not drawn.
##
## It is a child of the player. Made from AssistIndicator2D.tscn, which holds its draw order (absolute z -1: below
## every character, above the floor) and its colours.

@export_group("Style")
@export var range_fill := Color(0.25, 0.6, 1.0, 0.10):
	set(value):
		range_fill = value
		queue_redraw()
@export var range_edge := Color(0.4, 0.72, 1.0, 0.7):
	set(value):
		range_edge = value
		queue_redraw()
@export var range_inner := Color(0.4, 0.72, 1.0, 0.25):
	set(value):
		range_inner = value
		queue_redraw()
@export var marker_fill := Color(1.0, 0.3, 0.25, 0.22):
	set(value):
		marker_fill = value
		queue_redraw()
@export var marker_edge := Color(1.0, 0.42, 0.32, 0.95):
	set(value):
		marker_edge = value
		queue_redraw()
## Radius of the ring under the target, in pixels.
@export_range(4.0, 40.0, 0.5) var marker_radius := 15.0:
	set(value):
		marker_radius = value
		queue_redraw()
const ARC_POINTS := 64

var _range := 0.0
var _target: Node2D = null

## Shows the light-attack range circle (0 = none) and the one selected target marker (null = none).
func show_state(range_radius: float, target: Node2D) -> void:
	_range = maxf(range_radius, 0.0)
	_target = target if is_instance_valid(target) else null
	visible = _range > 0.0 or _target != null
	queue_redraw()

func clear() -> void:
	if not visible and _range == 0.0 and _target == null:
		return
	_range = 0.0
	_target = null
	visible = false
	queue_redraw()

func get_range_radius() -> float:
	return _range

func get_target() -> Node2D:
	return _target if is_instance_valid(_target) else null

func _draw() -> void:
	if Engine.is_editor_hint():
		_draw_editor_preview()
		return
	if _range > 0.0:
		draw_circle(Vector2.ZERO, _range, range_fill)
		draw_arc(Vector2.ZERO, _range, 0.0, TAU, ARC_POINTS, range_edge, 2.0, true)
		draw_arc(Vector2.ZERO, maxf(_range - 5.0, 1.0), 0.0, TAU, ARC_POINTS, range_inner, 1.0, true)
	var target := get_target()
	if target != null:
		var at := to_local(target.global_position)
		draw_circle(at, marker_radius, marker_fill)
		draw_arc(at, marker_radius, 0.0, TAU, 32, marker_edge, 2.5, true)

## Editor only: a sample range circle and one target marker, so the colours can be tuned in the Inspector.
func _draw_editor_preview() -> void:
	var radius := 90.0
	draw_circle(Vector2.ZERO, radius, range_fill)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, ARC_POINTS, range_edge, 2.0, true)
	draw_arc(Vector2.ZERO, radius - 5.0, 0.0, TAU, ARC_POINTS, range_inner, 1.0, true)
	var at := Vector2(50, -20)
	draw_circle(at, marker_radius, marker_fill)
	draw_arc(at, marker_radius, 0.0, TAU, 32, marker_edge, 2.5, true)
