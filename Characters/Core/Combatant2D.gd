class_name Combatant2D
extends RefCounted
## The one place that reads combat facts off "whatever dealt or received a hit" (H2.4): team, status controller, passive
## controller and health. A Character2D answers from its typed fields. Any other node (a test double, a future prop) is
## read by property name, once, here. Every helper is safe for null and for a freed instance, and returns the neutral
## value: an empty team, no controller, no health. The parameter is untyped on purpose: a typed Node parameter would
## reject an instance that was already freed.

## The character's team; &"" (neutral) for null, a freed node, or a node with no `team` property.
static func team_of(node) -> StringName:
	if not is_instance_valid(node):
		return &""
	if node is Character2D:
		return (node as Character2D).team
	var value: Variant = (node as Object).get("team")
	if typeof(value) == TYPE_STRING_NAME or typeof(value) == TYPE_STRING:
		return StringName(value)
	return &""

## The node's StatusController2D, or null when it has none, is freed, or is null itself.
static func status_controller_of(node) -> StatusController2D:
	if not is_instance_valid(node):
		return null
	var value: Variant = (node as Character2D).status_controller if node is Character2D else (node as Object).get("status_controller")
	return value as StatusController2D if is_instance_valid(value) and value is StatusController2D else null

## The node's PassiveController2D, or null when it has none, is freed, or is null itself.
static func passive_controller_of(node) -> PassiveController2D:
	if not is_instance_valid(node):
		return null
	var value: Variant = (node as Character2D).passive_controller if node is Character2D else (node as Object).get("passive_controller")
	return value as PassiveController2D if is_instance_valid(value) and value is PassiveController2D else null

## The node's HealthComponent2D: the node itself when it is one, a Character2D's health component, or a plain child
## named HealthComponent2D. Null when there is none.
static func health_of(node) -> HealthComponent2D:
	if not is_instance_valid(node):
		return null
	if node is HealthComponent2D:
		return node as HealthComponent2D
	if node is Character2D:
		var health := (node as Character2D).health_component
		return health if is_instance_valid(health) else null
	if node is Node:
		return (node as Node).get_node_or_null("HealthComponent2D") as HealthComponent2D
	return null
