extends "res://Characters/Core/Character2D.gd"
class_name BasicEnemy2D
## Reused goblin enemy form: simple health/death plus configurable target AI.

signal health_changed(current_health: int, maximum_health: int)
signal died

@export_range(1, 1000, 1) var max_health: int = 3

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _ai_controller: EnemyAIController2D = $EnemyAIController2D

var health: int = 0
var _hit_tween: Tween

func _ready() -> void:
	super._ready()
	health = maxi(max_health, 1)
	add_to_group("enemy")
	add_to_group("damageable")
	_ai_controller.initialize(self)
	if _animated_sprite.sprite_frames != null and _animated_sprite.sprite_frames.has_animation(&"idle"):
		_animated_sprite.play(&"idle")
	health_changed.emit(health, max_health)

func _physics_process(delta: float) -> void:
	if health <= 0:
		return
	_ai_controller.physics_update(delta)
	super._physics_process(delta)

func _get_movement_input() -> Vector2:
	return _ai_controller.get_movement_intent()

func _get_aim_direction() -> Vector2:
	return _ai_controller.get_aim_direction()

func _get_attack_requested() -> bool:
	return _ai_controller.consume_attack_request()

func _get_attack_direction() -> Vector2:
	return _ai_controller.get_attack_direction()

func _get_dash_requested() -> bool:
	return false

func is_alive() -> bool:
	return health > 0

func take_damage(amount: int) -> void:
	if health <= 0 or amount <= 0:
		return
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	if health <= 0:
		died.emit()
		if is_instance_valid(attack_component):
			attack_component.cancel()
		if is_instance_valid(dash_component):
			dash_component.cancel()
		queue_free()
		return
	_play_hit_feedback()

func _play_hit_feedback() -> void:
	# Tween-driven flash/shake leaves AnimatedSprite2D's frame animation in control.
	if not is_instance_valid(_animated_sprite):
		return
	if is_instance_valid(_hit_tween) and _hit_tween.is_running():
		_hit_tween.kill()
	_animated_sprite.position = Vector2.ZERO
	_animated_sprite.modulate = Color.WHITE
	_hit_tween = create_tween()
	_hit_tween.tween_property(_animated_sprite, "modulate", Color(2.2, 2.2, 2.2, 1.0), 0.045)
	_hit_tween.tween_property(_animated_sprite, "modulate", Color.WHITE, 0.12)
	_hit_tween.parallel().tween_property(_animated_sprite, "position", Vector2(-2, 0), 0.045)
	_hit_tween.tween_property(_animated_sprite, "position", Vector2.ZERO, 0.09)
