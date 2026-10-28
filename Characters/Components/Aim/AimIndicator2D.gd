@tool
extends Node2D
class_name AimIndicator2D
## H8.9: draws the aim shape of the action the player is about to do (a charging heavy attack, an aimed skill) so the
## player can see what the assist looks at. It draws the AimShape2D's own outline (get_outline), the very region that
## `contains` and `score` test, so the picture and the assist cannot drift apart. It also rings the targets inside the
## shape and marks the one the action will go for.
##
## It is a passive drawer: it has no input and decides nothing. The player tells it what to show (show_shape) and when
## to stop (clear). It is a child of the character, so it draws from the character's position. The real hitbox and
## damage of an attack or skill are not drawn and not changed: a shape is an aiming guide.
##
## Made from AimIndicator2D.tscn, which holds its draw order (z_index 50, above the characters, so the shape is never
## hidden by a body it is pointing at) and its colours. Change them in the Inspector, not here.

@export_group("Style")
@export var fill_color := Color(1.0, 1.0, 1.0, 0.14):
	set(value):
		fill_color = value
		queue_redraw()
@export var edge_color := Color(1.0, 1.0, 1.0, 0.55):
	set(value):
		edge_color = value
		queue_redraw()
@export var head_color := Color(1.0, 1.0, 1.0, 0.35):
	set(value):
		head_color = value
		queue_redraw()
@export var range_color := Color(1.0, 1.0, 1.0, 0.25):
	set(value):
		range_color = value
		queue_redraw()
@export var candidate_color := Color(1.0, 0.85, 0.3, 0.7):
	set(value):
		candidate_color = value
		queue_redraw()
@export var picked_color := Color(1.0, 0.35, 0.25, 0.95):
	set(value):
		picked_color = value
		queue_redraw()
## Optional white/grey transparent art. Leave empty to use the vector fallback.
@export_group("Replaceable Art")
@export var ring_texture: Texture2D:
	set(value):
		ring_texture = value
		queue_redraw()
@export var area_texture: Texture2D:
	set(value):
		area_texture = value
		queue_redraw()
@export var fan_texture: Texture2D:
	set(value):
		fan_texture = value
		queue_redraw()
## Texture sizing is based on the action's reach. Art should be square, centred, and transparent outside its shape.
@export_range(0.25, 2.0, 0.05) var texture_scale := 1.0:
	set(value):
		texture_scale = value
		queue_redraw()
## Radius of the ring round a target, in pixels. Rings are drawn at the target's position.
@export_range(4.0, 40.0, 0.5) var ring_radius := 14.0:
	set(value):
		ring_radius = value
		queue_redraw()

var _shape: AimShape2D = null
var _direction := Vector2.RIGHT
var _candidates: Array[Node2D] = []
var _picked: Node2D = null
## Placed shapes (the ground circle, H8.8): where the circle's centre is, as an offset from the character.
var _center := Vector2.ZERO
## Reach supplied by the active attack/skill definition; defaults to the shape range.
var _range_radius := 0.0

## Shows `shape` from the character along `direction`. `candidates` are the targets inside it and `picked` the one the
## action will take (null when it goes by the aim alone). `center` is only used by a placed shape (is_placed()): the
## offset from the character to the middle of the circle that is put down.
func show_shape(shape: AimShape2D, direction: Vector2, candidates: Array[Node2D] = [], picked: Node2D = null, center: Vector2 = Vector2.ZERO, range_radius: float = -1.0) -> void:
	if shape == null:
		clear()
		return
	_shape = shape
	_direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	_candidates = candidates
	_picked = picked
	_center = center
	_range_radius = shape.max_range if range_radius < 0.0 else maxf(range_radius, 0.0)
	visible = true
	queue_redraw()

## Hides the indicator.
func clear() -> void:
	if _shape == null and not visible:
		return
	_shape = null
	_candidates = []
	_picked = null
	_center = Vector2.ZERO
	_range_radius = 0.0
	visible = false
	queue_redraw()

func is_showing() -> bool:
	return _shape != null and visible

func get_shape() -> AimShape2D:
	return _shape

func get_direction() -> Vector2:
	return _direction

## Placed shapes: the offset from the character to the centre of the circle being put down (zero for the others).
func get_center_offset() -> Vector2:
	return _center

## Range used to clip this action's aim area (the definition's reach when supplied).
func get_range_radius() -> float:
	return _range_radius

func get_picked() -> Node2D:
	return _picked if is_instance_valid(_picked) else null

## The targets ringed right now (freed ones dropped).
func get_candidates() -> Array[Node2D]:
	var live: Array[Node2D] = []
	for node in _candidates:
		if is_instance_valid(node):
			live.append(node)
	return live

