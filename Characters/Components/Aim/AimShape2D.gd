extends Resource
class_name AimShape2D
## The area an aimed action looks at (H8.2): the fan of a sweep, the strip of a lunge or arrow, the circle around the
## caster. It is **data and geometry only**: no nodes, no input, no state. TargetingService2D asks it "is this point
## inside" and "how good a candidate is it"; the aim indicator (H8.9) draws the same shape, so what the player sees is
## what the assist uses.
##
## A shape guides aiming and targeting. It never changes the real hitbox, area or damage of an attack or skill.
##
## Subclasses override get_kind(), needs_direction(), _alignment() and (to add their own fields) validate().

enum Kind {
	## A wedge from the caster: angle and reach.
	FAN,
	## A strip along the aim: width and length (the arrow indicator is a line drawn with a head).
	LINE,
	## A circle around the caster; the direction does not matter.
	CIRCLE_SELF,
	## A circle placed at a point the player chooses (drag-to-place): GroundCircleAimShape2D.
	GROUND_CIRCLE,
}

## How much the angle to the aim counts against the distance when two targets are compared: the PDF asks for the
## direction first and the distance second.
const ANGLE_WEIGHT := 0.7

## How far the shape reaches, in pixels: the radius of a fan or circle, the length of a line.
@export_range(1.0, 2000.0, 1.0) var max_range: float = 120.0

func get_kind() -> Kind:
	return Kind.FAN

## How much lining up with the aim counts against being close when two targets are compared (0 to 1). A shape can lean
## toward the nearest target by returning less than ANGLE_WEIGHT.
func _angle_weight() -> float:
	return ANGLE_WEIGHT

## False when the aim direction is irrelevant (a circle around the caster). Such a shape also works with no direction.
func needs_direction() -> bool:
	return true

## True when `point` lies inside the shape drawn from `origin` along `direction` (any length; it is normalised here).
## `margin` is the radius of the thing being tested, so a big body just outside the edge still counts.
func contains(origin: Vector2, direction: Vector2, point: Vector2, margin: float = 0.0) -> bool:
	return _alignment(origin, direction, point, margin) >= 0.0

## True when a target already chosen for an action may be kept at `point` (H9.3). Default: it is still within the shape's
## reach. A shape that is not measured from the caster (the camera view) overrides this.
func keeps_target(origin: Vector2, point: Vector2, margin: float = 0.0) -> bool:
	return origin.distance_to(point) <= max_range + margin

## How good `point` is as a target: -1 when it is outside, otherwise 0 to 1, higher is better. About 70% is how well it
## lines up with the aim, 30% how close it is (ANGLE_WEIGHT), so a target in front beats a nearer one off to the side.
func score(origin: Vector2, direction: Vector2, point: Vector2, margin: float = 0.0) -> float:
	var alignment := _alignment(origin, direction, point, margin)
	if alignment < 0.0:
		return -1.0
	var closeness := 1.0 - clampf(origin.distance_to(point) / max_range, 0.0, 1.0)
	var weight := _angle_weight()
	return weight * alignment + (1.0 - weight) * closeness

## The shape's outline as a closed polygon of offsets from the origin (H8.9), for the aim indicator to draw. It is the
## same region `contains` tests, so what the player sees is what the assist uses. Empty when the shape has no outline
## to draw from the caster (a ground circle is placed at a point: see is_placed(), get_area_outline()).
func get_outline(_direction: Vector2) -> PackedVector2Array:
	return PackedVector2Array()

## True for a shape the player puts down at a point (the ground circle) instead of aiming it from the caster. Such a
## shape answers place(), place_on(), covers(), area_radius(), get_area_outline() and get_range_outline(); the others
## leave these at the defaults below, which are inert.
func is_placed() -> bool:
	return false

## Placed shapes: the world position of the centre for an aim `direction` and a `pull` (0 to 1 of the way to max_range;
## negative = none given). Others: the origin.
func place(origin: Vector2, _direction: Vector2, _pull: float = -1.0) -> Vector2:
	return origin

## Placed shapes: the centre for a shape put on `point`, held inside max_range. Others: the origin.
func place_on(origin: Vector2, _point: Vector2) -> Vector2:
	return origin

## Placed shapes: the radius of the circle that is put down. Others: 0.
func area_radius() -> float:
	return 0.0

## Placed shapes: true when `point` is inside the circle centred on `center`. Others: false.
func covers(_center: Vector2, _point: Vector2, _margin: float = 0.0) -> bool:
	return false

## Placed shapes: the circle that is put down, as offsets from its own centre. Others: empty.
func get_area_outline() -> PackedVector2Array:
	return PackedVector2Array()

## Placed shapes: the reach the centre can be put at, as offsets from the caster. Others: empty.
func get_range_outline() -> PackedVector2Array:
	return PackedVector2Array()

## Problems with this shape's values, empty when it is fine (the same convention as the other definitions).
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if max_range <= 0.0:
		problems.append("max_range must be above 0")
	return problems

## Virtual. -1 when the point is outside, otherwise 0 (on the edge) to 1 (dead on the aim).
func _alignment(_origin: Vector2, _direction: Vector2, _point: Vector2, _margin: float) -> float:
	return -1.0
