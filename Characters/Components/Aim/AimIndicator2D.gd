@tool
extends Node2D
class_name AimIndicator2D
## H8.9: draws the aim shape of the action the player is about to do (a charging heavy attack, an aimed skill) so the
## player can see what the assist looks at. It draws the AimShape2D's own outline (get_outline), the very region that
## `contains` and `score` test, so the picture and the assist cannot drift apart. It also marks the target the action
## will go for.
##
## It is a passive drawer: it has no input and decides nothing. The player tells it what to show (show_shape) and when
## to stop (clear). It is a child of the character, so it draws from the character's position. The real hitbox and
## damage of an attack or skill are not drawn and not changed: a shape is an aiming guide.
##
## INSPECTOR LAYOUT. One group per thing you can see, so every value has one obvious home:
##   Editor Preview         which shape the 2D view shows while you edit (no effect in game)
##   Range Circle           the circle around the caster showing how far the action reaches
##   Fan                    the cone / fan area (flat fill or a straight gradient from the caster outward)
##   Arrow                  the strip with an arrowhead (same)
##   Rectangle              the plain strip (same)
##   Circle (Self & Placed) the circle around the caster, and the ground circle that is put down, with a centre cross
##   Target Indicator       the ring on the enemy the action will take
##   All Shapes             outline thickness and pixelation, shared by everything above
##   Replaceable Art        optional textures that replace the vector drawing
## Presentation lives here, never on the shapes: these settings change how the guide is drawn, not what the assist
## targets. A shape's own `width` stays the one targeting width.
##
## Made from AimIndicator2D.tscn, which holds its draw order (z_index 50, above the characters, so the shape is never
## hidden by a body it is pointing at) and its colours. Change them in the Inspector, not here.

## Which sample the 2D view draws while editing the scene. Pick a shape to see exactly that shape with its group's
## settings; "All" lays every shape out side by side (zoom out to see them).
enum PreviewShape { FAN, ARROW, RECTANGLE, SELF_CIRCLE, PLACED_CIRCLE, ALL }

## What a shape looks like, which decides the colours it is drawn with.
enum Look { FAN, ARROW, RECTANGLE, CIRCLE }

## The mark in the middle of a circle: a plus, or an X.
enum CrossStyle { PLUS, X }

@export_group("Editor Preview")
## Editor only, no effect in game. Which shape the 2D view shows. Everything in the groups below is drawn through the
## same code the game uses.
@export var preview_shape: PreviewShape = PreviewShape.FAN:
	set(value):
		preview_shape = value
		queue_redraw()
## Editor only. Shows a sample target ring (and the picked one) so the Target Indicator group can be tuned.
@export var preview_show_targets := true:
	set(value):
		preview_show_targets = value
		queue_redraw()

@export_group("Range Circle")
## A circle on the caster showing how far the action reaches, drawn beneath the aim shape. It is not drawn for a
## self-circle whose shape already is that circle. A placed circle's cast-range ring is this circle.
@export var show_range_circle := true:
	set(value):
		show_range_circle = value
		queue_redraw()
## Outline colour of the range circle.
@export var range_color := Color(1.0, 1.0, 1.0, 0.25):
	set(value):
		range_color = value
		queue_redraw()
## Flat fill, used while Range Gradient is off.
@export var range_fill_color := Color(1.0, 1.0, 1.0, 0.06):
	set(value):
		range_fill_color = value
		queue_redraw()
## Fills the range circle from the centre outward instead of flat. Replaces the flat fill above.
@export var range_gradient := false:
	set(value):
		range_gradient = value
		queue_redraw()
@export var range_gradient_center_color := Color(1.0, 1.0, 1.0, 0.0):
	set(value):
		range_gradient_center_color = value
		queue_redraw()
@export var range_gradient_edge_color := Color(1.0, 1.0, 1.0, 0.18):
	set(value):
		range_gradient_edge_color = value
		queue_redraw()
## Pixelated only: the gradient is drawn in this many flat colour bands, centre to edge.
@export_range(2, 12, 1) var range_gradient_steps := 5:
	set(value):
		range_gradient_steps = value
		queue_redraw()

@export_group("Fan")
@export var fan_fill_color := Color(1.0, 1.0, 1.0, 0.14):
	set(value):
		fan_fill_color = value
		queue_redraw()
@export var fan_edge_color := Color(1.0, 1.0, 1.0, 0.55):
	set(value):
		fan_edge_color = value
		queue_redraw()
## Fills the fan with a straight gradient along the aim, from the caster (start colour) to near the edge of the
## reach (end colour), instead of the flat fill. Replaceable-art textures take priority over it.
@export var fan_gradient := false:
	set(value):
		fan_gradient = value
		queue_redraw()
## Colour at the caster.
@export var fan_gradient_start_color := Color(1.0, 1.0, 1.0, 0.0):
	set(value):
		fan_gradient_start_color = value
		queue_redraw()
## Colour at the far end (where All Shapes > Linear Gradient Reach says).
@export var fan_gradient_end_color := Color(1.0, 1.0, 1.0, 0.32):
	set(value):
		fan_gradient_end_color = value
		queue_redraw()
## Pixelated only: the fill gradient is drawn in this many flat colour bands, caster to far end.
@export_range(2, 12, 1) var fan_gradient_steps := 5:
	set(value):
		fan_gradient_steps = value
		queue_redraw()
## Colours the outline of the fan with a straight gradient too, from the caster (start colour) to near the edge of the
## reach (end colour), instead of the flat edge colour. Works with or without the fill gradient.
@export var fan_edge_gradient := false:
	set(value):
		fan_edge_gradient = value
		queue_redraw()
## Outline colour at the caster.
@export var fan_edge_gradient_start_color := Color(1.0, 1.0, 1.0, 0.1):
	set(value):
		fan_edge_gradient_start_color = value
		queue_redraw()
## Outline colour at the far end (where All Shapes > Linear Gradient Reach says).
@export var fan_edge_gradient_end_color := Color(1.0, 1.0, 1.0, 0.8):
	set(value):
		fan_edge_gradient_end_color = value
		queue_redraw()
