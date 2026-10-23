extends Control
## Player health display styled to match the add-on's dark-panel / gold-accent UI.
## Gameplay remains owned by the player; this node only observes health signals.

const HealthStyle = preload("res://UI/HUD/HealthBarStyle.gd")

@onready var card: PanelContainer = $Card
@onready var accent: ColorRect = $Accent
@onready var heart_icon: Label = $Card/Padding/Content/Header/HeartIcon
@onready var title_label: Label = $Card/Padding/Content/Header/Title
@onready var health_label: Label = $Card/Padding/Content/Header/HealthLabel
@onready var progress_bar: ProgressBar = $Card/Padding/Content/BarStack/ProgressBar
@onready var damage_bar: ProgressBar = $Card/Padding/Content/BarStack/DamageBar
@onready var damage_timer: Timer = $DamageTimer

var _player: Node
var _last_health: float = 0.0
var _maximum_health: float = 1.0
var _displayed_health: float = 0.0
var _main_tween: Tween
var _damage_tween: Tween
var _counter_tween: Tween
var _impact_tween: Tween
var _intro_tween: Tween
var _critical_tween: Tween
var _dead: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_ui()
	damage_timer.timeout.connect(_on_damage_timer_timeout)
	call_deferred("_bind_to_player")
	call_deferred("_play_intro")

func _style_ui() -> void:
	card.add_theme_stylebox_override("panel", HealthStyle.panel_style())
	HealthStyle.style_label(heart_icon, 23, HealthStyle.COLOR_HEALTH_LOW, 700, 3)
	HealthStyle.style_label(title_label, 13, HealthStyle.COLOR_ACCENT, 700, 3)
	HealthStyle.style_label(health_label, 14, HealthStyle.COLOR_TEXT, 700, 3)
	damage_bar.add_theme_stylebox_override("background", HealthStyle.bar_background())
	damage_bar.add_theme_stylebox_override("fill", HealthStyle.damage_fill())
	progress_bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	progress_bar.add_theme_stylebox_override("fill", HealthStyle.health_fill(HealthStyle.COLOR_HEALTH_HIGH))

func _play_intro() -> void:
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(card):
		return
	card.pivot_offset = card.size * 0.5
	card.modulate.a = 0.0
	card.scale = Vector2(0.96, 0.96)
	_intro_tween = create_tween().set_parallel(true)
	_intro_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_intro_tween.tween_property(card, "modulate:a", 1.0, 0.32)
	_intro_tween.tween_property(card, "scale", Vector2.ONE, 0.32)

func _bind_to_player() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		push_warning("PlayerHealthBar: no node in the 'player' group was found.")
		return

	_maximum_health = maxf(float(_player.get("max_health")), 1.0)
	var current := clampf(float(_player.get("health")), 0.0, _maximum_health)
	_last_health = current
	_displayed_health = current
	_set_values(current, _maximum_health)

	var health_callable := Callable(self, "_on_health_changed")
	if _player.has_signal("health_changed") and not _player.is_connected("health_changed", health_callable):
		_player.connect("health_changed", health_callable)
	var died_callable := Callable(self, "_on_died")
	if _player.has_signal("died") and not _player.is_connected("died", died_callable):
		_player.connect("died", died_callable)
	if current <= 0.0:
		_on_died()

func _on_health_changed(current_health: int, maximum_health: int) -> void:
	var maximum := maxf(float(maximum_health), 1.0)
	var current := clampf(float(current_health), 0.0, maximum)
	var previous := _last_health
	_maximum_health = maximum
	progress_bar.max_value = maximum
	damage_bar.max_value = maximum
	_update_health_color(current / maximum)
	_animate_counter(current)
	_kill_tween(_main_tween)
	_main_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_main_tween.tween_property(progress_bar, "value", current, 0.18 if current < previous else 0.24)

	if current < previous:
		_kill_tween(_damage_tween)
		damage_bar.value = clampf(maxf(damage_bar.value, previous), 0.0, maximum)
		damage_timer.start()
		_play_hit_feedback()
	elif current > previous:
		damage_timer.stop()
		_kill_tween(_damage_tween)
		_damage_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_damage_tween.tween_property(damage_bar, "value", current, 0.22)
		_play_heal_feedback()
	else:
		damage_bar.value = minf(damage_bar.value, maximum)

	_last_health = current

