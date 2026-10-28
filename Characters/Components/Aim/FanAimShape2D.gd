extends AimShape2D
class_name FanAimShape2D
## A wedge from the caster along the aim (sweeps, spins, the light-attack default arc). `max_range` is its radius.

## The full opening of the fan, in degrees (90 = 45 either side of the aim). 360 is a full circle.
@export_range(1.0, 360.0, 1.0) var angle_degrees: float = 90.0
## How much lining up with the aim counts against being close (see AimShape2D.ANGLE_WEIGHT). Lower = the nearest target
## wins more often.
@export_range(0.0, 1.0, 0.05) var angle_weight: float = AimShape2D.ANGLE_WEIGHT

## A fan built in code, for the project-wide light-attack arc (H8.5) and for tests.
static func make(angle: float, reach: float, weight: float = AimShape2D.ANGLE_WEIGHT) -> FanAimShape2D:
	var fan := FanAimShape2D.new()
	fan.angle_degrees = angle
	fan.max_range = reach
	fan.angle_weight = weight
	return fan

func _angle_weight() -> float:
	return angle_weight

func get_kind() -> Kind:
	return Kind.FAN

## Degrees between two points of the drawn arc (H8.9). Fine enough that the chord never strays visibly from the arc.
const OUTLINE_STEP_DEGREES := 6.0

## The wedge: the caster's point, then the arc from one edge to the other. A full circle has no point.
func get_outline(direction: Vector2) -> PackedVector2Array:
	var outline := PackedVector2Array()
	if max_range <= 0.0:
		return outline
	var axis := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	var full := angle_degrees >= 359.999
	var steps := maxi(int(ceil(angle_degrees / OUTLINE_STEP_DEGREES)), 2)
	var half := deg_to_rad(angle_degrees) * 0.5
	if not full:
		outline.append(Vector2.ZERO)
	for i in steps + 1:
		if full and i == steps:
			break
		outline.append(axis.rotated(-half + deg_to_rad(angle_degrees) * float(i) / float(steps)) * max_range)
	return outline

func validate() -> PackedStringArray:
	var problems := super.validate()
	if angle_degrees <= 0.0 or angle_degrees > 360.0:
		problems.append("angle_degrees must be above 0 and at most 360")
	return problems

func _alignment(origin: Vector2, direction: Vector2, point: Vector2, margin: float) -> float:
	if direction.length_squared() < 0.0001 or max_range <= 0.0:
		return -1.0
	var to_point := point - origin
	var distance := to_point.length()
	if distance > max_range + margin:
		return -1.0
	if distance < 0.001:
		return 1.0
	var half := deg_to_rad(angle_degrees) * 0.5
	var angle := absf(direction.normalized().angle_to(to_point / distance))
	# A body with a radius sticks out sideways by about atan(margin / distance) beyond its centre.
	# The small extra is float rounding: straight behind a 360 degree fan is exactly on its edge and must stay inside.
	if angle > half + atan2(margin, distance) + 0.0001:
		return -1.0
	return clampf(1.0 - angle / maxf(half, 0.0001), 0.0, 1.0)