## Pixelated only: the edge gradient is drawn in this many flat colour bands, caster to far end. Independent of the fill
## gradient's steps.
@export_range(2, 12, 1) var fan_edge_gradient_steps := 5:
	set(value):
		fan_edge_gradient_steps = value
		queue_redraw()

@export_group("Arrow")
@export var arrow_fill_color := Color(1.0, 1.0, 1.0, 0.14):
	set(value):
		arrow_fill_color = value
		queue_redraw()
@export var arrow_edge_color := Color(1.0, 1.0, 1.0, 0.55):
	set(value):
		arrow_edge_color = value
		queue_redraw()
## Fills the arrow strip with a straight gradient along the aim, from the caster (start colour) to near the edge of the
## reach (end colour), instead of the flat fill. Replaceable-art textures take priority over it.
@export var arrow_gradient := false:
	set(value):
		arrow_gradient = value
		queue_redraw()
## Colour at the caster.
@export var arrow_gradient_start_color := Color(1.0, 1.0, 1.0, 0.0):
	set(value):
		arrow_gradient_start_color = value
		queue_redraw()
## Colour at the far end (where All Shapes > Linear Gradient Reach says).
@export var arrow_gradient_end_color := Color(1.0, 1.0, 1.0, 0.32):
	set(value):
		arrow_gradient_end_color = value
		queue_redraw()
## Pixelated only: the fill gradient is drawn in this many flat colour bands, caster to far end.
@export_range(2, 12, 1) var arrow_gradient_steps := 5:
	set(value):
		arrow_gradient_steps = value
		queue_redraw()
## Colours the outline of the arrow strip with a straight gradient too, from the caster (start colour) to near the edge of the
## reach (end colour), instead of the flat edge colour. Works with or without the fill gradient.
@export var arrow_edge_gradient := false:
	set(value):
		arrow_edge_gradient = value
		queue_redraw()
## Outline colour at the caster.
@export var arrow_edge_gradient_start_color := Color(1.0, 1.0, 1.0, 0.1):
	set(value):
		arrow_edge_gradient_start_color = value
		queue_redraw()
## Outline colour at the far end (where All Shapes > Linear Gradient Reach says).
@export var arrow_edge_gradient_end_color := Color(1.0, 1.0, 1.0, 0.8):
	set(value):
		arrow_edge_gradient_end_color = value
		queue_redraw()
## Pixelated only: the edge gradient is drawn in this many flat colour bands, caster to far end. Independent of the fill
## gradient's steps.
@export_range(2, 12, 1) var arrow_edge_gradient_steps := 5:
	set(value):
		arrow_edge_gradient_steps = value
		queue_redraw()
## Fill of the arrowhead triangle. Always flat, also when the strip has a gradient.
@export var arrow_head_color := Color(1.0, 1.0, 1.0, 0.35):
	set(value):
		arrow_head_color = value
		queue_redraw()
## How wide an arrow strip is drawn, as a multiple of its shape's `width`. Range only sets the length. The arrowhead is
## as long as the drawn strip is wide, so it scales with it. Drawing only: targeting keeps the shape's own width.
@export_range(0.25, 4.0, 0.05) var arrow_width_scale := 1.0:
	set(value):
		arrow_width_scale = value
		queue_redraw()

@export_group("Rectangle")
@export var rectangle_fill_color := Color(1.0, 1.0, 1.0, 0.14):
	set(value):
		rectangle_fill_color = value
		queue_redraw()
@export var rectangle_edge_color := Color(1.0, 1.0, 1.0, 0.55):
	set(value):
		rectangle_edge_color = value
		queue_redraw()
## Fills the rectangle strip with a straight gradient along the aim, from the caster (start colour) to near the edge of the
## reach (end colour), instead of the flat fill. Replaceable-art textures take priority over it.
@export var rectangle_gradient := false:
	set(value):
		rectangle_gradient = value
		queue_redraw()
## Colour at the caster.
@export var rectangle_gradient_start_color := Color(1.0, 1.0, 1.0, 0.0):
	set(value):
		rectangle_gradient_start_color = value
		queue_redraw()
## Colour at the far end (where All Shapes > Linear Gradient Reach says).
@export var rectangle_gradient_end_color := Color(1.0, 1.0, 1.0, 0.32):
	set(value):
		rectangle_gradient_end_color = value
		queue_redraw()
## Pixelated only: the fill gradient is drawn in this many flat colour bands, caster to far end.
@export_range(2, 12, 1) var rectangle_gradient_steps := 5:
	set(value):
		rectangle_gradient_steps = value
		queue_redraw()
## Colours the outline of the rectangle strip with a straight gradient too, from the caster (start colour) to near the edge of the
## reach (end colour), instead of the flat edge colour. Works with or without the fill gradient.
@export var rectangle_edge_gradient := false:
	set(value):
		rectangle_edge_gradient = value
		queue_redraw()
## Outline colour at the caster.
@export var rectangle_edge_gradient_start_color := Color(1.0, 1.0, 1.0, 0.1):
	set(value):
		rectangle_edge_gradient_start_color = value
		queue_redraw()
## Outline colour at the far end (where All Shapes > Linear Gradient Reach says).
@export var rectangle_edge_gradient_end_color := Color(1.0, 1.0, 1.0, 0.8):
	set(value):
		rectangle_edge_gradient_end_color = value
		queue_redraw()
## Pixelated only: the edge gradient is drawn in this many flat colour bands, caster to far end. Independent of the fill
## gradient's steps.
@export_range(2, 12, 1) var rectangle_edge_gradient_steps := 5:
	set(value):
		rectangle_edge_gradient_steps = value
		queue_redraw()
## How wide a rectangle strip is drawn, as a multiple of its shape's `width`. Range only sets the length. Drawing only:
## targeting keeps the shape's own width.
@export_range(0.25, 4.0, 0.05) var rectangle_width_scale := 1.0:
	set(value):
		rectangle_width_scale = value
		queue_redraw()

@export_group("Circle (Self & Placed)")
## The circle around the caster (self-circle skills) and the ground circle that is put down (placed skills). This is
## NOT the range circle: that one has its own group above.
@export var circle_fill_color := Color(1.0, 1.0, 1.0, 0.14):
	set(value):
		circle_fill_color = value
		queue_redraw()
