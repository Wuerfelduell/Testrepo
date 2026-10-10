class_name OptionsMenu
extends Control
## docs/UI.md section 7. Every change is written to user://settings.cfg and applied at once.

signal closed

var resolution: OptionButton
var fullscreen: CheckButton
var sliders: Dictionary = {}
var dice_speed: OptionButton
var camera_speed: HSlider

func _ready() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.size = size
	add_child(shade)
	MenuTheme.panel(self, Rect2(560, 170, 800, 740))
	MenuTheme.label(self, Rect2(560, 200, 800, 60), tr("OPTIONS_TITLE"), 44, MenuTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var settings: GameSettings = get_node("/root/Settings") as GameSettings
	var row: float = 300.0
	_row_label(row, "OPTIONS_RESOLUTION")
	resolution = _option_button(row)
	for value: Vector2i in GameSettings.RESOLUTIONS:
		resolution.add_item("%d × %d" % [value.x, value.y])
	resolution.select(GameSettings.RESOLUTIONS.find(settings.resolution))
	resolution.item_selected.connect(func(index: int) -> void:
		settings.set_option("resolution", GameSettings.RESOLUTIONS[index]))
	row += 70.0
	_row_label(row, "OPTIONS_FULLSCREEN")
	fullscreen = CheckButton.new()
	fullscreen.position = Vector2(1000, row)
	fullscreen.size = Vector2(80, 44)
	fullscreen.button_pressed = settings.fullscreen
	fullscreen.toggled.connect(func(on: bool) -> void: settings.set_option("fullscreen", on))
	add_child(fullscreen)
	row += 70.0
	for bus: String in GameSettings.BUSES:
		_row_label(row, "OPTIONS_VOLUME_" + bus.to_upper())
		var slider: HSlider = _slider(row, 0.0, 1.0, 0.05, float(settings.volumes[bus]))
		slider.value_changed.connect(func(value: float) -> void: settings.set_option(bus, value))
		sliders[bus] = slider
		row += 70.0
	_row_label(row, "OPTIONS_DICE_SPEED")
	dice_speed = _option_button(row)
	for speed: String in GameSettings.DICE_SPEEDS:
		dice_speed.add_item(tr("OPTIONS_DICE_" + speed.to_upper()))
	dice_speed.select(GameSettings.DICE_SPEEDS.find(settings.dice_speed))
	dice_speed.item_selected.connect(func(index: int) -> void:
		settings.set_option("dice_speed", GameSettings.DICE_SPEEDS[index]))
	row += 70.0
	_row_label(row, "OPTIONS_CAMERA_SPEED")
	camera_speed = _slider(row, 0.25, 3.0, 0.25, settings.camera_rotation_speed)
	camera_speed.value_changed.connect(func(value: float) -> void:
		settings.set_option("camera_rotation_speed", value))
	var back: Button = MenuTheme.button(self, Rect2(810, 820, 300, 64), tr("MENU_BACK"))
	back.pressed.connect(close)

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	closed.emit()
	queue_free()

func _row_label(row: float, key: String) -> void:
	MenuTheme.label(self, Rect2(640, row + 4, 340, 40), tr(key), 24)

func _option_button(row: float) -> OptionButton:
	var result: OptionButton = OptionButton.new()
	result.position = Vector2(1000, row)
	result.size = Vector2(280, 44)
	result.add_theme_font_size_override("font_size", 22)
	add_child(result)
	return result

func _slider(row: float, minimum: float, maximum: float, step: float, value: float) -> HSlider:
	var result: HSlider = HSlider.new()
	result.position = Vector2(1000, row + 10)
	result.size = Vector2(280, 28)
	result.min_value = minimum
	result.max_value = maximum
	result.step = step
	result.value = value
	add_child(result)
	return result
