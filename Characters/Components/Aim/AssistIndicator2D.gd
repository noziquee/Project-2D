@tool
extends Node2D
class_name AssistIndicator2D
## The assist view: a blue circle on the ground round the player (how far a light tap looks for a target, the light
## attack's attack_range) and a ring under the enemy the next tap will go for, like a mobile MOBA's range circle and
## target mark. It is a passive drawer: the player tells it what to show every physics frame (show_state) and when
## to stop (clear). It never decides a target and changes nothing in combat; the swing's real hitbox is not drawn.
##
## This is the LIGHT ATTACK's view. Heavy attacks and skills are drawn by AimIndicator2D, which has its own settings.
##
## INSPECTOR LAYOUT. One group per thing you can see:
##   Editor Preview   what the 2D view shows while you edit (no effect in game)
##   Range Circle     the circle round the player: fill (flat or gradient), outline, inner ring
##   Target Marker    the ring under the enemy the next tap will go for
##   Pixelation       draws everything as square cells, like AimIndicator2D's Pixelation
##
## It is a child of the player. Made from AssistIndicator2D.tscn, which holds its draw order (absolute z -1: below
## every character, above the floor) and its colours.

@export_group("Editor Preview")
## Editor only, no effect in game. Shows a sample target marker next to the range circle.
@export var preview_show_target := true:
	set(value):
		preview_show_target = value
		queue_redraw()

@export_group("Range Circle")
## Flat fill, used while Range Gradient is off.
@export var range_fill := Color(0.25, 0.6, 1.0, 0.10):
	set(value):
		range_fill = value
		queue_redraw()
## Outline colour.
@export var range_edge := Color(0.4, 0.72, 1.0, 0.7):
	set(value):
		range_edge = value
		queue_redraw()
## Thickness of the outline, in pixels. 0 draws none. Pixelated: rounded to whole cells, never thinner than one cell.
@export_range(0.0, 12.0, 0.5) var range_edge_width := 2.0:
	set(value):
		range_edge_width = value
		queue_redraw()
## Colour of the thin ring just inside the outline.
@export var range_inner := Color(0.4, 0.72, 1.0, 0.25):
	set(value):
		range_inner = value
		queue_redraw()
## Thickness of the inner ring, in pixels. 0 hides it.
@export_range(0.0, 12.0, 0.5) var range_inner_width := 1.0:
	set(value):
		range_inner_width = value
		queue_redraw()
## How far inside the outline the inner ring sits, in pixels.
@export_range(1.0, 40.0, 0.5) var range_inner_gap := 5.0:
	set(value):
		range_inner_gap = value
		queue_redraw()
## Fills the circle from the centre outward instead of flat. Replaces the flat fill above.
@export var range_gradient := false:
	set(value):
		range_gradient = value
		queue_redraw()
@export var range_gradient_center_color := Color(0.25, 0.6, 1.0, 0.0):
	set(value):
		range_gradient_center_color = value
		queue_redraw()
@export var range_gradient_edge_color := Color(0.25, 0.6, 1.0, 0.18):
	set(value):
		range_gradient_edge_color = value
		queue_redraw()
## Pixelated only: the gradient is drawn in this many flat colour bands, centre to edge.
@export_range(2, 12, 1) var range_gradient_steps := 5:
	set(value):
		range_gradient_steps = value
		queue_redraw()

@export_group("Target Marker")
@export var marker_fill := Color(1.0, 0.3, 0.25, 0.22):
	set(value):
		marker_fill = value
		queue_redraw()
@export var marker_edge := Color(1.0, 0.42, 0.32, 0.95):
	set(value):
		marker_edge = value
		queue_redraw()
## Thickness of the marker's outline, in pixels. 0 draws none.
@export_range(0.0, 12.0, 0.5) var marker_edge_width := 2.5:
	set(value):
		marker_edge_width = value
		queue_redraw()
## Radius of the ring under the target, in pixels.
@export_range(4.0, 40.0, 0.5) var marker_radius := 15.0:
	set(value):
		marker_radius = value
		queue_redraw()

@export_group("Pixelation")
## Draws the range circle and the target marker as a grid of square cells.
@export var pixelate := false:
	set(value):
		pixelate = value
		queue_redraw()
## Side of one cell, in pixels.
@export_range(2, 16, 1) var pixel_size := 4:
	set(value):
		pixel_size = value
		queue_redraw()

