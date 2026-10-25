extends HBoxContainer
class_name SkillBar
## Scene-based three-slot HUD. SkillComponent2D owns skill/cooldown state; this node only binds slots and presents it.

const SLOT_COUNT := 3
const SLOT_ACTIONS: Array[StringName] = [&"skill_1", &"skill_2", &"skill_3"]

@export var skill_component_path: NodePath
@export var mana_component_path: NodePath

var _skill_component: SkillComponent2D
var _mana_component: ManaComponent2D
var _slots: Array[SkillSlot] = []
var _last_hotkeys: Array[String] = []

func _ready() -> void:
	for index in range(SLOT_COUNT):
		var slot := get_node_or_null("SkillSlot%d" % (index + 1)) as SkillSlot
		if slot == null:
			push_error("SkillBar requires child SkillSlot%d." % (index + 1))
			continue
		_slots.append(slot)
		_last_hotkeys.append("")

	_skill_component = get_node_or_null(skill_component_path) as SkillComponent2D if not skill_component_path.is_empty() else null
	_mana_component = get_node_or_null(mana_component_path) as ManaComponent2D if not mana_component_path.is_empty() else null

	if is_instance_valid(_skill_component):
		if not _skill_component.skills_changed.is_connected(_on_skills_changed):
			_skill_component.skills_changed.connect(_on_skills_changed)
	else:
		push_warning("SkillBar has no SkillComponent2D at skill_component_path; showing empty slots.")

	if is_instance_valid(_mana_component):
		if not _mana_component.mana_changed.is_connected(_on_mana_changed):
			_mana_component.mana_changed.connect(_on_mana_changed)
	else:
		push_warning("SkillBar has no ManaComponent2D at mana_component_path; mana-cost feedback will use SkillComponent2D state only.")

	_refresh_slots()

func _process(_delta: float) -> void:
	# InputMap has no change signal. Comparing the small set of labels lets runtime key rebinding show immediately.
	_refresh_hotkeys_if_changed()

func get_slot(index: int) -> SkillSlot:
	if index < 0 or index >= _slots.size():
		return null
	return _slots[index]

func get_skill_component() -> SkillComponent2D:
	return _skill_component

func get_mana_component() -> ManaComponent2D:
	return _mana_component

func _on_skills_changed() -> void:
	_refresh_slots()

func _on_mana_changed(_current: float, _maximum: float) -> void:
	for slot in _slots:
		if is_instance_valid(slot):
			slot.refresh_display()

func _refresh_slots() -> void:
	for index in range(_slots.size()):
		var hotkey := _get_action_label(SLOT_ACTIONS[index], str(index + 1))
		var skill: SkillDefinition2D = null
		if is_instance_valid(_skill_component):
			skill = _skill_component.get_skill_in_slot(index)
		_slots[index].bind(_skill_component, skill, hotkey)
		_last_hotkeys[index] = hotkey

func _refresh_hotkeys_if_changed() -> void:
	for index in range(_slots.size()):
		var hotkey := _get_action_label(SLOT_ACTIONS[index], str(index + 1))
		if hotkey == _last_hotkeys[index]:
			continue
		_last_hotkeys[index] = hotkey
		_slots[index].set_hotkey_text(hotkey)

func _get_action_label(action: StringName, fallback: String) -> String:
	if not InputMap.has_action(action):
		return fallback
	for event in InputMap.action_get_events(action):
		if not event is InputEventKey:
			continue
		var key_event := event as InputEventKey
		var code: int = key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
		if code == 0:
			continue
		var parts := PackedStringArray()
		if key_event.ctrl_pressed:
			parts.append("Ctrl")
		if key_event.alt_pressed:
			parts.append("Alt")
		if key_event.shift_pressed:
			parts.append("Shift")
		if key_event.meta_pressed:
			parts.append("Meta")
		parts.append(OS.get_keycode_string(code))
		return "+".join(parts)
	return fallback
