extends CharacterBody2D
class_name Character2D
## Shared action-RPG base. Controllers express intent; components execute actions.

const HealthComponentScript = preload("res://Characters/Components/Health/HealthComponent2D.gd")

signal health_changed(current_health: int, maximum_health: int)
signal damaged(hit: HitData)
signal died

## Which side this character is on. Attacks never hurt the attacker's own team; an empty
## team is neutral. Groups ("player", "enemy") are only used for target searches.
@export var team: StringName = &""
## How fast (px/s per second) knockback speed decays after a hit.
@export_range(0.0, 10000.0, 10.0) var knockback_friction: float = 1200.0

## Optional explicit references to the component nodes. Leave them empty to use the child
## nodes with the default names (MovementComponent2D, DashComponent2D, AttackComponent2D,
## HealthComponent2D, CharacterStateMachine). Per-character tuning (move_speed, dash values, attack_definition,
## max_health) lives on those nodes in the Scene dock.
@export_group("Components")
@export var movement_component: MovementComponent2D
@export var dash_component: DashComponent2D
@export var attack_component: AttackComponent2D
@export var health_component: HealthComponent2D
## Child node named "CharacterStateMachine" (its Idle/Move/Dash/Attack children are the states).
@export var state_machine: CharacterStateMachine
## Optional (9.7c-4): a child named "WeaponController2D". Only characters that can swap weapons (the
## player) have one; the goblin does not. Its starting_weapon is equipped when it is initialized.
@export var weapon_controller: WeaponController2D

var context: CharacterContext2D
## Read-through shim for tests; the attack component owns the value. Health is read from
## `health_component` (the Phase 4 `health` / `max_health` shims were removed in Phase 8).
var attack_definition: AttackDefinition2D:
	get:
		return attack_component.definition if is_instance_valid(attack_component) else null
	set(value):
		if is_instance_valid(attack_component):
			# The component rejects definitions that reference missing clips and keeps the old one.
			attack_component.set_attack_definition(value if value != null else AttackComponent2D.DEFAULT_ATTACK)

func _ready() -> void:
	context = CharacterContext2D.new(self)

	health_component = _resolve_component(health_component, "HealthComponent2D") as HealthComponent2D
	if health_component == null:
		push_warning("Character2D '%s' has no HealthComponent2D child; creating one with defaults." % name)
		health_component = HealthComponentScript.new() as HealthComponent2D
		health_component.name = "HealthComponent2D"
		add_child(health_component)
	health_component.health_changed.connect(_on_health_component_changed)
	health_component.damaged.connect(_on_health_component_damaged)
	health_component.died.connect(_on_health_component_died)

	movement_component = _resolve_component(movement_component, "MovementComponent2D") as MovementComponent2D
	dash_component = _resolve_component(dash_component, "DashComponent2D") as DashComponent2D
	attack_component = _resolve_component(attack_component, "AttackComponent2D") as AttackComponent2D
	state_machine = _resolve_component(state_machine, "CharacterStateMachine") as CharacterStateMachine
	weapon_controller = _resolve_component(weapon_controller, "WeaponController2D") as WeaponController2D
	var missing: Array[String] = []
	if movement_component == null:
		missing.append("MovementComponent2D")
	if dash_component == null:
		missing.append("DashComponent2D")
	if attack_component == null:
		missing.append("AttackComponent2D")
	if state_machine == null:
		missing.append("CharacterStateMachine")
	if not missing.is_empty():
		push_error("Character2D '%s' is missing required component node(s): %s. Add them as children in the scene. The character is disabled." % [name, ", ".join(missing)])
		set_physics_process(false)
		return
	# Components must not touch `context` in their own _ready() (children are ready before
	# this node); initialize() is where they receive it.
	movement_component.initialize(context)
	dash_component.initialize(context)
	attack_component.initialize(context)
	if is_instance_valid(weapon_controller):
		weapon_controller.initialize(context, attack_component)

	state_machine.initialize(context)

	if context.animated_sprite == null and context.character_animation_player == null:
		push_warning("Character2D '%s' has no recognized locomotion animation node." % name)

	health_changed.emit(health_component.health, health_component.max_health)

## Returns `current` if set, otherwise the child with the default name (or null).
func _resolve_component(current: Node, node_name: String) -> Node:
	return current if is_instance_valid(current) else get_node_or_null(node_name)

func _physics_process(delta: float) -> void:
	context.movement_input = _get_movement_input().normalized()
	context.hit_stun_remaining = maxf(context.hit_stun_remaining - delta, 0.0)
	context.knockback_velocity = context.knockback_velocity.move_toward(Vector2.ZERO, knockback_friction * delta)
	# Advance pre-existing timers before accepting new requests, avoiding a one-frame
	# cooldown/duration loss on the exact frame an action starts.
	dash_component.physics_update(delta)
	attack_component.physics_update(delta)
	_sample_attack_input(delta)
	_update_facing_direction()

	if is_alive() and not context.is_attacking:
		if dash_component.try_start(_get_dash_requested(), _get_dash_direction()):
			state_machine.transition_to(&"Dash")
	if is_alive() and not context.is_dashing:
		if _get_charge_release_requested() and attack_component.release_charge(_get_attack_direction()):
			state_machine.transition_to(&"Attack")
		var charge_id := _get_charge_begin_requested()
		if charge_id != &"" and attack_component.begin_charge(charge_id, _get_attack_direction()):
			state_machine.transition_to(&"Attack")
		if attack_component.try_start_attack(_get_attack_requested(), _get_attack_direction()):
			state_machine.transition_to(&"Attack")
			_update_facing_direction()

	movement_component.physics_update(delta)
	state_machine.physics_update(delta)

