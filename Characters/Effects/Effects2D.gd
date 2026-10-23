extends RefCounted
class_name Effects2D
## Where one-shot visual effects (slashes, impacts, death bursts) are parented.
##
## Main.tscn has an `Effects` Node2D in the `effects_root` group. When a scene has none
## (tests, a character dropped into an empty scene) the current scene, then the caller's
## parent, is used instead.

const GROUP := &"effects_root"

## The node effects should be added to, or null if `from` is not in a tree.
static func get_host(from: Node) -> Node:
	if from == null or not from.is_inside_tree():
		return null
	var tree := from.get_tree()
	var host := tree.get_first_node_in_group(GROUP)
	if host == null:
		host = tree.current_scene
	if host == null:
		host = from.get_parent()
	return host

## Instantiates `scene` into the effects host at a world position. Returns the new node,
## or null when there is no scene, no host, or the scene root is not a Node2D.
static func spawn(scene: PackedScene, from: Node, world_position: Vector2) -> Node2D:
	if scene == null:
		return null
	var host := get_host(from)
	if host == null:
		return null
	var node := scene.instantiate() as Node2D
	if node == null:
		push_error("Effects2D: effect scene root must be a Node2D.")
		return null
	host.add_child(node)
	node.global_position = world_position
	return node
