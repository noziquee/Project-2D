extends Resource
class_name AttackChoice2D
## One entry of EnemyBehaviorProfile.attack_choices: an attack the AI may pick, and how
## likely it is relative to the other entries.

## The attack to use. It must also be registered on the enemy's AttackComponent2D (its default
## attack or an entry of `attacks`), because the AI starts attacks by id; an entry that is not
## registered is ignored with a warning.
@export var attack: AttackDefinition2D
## Relative chance of this entry: 3 is picked three times as often as 1. 0 disables it.
@export_range(0.0, 100.0, 0.1) var weight: float = 1.0
