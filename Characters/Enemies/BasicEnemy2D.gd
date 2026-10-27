extends Character2D
class_name BasicEnemy2D
## Reused goblin enemy form: configurable target AI. Health lives in the HealthComponent2D child
## and the hit flash, death effect and freeing on death in the ReactionComponent2D child (P1; see
## Character2D). Groups ("enemy", "damageable") are set on the scene root in BasicEnemy2D.tscn.

@onready var _ai_controller: EnemyAIController2D = $EnemyAIController2D

func _ready() -> void:
	super._ready()
	_ai_controller.initialize(self)
	# The sprite comes from the context (P2), so a rig whose sprite is not named AnimatedSprite2D still works.
	var sprite := context.animated_sprite
	if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation(context.idle_clip):
		sprite.play(context.idle_clip)

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
