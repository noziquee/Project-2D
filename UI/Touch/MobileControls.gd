extends Control
class_name MobileControls
## H7.6 / H8.8: the touch overlay, laid out like a mobile MOBA (D13, D17): a move stick on the left, and on the right one
## large attack button with the dodge and the three skill buttons in an arc around it and a small weapon-swap button
## beside the dodge. There is no aim stick: a tap attacks with assistance, and dragging from the attack button (while
## held, an aimed heavy attack) or from an aimed skill button aims by hand. It sits in the HUD CanvasLayer, is shown
## only while the InputModeManager says the player is on touch, and builds its own children in _ready so the layout
## can be tuned from the exports below.
##
## Everything here presses the existing named actions (move_*, aim_*, attack_light, dash, weapon_next, skill_1 to
## skill_3). There is no combat code in this folder: weapons, attacks and skills cannot tell touch from a key or a
## controller. The one question it asks the player is whether a skill slot has an aim at all (slot_has_aim_shape), to
## know whether that button aims on a drag and casts on the lift, or casts on touch-down like a buff (D16).

const GROUP := &"mobile_controls"

## Where the buttons sit around the attack button: the angle of each one's centre on a circle round the attack button
## (0 = right, 90 = up, 180 = left). The circle's radius is the attack button's radius plus a button's radius plus
## button_gap. Dodge and skills run from the lower left round to the top, so a thumb resting on the attack button
## reaches each one by sliding up and left.
const ARC := {
	&"dash": 195.0,
	&"skill_1": 155.0,
	&"skill_2": 115.0,
	&"skill_3": 75.0,
}
const CAPTIONS := {
	&"skill_1": "1", &"skill_2": "2", &"skill_3": "3",
	&"weapon_next": "Swap", &"dash": "Dash", &"attack_light": "Atk",
}

## The layout exports below (edge_margin to button_gap, and ARC) are used only when this node has no children, that is when
## the layout is built in code. With MobileControls.tscn the buttons are placed in the scene editor and these are ignored.

## Forces the overlay on whatever the device, to try it on a desktop. Leave off in a shipped build.
@export var debug_force_visible := false:
	set(value):
		debug_force_visible = value
		_refresh_visibility()
## Gap between the overlay and the screen edge, in base viewport pixels (the base is 1280 x 720).
@export var edge_margin := 30.0
@export var stick_size := 180.0
## The dodge and the three skill buttons.
@export var button_size := 80.0
## The weapon swap button, used less often, is smaller and sits beside the dodge.
@export var small_button_size := 60.0
## The attack button: the biggest target on the screen.
@export var attack_button_size := 150.0
@export var button_gap := 14.0

var _manager: InputModeManager
var _move_stick: VirtualStick
var _buttons: Dictionary = {}

func _ready() -> void:
	add_to_group(GROUP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	_build()
	_refresh_visibility()
	# The manager is a later sibling of the HUD, so it has not joined its group yet while this node is readying.
	_bind_manager.call_deferred()

func _exit_tree() -> void:
	if is_instance_valid(_manager) and _manager.device_changed.is_connected(_on_device_changed):
		_manager.device_changed.disconnect(_on_device_changed)

func get_move_stick() -> VirtualStick:
	return _move_stick

## The button for an action, or null.
func get_button(action: StringName) -> TouchActionButton:
	return _buttons.get(action) as TouchActionButton

## Every action a control here can press.
func get_actions() -> Array[StringName]:
	# The aim_* actions are pressed by a drag on the attack or a skill button; there is no aim stick.
	var actions: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down", &"aim_left", &"aim_right", &"aim_up", &"aim_down"]
	for action in _buttons:
		actions.append(action)
	return actions

func _bind_manager() -> void:
	_manager = get_tree().get_first_node_in_group(InputModeManager.GROUP) as InputModeManager
	if _manager != null and not _manager.device_changed.is_connected(_on_device_changed):
		_manager.device_changed.connect(_on_device_changed)
	_refresh_visibility()

func _on_device_changed(_device: InputModeManager.Device) -> void:
	_refresh_visibility()

## Shown on touch only, or when forced. Hiding lets go of anything held (each control does that itself).
func _refresh_visibility() -> void:
	visible = debug_force_visible or (_manager != null and _manager.is_touch())

## Uses the layout saved in the scene when there is one (MobileControls.tscn: a MoveStick and a RightCluster holding the
## TouchActionButtons), else builds the same layout in code from the exports and ARC above. The scene is the place to
## move and resize things; the code layout is the fallback for a MobileControls node that has no children.
func _build() -> void:
	if _move_stick != null:
		return
	if not _adopt_scene_layout():
		_build_layout_in_code()

## True when the scene supplied the controls. The buttons are found by their `action`, so their names and order do not
## matter. The MoveStick must be a VirtualStick (its script is attached in the scene); if it is not, the scene is
## rejected with a warning.
func _adopt_scene_layout() -> bool:
	var cluster := get_node_or_null("RightCluster") as Control
	var stick_node := get_node_or_null("MoveStick") as Control
	if cluster == null or stick_node == null:
		return false
	if not stick_node is VirtualStick:
		push_warning("MobileControls: MoveStick in the scene is not a VirtualStick (attach UI/Touch/VirtualStick.gd to it); building the layout in code instead.")
		return false
	var found := false
	for child in cluster.get_children():
		var button := child as TouchActionButton
		if button != null and button.action != &"":
			_register_button(button)
			found = true
	if not found:
		return false
	_move_stick = stick_node as VirtualStick
	return true

func _build_layout_in_code() -> void:
	# Left: the move stick, pinned to the bottom-left corner.
	_move_stick = VirtualStick.new()
	_move_stick.name = "MoveStick"
	_move_stick.custom_minimum_size = Vector2(stick_size, stick_size)
	add_child(_move_stick)
	_pin(_move_stick, false, Vector2(stick_size, stick_size))

	# Right: the attack button in the corner and the other buttons round it, pinned to the bottom-right corner.
	var placements := _placements()
	var bounds := Rect2(placements[&"attack_light"].center - Vector2.ONE * attack_button_size * 0.5, Vector2.ONE * attack_button_size)
	for action in placements:
		var entry: Dictionary = placements[action]
		var half := Vector2.ONE * float(entry.extent) * 0.5
		bounds = bounds.merge(Rect2(entry.center - half, half * 2.0))
	var cluster := Control.new()
	cluster.name = "RightCluster"
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cluster)
	_pin(cluster, true, bounds.size)
	for action in placements:
		var entry: Dictionary = placements[action]
		var button_extent: float = entry.extent
		var button := TouchActionButton.new()
		button.name = "Button_%s" % action
		button.action = action
		button.caption = CAPTIONS.get(action, "")
		button.custom_minimum_size = Vector2(button_extent, button_extent)
		button.size = Vector2(button_extent, button_extent)
		button.position = entry.center - bounds.position - Vector2(button_extent, button_extent) * 0.5
		cluster.add_child(button)
		_register_button(button)

