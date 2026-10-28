extends Control
class_name HealthBar
## One health bar for every character. It only observes a HealthComponent2D.
##
## Look: panels, bars and font are .tres files under UI/HUD/Styles, the high/mid/low colour is
## `color_gradient`, and the intro / hit / heal / critical feedback are clips on the
## AnimationPlayer child. Only the animated values (bar fill, damage trail, number counter)
## are tweened here. EnemyHealthBar.tscn is the compact variant used by enemies.

const CLIP_INTRO := &"intro"
const CLIP_HIT := &"hit"
const CLIP_HEAL := &"heal"
const CLIP_CRITICAL := &"critical"

## Path (relative to this node) to the HealthComponent2D to display.
@export var health_source: NodePath
## Fill colour by health ratio (constant gradient: low / mid / high).
@export var color_gradient: Gradient
@export var dead_color := Color(0.466667, 0.439216, 0.419608, 1.0)
@export_group("Labels")
@export var health_icon_text := "♥"
@export var health_title_text := "VITALITY"
@export var dead_text := "DEAD"
@export var dead_icon_text := "×"
@export var health_icon_color := Color(0.843137, 0.329412, 0.321569, 1.0)
@export var health_title_color := Color(1.0, 0.760784, 0.243137, 1.0)
## At or below this ratio (and above 0) the critical clip pulses the bar.
@export_range(0.0, 1.0, 0.01) var critical_ratio: float = 0.25
## Hidden until the first point of damage is taken (floating enemy bars).
@export var hide_until_damaged: bool = false
## Hide on death instead of showing the DEAD state.
@export var hide_on_death: bool = false

@onready var card: PanelContainer = $Card
@onready var heart_icon: Label = $Card/Padding/Content/Header/HeartIcon
@onready var health_label: Label = $Card/Padding/Content/Header/HealthLabel
@onready var bar_label: Label = $Card/Padding/Content/BarStack/BarLabel
@onready var progress_bar: ProgressBar = $Card/Padding/Content/BarStack/ProgressBar
@onready var damage_bar: ProgressBar = $Card/Padding/Content/BarStack/DamageBar
@onready var damage_timer: Timer = $DamageTimer
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var _health: HealthComponent2D
var _last_health: float = 0.0
var _maximum_health: float = 1.0
var _displayed_health: float = 0.0
var _main_tween: Tween
var _damage_tween: Tween
var _counter_tween: Tween
var _dead: bool = false
var _critical: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	heart_icon.text = health_icon_text
	heart_icon.add_theme_color_override("font_color", health_icon_color)
	var title_label := get_node_or_null("Card/Padding/Content/Header/Title") as Label
	if title_label != null:
		title_label.text = health_title_text
		title_label.add_theme_color_override("font_color", health_title_color)
	card.resized.connect(_update_card_pivot)
	_update_card_pivot()
	damage_timer.timeout.connect(_on_damage_timer_timeout)
	if hide_until_damaged:
		visible = false
	var source: HealthComponent2D = null
	if not health_source.is_empty():
		source = get_node_or_null(health_source) as HealthComponent2D
	if source == null:
		push_warning("HealthBar '%s': health_source does not point to a HealthComponent2D." % name)
	else:
		bind(source)
	if not hide_until_damaged:
		animation_player.play(CLIP_INTRO)
		animation_player.advance(0.0)
		_sync_critical()

## Starts showing `component`. Called automatically for `health_source`.
func bind(component: HealthComponent2D) -> void:
	_unbind()
	_health = component
	_dead = false
	var maximum := maxf(float(component.max_health), 1.0)
	var current := clampf(_read_health(component), 0.0, maximum)
	_maximum_health = maximum
	_last_health = current
	_set_values(current, maximum)
	component.health_changed.connect(_on_health_changed)
	component.died.connect(_on_died)
	if current <= 0.0:
		_on_died()

func get_shown_health() -> float:
	return progress_bar.value

func get_trail_health() -> float:
	return damage_bar.value

func get_counter_text() -> String:
	return health_label.text

func is_dead_state() -> bool:
	return _dead

func is_critical() -> bool:
	return _critical

func _unbind() -> void:
	if is_instance_valid(_health):
		if _health.health_changed.is_connected(_on_health_changed):
			_health.health_changed.disconnect(_on_health_changed)
		if _health.died.is_connected(_on_died):
			_health.died.disconnect(_on_died)
	_health = null

