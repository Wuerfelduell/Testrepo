class_name GameSettings
extends Node
## Autoload "Settings": player options from docs/UI.md section 7, stored in
## user://settings.cfg and applied immediately. Presentation only, never game state.

signal changed

const DEFAULT_PATH: String = "user://settings.cfg"
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440)]
const DICE_SPEEDS: Array[String] = ["slow", "normal", "fast", "off"]
## DicePopup.speed multipliers; "off" lands every roll almost instantly so results still show.
const DICE_SPEED_VALUES: Dictionary = {"slow": 0.6, "normal": 1.0, "fast": 2.0, "off": 40.0}
const BUSES: Array[String] = ["Master", "Music", "Effects"]

var path: String = DEFAULT_PATH
var resolution: Vector2i = Vector2i(1280, 720)
var fullscreen: bool = false
var volumes: Dictionary = {"Master": 1.0, "Music": 0.8, "Effects": 1.0}
var dice_speed: String = "normal"
## Multiplier on the camera's base rotation speed.
var camera_rotation_speed: float = 1.0

func _ready() -> void:
	# Without a stored file the window keeps its launch size (--resolution, captures).
	apply(load_settings())

## Returns true when a settings file was read.
func load_settings() -> bool:
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK:
		return false
	var stored: Variant = config.get_value("display", "resolution", resolution)
	if stored is Vector2i and stored in RESOLUTIONS:
		resolution = stored
	fullscreen = bool(config.get_value("display", "fullscreen", fullscreen))
	for bus: String in BUSES:
		volumes[bus] = clampf(float(config.get_value("audio", bus.to_lower(), volumes[bus])), 0.0, 1.0)
	var speed: Variant = config.get_value("gameplay", "dice_speed", dice_speed)
	if speed is String and speed in DICE_SPEEDS:
		dice_speed = speed
	camera_rotation_speed = clampf(float(config.get_value("gameplay", "camera_rotation_speed", camera_rotation_speed)), 0.25, 3.0)
	return true

func save_settings() -> Error:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("display", "resolution", resolution)
	config.set_value("display", "fullscreen", fullscreen)
	for bus: String in BUSES:
		config.set_value("audio", bus.to_lower(), volumes[bus])
	config.set_value("gameplay", "dice_speed", dice_speed)
	config.set_value("gameplay", "camera_rotation_speed", camera_rotation_speed)
	return config.save(path)

## Stores and applies one option; the options screen calls this on every change.
func set_option(key: String, value: Variant) -> void:
	match key:
		"resolution":
			if value is Vector2i and value in RESOLUTIONS:
				resolution = value
		"fullscreen": fullscreen = bool(value)
		"dice_speed":
			if String(value) in DICE_SPEEDS:
				dice_speed = String(value)
		"camera_rotation_speed": camera_rotation_speed = clampf(float(value), 0.25, 3.0)
		_:
			if key in BUSES:
				volumes[key] = clampf(float(value), 0.0, 1.0)
	save_settings()
	apply()

func dice_speed_value() -> float:
	return float(DICE_SPEED_VALUES[dice_speed])

func apply(include_window: bool = true) -> void:
	for bus: String in BUSES:
		var index: int = AudioServer.get_bus_index(bus)
		if index < 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, "Master")
		var volume: float = float(volumes[bus])
		AudioServer.set_bus_mute(index, volume <= 0.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))
	if include_window and is_inside_tree() and DisplayServer.get_name() != "headless":
		if fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(resolution)
	changed.emit()
