extends Node2D
class_name EnemyAttackTelegraph2D
## Red ground lane shown before an enemy attack starts (wind-up warning). EnemyAIController2D owns it: it calls show_lane()
## when the wind-up begins, keeps the direction up to date, and hide_lane() when the attack starts or the wind-up is
## cancelled. It draws nothing else and never touches combat.
##
## The lane is a generic forward rectangle: `length` is the chosen attack's effective range, `width` its hitbox_size.y.
## It starts at this node's origin (the enemy's position) and points along `direction`.

const MIN_WIDTH := 4.0
const FILL_COLOR := Color(1.0, 0.1, 0.1, 0.28)
const EDGE_COLOR := Color(1.0, 0.2, 0.2, 0.75)

var _direction := Vector2.RIGHT
var _length := 0.0
var _width := 0.0
var _polygon := PackedVector2Array() # a warning shape (DE3), as offsets from this node; empty when the lane is shown

func _ready() -> void:
	z_index = -1 # under the enemy's sprite
	visible = false

## Shows (or updates) the lane.
func show_lane(direction: Vector2, length: float, width: float) -> void:
	_direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	_length = maxf(length, 0.0)
	_width = maxf(width, MIN_WIDTH)
	visible = _length > 0.0
	queue_redraw()

## Shows a warning shape (an enemy skill's fan, circle or line) given as a closed polygon of offsets from the enemy.
func show_shape(points: PackedVector2Array) -> void:
	_polygon = points
	_length = 0.0
	visible = points.size() >= 3
	queue_redraw()

func get_shape_points() -> PackedVector2Array:
	return _polygon

func hide_lane() -> void:
	visible = false
	_length = 0.0
	_polygon = PackedVector2Array()
	queue_redraw()

func is_lane_visible() -> bool:
	return visible

func get_lane_direction() -> Vector2:
	return _direction

func get_lane_length() -> float:
	return _length

func get_lane_width() -> float:
	return _width

func _draw() -> void:
	if _polygon.size() >= 3:
		draw_colored_polygon(_polygon, FILL_COLOR)
		var closed := _polygon.duplicate()
		closed.append(_polygon[0])
		draw_polyline(closed, EDGE_COLOR, 1.0)
		return
	if _length <= 0.0:
		return
	draw_set_transform(Vector2.ZERO, _direction.angle(), Vector2.ONE)
	var rect := Rect2(Vector2(0.0, -_width * 0.5), Vector2(_length, _width))
	draw_rect(rect, FILL_COLOR, true)
	draw_rect(rect, EDGE_COLOR, false, 1.0)