@export var circle_edge_color := Color(1.0, 1.0, 1.0, 0.55):
	set(value):
		circle_edge_color = value
		queue_redraw()
## The line from the caster to a placed circle.
@export var circle_guide_color := Color(1.0, 1.0, 1.0, 0.35):
	set(value):
		circle_guide_color = value
		queue_redraw()
## A cross in the middle of the circle: on the caster for a self-circle, at the spot for a placed circle.
@export var show_circle_cross := true:
	set(value):
		show_circle_cross = value
		queue_redraw()
@export var circle_cross_color := Color(1.0, 1.0, 1.0, 0.7):
	set(value):
		circle_cross_color = value
		queue_redraw()
@export var circle_cross_style: CrossStyle = CrossStyle.PLUS:
	set(value):
		circle_cross_style = value
		queue_redraw()
## Length of each arm from the centre, in pixels. Stroke thickness is All Shapes > Outline Width (at least 1).
@export_range(2.0, 40.0, 0.5) var circle_cross_size := 8.0:
	set(value):
		circle_cross_size = value
		queue_redraw()
## Fills these circles from the centre outward instead of flat. The outline uses Circle Edge Color. Replaceable-art
## textures take priority over it.
@export var circle_gradient := false:
	set(value):
		circle_gradient = value
		queue_redraw()
@export var circle_gradient_center_color := Color(1.0, 1.0, 1.0, 0.0):
	set(value):
		circle_gradient_center_color = value
		queue_redraw()
@export var circle_gradient_edge_color := Color(1.0, 1.0, 1.0, 0.32):
	set(value):
		circle_gradient_edge_color = value
		queue_redraw()
## Pixelated only: the gradient is drawn in this many flat colour bands, centre to edge.
@export_range(2, 12, 1) var circle_gradient_steps := 5:
	set(value):
		circle_gradient_steps = value
		queue_redraw()

@export_group("Target Indicator")
## Ring on an enemy the action could take.
@export var candidate_color := Color(1.0, 0.85, 0.3, 0.7):
	set(value):
		candidate_color = value
		queue_redraw()
## Ring on the one enemy the action will go for. It is drawn 30 % larger.
@export var picked_color := Color(1.0, 0.35, 0.25, 0.95):
	set(value):
		picked_color = value
		queue_redraw()
## Radius of the ring round a target, in pixels. Rings are drawn at the target's position.
@export_range(4.0, 40.0, 0.5) var ring_radius := 14.0:
	set(value):
		ring_radius = value
		queue_redraw()

@export_group("All Shapes")
## Thickness of every outline (fan, arrow, rectangle, circles, range circle), in pixels. 0 draws none.
## Pixelated: rounded to whole pixel cells, never thinner than one cell.
@export_range(0.0, 12.0, 0.5) var outline_width := 2.0:
	set(value):
		outline_width = value
		queue_redraw()
## Where the Fan, Arrow and Rectangle gradients (fill and edge) reach their end colour, as a fraction of the action's reach.
## 1.0 is the very edge of the reach; the default stops a little short of it.
@export_range(0.1, 1.0, 0.05) var linear_gradient_reach := 0.9:
	set(value):
		linear_gradient_reach = value
		queue_redraw()
## Draws fills, outlines, the placed-circle guide line and target rings as a grid of square cells.
@export var pixelate := false:
	set(value):
		pixelate = value
		queue_redraw()
## Side of one cell, in pixels.
@export_range(2, 16, 1) var pixel_size := 4:
	set(value):
		pixel_size = value
		queue_redraw()

## Optional white/grey transparent art. Leave empty to use the vector drawing.
@export_group("Replaceable Art")
## Replaces the target ring.
@export var ring_texture: Texture2D:
	set(value):
		ring_texture = value
		queue_redraw()
## Replaces the fill of arrows, rectangles and circles.
@export var area_texture: Texture2D:
	set(value):
		area_texture = value
		queue_redraw()
## Replaces the fill of the fan.
@export var fan_texture: Texture2D:
	set(value):
		fan_texture = value
		queue_redraw()
## Texture sizing is based on the action's reach. Art should be square, centred, and transparent outside its shape.
@export_range(0.25, 2.0, 0.05) var texture_scale := 1.0:
	set(value):
		texture_scale = value
		queue_redraw()

## --- Old property names, kept so older scripts and checks keep working. Not shown in the Inspector. Setting one sets
## every new property it used to cover. ---
var fill_color: Color:
	get:
		return fan_fill_color
	set(value):
		fan_fill_color = value
		arrow_fill_color = value
		rectangle_fill_color = value
		circle_fill_color = value
var edge_color: Color:
	get:
		return fan_edge_color
	set(value):
		fan_edge_color = value
		arrow_edge_color = value
		rectangle_edge_color = value
		circle_edge_color = value
var head_color: Color:
	get:
		return arrow_head_color
	set(value):
		arrow_head_color = value
var gradient_center_color: Color:
	get:
		return circle_gradient_center_color
	set(value):
		circle_gradient_center_color = value
var gradient_edge_color: Color:
	get:
		return circle_gradient_edge_color
	set(value):
		circle_gradient_edge_color = value
var gradient_steps: int:
	get:
		return circle_gradient_steps
	set(value):
		circle_gradient_steps = value

## Sample sizes for the editor preview (pixels). One shape fills the view; "All" uses smaller tiles.
const PREVIEW_RANGE := 110.0
const PREVIEW_TILE_RANGE := 70.0
const PREVIEW_STRIP_WIDTH := 24.0

