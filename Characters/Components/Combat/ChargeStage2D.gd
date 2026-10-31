class_name ChargeStage2D
extends Resource
## RD6 step 3: one discrete level of a charge. An attack lists its stages in `AttackDefinition2D.charge_stages`; the stage a
## released shot takes is the one with the highest `at_ratio` that the charge has reached. A stage changes only what it sets
## here (damage, crit chance); reach, hitbox size and projectile look keep following their own settings.

## Display name, free to leave empty (a charge bar can show it).
@export var id: StringName = &""
## Charge ratio (0 to 1, the same ratio the reach uses) at which the stage starts.
@export_range(0.0, 1.0, 0.01) var at_ratio: float = 1.0
## The attack's damage is multiplied by this when the shot is released in this stage.
@export_range(0.1, 10.0, 0.05) var damage_multiplier: float = 1.0
## Added to the attack's crit_chance (the sum is capped at 1).
@export_range(0.0, 1.0, 0.01) var crit_chance_bonus: float = 0.0
