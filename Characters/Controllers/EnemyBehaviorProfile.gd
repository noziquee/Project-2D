extends Resource
class_name EnemyBehaviorProfile
## Tuning for EnemyAIController2D. One resource per enemy kind; the swing distance is not
## here, it comes from the attack definition (AttackDefinition2D.ai_attack_range).

## Radius of the detection circle. 0 (default) keeps the CircleShape2D exactly as drawn on
## the enemy's DetectionArea, so the radius can be changed by dragging it in the 2D view.
## A value above 0 overrides the drawn shape for this enemy kind.
@export_range(0.0, 2000.0, 1.0) var detection_radius: float = 0.0
## A target that is already being chased is only dropped beyond this distance.
@export_range(1.0, 2500.0, 1.0) var disengage_radius: float = 250.0
## How long a target may stay beyond disengage_radius before the enemy gives up.
@export_range(0.0, 5.0, 0.05) var lost_target_grace_duration: float = 0.75
## The enemy counts as home (and goes idle) once it is this close to its start position.
@export_range(0.0, 100.0, 1.0) var home_stop_distance: float = 5.0