## Points of the drawn range circle and of a circle outline; of a target ring; triangles in a smooth gradient disc.
const RANGE_POINTS := 96
const RING_POINTS := 24
const GRADIENT_SEGMENTS := 48
## Half-size of the cutting slabs for the straight gradient (pixels); far larger than any shape.
const SLAB_HALF := 100000.0
## Smallest polygon area (square pixels) worth drawing; thinner slivers fail triangulation.
const MIN_FILL_AREA := 0.01

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
	# The range circle goes first, so the aim shape is drawn on top of it.
	_draw_range_circle()
	if _shape.is_placed():
		_draw_placed()
		_draw_rings()
		return
	# H9.5: clip every aimed area to this action's own reach circle. The light-attack
	# range circle is drawn separately by AssistIndicator2D and remains visible during previews.
	# A placed ground circle is intentionally handled above: its area is centred at _center and
	# is not meant to be clipped by the caster-centred placement-range circle.
	var look := look_for(_shape)
	var outline := _aim_outline()
	var texture := _texture_for_shape()
	if texture != null:
		_draw_shape_texture(texture, outline, _fill_for(look))
	elif circle_gradient and _shape.get_kind() == AimShape2D.Kind.CIRCLE_SELF:
		_paint_circle_gradient(Vector2.ZERO, minf(_shape.max_range, _range_radius))
	else:
		if outline.size() >= 3:
			_draw_clipped_look(outline, look)
		if _shape is LineAimShape2D:
			var line := _shape as LineAimShape2D
			var head := line.get_head_outline_at_width(_direction, drawn_width_for(line))
			if head.size() >= 3:
				_draw_clipped_head(head)
	if look == Look.CIRCLE:
		_paint_circle_cross(Vector2.ZERO)
	_draw_rings()

## Which Inspector group styles `shape`: a strip is an arrow or a rectangle by its style, the two circle kinds share the
## circle group, everything else (the fan) is the fan.
func look_for(shape: AimShape2D) -> Look:
	if shape is LineAimShape2D:
		return Look.ARROW if (shape as LineAimShape2D).style == LineAimShape2D.Style.ARROW else Look.RECTANGLE
	var kind := shape.get_kind()
	if kind == AimShape2D.Kind.CIRCLE_SELF or kind == AimShape2D.Kind.GROUND_CIRCLE:
		return Look.CIRCLE
	return Look.FAN

func _fill_for(look: Look) -> Color:
	match look:
		Look.ARROW:
			return arrow_fill_color
		Look.RECTANGLE:
			return rectangle_fill_color
		Look.CIRCLE:
			return circle_fill_color
	return fan_fill_color

func _edge_for(look: Look) -> Color:
	match look:
		Look.ARROW:
			return arrow_edge_color
		Look.RECTANGLE:
			return rectangle_edge_color
		Look.CIRCLE:
			return circle_edge_color
	return fan_edge_color

## The fan uses its own art when it has some, everything else uses the shared area art.
func _texture_for_look(look: Look) -> Texture2D:
	if look == Look.FAN and fan_texture != null:
		return fan_texture
	return area_texture

## The outline to draw: the shape's own, except a strip, which is drawn at its scaled width.
func _aim_outline() -> PackedVector2Array:
	if _shape is LineAimShape2D:
		var line := _shape as LineAimShape2D
		return line.get_outline_at_width(_direction, drawn_width_for(line))
	return _shape.get_outline(_direction)

## How wide `line` is drawn: its own width times the scale for its style (arrow or rectangle).
func drawn_width_for(line: LineAimShape2D) -> float:
	return line.width * (arrow_width_scale if line.style == LineAimShape2D.Style.ARROW else rectangle_width_scale)

func _texture_for_shape() -> Texture2D:
	return _texture_for_look(look_for(_shape))

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
		_draw_polygon_area(clipped, fill, edge)

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

## A placed shape: a line out to the centre and the circle itself there. The ring of how far the centre can go is the
## range circle, drawn first by _draw().
func _draw_placed() -> void:
	_draw_guide_line(Vector2.ZERO, _center)
	var area := _shape.get_area_outline()
	if area.size() >= 3:
		var moved := PackedVector2Array()
		for point in area:
			moved.append(point + _center)
		if area_texture != null:
			var uvs := PackedVector2Array()
			for point in moved:
				uvs.append(Vector2(0.5, 0.5) + (point - _center) / maxf(_shape.max_range * 2.0, 0.001) * texture_scale)
			draw_polygon(moved, PackedColorArray([circle_fill_color]), uvs, area_texture)
		elif circle_gradient:
			_paint_circle_gradient(_center, _shape.area_radius())
		else:
			_draw_polygon_area(moved, circle_fill_color, circle_edge_color)
	_paint_circle_cross(_center)

func _draw_rings() -> void:
	for node in get_candidates():
		_paint_target_ring(to_local(node.global_position), node == _picked)

## One target ring (or its replaceable art) at `center`. The picked target's ring is a third larger and thicker.
func _paint_target_ring(center: Vector2, picked: bool) -> void:
	var radius := ring_radius * (1.3 if picked else 1.0)
	var tint := picked_color if picked else candidate_color
	if ring_texture != null:
		var side := radius * 2.0
		draw_texture_rect(ring_texture, Rect2(center - Vector2.ONE * radius, Vector2.ONE * side), false, tint)
	elif pixelate:
		_draw_pixel_polyline(_circle_points(center, radius, RING_POINTS), true, tint, 3.0 if picked else 2.0)
	else:
		draw_arc(center, radius, 0.0, TAU, 24, tint, 3.0 if picked else 2.0, true)

## The circle of how far the action reaches, round the caster, beneath everything else. Skipped when the shape is a
## self-circle of that very radius (it would only be drawn twice).
func _draw_range_circle() -> void:
	if not show_range_circle or _range_radius <= 0.0:
		return
	if _shape.get_kind() == AimShape2D.Kind.CIRCLE_SELF and is_equal_approx(_shape.max_range, _range_radius):
		return
	_paint_range_circle(Vector2.ZERO, _range_radius)

## The range circle itself: a flat fill, or (range_gradient) a gradient from the centre out, with the range outline.
func _paint_range_circle(center: Vector2, radius: float) -> void:
	if radius <= 0.0:
		return
	if range_gradient:
		_paint_gradient_disc(center, radius, range_gradient_center_color, range_gradient_edge_color, range_gradient_steps, range_color)
	else:
		_draw_polygon_area(_circle_points(center, radius, RANGE_POINTS), range_fill_color, range_color)

## A self-circle or placed circle filled with the Circle group's gradient and outlined with circle_edge_color.
func _paint_circle_gradient(center: Vector2, radius: float) -> void:
	_paint_gradient_disc(center, radius, circle_gradient_center_color, circle_gradient_edge_color, circle_gradient_steps, circle_edge_color)

