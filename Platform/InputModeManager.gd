extends Node
class_name InputModeManager
## H7.5: which kind of device the player is using right now, so the HUD can show the right prompts and controls
## (H7.6, H7.7) and gameplay can stay the same. It only watches input; it never changes what an action does.
##
## Rules:
## - The mode starts as TOUCH on Android and iOS (and web on them) and as KEYBOARD_MOUSE everywhere else. A connected
##   controller does not make it the active device: it takes over only when a controller input is actually used.
## - The last device used wins: a key or real mouse input is KEYBOARD_MOUSE, a controller button or a stick pushed past
##   STICK_THRESHOLD is CONTROLLER, a touch or drag is TOUCH. A resting stick (drift) and key releases do not count.
## - Mouse events that Godot makes from touches (device id DEVICE_ID_EMULATION) belong to TOUCH, not the mouse.
## - If the active controller is unplugged and none is left, the mode falls back to the platform's start mode.

enum Device { KEYBOARD_MOUSE, CONTROLLER, TOUCH }

## Emitted when the active device changes, never twice in a row for the same device.
signal device_changed(device: Device)

const GROUP := &"input_mode_manager"
## How far a stick must be pushed before it counts as using the controller (resting drift stays below it).
const STICK_THRESHOLD := 0.4
## OS feature names that start the game in TOUCH mode.
const TOUCH_FEATURES: Array[String] = ["android", "ios", "web_android", "web_ios"]

var active_device: Device = Device.KEYBOARD_MOUSE
var _platform_default: Device = Device.KEYBOARD_MOUSE

## The mode a platform starts in, from its OS feature names.
static func default_device_for(features: Array[String]) -> Device:
	for feature in TOUCH_FEATURES:
		if features.has(feature):
			return Device.TOUCH
	return Device.KEYBOARD_MOUSE

func _ready() -> void:
	add_to_group(GROUP)
	var features: Array[String] = []
	for feature in TOUCH_FEATURES:
		if OS.has_feature(feature):
			features.append(feature)
	_platform_default = default_device_for(features)
	active_device = _platform_default
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)

func _exit_tree() -> void:
	if Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.disconnect(_on_joy_connection_changed)

func is_touch() -> bool:
	return active_device == Device.TOUCH

func is_controller() -> bool:
	return active_device == Device.CONTROLLER

## True when at least one controller is plugged in. Says nothing about which device the player is using.
func has_controller() -> bool:
	return not Input.get_connected_joypads().is_empty()

## Sets the mode directly (a debug switch, or a settings screen). Emits device_changed when it changes.
func set_device(device: Device) -> void:
	if device == active_device:
		return
	active_device = device
	device_changed.emit(device)

func _input(event: InputEvent) -> void:
	var used := classify(event)
	if used >= 0:
		set_device(used as Device)

## The device an event shows the player is using, or -1 when it shows nothing (a release, an echo, a resting stick,
## an emulated mouse event).
func classify(event: InputEvent) -> int:
	var key := event as InputEventKey
	if key != null:
		return Device.KEYBOARD_MOUSE if key.pressed and not key.echo else -1
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return -1
		var motion := event as InputEventMouseMotion
		if motion != null and motion.relative.length_squared() <= 0.0:
			return -1
		var button := event as InputEventMouseButton
		if button != null and not button.pressed:
			return -1
		return Device.KEYBOARD_MOUSE
	var pad_button := event as InputEventJoypadButton
	if pad_button != null:
		return Device.CONTROLLER if pad_button.pressed else -1
	var pad_motion := event as InputEventJoypadMotion
	if pad_motion != null:
		return Device.CONTROLLER if absf(pad_motion.axis_value) >= STICK_THRESHOLD else -1
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		return Device.TOUCH
	return -1

func _on_joy_connection_changed(_device_id: int, _connected: bool) -> void:
	if active_device == Device.CONTROLLER and not has_controller():
		set_device(_platform_default)
