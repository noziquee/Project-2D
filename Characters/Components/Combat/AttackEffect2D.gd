extends Node2D
class_name AttackEffect2D
## Base class of every effect scene an attack can spawn (10.2): the melee slash today, projectiles and area
## effects later. AttackComponent2D only knows this class, so a new kind of attack is a new subclass that
## keeps the same configure(...) signature, never a change to the attack component.
##
## This class owns the part every effect shares: the attack numbers handed over by configure(), the signals,
## the target filter (not the attacker, can take a hit, not the same team), hit-once tracking and the HitData
## call into apply_hit(). A subclass decides WHEN it can hit (_can_hit), WHERE the hit area is
## (_get_hit_origin) and how it finds targets, then calls _try_hit(target) for each body it touches.

signal hit_confirmed(target: Node, damage: int)
## Emitted just before hit_confirmed with the world position where the hit landed
## (halfway between the hit area and the target), for impact effects.
signal hit_contact(target: Node, damage: int, point: Vector2)

const DEFAULT_ANIMATION := &"slash"

var source: Node2D
var damage: int = 1
var direction: Vector2 = Vector2.RIGHT
var hitbox_size: Vector2 = Vector2(16.0, 16.0)
var hitbox_offset: Vector2 = Vector2.ZERO
## Physics layers the hit area looks at. -1 keeps the mask set in the scene.
var hit_layers: int = -1
var knockback: float = 0.0
var hit_stun: float = 0.0
## The clip this effect plays and ends with (the attack's effect_animation).
var effect_animation: StringName = DEFAULT_ANIMATION
## Hit policy (10.4). max_targets: the most different targets this effect can hit (0 = no limit). pierce: when
## false the effect is spent by its first target. Defaults keep the old behavior: hit everything it touches, once each.
var max_targets: int = 0
var pierce: bool = true
## Flight speed in px/s for effects that move (11.2). 0 = the effect keeps its own default. Melee ignores it.
var projectile_speed: float = 0.0
## Critical hit numbers and statuses of the attack (12.3, 12.4), copied onto every HitData this effect makes.
var crit_chance: float = 0.0
var crit_multiplier: float = 2.0
var status_effects: Array = []

## Targets this effect has already hit. One effect hits each target once.
var _hit_targets: Dictionary = {}
## True once the hit policy says this effect can hit nothing more. _on_spent() is called at that moment.
var _spent := false

func is_spent() -> bool:
	return _spent

## Call before adding the effect to the tree. Every subclass takes the same arguments.
func configure(attacker: Node2D, damage_amount: int, aim_direction: Vector2, shape_size: Vector2, origin_offset: Vector2, layers: int = -1, knockback_strength: float = 0.0, stun_seconds: float = 0.0, animation: StringName = DEFAULT_ANIMATION, max_target_count: int = 0, pierces: bool = true, flight_speed: float = 0.0, critical_chance: float = 0.0, critical_multiplier: float = 2.0, statuses: Array = []) -> void:
	source = attacker
	damage = maxi(damage_amount, 0)
	direction = aim_direction.normalized() if aim_direction.length_squared() > 0.0001 else Vector2.RIGHT
	hitbox_size = Vector2(maxf(shape_size.x, 1.0), maxf(shape_size.y, 1.0))
	hitbox_offset = origin_offset
	hit_layers = layers
	knockback = maxf(knockback_strength, 0.0)
	hit_stun = maxf(stun_seconds, 0.0)
	effect_animation = animation if animation != &"" else DEFAULT_ANIMATION
	max_targets = maxi(max_target_count, 0)
	pierce = pierces
	projectile_speed = maxf(flight_speed, 0.0)
	crit_chance = clampf(critical_chance, 0.0, 1.0)
	crit_multiplier = maxf(critical_multiplier, 1.0)
	status_effects = statuses

## Override: true while the effect is allowed to hit (for the slash, its hit window is open).
func _can_hit() -> bool:
	return true

## Override: world position of the hit area, used for the contact point of an impact.
func _get_hit_origin() -> Vector2:
	return global_position

## Override: called once when the hit policy is used up. A projectile frees itself here; a slash lets its
## animation play out (its hit window simply cannot hit anything more).
func _on_spent() -> void:
	pass

## Applies this effect's hit to `target` when it is a valid, enemy, not yet hit target.
func _try_hit(target: Node) -> void:
	if (
		_spent
		or not is_instance_valid(target)
		or not _can_hit()
		or target == source
		or not (target.has_method("apply_hit") or target.has_method("take_damage"))
	):
		return
	if _is_same_team(target):
		return
	var target_id := target.get_instance_id()
	if _hit_targets.has(target_id):
		return
	_hit_targets[target_id] = true
	# Read the contact point first: the hit may kill and free the target.
	var point := _contact_point(target)
	if target.has_method("apply_hit"):
		var hit := HitData.new(damage, source, direction, knockback, hit_stun)
		hit.crit_chance = crit_chance
		hit.crit_multiplier = crit_multiplier
		hit.statuses = status_effects
		var dealt := int(target.call("apply_hit", hit))
		if dealt > 0:
			hit_contact.emit(target, dealt, point)
			hit_confirmed.emit(target, dealt)
	else:
		target.call("take_damage", damage)
		hit_contact.emit(target, damage, point)
		hit_confirmed.emit(target, damage)
	_check_spent()