func _draw() -> void:
	if Engine.is_editor_hint():
		_draw_editor_preview()
		return
	if _shape == null:
		return
	if _shape.is_placed():
		_draw_placed()
		_draw_rings()
		return
	# H9.5: clip every aimed area to this action's own reach circle. The light-attack
	# range circle is drawn separately by AssistIndicator2D and remains visible during previews.
	# A placed ground circle is intentionally handled above: its area is centred at _center and
	# is not meant to be clipped by the caster-centred placement-range circle.
	var outline := _shape.get_outline(_direction)
	var texture := _texture_for_shape()
	if texture != null:
		_draw_shape_texture(texture, outline, fill_color)
	else:
		if outline.size() >= 3:
			_draw_clipped_polygon(outline, fill_color, edge_color)
		if _shape is LineAimShape2D:
			var head := (_shape as LineAimShape2D).get_head_outline(_direction)
			if head.size() >= 3:
				_draw_clipped_polygon(head, head_color, edge_color)
	_draw_rings()

## Draws a polygon after intersecting it with the action's own range circle. Kept here rather
## than in targeting: clipping changes presentation only, never candidate eligibility or damage.
func _texture_for_shape() -> Texture2D:
	if _shape is FanAimShape2D and fan_texture != null:
		return fan_texture
	if area_texture != null:
		return area_texture
	return null

## Draws a replaceable texture only inside the same clipped geometry used by the vector fallback.
func _draw_shape_texture(texture: Texture2D, outline: PackedVector2Array, tint: Color) -> void:
	for clipped in clip_polygon_to_range(outline, _range_radius):
		if clipped.size() < 3:
			continue
		var uvs := PackedVector2Array()
		for point in clipped:
			uvs.append(Vector2(0.5, 0.5) + point / maxf(_range_radius * 2.0, 0.001) * texture_scale)
		draw_polygon(clipped, PackedColorArray([tint]), uvs, texture)

func _draw_clipped_polygon(outline: PackedVector2Array, fill: Color, edge: Color) -> void:
	for clipped in clip_polygon_to_range(outline, _range_radius):
		if clipped.size() < 3:
			continue
		draw_colored_polygon(clipped, fill)
		var closed := clipped.duplicate()
		closed.append(clipped[0])
		draw_polyline(closed, edge, 2.0, true)

## Returns the visible polygon fragments after clipping `outline` to a circle around the origin.
## Public static geometry helper so smoke tests can check the clipping without rendering a frame.
static func clip_polygon_to_range(outline: PackedVector2Array, range_radius: float) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if outline.size() < 3 or range_radius <= 0.0:
		return result
	var circle := PackedVector2Array()
	const RANGE_CIRCLE_POINTS := 96
	for i in RANGE_CIRCLE_POINTS:
		circle.append(Vector2.RIGHT.rotated(TAU * float(i) / float(RANGE_CIRCLE_POINTS)) * range_radius)
	for polygon in Geometry2D.intersect_polygons(outline, circle):
		if polygon.size() >= 3:
			result.append(polygon)
	return result

## A placed shape: a faint ring for how far the centre can go, a line out to the centre, and the circle itself there.
func _draw_placed() -> void:
	var reach := _shape.get_range_outline()
	if reach.size() >= 3:
		var closed_reach := reach.duplicate()
		closed_reach.append(reach[0])
		draw_polyline(closed_reach, range_color, 1.5, true)
	draw_line(Vector2.ZERO, _center, head_color, 2.0, true)
	var area := _shape.get_area_outline()
	if area.size() < 3:
		return
	var moved := PackedVector2Array()
	for point in area:
		moved.append(point + _center)
	if area_texture != null:
		var uvs := PackedVector2Array()
		for point in moved:
			uvs.append(Vector2(0.5, 0.5) + (point - _center) / maxf(_shape.max_range * 2.0, 0.001) * texture_scale)
		draw_polygon(moved, PackedColorArray([fill_color]), uvs, area_texture)
	else:
		draw_colored_polygon(moved, fill_color)
		var closed := moved.duplicate()
		closed.append(moved[0])
		draw_polyline(closed, edge_color, 2.0, true)

func _draw_rings() -> void:
	for node in get_candidates():
		var picked := node == _picked
		var center := to_local(node.global_position)
		var radius := ring_radius * (1.3 if picked else 1.0)
		var tint := picked_color if picked else candidate_color
		if ring_texture != null:
			var side := radius * 2.0
			draw_texture_rect(ring_texture, Rect2(center - Vector2.ONE * radius, Vector2.ONE * side), false, tint)
		else:
			draw_arc(center, radius, 0.0, TAU, 24, tint, 3.0 if picked else 2.0, true)

## Editor only: a sample fan and two target rings, so the colours can be tuned in the Inspector. The shape classes are
## not @tool, so this uses plain geometry instead of an AimShape2D.
func _draw_editor_preview() -> void:
	var outline := PackedVector2Array([Vector2.ZERO])
	for i in range(-6, 7):
		outline.append(Vector2.RIGHT.rotated(deg_to_rad(i * 7.5)) * 100.0)
	draw_colored_polygon(outline, fill_color)
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, edge_color, 2.0, true)
	draw_arc(Vector2(60, -10), ring_radius, 0.0, TAU, 24, candidate_color, 2.0, true)
	draw_arc(Vector2(80, 15), ring_radius * 1.3, 0.0, TAU, 24, picked_color, 3.0, true)