func _animate_counter(target: float) -> void:
	_kill_tween(_counter_tween)
	_counter_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_counter_tween.tween_method(_set_counter_value, _displayed_health, target, 0.20)

func _set_counter_value(value: float) -> void:
	_displayed_health = value
	health_label.text = "%d / %d" % [roundi(value), roundi(_maximum_health)]

func _update_health_color(ratio: float) -> void:
	var color: Color
	if ratio <= 0.25:
		color = HealthStyle.COLOR_HEALTH_LOW
	elif ratio <= 0.5:
		color = HealthStyle.COLOR_HEALTH_MID
	else:
		color = HealthStyle.COLOR_HEALTH_HIGH
	progress_bar.add_theme_stylebox_override("fill", HealthStyle.health_fill(color))
	heart_icon.add_theme_color_override("font_color", color)
	_update_critical_pulse(ratio <= 0.25 and ratio > 0.0 and not _dead)

func _update_critical_pulse(enabled: bool) -> void:
	if enabled and (_critical_tween == null or not _critical_tween.is_running()):
		progress_bar.self_modulate = Color.WHITE
		_critical_tween = create_tween().set_loops()
		_critical_tween.tween_property(progress_bar, "self_modulate:a", 0.58, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_critical_tween.tween_property(progress_bar, "self_modulate:a", 1.0, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif not enabled:
		_kill_tween(_critical_tween)
		_critical_tween = null
		progress_bar.self_modulate = Color.WHITE

func _on_damage_timer_timeout() -> void:
	if not is_instance_valid(_player) or _dead:
		return
	_kill_tween(_damage_tween)
	_damage_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_damage_tween.tween_property(damage_bar, "value", float(_player.get("health")), 0.42)

func _play_hit_feedback() -> void:
	_kill_tween(_impact_tween)
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2.ONE
	card.self_modulate = Color(1.0, 0.82, 0.82, 1.0)
	_impact_tween = create_tween().set_parallel(true)
	_impact_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_impact_tween.tween_property(card, "scale", Vector2(1.025, 1.07), 0.10)
	_impact_tween.tween_property(card, "self_modulate", Color.WHITE, 0.20)
	_impact_tween.chain().tween_property(card, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _play_heal_feedback() -> void:
	_kill_tween(_impact_tween)
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2.ONE
	card.self_modulate = Color(1.0, 1.0, 0.78, 1.0)
	_impact_tween = create_tween().set_parallel(true)
	_impact_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_impact_tween.tween_property(card, "scale", Vector2(1.015, 1.04), 0.10)
	_impact_tween.tween_property(card, "self_modulate", Color.WHITE, 0.24)
	_impact_tween.chain().tween_property(card, "scale", Vector2.ONE, 0.12)

func _on_died() -> void:
	_dead = true
	damage_timer.stop()
	_kill_tween(_main_tween)
	_kill_tween(_damage_tween)
	_kill_tween(_counter_tween)
	_kill_tween(_critical_tween)
	critical_state_reset()
	health_label.text = "DEAD"
	heart_icon.text = "×"
	heart_icon.add_theme_color_override("font_color", HealthStyle.COLOR_DEAD)
	progress_bar.add_theme_stylebox_override("fill", HealthStyle.health_fill(HealthStyle.COLOR_DEAD))
	progress_bar.value = 0.0
	damage_bar.value = 0.0
	card.self_modulate = Color.WHITE

func critical_state_reset() -> void:
	_critical_tween = null
	progress_bar.self_modulate = Color.WHITE

func _set_values(current: float, maximum: float) -> void:
	progress_bar.min_value = 0.0
	progress_bar.max_value = maximum
	progress_bar.value = current
	damage_bar.min_value = 0.0
	damage_bar.max_value = maximum
	damage_bar.value = current
	_displayed_health = current
	health_label.text = "%d / %d" % [roundi(current), roundi(maximum)]
	_update_health_color(current / maximum if maximum > 0.0 else 0.0)

func _kill_tween(tween: Tween) -> void:
	if is_instance_valid(tween) and tween.is_running():
		tween.kill()