func _update_facing_direction() -> void:
	if context.movement_input.x < -0.001:
		context.movement_facing_direction = Vector2.LEFT
	elif context.movement_input.x > 0.001:
		context.movement_facing_direction = Vector2.RIGHT
	var visible_facing: Vector2 = context.movement_facing_direction
	if context.is_attacking and absf(context.attack_direction.x) > 0.001:
		visible_facing = Vector2.LEFT if context.attack_direction.x < 0.0 else Vector2.RIGHT
	context.facing_direction = visible_facing
	context.aim_direction = context.attack_direction if context.is_attacking else _get_aim_direction()

	if is_instance_valid(context.visual_root):
		var sx := absf(context.visual_root.scale.x)
		context.visual_root.scale.x = -sx if visible_facing.x < 0.0 else sx
		if context.animated_sprite != null:
			context.animated_sprite.flip_h = false
	if is_instance_valid(context.weapon_facing_root):
		var fx := absf(context.weapon_facing_root.scale.x)
		context.weapon_facing_root.scale.x = -fx if visible_facing.x < 0.0 else fx
	_update_weapon_aim()

## Rotates the weapon pivot toward the attack direction for attacks that set aim_weapon,
## and back to 0 otherwise. The pivot is mirrored on x when facing left, so the angle is
## measured from the mirrored forward axis: the authored right-facing arc is centred on
## the aim, and the mirror reflects it for the left.
func _update_weapon_aim() -> void:
	if not is_instance_valid(context.weapon_facing_root):
		return
	var rotation_target := 0.0
	if is_instance_valid(attack_component) and attack_component.is_aiming_weapon():
		var aim := context.attack_direction
		rotation_target = atan2(aim.y, aim.x) if context.facing_direction.x >= 0.0 else atan2(-aim.y, -aim.x)
	context.weapon_facing_root.rotation = rotation_target

## Called by a method track on this character's own weapon AnimationPlayer with the
## event name as the single argument, e.g. attack_event(&"spawn_effect").
func attack_event(event: StringName) -> void:
	if is_instance_valid(attack_component):
		attack_component.handle_event(event)

func is_alive() -> bool:
	return is_instance_valid(health_component) and health_component.is_alive()

## Applies a hit through the health component. Returns the damage actually dealt.
func apply_hit(hit: HitData) -> int:
	return health_component.apply_hit(hit) if is_instance_valid(health_component) else 0

## Shim for callers that only have a number. Prefer apply_hit().
func take_damage(amount: int) -> void:
	apply_hit(HitData.new(amount))

func heal(amount: int) -> int:
	return health_component.heal(amount) if is_instance_valid(health_component) else 0

## Presentation hook: called for every hit that deals damage, including the killing one
## (check is_alive()). Subclasses play hit reactions here.
func _on_damaged(_hit: HitData) -> void:
	pass

## Presentation hook: called once on death after the shared cleanup (attack and dash
## cancelled, velocity cleared). Subclasses play the death clip or free the node here.
func _on_death() -> void:
	pass

func _on_health_component_changed(current_health: int, maximum_health: int) -> void:
	health_changed.emit(current_health, maximum_health)

func _on_health_component_damaged(hit: HitData) -> void:
	_apply_hit_reaction(hit)
	damaged.emit(hit)
	_on_damaged(hit)

## Knockback, hit stun and swing interruption for a hit that did damage. A killing hit
## skips this: the death handler clears everything.
func _apply_hit_reaction(hit: HitData) -> void:
	if not is_alive():
		return
	if hit.knockback > 0.0 and hit.direction.length_squared() > 0.0001:
		context.knockback_velocity = hit.direction.normalized() * hit.knockback
	if hit.hit_stun > 0.0:
		context.hit_stun_remaining = maxf(context.hit_stun_remaining, hit.hit_stun)
	if is_instance_valid(attack_component):
		attack_component.interrupt()

func is_stunned() -> bool:
	return context != null and context.hit_stun_remaining > 0.0

func _on_health_component_died() -> void:
	died.emit()
	velocity = Vector2.ZERO
	context.knockback_velocity = Vector2.ZERO
	context.hit_stun_remaining = 0.0
	if is_instance_valid(attack_component):
		attack_component.cancel()
	if is_instance_valid(dash_component):
		dash_component.cancel()
	_update_weapon_aim()
	_on_death()

func _get_movement_input() -> Vector2:
	return Vector2.ZERO

func _get_dash_requested() -> bool:
	return false

func _get_dash_direction() -> Vector2:
	return context.movement_input if context != null else Vector2.ZERO

## Attack input sampled once per physics frame, before the attack hooks below are read.
## Controllers that do not charge keep these defaults (9.6c/9.6d).
func _sample_attack_input(_delta: float) -> void:
	pass

## The heavy attack this character wants to start charging this frame (empty for none).
func _get_charge_begin_requested() -> StringName:
	return &""

## True when the charge in progress should be released this frame.
func _get_charge_release_requested() -> bool:
	return false

## Which attack this character wants to start this frame: an attack id that
## AttackComponent2D.try_start_attack() understands, or an empty id for "none".
func _get_attack_requested() -> StringName:
	return &""

## Id of the attack component's default attack (empty if there is none). Controllers that
## have only one attack return this from _get_attack_requested().
func get_default_attack_id() -> StringName:
	return attack_component.definition.id if is_instance_valid(attack_component) and attack_component.definition != null else &""

func _get_aim_direction() -> Vector2:
	if context != null and context.movement_input.length_squared() > 0.0001:
		return context.movement_input
	return context.facing_direction if context != null else Vector2.RIGHT

func _get_attack_direction() -> Vector2:
	return _get_aim_direction()

func _exit_tree() -> void:
	if is_instance_valid(attack_component):
		attack_component.cancel()
	if is_instance_valid(dash_component):
		dash_component.cancel()
