extends Resource
class_name PassiveDefinition2D
## One passive (14.1) as data: what it counts, how many it needs, and what it gives. Runtime state (the counter, the
## idle timer, whether the reward is waiting) lives in PassiveController2D, never here, because this resource is shared
## by every character that wields the weapon.
##
## The counter rules were written down in docs/phase14/14.0-notes.md before this class existed. In short:
##   - Only a hit of the wielder's basic or heavy attack counts (AttackComponent2D.attack_hit). Skill hits, status
##     ticks and misses do not.
##   - A swing counts at most once, however many targets it hits.
##   - The counter pauses while the reward is waiting or active, so rewards never overlap.
## Event passives (14.3) do not use the counter: HEAL_SELF and STATUS_ON_TARGET act on every target a basic or heavy
## attack hits, and DAMAGE_BONUS_LOW_HEALTH changes the damage of every hit the wielder lands (docs/phase14/14.3-notes.md).

enum Trigger {
	## A basic or heavy attack of the wielder lands on a target.
	ATTACK_HIT,
}

## What the passive does.
enum Effect {
	## Counter passive (14.2): after required_count qualifying swings, grant status_effect to the wielder.
	GRANT_STATUS,
	## Event passive: every target a basic or heavy attack hits heals the wielder by heal_amount.
	HEAL_SELF,
	## Event passive: every target a basic or heavy attack hits receives status_effect (bleed on hit).
	STATUS_ON_TARGET,
	## Event passive: a hit on a target whose health is at or below health_threshold (a fraction of its maximum) deals
	## damage x damage_multiplier, resolved with the other multipliers in CombatResolver2D.
	DAMAGE_BONUS_LOW_HEALTH,
}

## Identifies the passive on its weapon. Must not be empty and must be unique among the weapon's passives.
@export var id: StringName = &""
@export var display_name: String = ""
@export var trigger: Trigger = Trigger.ATTACK_HIT
@export var effect: Effect = Effect.GRANT_STATUS
## GRANT_STATUS only: qualifying swings needed to earn the reward. The counter then goes back to 0.
@export_range(1, 20, 1) var required_count: int = 3
## GRANT_STATUS only: seconds without a qualifying swing after which the counter goes back to 0. 0 = it never times out.
@export_range(0.0, 60.0, 0.1) var counter_window: float = 0.0
## GRANT_STATUS: the status granted to the wielder when the counter is reached. STATUS_ON_TARGET: the status put on each
## target hit. Required for those two effects (the 12.4 framework).
@export var status_effect: StatusEffectDefinition2D
## GRANT_STATUS only. True: the next attack that starts after the status was granted uses it up (the status ends when that swing ends, hit
## or miss). False: the status simply runs for its own duration.
@export var consumed_by_next_attack: bool = true

## HEAL_SELF: health restored per target hit. At least 1.
@export_range(0, 1000, 1) var heal_amount: int = 0
## DAMAGE_BONUS_LOW_HEALTH: the target's health fraction (0 to 1, compared with <=) at or below which the bonus applies.
@export_range(0.0, 1.0, 0.01) var health_threshold: float = 0.3
## DAMAGE_BONUS_LOW_HEALTH: the damage multiplier, above 1. It multiplies with other outgoing multipliers (buff statuses).
@export_range(1.0, 10.0, 0.05) var damage_multiplier: float = 1.5

## True for the counter passive (GRANT_STATUS); false for the event effects.
func uses_counter() -> bool:
	return effect == Effect.GRANT_STATUS

## Every reason this passive cannot work, as readable messages. Empty when it is valid. Changes nothing.
func validate() -> Array[String]:
	var problems: Array[String] = []
	var label := _label()
	if id == &"":
		problems.append("%s: has an empty id (every passive needs a unique id)." % label)
	if required_count < 1:
		problems.append("%s: required_count must be at least 1." % label)
	if counter_window < 0.0:
		problems.append("%s: counter_window cannot be negative." % label)
	match effect:
		Effect.GRANT_STATUS, Effect.STATUS_ON_TARGET:
			if status_effect == null:
				problems.append("%s: needs a status_effect (the status it applies)." % label)
			else:
				if status_effect.id == &"":
					problems.append("%s: its status_effect has an empty id." % label)
				if status_effect.duration <= 0.0:
					problems.append("%s: its status_effect needs a duration above 0." % label)
		Effect.HEAL_SELF:
			if heal_amount < 1:
				problems.append("%s: heal_amount must be at least 1." % label)
		Effect.DAMAGE_BONUS_LOW_HEALTH:
			if health_threshold <= 0.0 or health_threshold > 1.0:
				problems.append("%s: health_threshold must be above 0 and at most 1." % label)
			if damage_multiplier <= 1.0:
				problems.append("%s: damage_multiplier must be above 1 (a bonus)." % label)
	return problems

func _label() -> String:
	if id != &"":
		return "passive '%s'" % id
	if display_name != "":
		return "passive '%s'" % display_name
	return "passive (unnamed)"
