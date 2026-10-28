extends HBoxContainer
class_name SkillBar
## Scene-based three-slot HUD. SkillComponent2D owns skill/cooldown state; this node only binds slots and presents it.

const SLOT_COUNT := 3
const SLOT_ACTIONS: Array[StringName] = [&"skill_1", &"skill_2", &"skill_3"]

## Emitted when click-to-cast is switched on or off.
signal click_to_cast_changed(enabled: bool)

## When true (the default) a left click on a slot casts its skill, exactly like its key. When false a click on a slot
## does nothing (it still does not swing the weapon). Toggle it with the toggle_click_cast action (H by default) or
## set_click_to_cast().
@export var click_to_cast := true

@export var skill_component_path: NodePath
@export var mana_component_path: NodePath

var _skill_component: SkillComponent2D
var _mana_component: ManaComponent2D
var _slots: Array[SkillSlot] = []
var _last_hotkeys: Array[String] = []
## H7.7: which device the player is using, so the slots show a key, a controller button or nothing (touch has its own
## on-screen buttons). Follows InputModeManager.device_changed.
var _device: InputModeManager.Device = InputModeManager.Device.KEYBOARD_MOUSE

func _ready() -> void:
	for index in range(SLOT_COUNT):
		var slot := get_node_or_null("SkillSlot%d" % (index + 1)) as SkillSlot
		if slot == null:
			push_error("SkillBar requires child SkillSlot%d." % (index + 1))
			continue
		_slots.append(slot)
		_last_hotkeys.append("")
		slot.clicked.connect(_on_slot_clicked.bind(index))
		slot.set_clickable(click_to_cast)

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
	# The manager is a later sibling of the HUD, so it is not in its group yet while this node is readying.
	_bind_input_mode.call_deferred()

func _process(_delta: float) -> void:
	# InputMap has no change signal. Comparing the small set of labels lets runtime key rebinding show immediately.
	_refresh_hotkeys_if_changed()

func _bind_input_mode() -> void:
	var manager := get_tree().get_first_node_in_group(InputModeManager.GROUP) as InputModeManager
	if manager == null:
		return
	if not manager.device_changed.is_connected(_on_device_changed):
		manager.device_changed.connect(_on_device_changed)
	_on_device_changed(manager.active_device)

## The labels follow in the next _process (it compares them every frame), so nothing else is needed here.
func _on_device_changed(device: InputModeManager.Device) -> void:
	_device = device
	# H8.8d: on touch the skills are the buttons of the touch layout (TouchSkillFace), so the hotbar is hidden. Keyboard
	# and controller keep it. Hiding changes nothing else: the bar still binds and updates.
	visible = device != InputModeManager.Device.TOUCH

func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action(&"toggle_click_cast") and event.is_action_pressed(&"toggle_click_cast") and not event.is_echo():
		set_click_to_cast(not click_to_cast)

func is_click_to_cast() -> bool:
	return click_to_cast

func set_click_to_cast(enabled: bool) -> void:
	if enabled == click_to_cast:
		return
	click_to_cast = enabled
	for slot in _slots:
		slot.set_clickable(enabled)
	click_to_cast_changed.emit(enabled)

## A click on slot `index`: the same request the key makes. No direction is given, so SkillComponent2D uses the aim
## the character already has (the pointer is over the hotbar, so the player keeps its last aim, see player.gd).
## The component stays the authority for cost, cooldown and refusal.
func _on_slot_clicked(index: int) -> void:
	if not click_to_cast or not is_instance_valid(_skill_component):
		return
	_skill_component.try_use_slot(index)

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
	if _device == InputModeManager.Device.TOUCH:
		return ""
	if _device == InputModeManager.Device.CONTROLLER:
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton:
				return _joy_button_label((event as InputEventJoypadButton).button_index, fallback)
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

## Xbox names for the buttons the skill actions use; anything else falls back to the given text.
func _joy_button_label(button: int, fallback: String) -> String:
	match button:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
	return fallback
