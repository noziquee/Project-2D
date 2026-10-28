extends AimShape2D
class_name LineAimShape2D
## A strip along the aim (lunges, dashes, arrows and other projectiles). `max_range` is its length.

## How the indicator draws it (H8.9). The targeting is the same for both.
enum Style { RECTANGLE, ARROW }

## Full width of the strip, in pixels.
@export_range(1.0, 500.0, 1.0) var width: float = 24.0
@export var style: Style = Style.RECTANGLE

func get_kind() -> Kind:
	return Kind.LINE

## The strip: four corners, the same region `contains` tests, for both styles (H8.9). It starts at the caster and runs
## `max_range` along the aim.
func get_outline(direction: Vector2) -> PackedVector2Array:
	var outline := PackedVector2Array()
	if max_range <= 0.0 or width <= 0.0:
		return outline
	var axis := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	var side := axis.orthogonal() * width * 0.5
	var far := axis * max_range
	outline.append_array(PackedVector2Array([-side, side, far + side, far - side]))
	return outline

## The ARROW style's head: a triangle that points along the aim and sits inside the strip at its far end. Empty for the
## RECTANGLE style. Decoration only; the targeting still uses the whole strip.
func get_head_outline(direction: Vector2) -> PackedVector2Array:
	var head := PackedVector2Array()
	if style != Style.ARROW or max_range <= 0.0 or width <= 0.0:
		return head
	var axis := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	var side := axis.orthogonal() * width * 0.5
	var length := minf(width, max_range)
	head.append_array(PackedVector2Array([axis * max_range, axis * (max_range - length) + side, axis * (max_range - length) - side]))
	return head

func validate() -> PackedStringArray:
	var problems := super.validate()
	if width <= 0.0:
		problems.append("width must be above 0")
	return problems

func _alignment(origin: Vector2, direction: Vector2, point: Vector2, margin: float) -> float:
	if direction.length_squared() < 0.0001 or max_range <= 0.0:
		return -1.0
	var along := direction.normalized()
	var to_point := point - origin
	var forward := to_point.dot(along)
	var sideways := absf(to_point.cross(along))
	if forward < -margin or forward > max_range + margin:
		return -1.0
	var half := width * 0.5
	if sideways > half + margin:
		return -1.0
	return clampf(1.0 - sideways / maxf(half, 0.0001), 0.0, 1.0)
