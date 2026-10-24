extends Character2D
class_name BasicEnemy2D
## Reused goblin enemy form: configurable target AI plus hit/death presentation.
## Health lives in the HealthComponent2D child (see Character2D). Groups ("enemy",
## "damageable") are set on the scene root in BasicEnemy2D.tscn.

## Spawned into the effects container where the enemy dies.
@export var death_effect_scene: PackedScene

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _ai_controller: EnemyAIController2D = $EnemyAIController2D

## Plays the authored take_damage flash. Its clip only animates modulate and position, so
## the idle/run frame animation keeps running underneath.
@onready var _hit_animation_player: AnimationPlayer = get_node_or_null("AnimatedSprite2D/AnimationPlayer") as AnimationPlayer

func _ready() -> void:
	super._ready()
	_ai_controller.initialize(self)
	if _animated_sprite.sprite_frames != null and _animated_sprite.sprite_frames.has_animation(&"idle"):
		_animated_sprite.play(&"idle")

func _physics_process(delta: float) -> void:
	if not is_alive():
		return
	_ai_controller.physics_update(delta)
	super._physics_process(delta)

func _get_movement_input() -> Vector2:
	return _ai_controller.get_movement_intent()

func _get_aim_direction() -> Vector2:
	return _ai_controller.get_aim_direction()

func _get_attack_requested() -> StringName:
	return _ai_controller.consume_attack_request()

func _get_attack_direction() -> Vector2:
	return _ai_controller.get_attack_direction()

func _get_dash_requested() -> bool:
	return false

func _on_damaged(_hit: HitData) -> void:
	if is_alive() and is_instance_valid(_hit_animation_player) and _hit_animation_player.has_animation(&"take_damage"):
		_hit_animation_player.play(&"take_damage")

func _on_death() -> void:
	Effects2D.spawn(death_effect_scene, self, global_position)
	queue_free()
