extends AimShape2D
class_name ViewAimShape2D
## The camera view as an aim area (H9.3, T1, D20): every point inside the rectangle the camera shows can be targeted, and
## how far the caster's weapon reaches decides nothing here. It is what a light tap looks inside; a heavy attack or a
## skill keeps its own shape. Like every shape it is data and geometry only: the service builds one from the live camera
## (TargetingService2D.make_view_shape) each time it is needed.
##
## Camera visibility is not permission to attack: a target in view can still be out of the swing's range. Closing that
## distance is auto-approach (H9.4), not targeting.

## The visible area in world coordinates. Empty = nothing is inside.
var view_rect := Rect2()
## How wide a fan around the aim is searched, in degrees. 360 = all round the caster.
@export_range(1.0, 360.0, 1.0) var angle_degrees: float = 360.0
## How much lining up with the aim counts against being close (see AimShape2D.ANGLE_WEIGHT).
@export_range(0.0, 1.0, 0.05) var angle_weight: float = AimShape2D.ANGLE_WEIGHT
## Selection preference cone around the aim axis. Targets in this cone always rank above targets outside it;
## within either group the nearest target wins. This is independent of angle_degrees, which defines eligibility.
@export_range(1.0, 360.0, 1.0) var front_angle: float = 120.0

## A view shape for `rect`. `max_range` is the rect's diagonal, so "closeness" in the score is measured against the
## screen and a target at the far corner scores 0 for distance.
static func make(rect: Rect2, angle: float = 360.0, weight: float = AimShape2D.ANGLE_WEIGHT) -> ViewAimShape2D:
	var shape := ViewAimShape2D.new()
	shape.view_rect = rect
	shape.angle_degrees = angle
	shape.angle_weight = weight
	shape.max_range = maxf(rect.size.length(), 1.0)
	return shape

func _angle_weight() -> float:
	return angle_weight

## H9.4.0: prioritise the front cone as a group, then distance. A front target must always outrank a target
## behind/outside the cone, regardless of distance; nearest wins within each group.
func score(origin: Vector2, direction: Vector2, point: Vector2, margin: float = 0.0) -> float:
	if _alignment(origin, direction, point, margin) < 0.0:
		return -1.0
	var to_point := point - origin
	var distance := to_point.length()
	var axis := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	var angle := absf(axis.angle_to(to_point / distance)) if distance > 0.001 else 0.0
	var in_front := angle <= deg_to_rad(front_angle * 0.5) + atan2(margin, maxf(distance, 0.001))
	var closeness := 1.0 - clampf(distance / maxf(max_range, 1.0), 0.0, 1.0)
	return (2.0 if in_front else 1.0) + closeness

func get_kind() -> Kind:
	return Kind.FAN

## A target stays eligible for as long as it is still in view, however far it is.
func keeps_target(_origin: Vector2, point: Vector2, margin: float = 0.0) -> bool:
	return view_rect.grow(margin).has_point(point)

func validate() -> PackedStringArray:
	var problems := super.validate()
	if view_rect.size.x <= 0.0 or view_rect.size.y <= 0.0:
		problems.append("view_rect has no area")
	if angle_degrees <= 0.0 or angle_degrees > 360.0:
		problems.append("angle_degrees must be above 0 and at most 360")
	if front_angle <= 0.0 or front_angle > 360.0:
		problems.append("front_angle must be above 0 and at most 360")
	return problems

func _alignment(origin: Vector2, direction: Vector2, point: Vector2, margin: float) -> float:
	if direction.length_squared() < 0.0001 or not view_rect.grow(margin).has_point(point):
		return -1.0
	var to_point := point - origin
	var distance := to_point.length()
	if distance < 0.001:
		return 1.0
	var half := deg_to_rad(angle_degrees) * 0.5
	var angle := absf(direction.normalized().angle_to(to_point / distance))
	if angle > half + atan2(margin, distance) + 0.0001:
		return -1.0
	return clampf(1.0 - angle / maxf(half, 0.0001), 0.0, 1.0)