## Marks the effect spent when it has touched as many targets as its policy allows.
func _check_spent() -> void:
	var cap := max_targets if pierce else 1
	if cap > 0 and _hit_targets.size() >= cap:
		_spent = true
		_on_spent()

func _contact_point(target: Node) -> Vector2:
	var origin := _get_hit_origin()
	if target is Node2D:
		return origin.lerp((target as Node2D).global_position, 0.5)
	return origin

## Teams come from the `team` property on the attacker and the target. An empty team is
## neutral and can always be hit; two characters on the same non-empty team cannot hit
## each other. A new faction is just a new team name.
func _is_same_team(target: Node) -> bool:
	if not is_instance_valid(source):
		return false
	var source_team := Combatant2D.team_of(source)
	var target_team := Combatant2D.team_of(target)
	return source_team != &"" and source_team == target_team

## ---------- Scene checks (H3.2) ----------
## An effect scene can be wrong in ways that only show once an attack spawns it: a hitbox path that leads nowhere, a
## hit shape that is missing, a slash clip that never opens its hit window. These checks read the scene without running
## it, so a weapon with a bad effect scene is refused when it is equipped instead.

## Problems with this (not yet running) effect's own scene as readable messages. Each subclass adds its own. Empty = fine.
## `effect_clip` is the attack's effect_animation; only effects that play a clip look at it.
func get_scene_problems(_effect_clip: StringName) -> Array[String]:
	return []

## Things that work but probably are not what the author meant. Never a reason to refuse a scene.
func get_scene_warnings() -> Array[String]:
	return []

## Problems with the effect scene `scene`: it cannot be instantiated, its root is not an AttackEffect2D, or the root's own
## scene problems. An empty list for a null scene (a missing scene is reported where the attack is checked).
static func validate_scene(scene: PackedScene, effect_clip: StringName = &"") -> Array[String]:
	return _scene_messages(scene, effect_clip, false)

## The warnings of the effect scene `scene` (empty for a null or unusable scene).
static func scene_warnings(scene: PackedScene) -> Array[String]:
	return _scene_messages(scene, &"", true)

static func _scene_messages(scene: PackedScene, effect_clip: StringName, warnings: bool) -> Array[String]:
	var found: Array[String] = []
	if scene == null:
		return found
	if not scene.can_instantiate():
		if not warnings:
			found.append("the effect scene cannot be instantiated.")
		return found
	var instance := scene.instantiate()
	if instance is AttackEffect2D:
		var effect := instance as AttackEffect2D
		found.append_array(effect.get_scene_warnings() if warnings else effect.get_scene_problems(effect_clip))
	elif not warnings:
		found.append("the effect scene's root must be an AttackEffect2D (an AttackSlash2D, AreaEffect2D or ProjectileEffect2D), not a %s." % instance.get_class())
	instance.free()
	return found

func _effect_name() -> String:
	var effect_script := get_script() as Script
	return str(effect_script.get_global_name()) if effect_script != null and effect_script.get_global_name() != &"" else "effect"

## The hit area and its shape: both paths lead to the right kind of node and the shape exists.
func _hitbox_scene_problems(hitbox_np: NodePath, shape_np: NodePath) -> Array[String]:
	var found: Array[String] = []
	var area := get_node_or_null(hitbox_np) as Area2D
	if area == null:
		found.append("%s: hitbox_path '%s' does not lead to an Area2D." % [_effect_name(), hitbox_np])
	var shape_node := get_node_or_null(shape_np) as CollisionShape2D
	if shape_node == null:
		found.append("%s: collision_shape_path '%s' does not lead to a CollisionShape2D." % [_effect_name(), shape_np])
	elif shape_node.shape == null:
		found.append("%s: the CollisionShape2D at '%s' has no shape, so nothing can be hit." % [_effect_name(), shape_np])
	return found

## The effect resizes only one kind of shape from the attack's hitbox_size; any other kind is used exactly as drawn.
func _shape_scene_warnings(shape_np: NodePath, expected_class: String) -> Array[String]:
	var found: Array[String] = []
	var shape_node := get_node_or_null(shape_np) as CollisionShape2D
	if shape_node != null and shape_node.shape != null and shape_node.shape.get_class() != expected_class:
		found.append("%s: its hit shape is a %s, so the attack's hitbox_size does not resize it and the scene's own shape is used as drawn (a %s is resized)." % [_effect_name(), shape_node.shape.get_class(), expected_class])
	return found