## A disc filled from `center_color` at the middle to `rim_color` at the rim, with an outline in `outline_color`.
## Smooth: a fan of triangles with a colour on each corner. Pixelated: `bands` flat bands of cells.
func _paint_gradient_disc(center: Vector2, radius: float, center_color: Color, rim_color: Color, bands: int, outline_color: Color) -> void:
	if radius <= 0.0:
		return
	if pixelate:
		var steps := maxi(bands, 2)
		for band in steps:
			var color := center_color.lerp(rim_color, float(band) / float(steps - 1))
			_draw_runs(pixel_annulus_runs(center, radius * float(band) / float(steps), radius * float(band + 1) / float(steps), float(pixel_size)), color)
		if outline_width > 0.0:
			_draw_pixel_polyline(_circle_points(center, radius, RANGE_POINTS), true, outline_color, outline_width)
		return
	var colors := PackedColorArray([center_color, rim_color, rim_color])
	var previous := center + Vector2.RIGHT * radius
	for i in range(1, GRADIENT_SEGMENTS + 1):
		var next := center + Vector2.RIGHT.rotated(TAU * float(i) / float(GRADIENT_SEGMENTS)) * radius
		draw_polygon(PackedVector2Array([center, previous, next]), colors)
		previous = next
	if outline_width > 0.0:
		draw_arc(center, radius, 0.0, TAU, RANGE_POINTS, outline_color, outline_width, true)

func _draw_guide_line(from: Vector2, to: Vector2) -> void:
	if pixelate:
		_draw_pixel_polyline(PackedVector2Array([from, to]), false, circle_guide_color, 2.0)
	else:
		draw_line(from, to, circle_guide_color, 2.0, true)

## A filled polygon and its outline, smooth or (pixelate) as a grid of cells. The one place flat fills are drawn.
func _draw_polygon_area(polygon: PackedVector2Array, fill: Color, edge: Color) -> void:
	_fill_polygon(polygon, fill)
	_draw_polygon_outline(polygon, edge)

## Just the flat fill of a polygon, smooth or as cells.
func _fill_polygon(polygon: PackedVector2Array, fill: Color) -> void:
	if pixelate:
		_draw_runs(pixel_polygon_runs(polygon, float(pixel_size)), fill)
	else:
		draw_colored_polygon(polygon, fill)

## Just the closed outline of a polygon, smooth or as cells. Nothing when outline_width is 0.
func _draw_polygon_outline(polygon: PackedVector2Array, edge: Color) -> void:
	if outline_width <= 0.0 or polygon.size() < 2:
		return
	if pixelate:
		_draw_pixel_polyline(polygon, true, edge, outline_width)
		return
	var closed := polygon.duplicate()
	closed.append(polygon[0])
	draw_polyline(closed, edge, outline_width, true)

## A fan or strip piece: fill (a straight gradient when its group has one on, else flat), then outline (a straight
## gradient when the edge gradient is on, else the flat edge colour). `length` is the action's reach; the gradients run
## from the origin along `direction` to linear_gradient_reach of it.
func _draw_look_area(polygon: PackedVector2Array, look: Look, direction: Vector2, length: float) -> void:
	if _linear_gradient_on(look) and length > 0.0:
		_fill_linear_gradient(polygon, direction, length * linear_gradient_reach, _linear_start(look), _linear_end(look), _linear_steps(look))
	else:
		_fill_polygon(polygon, _fill_for(look))
	_draw_look_outline(polygon, look, direction, length)

## The outline of a fan or strip piece (or the arrowhead): flat edge colour, or its straight edge gradient.
func _draw_look_outline(polygon: PackedVector2Array, look: Look, direction: Vector2, length: float) -> void:
	if _edge_gradient_on(look) and length > 0.0:
		_draw_outline_linear(polygon, direction, length * linear_gradient_reach, _edge_start(look), _edge_end(look), _edge_steps(look))
	else:
		_draw_polygon_outline(polygon, _edge_for(look))

## The arrowhead, clipped to the reach: flat head colour, outlined like the arrow.
func _draw_clipped_head(head: PackedVector2Array) -> void:
	for clipped in clip_polygon_to_range(head, _range_radius):
		if clipped.size() >= 3:
			_fill_polygon(clipped, arrow_head_color)
			_draw_look_outline(clipped, Look.ARROW, _direction, _range_radius)

## The aim area clipped to the action's reach, each piece drawn with _draw_look_area.
func _draw_clipped_look(outline: PackedVector2Array, look: Look) -> void:
	for clipped in clip_polygon_to_range(outline, _range_radius):
		if clipped.size() >= 3:
			_draw_look_area(clipped, look, _direction, _range_radius)

func _linear_gradient_on(look: Look) -> bool:
	match look:
		Look.FAN:
			return fan_gradient
		Look.ARROW:
			return arrow_gradient
		Look.RECTANGLE:
			return rectangle_gradient
	return false

func _linear_start(look: Look) -> Color:
	match look:
		Look.ARROW:
			return arrow_gradient_start_color
		Look.RECTANGLE:
			return rectangle_gradient_start_color
	return fan_gradient_start_color

func _linear_end(look: Look) -> Color:
	match look:
		Look.ARROW:
			return arrow_gradient_end_color
		Look.RECTANGLE:
			return rectangle_gradient_end_color
	return fan_gradient_end_color

func _edge_gradient_on(look: Look) -> bool:
	match look:
		Look.FAN:
			return fan_edge_gradient
		Look.ARROW:
			return arrow_edge_gradient
		Look.RECTANGLE:
			return rectangle_edge_gradient
	return false

func _edge_start(look: Look) -> Color:
	match look:
		Look.ARROW:
			return arrow_edge_gradient_start_color
		Look.RECTANGLE:
			return rectangle_edge_gradient_start_color
	return fan_edge_gradient_start_color

func _edge_end(look: Look) -> Color:
	match look:
		Look.ARROW:
			return arrow_edge_gradient_end_color
		Look.RECTANGLE:
			return rectangle_edge_gradient_end_color
	return fan_edge_gradient_end_color

func _edge_steps(look: Look) -> int:
	match look:
		Look.ARROW:
			return arrow_edge_gradient_steps
		Look.RECTANGLE:
			return rectangle_edge_gradient_steps
	return fan_edge_gradient_steps

