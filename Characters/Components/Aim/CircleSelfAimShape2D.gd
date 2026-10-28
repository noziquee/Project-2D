extends AimShape2D
class_name CircleSelfAimShape2D
## A circle around the caster (bursts, slams). The direction does not matter, so it works with none at all.
## `max_range` is its radius. Every target inside is equally well aimed; only the distance orders them.

func get_kind() -> Kind:
	return Kind.CIRCLE_SELF

func needs_direction() -> bool:
	return false

func _alignment(origin: Vector2, _direction: Vector2, point: Vector2, margin: float) -> float:
	if max_range <= 0.0:
		return -1.0
	return 1.0 if origin.distance_to(point) <= max_range + margin else -1.0

## Degrees between two points of the drawn circle (H8.9).
const OUTLINE_STEP_DEGREES := 6.0

func get_outline(_direction: Vector2) -> PackedVector2Array:
	var outline := PackedVector2Array()
	if max_range <= 0.0:
		return outline
	var steps := int(360.0 / OUTLINE_STEP_DEGREES)
	for i in steps:
		outline.append(Vector2.RIGHT.rotated(TAU * float(i) / float(steps)) * max_range)
	return outline
