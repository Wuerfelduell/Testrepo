extends GutTest
## Ironman save: round trip of a running combat, permadeath delete, version and corruption.

const TEST_PATH: String = "user://test_ironman.save"

func before_each() -> void:
	SaveGame.path = TEST_PATH
	SaveGame.delete()

func after_each() -> void:
	SaveGame.delete()
	SaveGame.path = SaveGame.DEFAULT_PATH

func running_combat() -> GameState:
	var state: GameState = GameState.new()
	var look: Dictionary = HeroLooks.for_class("wizard", "female")[0]
	var setup: SetupArenaCommand = SetupArenaCommand.new(HeroFactory.build_record("wizard", look, "Mira"))
	assert_eq(setup.validate(state), OK)
	setup.apply(state)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 77
	Rng.rng.seed = 77
	var start: StartCombatCommand = StartCombatCommand.new()
	assert_eq(start.validate(state), OK)
	start.apply(state)
	# An attack in flight with a resumable move behind it: the deepest pending shape.
	state.pending = CombatRules.attack_pending("guard", "hero", true, state.actors["guard"]["weapon"])
	state.pending["resume"] = {"type": "move", "actor_id": "hero", "elapsed": 0.4, "distance": 1.2,
		"length": 4.0, "interruptions": [], "path": PackedVector3Array([Vector3(0, 0, 7), Vector3(0, 0, 3)])}
	state.actors["hero"]["hp"] = 5
	state.round_number = 3
	return state

func write_raw(data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(JSON.from_native(data)))
	file.close()

func test_round_trip_of_running_combat_keeps_every_value_and_type() -> void:
	var state: GameState = running_combat()
	assert_false(SaveGame.exists())
	assert_eq(SaveGame.save(state, 123456789), OK)
	assert_true(SaveGame.exists())
	var loaded: SaveGame.LoadResult = SaveGame.load_save()
	assert_true(loaded.is_valid(), String(loaded.error))
	assert_eq(loaded.version, SaveGame.VERSION)
	assert_eq(loaded.rng_state, 123456789)
	assert_eq(loaded.state.to_dict(), state.to_dict(), "Snapshot survives byte-for-byte in value")
	assert_eq(typeof(loaded.state.mode), TYPE_STRING_NAME)
	assert_eq(loaded.state.mode, &"combat")
	assert_true(loaded.state.actors["hero"]["position"] is Vector3)
	assert_true(loaded.state.pending["resume"]["path"] is PackedVector3Array)
	assert_true(loaded.state.actors["hero"]["ability_scores"].has(&"int"))
	assert_eq(loaded.state.current_actor_id(), state.current_actor_id())
	assert_eq(loaded.state.actors["hero"]["name_key"], "Mira")

func test_restored_combat_continues_through_commands() -> void:
	var state: GameState = running_combat()
	state.pending = {}
	SaveGame.save(state)
	var loaded: SaveGame.LoadResult = SaveGame.load_save()
	var fresh: GameState = GameState.new()
	var restore: RestoreSaveCommand = RestoreSaveCommand.new(loaded.state)
	assert_eq(restore.validate(fresh), OK)
	restore.apply(fresh)
	assert_eq(fresh.to_dict(), state.to_dict())
	var active: String = fresh.current_actor_id()
	assert_eq(EndTurnCommand.new(active).validate(fresh), OK, "The loaded turn can be ended")
	assert_eq(restore.validate(fresh), ERR_ALREADY_IN_USE, "Restore never overwrites a running game")

func test_dead_hero_is_never_saved_and_the_slot_is_deleted() -> void:
	var state: GameState = running_combat()
	assert_eq(SaveGame.save(state), OK)
	state.actors["hero"]["hp"] = 0
	state.mode = &"defeat"
	assert_eq(SaveGame.save(state), ERR_UNAVAILABLE)
	assert_false(SaveGame.exists(), "Permadeath deletes the ironman save")
	assert_eq(RestoreSaveCommand.new(state).validate(GameState.new()), ERR_UNAVAILABLE)

func test_on_defeat_deletes_and_ends_the_run() -> void:
	SaveGame.save(running_combat())
	SaveGame.run_active = true
	RunFlow.on_defeat()
	assert_false(SaveGame.exists())
	assert_false(SaveGame.run_active)
	assert_eq(RunFlow.save_run(), ERR_UNAVAILABLE, "A finished run is not written again")
	assert_false(SaveGame.exists())

func test_newer_version_is_reported_not_loaded() -> void:
	write_raw({"format": SaveGame.FORMAT, "version": SaveGame.VERSION + 1, "rng_state": 0,
		"state": {"future": Vector3.ONE}})
	var loaded: SaveGame.LoadResult = SaveGame.load_save()
	assert_eq(loaded.error, &"newer_version")
	assert_null(loaded.state)
	assert_eq(loaded.message_key(), "SAVE_ERROR_NEWER_VERSION")
	assert_true(SaveGame.exists(), "A newer save is kept for the newer game")

func test_corrupt_files_are_reported_not_crashing() -> void:
	for text: String in ["", "garbage {{", "[1, 2, 3]", "{\"format\": \"x\"}",
			JSON.stringify(JSON.from_native({"format": SaveGame.FORMAT, "version": "1"}))]:
		var file: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		var loaded: SaveGame.LoadResult = SaveGame.load_save()
		assert_eq(loaded.error, &"corrupt", "Rejected: " + text.left(40))
		assert_eq(loaded.message_key(), "SAVE_ERROR_CORRUPT")
	write_raw({"format": SaveGame.FORMAT, "version": SaveGame.VERSION, "rng_state": 0,
		"state": {"actors": {}, "pending": {}, "turn_order": [], "turn_index": 0,
			"round_number": 1, "mode": &"exploration"}})
	assert_eq(SaveGame.load_save().error, &"corrupt", "A save without a hero is not a run")
	write_raw({"format": SaveGame.FORMAT, "version": SaveGame.VERSION, "rng_state": 0,
		"state": {"actors": {"hero": {}}, "pending": {}, "turn_order": ["ghost"], "turn_index": 0,
			"round_number": 1, "mode": &"combat"}})
	assert_eq(SaveGame.load_save().error, &"corrupt", "Turn order must name existing actors")

func test_saved_objects_are_refused() -> void:
	var file: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	var payload: String = JSON.stringify(JSON.from_native({"format": SaveGame.FORMAT,
		"version": SaveGame.VERSION, "rng_state": 0, "state": {}}))
	payload = payload.replace("\"s:state\",{\"type\":\"Dictionary\",\"args\":[]}",
		"\"s:state\",{\"type\":\"Object\",\"args\":[\"Node\"]}")
	file.store_string(payload)
	file.close()
	assert_eq(SaveGame.load_save().error, &"corrupt")

func test_missing_save() -> void:
	assert_eq(SaveGame.load_save().error, &"missing")

func test_unsaved_test_runs_do_not_write() -> void:
	SaveGame.run_active = false
	assert_eq(RunFlow.save_run(), ERR_UNAVAILABLE)
	assert_false(SaveGame.exists())
