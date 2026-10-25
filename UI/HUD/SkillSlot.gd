extends Control
class_name SkillSlot
## One reusable active-skill slot. Scene resources define all visuals; SkillComponent2D remains the authority for costs,
## cooldowns and casts. The slot reads remaining values for presentation but reacts to signals for events.

const CLIP_READY := &"ready"
const CLIP_DENIED := &"denied"
const CLIP_STARTED := &"started"
const CLIP_UNAFFORDABLE := &"unaffordable"

@export var cooldown_warning_color := Color(0.18, 0.2, 0.24, 0.9)
@export var cast_color := Color(0.22, 0.62, 1.0, 0.88)

@onready var card: PanelContainer = $Card
@onready var icon_rect: TextureRect = $Card/Icon
@onready var cooldown_wipe: TextureProgressBar = $Card/CooldownWipe
@onready var cooldown_label: Label = $Card/CooldownLabel
@onready var hotkey_label: Label = $Card/HotkeyLabel
@onready var cost_label: Label = $Card/CostLabel
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var _skill_component: SkillComponent2D
var _skill: SkillDefinition2D
var _hotkey_text := ""
var _last_cooldown_active := false
var _last_casting := false
var _last_unaffordable := false
var _last_refusal := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.resized.connect(_update_card_pivot)
	_update_card_pivot()
	_show_empty()

## Binds a skill to this slot. Passing null displays the empty frame without labels or an icon.
func bind(skill_component: SkillComponent2D, skill: SkillDefinition2D, hotkey_text: String = "") -> void:
	_unbind()
	_skill_component = skill_component
	_skill = skill
	_hotkey_text = hotkey_text
	hotkey_label.text = hotkey_text
	if _skill == null:
		_show_empty()
		return
	icon_rect.texture = _skill.icon
	icon_rect.visible = _skill.icon != null
	cost_label.visible = _skill.cost_resource != SkillDefinition2D.CostResource.NONE and _skill.cost_amount > 0.0
	cost_label.text = "◆ " + _format_cost(_skill.cost_amount)
	cooldown_label.visible = false
	cooldown_wipe.value = 0.0
	cooldown_wipe.tint_progress = cooldown_warning_color
	if is_instance_valid(_skill_component):
		_skill_component.cooldown_started.connect(_on_cooldown_started)
		_skill_component.cooldown_finished.connect(_on_cooldown_finished)
		_skill_component.skill_refused.connect(_on_skill_refused)
		_skill_component.skill_started.connect(_on_skill_started)
		_sync_visuals(true)
	else:
		_set_unaffordable(false)

func get_bound_skill() -> SkillDefinition2D:
	return _skill

## Updates the displayed key without rebinding the skill or disturbing its cooldown presentation.
func set_hotkey_text(value: String) -> void:
	_hotkey_text = value
	hotkey_label.text = value

## Refreshes affordability and cooldown presentation after an external resource change.
func refresh_display() -> void:
	_sync_visuals(true)

func get_cooldown_fraction() -> float:
	return cooldown_wipe.value / maxf(cooldown_wipe.max_value, 1.0)

func get_cooldown_text() -> String:
	return cooldown_label.text

func is_unaffordable() -> bool:
	return _last_unaffordable

func _process(_delta: float) -> void:
	if _skill == null or not is_instance_valid(_skill_component):
		return
	_sync_visuals(false)

func _sync_visuals(initial: bool) -> void:
	if _skill == null or not is_instance_valid(_skill_component):
		return
	var remaining := _skill_component.get_cooldown_remaining(_skill.id)
	var duration := _skill_component.get_cooldown_duration(_skill.id)
	var cooldown_active := remaining > 0.0 and duration > 0.0
	# TextureProgressBar is a radial fraction, not a seconds display. Normalize
	# remaining time against the component-owned duration so every cooldown uses
	# the full 0..1 range and stays consistent with cast progress.
	cooldown_wipe.max_value = 1.0
	cooldown_wipe.value = clampf(remaining / duration, 0.0, 1.0) if cooldown_active else 0.0
	cooldown_wipe.visible = cooldown_active
	cooldown_label.visible = cooldown_active
	cooldown_label.text = _format_seconds(remaining) if cooldown_active else ""

	var casting_skill := _skill_component.get_casting_skill()
	var casting := casting_skill != null and casting_skill.id == _skill.id
	if casting:
		cooldown_wipe.visible = true
		cooldown_wipe.tint_progress = cast_color
		cooldown_wipe.max_value = 1.0
		cooldown_wipe.value = _skill_component.get_cast_progress()
		cooldown_label.visible = true
		cooldown_label.text = _format_seconds(_skill_component.get_cast_remaining())
	else:
		cooldown_wipe.tint_progress = cooldown_warning_color

	var reason := _skill_component.can_use(_skill.id)
	var unaffordable := reason.begins_with("not enough mana") or reason.begins_with("the character has no mana pool")
	_set_unaffordable(unaffordable)
	if not initial and _last_cooldown_active and not cooldown_active and not casting:
		_play(CLIP_READY)
	_last_cooldown_active = cooldown_active
	_last_casting = casting