func _linear_steps(look: Look) -> int:
	match look:
		Look.ARROW:
			return arrow_gradient_steps
		Look.RECTANGLE:
			return rectangle_gradient_steps
	return fan_gradient_steps

## `polygon` filled with a straight gradient: `start_color` at the origin to `end_color` at `span` pixels along
## `direction` (flat beyond both ends). No outline. Smooth: colours per corner, exact because the colour is a linear
## function of position. Pixelated: `bands` flat bands of cells.
func _fill_linear_gradient(polygon: PackedVector2Array, direction: Vector2, span: float, start_color: Color, end_color: Color, bands: int) -> void:
	if polygon.size() < 3 or span <= 0.0:
		return
	var axis := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	if pixelate:
		_draw_runs_linear(pixel_polygon_runs(polygon, float(pixel_size)), axis, span, start_color, end_color, bands)
	else:
		_draw_smooth_linear(polygon, axis, span, start_color, end_color)

## The closed outline of `polygon` coloured by a straight gradient, like _fill_linear_gradient. Smooth: a polyline with
## a colour on each point, with extra points where an edge crosses the start and the end so the colour stays flat
## beyond them. Pixelated: each outline cell takes the colour of its band.
func _draw_outline_linear(polygon: PackedVector2Array, direction: Vector2, span: float, start_color: Color, end_color: Color, bands: int) -> void:
	if outline_width <= 0.0 or polygon.size() < 2 or span <= 0.0:
		return
	var axis := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	if pixelate:
		var size := float(pixel_size)
		var steps := maxi(bands, 2)
		for cell in pixel_line_cells(polygon, true, size, maxi(1, roundi(outline_width / size))):
			var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * size
			var band := mini(int(clampf(centre.dot(axis) / span, 0.0, 1.0) * float(steps)), steps - 1)
			draw_rect(Rect2(Vector2(cell) * size, Vector2(size, size)), start_color.lerp(end_color, float(band) / float(steps - 1)))
		return
	var points := PackedVector2Array()
	var count := polygon.size()
	for i in count:
		var from := polygon[i]
		var to := polygon[(i + 1) % count]
		points.append(from)
		var from_d := from.dot(axis)
		var to_d := to.dot(axis)
		var crossings: Array[float] = []
		for stop in [0.0, span]:
			if (from_d < stop and to_d > stop) or (from_d > stop and to_d < stop):
				crossings.append((stop - from_d) / (to_d - from_d))
		crossings.sort()
		for fraction in crossings:
			points.append(from.lerp(to, fraction))
	points.append(polygon[0])
	var colors := PackedColorArray()
	for point in points:
		colors.append(start_color.lerp(end_color, clampf(point.dot(axis) / span, 0.0, 1.0)))
	draw_polyline_colors(points, colors, outline_width, true)

## Absolute area of a simple polygon (shoelace formula).
func _polygon_area(points: PackedVector2Array) -> float:
	var total := 0.0
	var count := points.size()
	for i in count:
		total += points[i].cross(points[(i + 1) % count])
	return absf(total) * 0.5

## The polygon is cut at the origin and at `span` along the axis: the part behind the start is flat start colour, the
## part beyond the end flat end colour, and the middle part gets a colour on each corner.
func _draw_smooth_linear(polygon: PackedVector2Array, axis: Vector2, span: float, start_color: Color, end_color: Color) -> void:
	var side := axis.orthogonal()
	for part in 3:
		var from_d := -SLAB_HALF if part == 0 else (0.0 if part == 1 else span)
		var to_d := 0.0 if part == 0 else (span if part == 1 else SLAB_HALF)
		var slab := PackedVector2Array([axis * from_d - side * SLAB_HALF, axis * from_d + side * SLAB_HALF, axis * to_d + side * SLAB_HALF, axis * to_d - side * SLAB_HALF])
		for piece in Geometry2D.intersect_polygons(polygon, slab):
			# A sliver with (almost) no area cannot be triangulated; it happens when an edge lies on the cut line.
			if piece.size() < 3 or _polygon_area(piece) < MIN_FILL_AREA:
				continue
			if part == 1:
				var colors := PackedColorArray()
				for point in piece:
					colors.append(start_color.lerp(end_color, clampf(point.dot(axis) / span, 0.0, 1.0)))
				draw_polygon(piece, colors)
			else:
				draw_colored_polygon(piece, start_color if part == 0 else end_color)

## Cells of a polygon (runs from pixel_polygon_runs) coloured by where their centre falls along the axis: `bands`
## equal bands over `span`, flat beyond. Neighbouring cells of one band are drawn as one rectangle.
func _draw_runs_linear(runs: Array[Vector3i], axis: Vector2, span: float, start_color: Color, end_color: Color, bands: int) -> void:
	var size := float(pixel_size)
	var steps := maxi(bands, 2)
	for run in runs:
		var y := (float(run.x) + 0.5) * size
		var current := -1
		var first := run.y
		for column in range(run.y, run.z + 1):
			var t := clampf(Vector2((float(column) + 0.5) * size, y).dot(axis) / span, 0.0, 1.0)
			var band := mini(int(t * float(steps)), steps - 1)
			if band != current:
				if current >= 0:
					_draw_cells(run.x, first, column - 1, start_color.lerp(end_color, float(current) / float(steps - 1)))
				current = band
				first = column
		if current >= 0:
			_draw_cells(run.x, first, run.z, start_color.lerp(end_color, float(current) / float(steps - 1)))

func _draw_cells(row: int, first_column: int, last_column: int, color: Color) -> void:
	var size := float(pixel_size)
	draw_rect(Rect2(float(first_column) * size, float(row) * size, float(last_column - first_column + 1) * size, size), color)

