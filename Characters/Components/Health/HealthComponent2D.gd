extends Node
class_name HealthComponent2D
## Owns health, damage, healing, death and an optional invulnerability window.
## Characters forward their health_changed / damaged / died signals from here.
##
## Signal order for a hit: health_changed, damaged (also for the killing hit), then died.
## The dead state is set before any signal is emitted, so handlers can rely on is_alive().

signal health_changed(current_health: int, maximum_health: int)
signal damaged(hit: HitData)
signal healed(amount: int)
signal died

@export_range(1, 1000, 1) var max_health: int = 3:
	set(value):
		max_health = maxi(value, 1)
		if health >= 0: # already initialised (not just loaded from a scene)
			health = mini(health, max_health)
			health_changed.emit(health, max_health)
## After a hit that does not kill, further hits are ignored for this many seconds.
## 0 disables the window.
@export_range(0.0, 5.0, 0.01) var invulnerability_duration: float = 0.0

## -1 until _ready() so that a max_health loaded from a scene is not clamped early.
var health: int = -1
var _dead := false
var _invulnerable_remaining := 0.0

func _ready() -> void:
	if health < 0:
		health = max_health
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	_invulnerable_remaining = maxf(_invulnerable_remaining - delta, 0.0)
	if _invulnerable_remaining <= 0.0:
		set_physics_process(false)

func is_alive() -> bool:
	return not _dead and health > 0

func is_invulnerable() -> bool:
	return _invulnerable_remaining > 0.0

## Ignores hits while invulnerable (extends the window if it is already running).
func grant_invulnerability(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_invulnerable_remaining = maxf(_invulnerable_remaining, seconds)
	set_physics_process(true)

## Applies a hit and returns the damage actually dealt (0 when the hit was ignored:
## null, no damage, already dead, or invulnerable). Damage is capped at the health left.
func apply_hit(hit: HitData) -> int:
	if hit == null or hit.damage <= 0 or _dead or health <= 0 or is_invulnerable():
		return 0
	var dealt := mini(hit.damage, health)
	health -= dealt
	_dead = health <= 0
	health_changed.emit(health, max_health)
	damaged.emit(hit)
	if _dead:
		died.emit()
	else:
		grant_invulnerability(invulnerability_duration)
	return dealt

## Restores up to `amount` health, never above max_health. Returns the amount restored.
func heal(amount: int) -> int:
	if _dead or health <= 0 or amount <= 0 or health >= max_health:
		return 0
	var restored := mini(amount, max_health - health)
	health += restored
	health_changed.emit(health, max_health)
	healed.emit(restored)
	return restored
