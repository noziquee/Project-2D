extends Resource
class_name StatusEffectDefinition2D
## One status (bleed, burn...) as data (12.4). An attack applies it with its status_effects array; the target's
## StatusController2D runs it. Runtime state (time left, stacks) lives in the controller, never in this resource.

## What happens when the same status (same id) is applied again while it is still running.
enum StackRule {
	## The time left goes back to duration; the stack count stays at 1.
	REFRESH,
	## One more stack (up to max_stacks) and the time goes back to duration. Each tick does tick_damage x stacks.
	STACK,
	## The running status is left alone.
	IGNORE,
}

## Identifies the status. The same id on two definitions means the same status.
@export var id: StringName = &"status"
## Seconds the status runs. Must be above 0.
@export_range(0.1, 60.0, 0.1) var duration: float = 3.0
## Seconds between ticks. 0 = the status never ticks.
@export_range(0.0, 10.0, 0.05) var tick_interval: float = 1.0
## Damage of one tick per stack. Ignores defense and cannot crit. 0 = no tick damage.
@export_range(0, 1000, 1) var tick_damage: int = 1
@export var stack_rule: StackRule = StackRule.REFRESH
## The most stacks the STACK rule can reach.
@export_range(1, 20, 1) var max_stacks: int = 1
## Outgoing damage modifier of the character that carries the status (13.3.4). 1 = none, 1.5 = +50%, 0.5 = -50%. Each stack
## adds (damage_multiplier - 1) once, so two stacks of 1.25 give 1.5. The bonus applies to every hit that character lands
## (melee, projectile, area, skill) at the moment the hit is resolved, before crit and defense. Statuses that only tick
## (bleed) leave it at 1.
@export_range(0.0, 10.0, 0.05) var damage_multiplier: float = 1.0