const ARC_POINTS := 64
const MARKER_POINTS := 32
## Points of a pixelated ring, and triangles in a smooth gradient disc.
const PIXEL_RING_POINTS := 96
const GRADIENT_SEGMENTS := 48
const PREVIEW_RANGE := 90.0

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
		_paint_range_circle(Vector2.ZERO, _range)
	var target := get_target()
	if target != null:
		_paint_marker(to_local(target.global_position))

## Editor only: a sample range circle and one target marker, drawn by the same code as the game, so everything in the
## groups above can be tuned in the Inspector.
func _draw_editor_preview() -> void:
	_paint_range_circle(Vector2.ZERO, PREVIEW_RANGE)
	if preview_show_target:
		_paint_marker(Vector2(50.0, -20.0))

## The range circle: fill (flat or gradient), then the outline, then the thin inner ring.
func _paint_range_circle(center: Vector2, radius: float) -> void:
	if radius <= 0.0:
		return
	if range_gradient:
		_fill_gradient_disc(center, radius)
	else:
		_fill_disc(center, radius, range_fill)
	_paint_ring(center, radius, range_edge, range_edge_width, ARC_POINTS)
	if range_inner_width > 0.0:
		_paint_ring(center, maxf(radius - range_inner_gap, 1.0), range_inner, range_inner_width, ARC_POINTS)

## The ring under the target: a flat disc and an outline.
func _paint_marker(at: Vector2) -> void:
	_fill_disc(at, marker_radius, marker_fill)
	_paint_ring(at, marker_radius, marker_edge, marker_edge_width, MARKER_POINTS)

## A flat disc, smooth or as cells.
func _fill_disc(center: Vector2, radius: float, color: Color) -> void:
	if radius <= 0.0:
		return
	if pixelate:
		_draw_runs(AimIndicator2D.pixel_annulus_runs(center, 0.0, radius, float(pixel_size)), color)
	else:
		draw_circle(center, radius, color)

## The range gradient: `range_gradient_center_color` in the middle to `range_gradient_edge_color` at the rim.
## Smooth: a fan of triangles with a colour on each corner. Pixelated: `range_gradient_steps` flat bands of cells.
func _fill_gradient_disc(center: Vector2, radius: float) -> void:
	if pixelate:
		var steps := maxi(range_gradient_steps, 2)
		for band in steps:
			var color := range_gradient_center_color.lerp(range_gradient_edge_color, float(band) / float(steps - 1))
			_draw_runs(AimIndicator2D.pixel_annulus_runs(center, radius * float(band) / float(steps), radius * float(band + 1) / float(steps), float(pixel_size)), color)
		return
	var colors := PackedColorArray([range_gradient_center_color, range_gradient_edge_color, range_gradient_edge_color])
	var previous := center + Vector2.RIGHT * radius
	for i in range(1, GRADIENT_SEGMENTS + 1):
		var next := center + Vector2.RIGHT.rotated(TAU * float(i) / float(GRADIENT_SEGMENTS)) * radius
		draw_polygon(PackedVector2Array([center, previous, next]), colors)
		previous = next

## A circle outline `width` thick, smooth or as cells. Nothing when the width is 0.
func _paint_ring(center: Vector2, radius: float, color: Color, width: float, smooth_points: int) -> void:
	if width <= 0.0 or radius <= 0.0:
		return
	if not pixelate:
		draw_arc(center, radius, 0.0, TAU, smooth_points, color, width, true)
		return
	# Half a step of turn is added so no point sits exactly on an axis: a point on a cell boundary would add one stray
	# cell on two sides of the circle only.
	var points := PackedVector2Array()
	for i in PIXEL_RING_POINTS:
		points.append(center + Vector2.RIGHT.rotated(TAU * (float(i) + 0.5) / float(PIXEL_RING_POINTS)) * radius)
	var size := float(pixel_size)
	for cell in AimIndicator2D.pixel_line_cells(points, true, size, maxi(1, roundi(width / size))):
		draw_rect(Rect2(Vector2(cell) * size, Vector2(size, size)), color)

func _draw_runs(runs: Array[Vector3i], color: Color) -> void:
	var size := float(pixel_size)
	for run in runs:
		draw_rect(Rect2(float(run.y) * size, float(run.x) * size, float(run.z - run.y + 1) * size, size), color)