## The cross in the middle of a self or placed circle, at `center`. Smooth lines, or cells when pixelated.
func _paint_circle_cross(center: Vector2) -> void:
	if not show_circle_cross or circle_cross_size <= 0.0:
		return
	var arm := circle_cross_size
	var strokes: Array[PackedVector2Array] = []
	if circle_cross_style == CrossStyle.X:
		var diagonal := arm * 0.70710678
		strokes.append(PackedVector2Array([center + Vector2(-diagonal, -diagonal), center + Vector2(diagonal, diagonal)]))
		strokes.append(PackedVector2Array([center + Vector2(-diagonal, diagonal), center + Vector2(diagonal, -diagonal)]))
	else:
		strokes.append(PackedVector2Array([center + Vector2(-arm, 0.0), center + Vector2(arm, 0.0)]))
		strokes.append(PackedVector2Array([center + Vector2(0.0, -arm), center + Vector2(0.0, arm)]))
	var width := maxf(outline_width, 1.0)
	for stroke in strokes:
		if pixelate:
			_draw_pixel_polyline(stroke, false, circle_cross_color, width)
		else:
			draw_line(stroke[0], stroke[1], circle_cross_color, width, true)

## Half a step of turn is added so no point sits exactly on an axis: a point on a cell boundary would, when pixelated, add
## one stray cell on two sides of the circle only.
func _circle_points(center: Vector2, radius: float, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in steps:
		points.append(center + Vector2.RIGHT.rotated(TAU * (float(i) + 0.5) / float(steps)) * radius)
	return points

## --- Pixelation: everything below is plain geometry on a grid of `size`-pixel cells, cell (column, row) covering
## [column * size, (column + 1) * size] by the same for the row. A cell belongs to an area when its centre is inside it. ---

func _draw_runs(runs: Array[Vector3i], color: Color) -> void:
	var size := float(pixel_size)
	for run in runs:
		draw_rect(Rect2(float(run.y) * size, float(run.x) * size, float(run.z - run.y + 1) * size, size), color)

func _draw_pixel_polyline(points: PackedVector2Array, closed: bool, color: Color, width: float) -> void:
	var size := float(pixel_size)
	for cell in pixel_line_cells(points, closed, size, maxi(1, roundi(width / size))):
		draw_rect(Rect2(Vector2(cell) * size, Vector2(size, size)), color)

## The first and last column whose cell centre lies strictly inside (center_x - half_width, center_x + half_width).
## Empty (first above last) when none does.
static func cell_columns(center_x: float, half_width: float, size: float) -> Vector2i:
	return Vector2i(floori((center_x - half_width) / size - 0.5) + 1, ceili((center_x + half_width) / size - 0.5) - 1)

## The x positions where the horizontal line at `y` crosses the polygon's edges, sorted. Pairs of them (first and second,
## third and fourth...) bound the stretches of the line inside the polygon.
static func polygon_crossings(polygon: PackedVector2Array, y: float) -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	var count := polygon.size()
	for i in count:
		var a := polygon[i]
		var b := polygon[(i + 1) % count]
		if (a.y <= y) != (b.y <= y):
			xs.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
	xs.sort()
	return xs

## The cells inside `polygon`, one run per stretch of a row: Vector3i(row, first column, last column).
static func pixel_polygon_runs(polygon: PackedVector2Array, size: float) -> Array[Vector3i]:
	var runs: Array[Vector3i] = []
	if polygon.size() < 3 or size <= 0.0:
		return runs
	var top := polygon[0].y
	var bottom := polygon[0].y
	for point in polygon:
		top = minf(top, point.y)
		bottom = maxf(bottom, point.y)
	for row in range(ceili(top / size - 0.5), floori(bottom / size - 0.5) + 1):
		var xs := polygon_crossings(polygon, (float(row) + 0.5) * size)
		for i in range(0, xs.size() - 1, 2):
			var columns := cell_columns((xs[i] + xs[i + 1]) * 0.5, (xs[i + 1] - xs[i]) * 0.5, size)
			if columns.x <= columns.y:
				runs.append(Vector3i(row, columns.x, columns.y))
	return runs

## The cells whose centre is at least `r_in` and below `r_out` from `center` (a disc when r_in is 0), as runs like
## pixel_polygon_runs. Bands that share a radius never share a cell, so they can be stacked without gaps or overlap.
static func pixel_annulus_runs(center: Vector2, r_in: float, r_out: float, size: float) -> Array[Vector3i]:
	var runs: Array[Vector3i] = []
	if r_out <= 0.0 or size <= 0.0:
		return runs
	for row in range(ceili((center.y - r_out) / size - 0.5), floori((center.y + r_out) / size - 0.5) + 1):
		var dy := (float(row) + 0.5) * size - center.y
		if absf(dy) >= r_out:
			continue
		var outer := cell_columns(center.x, sqrt(r_out * r_out - dy * dy), size)
		if outer.x > outer.y:
			continue
		var inner := Vector2i(1, 0)
		if r_in > 0.0 and absf(dy) < r_in:
			inner = cell_columns(center.x, sqrt(r_in * r_in - dy * dy), size)
		if inner.x > inner.y:
			runs.append(Vector3i(row, outer.x, outer.y))
			continue
		if inner.x > outer.x:
			runs.append(Vector3i(row, outer.x, inner.x - 1))
		if inner.y < outer.y:
			runs.append(Vector3i(row, inner.y + 1, outer.y))
	return runs

## The cells a line (or a closed outline) passes through, each `thickness` cells thick and listed once, so a
## translucent colour is not drawn twice where stamps overlap.
static func pixel_line_cells(points: PackedVector2Array, closed: bool, size: float, thickness: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if points.size() < 2 or size <= 0.0:
		return cells
	var seen := {}
	var low := -int(float(thickness - 1) * 0.5)
	var edges := points.size() if closed else points.size() - 1
	for i in edges:
		var from := points[i]
		var to := points[(i + 1) % points.size()]
		var steps := maxi(1, ceili(from.distance_to(to) / (size * 0.5)))
		for step in steps + 1:
			var at := from.lerp(to, float(step) / float(steps))
			var column := floori(at.x / size) + low
			var row := floori(at.y / size) + low
			for dx in thickness:
				for dy in thickness:
					var cell := Vector2i(column + dx, row + dy)
					if not seen.has(cell):
						seen[cell] = true
						cells.append(cell)
	return cells

## --- Editor preview. Editor only: the shape classes are not @tool, so the samples below are plain geometry, but every
## fill, outline, gradient, ring and pixel cell goes through the very same paint functions the game uses. ---

## Draws what `preview_shape` says: one shape at full size, or all of them side by side.
func _draw_editor_preview() -> void:
	if preview_shape == PreviewShape.ALL:
		var order: Array[PreviewShape] = [PreviewShape.FAN, PreviewShape.ARROW, PreviewShape.RECTANGLE, PreviewShape.SELF_CIRCLE, PreviewShape.PLACED_CIRCLE]
		for i in order.size():
			var column := i % 3
			var row := floori(float(i) / 3.0)
			_draw_preview_tile(order[i], Vector2((float(column) - 1.0) * 230.0, -105.0 + float(row) * 210.0), PREVIEW_TILE_RANGE)
	else:
		_draw_preview_tile(preview_shape, Vector2.ZERO, PREVIEW_RANGE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## One sample shape with the caster at `origin`, as the game would draw it for an action of reach `reach`.
func _draw_preview_tile(which: PreviewShape, origin: Vector2, reach: float) -> void:
	draw_set_transform(origin, 0.0, Vector2.ONE)
	_range_radius = reach  # the texture helper clips and scales to the reach
	var length := reach  # the strip and fan reach the edge of the range circle
	var label := ""
	var candidate_at := Vector2.ZERO
	var picked_at := Vector2.ZERO
	match which:
		PreviewShape.FAN:
			label = "Fan"
			if show_range_circle:
				_paint_range_circle(Vector2.ZERO, reach)
			var fan := PackedVector2Array([Vector2.ZERO])
			for i in range(-6, 7):
				fan.append(Vector2.RIGHT.rotated(deg_to_rad(float(i) * 7.5)) * length)
			_paint_preview_area(fan, Look.FAN)
			candidate_at = Vector2(length * 0.6, -length * 0.1)
			picked_at = Vector2(length * 0.75, length * 0.15)
		PreviewShape.ARROW, PreviewShape.RECTANGLE:
			var is_arrow := which == PreviewShape.ARROW
			label = "Arrow" if is_arrow else "Rectangle"
			if show_range_circle:
				_paint_range_circle(Vector2.ZERO, reach)
			var drawn_width := PREVIEW_STRIP_WIDTH * (arrow_width_scale if is_arrow else rectangle_width_scale)
			_paint_preview_area(strip_outline(Vector2.RIGHT, length, drawn_width), Look.ARROW if is_arrow else Look.RECTANGLE)
			if is_arrow:
				var head := strip_head_outline(Vector2.RIGHT, length, drawn_width)
				if head.size() >= 3:
					_fill_polygon(head, arrow_head_color)
					_draw_look_outline(head, Look.ARROW, Vector2.RIGHT, _range_radius)
			candidate_at = Vector2(length * 0.45, 0.0)
			picked_at = Vector2(length * 0.8, 0.0)
		PreviewShape.SELF_CIRCLE:
			label = "Self circle"
			# The game skips the range circle here: the shape already is that circle.
			var radius := reach * 0.75
			_paint_circle_area(Vector2.ZERO, radius, reach)
			_paint_circle_cross(Vector2.ZERO)
			candidate_at = Vector2(radius * 0.5, -radius * 0.2)
			picked_at = Vector2(-radius * 0.2, radius * 0.45)
		PreviewShape.PLACED_CIRCLE:
			label = "Placed circle"
			if show_range_circle:
				_paint_range_circle(Vector2.ZERO, reach)
			var spot := Vector2(reach * 0.55, 0.0)
			var radius := reach * 0.38
			_draw_guide_line(Vector2.ZERO, spot)
			_paint_circle_area(spot, radius, reach)
			_paint_circle_cross(spot)
			candidate_at = spot + Vector2(-radius * 0.3, -radius * 0.35)
			picked_at = spot + Vector2(radius * 0.25, radius * 0.3)
	if preview_show_targets:
		_paint_target_ring(candidate_at, false)
		_paint_target_ring(picked_at, true)
	draw_string(ThemeDB.fallback_font, Vector2(-reach, reach + 22.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(1.0, 1.0, 1.0, 0.55))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## A fan or strip sample: its art when it has some, else the flat fill and outline of its group.
func _paint_preview_area(outline: PackedVector2Array, look: Look) -> void:
	var texture := _texture_for_look(look)
	if texture != null:
		_draw_shape_texture(texture, outline, _fill_for(look))
	else:
		_draw_look_area(outline, look, Vector2.RIGHT, _range_radius)

## A circle sample (self or placed): its art, else the gradient, else the flat fill of the Circle group.
func _paint_circle_area(center: Vector2, radius: float, uv_span: float) -> void:
	if radius <= 0.0:
		return
	if area_texture != null:
		var ring := _circle_points(center, radius, RANGE_POINTS)
		var uvs := PackedVector2Array()
		for point in ring:
			uvs.append(Vector2(0.5, 0.5) + (point - center) / maxf(uv_span * 2.0, 0.001) * texture_scale)
		draw_polygon(ring, PackedColorArray([circle_fill_color]), uvs, area_texture)
	elif circle_gradient:
		_paint_circle_gradient(center, radius)
	else:
		_draw_polygon_area(_circle_points(center, radius, RANGE_POINTS), circle_fill_color, circle_edge_color)

## The strip geometry of LineAimShape2D, for the preview only (that class is not a tool script). Corners match
## LineAimShape2D.get_outline_at_width and get_head_outline_at_width.
static func strip_outline(direction: Vector2, length: float, drawn_width: float) -> PackedVector2Array:
	var outline := PackedVector2Array()
	if length <= 0.0 or drawn_width <= 0.0:
		return outline
	var axis := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	var side := axis.orthogonal() * drawn_width * 0.5
	var far := axis * length
	outline.append_array(PackedVector2Array([-side, side, far + side, far - side]))
	return outline

static func strip_head_outline(direction: Vector2, length: float, drawn_width: float) -> PackedVector2Array:
	var head := PackedVector2Array()
	if length <= 0.0 or drawn_width <= 0.0:
		return head
	var axis := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	var side := axis.orthogonal() * drawn_width * 0.5
	var head_length := minf(drawn_width, length)
	head.append_array(PackedVector2Array([axis * length, axis * (length - head_length) + side, axis * (length - head_length) - side]))
	return head