## Wires one button to the player. This is the only place a button learns what it is for, so a button made in the scene
## and one made in code behave the same: a tap attacks, a drag from the attack button aims (D14, D15); an aimed skill
## casts on the lift and a buff on touch-down (D16), with its shape drawn while a finger rests on it (H8.9).
func _register_button(button: TouchActionButton) -> void:
	var action := button.action
	_buttons[action] = button
	if action == &"attack_light":
		button.drag_aim = true
	elif String(action).begins_with("skill_"):
		var slot := int(String(action).trim_prefix("skill_")) - 1
		button.mode = TouchActionButton.Mode.AIM_ON_RELEASE
		button.aim_query = func() -> bool: return _slot_has_aim(slot)
		button.cast_pending_changed.connect(func(pending: bool) -> void: _preview_skill(slot, pending))
		# How far out a drag reaches, for a ground circle (H8.8). Dropped to -1 together with the aim, after the cast.
		button.pull_changed.connect(func(pull: float) -> void: _pull_skill(pull))
		_attach_skill_face(button, slot)

## H8.8d: the skill button shows its skill (icon, cooldown, cost), so the hotbar is not needed on touch. The face is added
## here, using the scene-authored child when present and creating a fallback for code-built layouts, then bound once
## the player is in the tree.
func _attach_skill_face(button: TouchActionButton, slot: int) -> void:
	var face := button.get_node_or_null("SkillFace") as TouchSkillFace
	if face == null:
		face = TouchSkillFace.new()
		face.name = "SkillFace"
		button.add_child(face)
	_bind_skill_face.call_deferred(face, button, slot)

func _bind_skill_face(face: TouchSkillFace, button: TouchActionButton, slot: int) -> void:
	var player := get_tree().get_first_node_in_group("player")
	var component: SkillComponent2D = player.get("skill_component") as SkillComponent2D if player != null else null
	if is_instance_valid(face) and is_instance_valid(button):
		face.bind(button, component, slot)

## The face on the button for `action` (skill_1 to skill_3), or null.
func get_skill_face(action: StringName) -> TouchSkillFace:
	var button := get_button(action)
	return button.get_node_or_null("SkillFace") as TouchSkillFace if button != null else null

## Where every right-hand button's centre goes, relative to the attack button's centre, and how big it is.
func _placements() -> Dictionary:
	var placements := {&"attack_light": {"center": Vector2.ZERO, "extent": attack_button_size}}
	var ring := attack_button_size * 0.5 + button_size * 0.5 + button_gap
	for action in ARC:
		var angle := deg_to_rad(float(ARC[action]))
		placements[action] = {"center": Vector2(cos(angle), -sin(angle)) * ring, "extent": button_size}
	# The swap button sits on the dodge's far side, on the same line.
	var dash_center: Vector2 = placements[&"dash"].center
	placements[&"weapon_next"] = {"center": dash_center - Vector2(button_size * 0.5 + small_button_size * 0.5 + button_gap, 0.0), "extent": small_button_size}
	return placements

## Whether the skill in `slot` has an aim (an aim_shape, not a buff or a self skill), asked of the player.
func _slot_has_aim(slot: int) -> bool:
	var player := get_tree().get_first_node_in_group("player")
	return player != null and player.has_method("slot_has_aim_shape") and bool(player.slot_has_aim_shape(slot))

## Tells the player to show (or stop showing) the aim shape of the skill in `slot`.
func _preview_skill(slot: int, pending: bool) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if pending and player.has_method("begin_skill_preview"):
		player.begin_skill_preview(slot)
	elif not pending and player.has_method("end_skill_preview"):
		player.end_skill_preview()

## Tells the player how far out the drag on a skill button reaches (0 to 1; -1 when there is no manual aim).
func _pull_skill(pull: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("set_manual_pull"):
		player.set_manual_pull(pull)

## Pins a control to the bottom-left or bottom-right corner, edge_margin in from both edges, with the given size.
## Anchors, not a fixed screen position: it follows the corner at every aspect ratio.
func _pin(control: Control, right_side: bool, control_size: Vector2) -> void:
	var anchor := 1.0 if right_side else 0.0
	control.anchor_left = anchor
	control.anchor_right = anchor
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	if right_side:
		control.offset_right = -edge_margin
		control.offset_left = -edge_margin - control_size.x
	else:
		control.offset_left = edge_margin
		control.offset_right = edge_margin + control_size.x
	control.offset_bottom = -edge_margin
	control.offset_top = -edge_margin - control_size.y