func _on_cooldown_started(skill: SkillDefinition2D, duration: float) -> void:
	if _skill != null and skill != null and skill.id == _skill.id:
		_last_cooldown_active = true
		# Populate the scene progress control synchronously from the component signal. This avoids a one-frame
		# empty wipe if the HUD is inspected before its next idle-process tick.
		cooldown_wipe.max_value = 1.0
		cooldown_wipe.value = clampf(_skill_component.get_cooldown_remaining(skill.id) / maxf(duration, 0.001), 0.0, 1.0)
		cooldown_wipe.tint_progress = cooldown_warning_color
		cooldown_wipe.visible = cooldown_wipe.value > 0.0
		cooldown_label.visible = cooldown_wipe.visible
		cooldown_label.text = _format_seconds(cooldown_wipe.value) if cooldown_wipe.visible else ""
		_sync_visuals(true)

func _on_cooldown_finished(skill_id: StringName) -> void:
	if _skill != null and skill_id == _skill.id:
		_last_cooldown_active = false
		_sync_visuals(true)
		_play(CLIP_READY)

func _on_skill_refused(skill: SkillDefinition2D, reason: String) -> void:
	if _skill != null and skill != null and skill.id == _skill.id:
		_last_refusal = reason
		_play(CLIP_DENIED)
		_sync_visuals(true)

func _on_skill_started(skill: SkillDefinition2D) -> void:
	if _skill != null and skill != null and skill.id == _skill.id:
		_play(CLIP_STARTED)
		_sync_visuals(true)

func _set_unaffordable(unaffordable: bool) -> void:
	var became_unaffordable := unaffordable and not _last_unaffordable
	_last_unaffordable = unaffordable
	icon_rect.self_modulate = Color(0.48, 0.49, 0.53, 1.0) if unaffordable else Color.WHITE
	cost_label.self_modulate = Color(1.0, 0.38, 0.32, 1.0) if unaffordable else Color.WHITE
	if became_unaffordable:
		_play(CLIP_UNAFFORDABLE)

func _show_empty() -> void:
	icon_rect.texture = null
	icon_rect.visible = false
	cooldown_wipe.value = 0.0
	cooldown_wipe.visible = false
	cooldown_label.text = ""
	cooldown_label.visible = false
	cost_label.text = ""
	cost_label.visible = false
	hotkey_label.text = _hotkey_text
	_last_cooldown_active = false
	_last_casting = false
	_set_unaffordable(false)

func _unbind() -> void:
	if is_instance_valid(_skill_component):
		if _skill_component.cooldown_started.is_connected(_on_cooldown_started):
			_skill_component.cooldown_started.disconnect(_on_cooldown_started)
		if _skill_component.cooldown_finished.is_connected(_on_cooldown_finished):
			_skill_component.cooldown_finished.disconnect(_on_cooldown_finished)
		if _skill_component.skill_refused.is_connected(_on_skill_refused):
			_skill_component.skill_refused.disconnect(_on_skill_refused)
		if _skill_component.skill_started.is_connected(_on_skill_started):
			_skill_component.skill_started.disconnect(_on_skill_started)
	_skill_component = null

func _format_seconds(seconds: float) -> String:
	if seconds < 10.0:
		return "%.1f" % maxf(seconds, 0.0)
	return "%d" % ceili(seconds)

func _format_cost(amount: float) -> String:
	if is_equal_approx(amount, roundf(amount)):
		return "%d" % roundi(amount)
	return "%.1f" % amount

func _play(clip: StringName) -> void:
	if animation_player.has_animation(clip):
		animation_player.play(clip)

func _update_card_pivot() -> void:
	card.pivot_offset = card.size * 0.5
