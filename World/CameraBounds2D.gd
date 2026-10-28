extends Node
class_name CameraBounds2D
## H7.3: keeps the player's camera inside the world. The world is the outline of a Polygon2D (the arena floor): this
## node reads it once and sets the camera's limits to its bounds, so the view never shows past the floor at any window
## shape. It does not change the zoom. Edit the floor and the limits follow.
##
## With stretch aspect `expand` the visible world is (viewport size / zoom): the height stays 720 on a wide window
## and the width stays 1280 on a tall one. See docs/trackH/H7.2-H7.3-notes.md for the shapes that fit.

## The Polygon2D whose outline is the playable world.
@export var floor_path: NodePath
## The group of the character whose Camera2D is limited, and that camera's node name.
@export var camera_owner_group: StringName = &"player"
@export var camera_name: StringName = &"Camera2D"

func _ready() -> void:
	apply()

## Sets the limits now. Returns false (and changes nothing) when the floor or the camera is missing.
func apply() -> bool:
	var floor_polygon := get_node_or_null(floor_path) as Polygon2D
	var owner_node := get_tree().get_first_node_in_group(camera_owner_group)
	var camera := owner_node.get_node_or_null(NodePath(camera_name)) as Camera2D if owner_node != null else null
	if floor_polygon == null or camera == null:
		push_warning("CameraBounds2D needs a Polygon2D at floor_path and a Camera2D on the '%s' character." % camera_owner_group)
		return false
	var bounds := rect_of(floor_polygon)
	camera.limit_left = floori(bounds.position.x)
	camera.limit_top = floori(bounds.position.y)
	camera.limit_right = ceili(bounds.end.x)
	camera.limit_bottom = ceili(bounds.end.y)
	return true

## The world-space bounding rectangle of a polygon (its transform included). Empty polygon: an empty Rect2.
static func rect_of(polygon: Polygon2D) -> Rect2:
	if polygon.polygon.is_empty():
		return Rect2()
	var to_world := polygon.global_transform if polygon.is_inside_tree() else polygon.transform
	var first: Vector2 = to_world * polygon.polygon[0]
	var bounds := Rect2(first, Vector2.ZERO)
	for point in polygon.polygon:
		bounds = bounds.expand(to_world * point)
	return bounds
