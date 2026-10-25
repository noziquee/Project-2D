extends Control
class_name ManaBar
## Player mana display. ManaComponent2D owns the resource; this scene only observes it.

const CLIP_INTRO := &"intro"
const CLIP_SPEND := &"spend"
const CLIP_RESTORE := &"restore"

## Path relative to this node to the ManaComponent2D being displayed.
@export var mana_source: NodePath

@onready var card: PanelContainer = $Card
@onready var mana_icon: Label = $Card/Padding/Content/Header/ManaIcon
@onready var mana_label: Label = $Card/Padding/Content/Header/ManaLabel
@onready var progress_bar: ProgressBar = $Card/Padding/Content/BarStack/ProgressBar
@onready var bar_label: Label = $Card/Padding/Content/BarStack/BarLabel
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var _mana: ManaComponent2D
var _last_mana: float = 0.0
var _maximum_mana: float = 1.0
var _displayed_mana: float = 0.0
var _bar_tween: Tween
var _counter_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.resized.connect(_update_card_pivot)
	_update_card_pivot()
	var source: ManaComponent2D = null
	if not mana_source.is_empty():
		source = get_node_or_null(mana_source) as ManaComponent2D
	if source == null:
		push_warning("ManaBar '%s': mana_source does not point to a ManaComponent2D." % name)
		return
	bind(source)
	animation_player.play(CLIP_INTRO)
	animation_player.advance(0.0)

## Starts observing `component`. Called automatically for mana_source.
func bind(component: ManaComponent2D) -> void:
	_unbind()
	_mana = component
	var maximum := maxf(float(component.max_mana), 1.0)
	var current := clampf(float(component.mana), 0.0, maximum)
	_maximum_mana = maximum
	_last_mana = current
	_set_values(current, maximum)
	component.mana_changed.connect(_on_mana_changed)

func get_shown_mana() -> float:
	return progress_bar.value

func get_counter_text() -> String:
	return mana_label.text

func _unbind() -> void:
	if is_instance_valid(_mana) and _mana.mana_changed.is_connected(_on_mana_changed):
		_mana.mana_changed.disconnect(_on_mana_changed)
	_mana = null

func _on_mana_changed(current_mana: float, maximum_mana: float) -> void:
	var maximum := maxf(maximum_mana, 1.0)
	var current := clampf(current_mana, 0.0, maximum)
	var previous := _last_mana
	_maximum_mana = maximum
	progress_bar.max_value = maximum
	_animate_counter(current)
	_kill_tween(_bar_tween)
	_bar_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_bar_tween.tween_property(progress_bar, "value", current, 0.18 if current < previous else 0.24)
	if current < previous:
		_play_feedback(CLIP_SPEND)
	elif current > previous:
		_play_feedback(CLIP_RESTORE)
	_last_mana = current

func _play_feedback(clip: StringName) -> void:
	if animation_player.is_playing() and animation_player.current_animation == CLIP_INTRO:
		animation_player.queue(clip)
	else:
		animation_player.play(clip)

func _animate_counter(target: float) -> void:
	_kill_tween(_counter_tween)
	_counter_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_counter_tween.tween_method(_set_counter_value, _displayed_mana, target, 0.20)

func _set_counter_value(value: float) -> void:
	_displayed_mana = value
	_set_counter_text("%d / %d" % [roundi(value), roundi(_maximum_mana)])

func _set_counter_text(text: String) -> void:
	mana_label.text = text
	bar_label.text = text

func _set_values(current: float, maximum: float) -> void:
	progress_bar.min_value = 0.0
	progress_bar.max_value = maximum
	progress_bar.value = current
	_displayed_mana = current
	_set_counter_text("%d / %d" % [roundi(current), roundi(maximum)])

func _update_card_pivot() -> void:
	card.pivot_offset = card.size * 0.5

func _kill_tween(tween: Tween) -> void:
	if is_instance_valid(tween) and tween.is_running():
		tween.kill()