## The component's health is -1 until its own _ready() has run (a bar placed before it in
## the scene binds first), and equals max_health at that point.
func _read_health(component: HealthComponent2D) -> float:
	return float(component.health) if component.health >= 0 else float(component.max_health)

func _update_card_pivot() -> void:
	card.pivot_offset = card.size * 0.5

func _on_health_changed(current_health: int, maximum_health: int) -> void:
	if _dead:
		return
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
		_play_feedback(CLIP_HIT)
	elif current > previous:
		damage_timer.stop()
		_kill_tween(_damage_tween)
		_damage_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_damage_tween.tween_property(damage_bar, "value", current, 0.22)
		_play_feedback(CLIP_HEAL)
	else:
		damage_bar.value = minf(damage_bar.value, maximum)
		_sync_critical()
	_last_health = current

func _on_damage_timer_timeout() -> void:
	if _dead:
		return
	_kill_tween(_damage_tween)
	_damage_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_damage_tween.tween_property(damage_bar, "value", _last_health, 0.42)

func _on_died() -> void:
	_dead = true
	_critical = false
	damage_timer.stop()
	_kill_tween(_main_tween)
	_kill_tween(_damage_tween)
	_kill_tween(_counter_tween)
	animation_player.clear_queue()
	animation_player.stop()
	card.self_modulate = Color.WHITE
	card.scale = Vector2.ONE
	progress_bar.self_modulate = Color.WHITE
	if hide_on_death:
		visible = false
		return
	_set_counter_text(dead_text)
	heart_icon.text = dead_icon_text
	heart_icon.add_theme_color_override("font_color", dead_color)
	progress_bar.modulate = dead_color
	progress_bar.value = 0.0
	damage_bar.value = 0.0

## Plays one feedback clip. A hidden bar (hide_until_damaged) is revealed by the first hit
## with the intro clip, followed by the hit clip.
func _play_feedback(clip: StringName) -> void:
	animation_player.clear_queue()
	if not visible:
		if not (hide_until_damaged and clip == CLIP_HIT):
			return
		visible = true
		animation_player.play(CLIP_INTRO)
		animation_player.queue(CLIP_HIT)
	elif animation_player.is_playing() and animation_player.current_animation == CLIP_INTRO:
		# Never cut the intro short: it leaves the card partly transparent.
		animation_player.queue(clip)
	else:
		animation_player.play(clip)
	_sync_critical()

## Keeps the looping critical clip running whenever the bar is in the critical range and no
## one-shot clip is playing; it is queued behind a one-shot clip that is still playing.
func _sync_critical() -> void:
	var playing: StringName = animation_player.current_animation
	if _critical and visible:
		if not animation_player.is_playing():
			animation_player.play(CLIP_CRITICAL)
		elif playing != CLIP_CRITICAL:
			animation_player.queue(CLIP_CRITICAL)
	else:
		animation_player.clear_queue()
		if playing == CLIP_CRITICAL:
			animation_player.stop()
			progress_bar.self_modulate = Color.WHITE

func _update_health_color(ratio: float) -> void:
	var color := color_gradient.sample(ratio) if color_gradient != null else Color.WHITE
	progress_bar.modulate = color
	heart_icon.add_theme_color_override("font_color", color)
	_critical = ratio > 0.0 and ratio <= critical_ratio and not _dead

func _animate_counter(target: float) -> void:
	_kill_tween(_counter_tween)
	_counter_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_counter_tween.tween_method(_set_counter_value, _displayed_health, target, 0.20)

func _set_counter_value(value: float) -> void:
	_displayed_health = value
	_set_counter_text("%d / %d" % [roundi(value), roundi(_maximum_health)])

func _set_counter_text(text: String) -> void:
	health_label.text = text
	bar_label.text = text

func _set_values(current: float, maximum: float) -> void:
	progress_bar.min_value = 0.0
	progress_bar.max_value = maximum
	progress_bar.value = current
	damage_bar.min_value = 0.0
	damage_bar.max_value = maximum
	damage_bar.value = current
	_displayed_health = current
	_set_counter_text("%d / %d" % [roundi(current), roundi(maximum)])
	_update_health_color(current / maximum if maximum > 0.0 else 0.0)

func _kill_tween(tween: Tween) -> void:
	if is_instance_valid(tween) and tween.is_running():
		tween.kill()
