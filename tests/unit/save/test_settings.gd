extends GutTest
## Options persist in a ConfigFile and survive a restart.

const TEST_PATH: String = "user://test_settings.cfg"

func after_each() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)

func make() -> GameSettings:
	var settings: GameSettings = GameSettings.new()
	settings.path = TEST_PATH
	return settings

func test_settings_round_trip() -> void:
	var first: GameSettings = make()
	first.set_option("resolution", Vector2i(1920, 1080))
	first.set_option("fullscreen", true)
	first.set_option("Music", 0.35)
	first.set_option("Effects", 0.0)
	first.set_option("dice_speed", "fast")
	first.set_option("camera_rotation_speed", 1.75)
	var second: GameSettings = make()
	assert_true(second.load_settings())
	assert_eq(second.resolution, Vector2i(1920, 1080))
	assert_true(second.fullscreen)
	assert_almost_eq(float(second.volumes["Music"]), 0.35, 0.001)
	assert_eq(float(second.volumes["Effects"]), 0.0)
	assert_eq(second.dice_speed, "fast")
	assert_almost_eq(second.dice_speed_value(), 2.0, 0.001)
	assert_almost_eq(second.camera_rotation_speed, 1.75, 0.001)
	first.free()
	second.free()

func test_invalid_values_are_ignored_or_clamped() -> void:
	var settings: GameSettings = make()
	settings.set_option("resolution", Vector2i(13, 7))
	settings.set_option("dice_speed", "ludicrous")
	settings.set_option("Master", 4.0)
	settings.set_option("camera_rotation_speed", 99.0)
	assert_eq(settings.resolution, Vector2i(1280, 720))
	assert_eq(settings.dice_speed, "normal")
	assert_eq(float(settings.volumes["Master"]), 1.0)
	assert_eq(settings.camera_rotation_speed, 3.0)
	settings.free()

func test_missing_file_keeps_defaults() -> void:
	var settings: GameSettings = make()
	assert_false(settings.load_settings())
	assert_eq(settings.dice_speed, "normal")
	settings.free()

func test_volume_buses_exist_after_apply() -> void:
	var settings: GameSettings = make()
	settings.apply(false)
	for bus: String in GameSettings.BUSES:
		assert_true(AudioServer.get_bus_index(bus) >= 0, bus)
	settings.free()
