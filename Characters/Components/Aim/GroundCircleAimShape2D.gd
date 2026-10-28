extends AimShape2D
class_name GroundCircleAimShape2D
## A circle the player places on the ground (H8.8, ground-target skills). Two numbers describe it:
##   `max_range`  how far from the caster the circle's centre may be put (the cast range);
##   `radius`     the size of the circle itself (the area the skill covers).
##
## Where it lands, in the order the player's input decides:
##   - a drag on the skill button, a pushed stick or the mouse: the centre goes that way, `pull` (0 to 1) of the way out
##     to `max_range`. A drag that reaches the edge of the aim ring places it at full range;
##   - no aim given (a tap): the best target inside the assist region, the circle centred on it (and held inside the
##     cast range); with no target, `default_pull` of the way out along the last aim or the facing.
##
## Like every shape it only guides aiming. The skill keeps its own area and damage rules; this circle is where the
## player puts them, not a change to them.

## Assist: a target counts when it lies within `max_range + radius` of the caster (the circle can reach it) and within
## this many degrees (full width) of the aim. 360 looks all round. It only chooses a centre for a tap; a drag ignores it.
@export_range(1.0, 360.0, 1.0) var assist_angle: float = 180.0
## Size of the placed circle, in pixels.
@export_range(1.0, 1000.0, 1.0) var radius: float = 60.0
## How far out a tap with no target puts the circle, as a fraction of `max_range`.
@export_range(0.0, 1.0, 0.01) var default_pull: float = 0.6

func get_kind() -> Kind:
	return Kind.GROUND_CIRCLE

func is_placed() -> bool:
	return true

func area_radius() -> float:
	return radius

## The centre, in world space: `pull` (0 to 1, clamped) of the way from `origin` to the cast range along `direction`.
## A negative pull means "none given" and uses `default_pull`. A zero direction places it on the caster.
func place(origin: Vector2, direction: Vector2, pull: float = -1.0) -> Vector2:
	if direction.length_squared() < 0.0001:
		return origin
	var fraction := default_pull if pull < 0.0 else clampf(pull, 0.0, 1.0)
	return origin + direction.normalized() * max_range * fraction

## The centre for a circle put on `point`: the point itself, pulled back along the line to the caster when it is farther
## than the cast range.
func place_on(origin: Vector2, point: Vector2) -> Vector2:
	var offset := point - origin
	if offset.length() > max_range:
		offset = offset.normalized() * max_range
	return origin + offset

## True when a thing at `point` (with a body of radius `margin`) is inside the circle centred on `center`.
func covers(center: Vector2, point: Vector2, margin: float = 0.0) -> bool:
	return center.distance_to(point) <= radius + margin

## The area circle as offsets from its own centre (the indicator draws it where the centre is).
func get_area_outline() -> PackedVector2Array:
	return _circle(radius)

## The cast range as offsets from the caster: the reach the centre can be put at.
func get_range_outline() -> PackedVector2Array:
	return _circle(max_range)

func validate() -> PackedStringArray:
	var problems := super.validate()
	if radius <= 0.0:
		problems.append("radius must be above 0")
	return problems

## The assist region: inside the angle round the aim and no farther than the circle can reach.
func _alignment(origin: Vector2, direction: Vector2, point: Vector2, margin: float) -> float:
	if max_range <= 0.0 or radius <= 0.0:
		return -1.0
	var to_point := point - origin
	if to_point.length() > max_range + radius + margin:
		return -1.0
	if direction.length_squared() < 0.0001 or assist_angle >= 360.0 or to_point.length_squared() < 0.0001:
		return 1.0
	var half := deg_to_rad(assist_angle) * 0.5
	var angle := absf(direction.normalized().angle_to(to_point))
	if angle > half:
		return -1.0
	return clampf(1.0 - angle / half, 0.0, 1.0)

const OUTLINE_STEP_DEGREES := 6.0

func _circle(r: float) -> PackedVector2Array:
	var outline := PackedVector2Array()
	if r <= 0.0:
		return outline
	var steps := int(360.0 / OUTLINE_STEP_DEGREES)
	for i in steps:
		outline.append(Vector2.RIGHT.rotated(TAU * float(i) / float(steps)) * r)
	return outline
