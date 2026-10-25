extends Node
class_name ManaComponent2D
## A mana pool (13.2): the one skill cost resource the game supports so far. Optional: a character that has a child named
## ManaComponent2D can pay mana costs; one without it can only use skills that cost nothing.
##
## Runtime state (`mana`) lives here, never in a resource. Mana regenerates by itself; a skill that is cancelled before it
## executes gets its cost back through restore().

signal mana_changed(current: float, maximum: float)

@export_range(1.0, 1000.0, 1.0) var max_mana: float = 100.0
## Mana regained per second. 0 = none.
@export_range(0.0, 100.0, 0.1) var regen_per_second: float = 5.0

## Costs and amounts are compared with this slack so that 25 of 25 is affordable after float sums.
const EPSILON := 0.0001

var mana: float = 0.0

func _ready() -> void:
	mana = max_mana
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	if mana >= max_mana or regen_per_second <= 0.0:
		set_physics_process(false)
		return
	restore(regen_per_second * delta)

func can_afford(amount: float) -> bool:
	return amount <= mana + EPSILON

## Takes `amount` away. False and nothing changes when the pool holds less.
func spend(amount: float) -> bool:
	if amount < 0.0 or not can_afford(amount):
		return false
	mana = maxf(mana - amount, 0.0)
	mana_changed.emit(mana, max_mana)
	if regen_per_second > 0.0:
		set_physics_process(true)
	return true

## Adds up to `amount` (never above max_mana). Returns how much was actually added.
func restore(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var before := mana
	mana = minf(mana + amount, max_mana)
	if mana != before:
		mana_changed.emit(mana, max_mana)
	return mana - before
