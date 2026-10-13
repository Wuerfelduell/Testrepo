extends GutTest
## Package 11: audio mapping, buses, music states and the Audio autoload hooks.

const TEST_SETTINGS: String = "user://test_audio_settings.cfg"

class ArenaSetup extends Command:
	var mode: StringName = &"exploration"
	var boss: bool = false

	func validate(_state: GameState) -> Error:
		return OK

	func apply(state: GameState) -> Dictionary:
		state.actors = {
			"hero": {"team": "hero", "hp": 12, "dex": 14, "speed_m": 9.0, "position": Vector3.ZERO},
			"enemy": {"team": "enemy", "hp": 7, "dex": 10, "speed_m": 9.0, "position": Vector3(3, 0, 0),
				"model": "res://assets/characters/boss_cult_priest/model.glb" if boss else "res://assets/characters/enemy_guard/model.glb"},
		}
		state.pending = {}
		state.turn_order.clear()
		state.mode = mode
		return {}

class ClearRun extends Command:
	func validate(_state: GameState) -> Error:
		return OK

	func apply(state: GameState) -> Dictionary:
		state.actors = {}
		state.pending = {}
		state.turn_order.clear()
		state.mode = &"exploration"
		return {}

func _state(mode: StringName, boss: bool = false) -> GameState:
	var state: GameState = GameState.new()
	var setup: ArenaSetup = ArenaSetup.new()
	setup.mode = mode
	setup.boss = boss
	setup.apply(state)
	return state

func after_all() -> void:
	CommandBus.submit(ClearRun.new())

# --- buses and options ------------------------------------------------------------------

func test_all_buses_exist_and_route_into_the_option_buses() -> void:
	for bus: String in ["Master", "Music", "Effects", "Ambience", "UI"]:
		assert_gt(AudioServer.get_bus_index(bus), -1, bus)
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index("Music")), &"Master")
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index("Effects")), &"Master")
	# The options menu has Master/Music/Effects sliders; ambience and UI follow Effects.
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index("Ambience")), &"Effects")
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index("UI")), &"Effects")

func test_master_has_a_limiter_against_clipping() -> void:
	var master: int = AudioServer.get_bus_index("Master")
	assert_gt(AudioServer.get_bus_effect_count(master), 0)
	assert_true(AudioServer.get_bus_effect(master, 0) is AudioEffectHardLimiter)

func test_volume_options_change_the_buses() -> void:
	var settings: GameSettings = GameSettings.new()
	settings.path = TEST_SETTINGS
	add_child_autofree(settings)
	settings.set_option("Music", 0.5)
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(0.5), 0.01)
	settings.set_option("Effects", 0.0)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects")))
	settings.set_option("Effects", 1.0)
	settings.set_option("Music", 0.8)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))

# --- every mapped event has a sound -----------------------------------------------------

func test_every_mapped_cue_has_an_existing_sound_file() -> void:
	if not DirAccess.dir_exists_absolute("res://assets/audio"):
		pending("Sound set not imported yet (waiting for the owner's answer on music sources)")
		return
	for cue: String in SoundLibrary.all_event_cues():
		assert_true(SoundLibrary.CUES.has(cue), "cue defined: " + cue)
		var paths: PackedStringArray = SoundLibrary.cue_paths(cue)
		assert_false(paths.is_empty(), "cue has files: " + cue)
		for path: String in paths:
			assert_true(ResourceLoader.exists(path), "file exists: " + path)

func test_every_music_state_and_ambience_has_a_file() -> void:
	if not DirAccess.dir_exists_absolute("res://assets/audio"):
		pending("Sound set not imported yet (waiting for the owner's answer on music sources)")
		return
	for music_state: StringName in SoundLibrary.MUSIC_STATES:
		assert_true(ResourceLoader.exists(SoundLibrary.music_path(music_state)), String(music_state))
	for id: String in SoundLibrary.AMBIENCE:
		assert_true(ResourceLoader.exists(SoundLibrary.ambience_path(id)), id)

func test_sound_files_are_ogg_vorbis() -> void:
	for cue: String in SoundLibrary.CUES:
		for path: String in SoundLibrary.cue_paths(cue):
			assert_eq(path.get_extension(), "ogg", path)
			if ResourceLoader.exists(path):
				assert_true(load(path) is AudioStreamOggVorbis, path)

# --- event mapping ----------------------------------------------------------------------

func _cues(event: Dictionary) -> Array:
	return SoundLibrary.cues_for_event(event, _state(&"combat")).map(func(entry: Dictionary) -> String: return entry["cue"])

func test_combat_events_map_to_sounds() -> void:
	assert_eq(_cues({"type": "start_attack", "actor_id": "hero", "weapon": {"ranged": false}}), ["swing_melee"])
	assert_eq(_cues({"type": "start_attack", "actor_id": "hero", "weapon": {"ranged": true}}), ["shot_ranged"])
	assert_eq(_cues({"type": "roll", "kind": "attack", "hit": false, "critical": false, "target_id": "enemy"}), ["miss"])
	assert_eq(_cues({"type": "roll", "kind": "attack", "hit": true, "critical": true, "target_id": "enemy"}), ["critical"])
	assert_eq(_cues({"type": "roll", "kind": "attack", "hit": true, "critical": false}), [])
	assert_eq(_cues({"type": "damage", "damage_type": "slashing", "target_id": "enemy"}), ["hit_slashing"])
	assert_eq(_cues({"type": "damage", "damage_type": "fire", "target_id": "enemy"}), ["hit_fire"])
	assert_eq(_cues({"type": "damage", "damage_type": "necrotic", "target_id": "enemy"}), ["hit_generic"])
	assert_eq(_cues({"type": "death", "actor_id": "enemy"}), ["death"])
	assert_eq(_cues({"type": "heal", "actor_id": "hero"}), ["heal"])
	assert_eq(_cues({"type": "xp_awarded", "gained_levels": 1}), ["level_up"])
	assert_eq(_cues({"type": "xp_awarded", "gained_levels": 0}), [])

func test_hits_are_positional_at_the_target() -> void:
	var entries: Array[Dictionary] = SoundLibrary.cues_for_event(
		{"type": "damage", "damage_type": "piercing", "target_id": "enemy"}, _state(&"combat"))
	assert_eq(entries[0]["position"], Vector3(3, 0, 0))

func test_spells_have_cast_and_impact_sounds_with_fallback() -> void:
	for spell_id: String in SoundLibrary.SPELLS:
		assert_true(SoundLibrary.CUES.has(SoundLibrary.spell_cue(spell_id, "cast")), spell_id)
		assert_ne(SoundLibrary.spell_cue(spell_id, "cast"), "spell_cast", spell_id)
	assert_eq(_cues({"type": "start_spell", "spell_id": "fire_bolt", "actor_id": "hero"}), ["spell_cast_fire_bolt"])
	assert_eq(SoundLibrary.spell_cue("unknown_spell", "impact"), "spell_impact")
	assert_eq(SoundLibrary.spell_cue("magic_missile", "impact"), "spell_impact_magic_missile")

func test_every_spell_in_data_has_its_own_sounds() -> void:
	for file: String in DirAccess.get_files_at("res://data/spells"):
		if file.get_extension() == "tres":
			assert_true(file.get_basename() in SoundLibrary.SPELLS, file)

func test_loot_and_level_up_commands_are_recognised_by_name() -> void:
	var loot: Array = SoundLibrary.cues_for_command("res://src/commands/loot_take_command.gd", {}, GameState.new())
	assert_eq(loot[0]["cue"], "loot_pickup")
	var level: Array = SoundLibrary.cues_for_command("res://src/commands/level_up_command.gd", {}, GameState.new())
	assert_eq(level[0]["cue"], "level_up")

func test_footsteps_follow_the_surface() -> void:
	assert_eq(SoundLibrary.footstep_cue("water"), "footstep_water")
	assert_eq(SoundLibrary.footstep_cue("lava"), "footstep_stone")
	Audio.register_surface(AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)), "wood")
	assert_eq(Audio.surface_at(Vector3.ZERO), "wood")
	assert_eq(Audio.surface_at(Vector3(10, 0, 0)), "stone")
	Audio.clear_surfaces()

func test_walking_plays_a_footstep_per_stride() -> void:
	watch_signals(Audio)
	var state: GameState = _state(&"exploration")
	state.pending = {"type": "move", "actor_id": "hero", "distance": 0.3}
	Audio._step_marks.clear()
	Audio._update_footsteps(state)
	assert_signal_emit_count(Audio, "cue_played", 0)
	state.pending["distance"] = 0.9
	Audio._update_footsteps(state)
	state.pending["distance"] = 1.2
	Audio._update_footsteps(state)
	state.pending["distance"] = 1.8
	Audio._update_footsteps(state)
	assert_signal_emit_count(Audio, "cue_played", 2)
	assert_eq(get_signal_parameters(Audio, "cue_played", 0)[0], "footstep_stone")
	Audio._step_marks.clear()

# --- music states -----------------------------------------------------------------------

func test_music_state_follows_the_game_mode() -> void:
	assert_eq(SoundLibrary.music_state_for(GameState.new(), &"menu"), &"menu")
	assert_eq(SoundLibrary.music_state_for(_state(&"exploration"), &"menu"), &"exploration")
	assert_eq(SoundLibrary.music_state_for(_state(&"combat"), &"exploration"), &"combat")
	assert_eq(SoundLibrary.music_state_for(_state(&"combat", true), &"exploration"), &"boss")
	assert_eq(SoundLibrary.music_state_for(_state(&"exploration"), &"combat"), &"victory")
	assert_eq(SoundLibrary.music_state_for(_state(&"exploration"), &"victory"), &"victory")
	assert_eq(SoundLibrary.music_state_for(_state(&"defeat"), &"combat"), &"death")
	assert_eq(SoundLibrary.music_state_for(_state(&"exploration"), &"death"), &"exploration")

func test_dead_boss_no_longer_counts() -> void:
	var state: GameState = _state(&"combat", true)
	state.actors["enemy"]["hp"] = 0
	assert_false(SoundLibrary.boss_alive(state))

func test_music_changes_on_combat_start_and_end() -> void:
	Audio.set_music_state(&"menu")
	CommandBus.submit(ArenaSetup.new())
	assert_eq(Audio.music_state, &"exploration")
	assert_eq(CommandBus.submit(StartCombatCommand.new()), OK)
	assert_eq(Audio.music_state, &"combat")
	CommandBus.submit(ArenaSetup.new())
	assert_eq(Audio.music_state, &"victory")
	Audio._on_music_finished(Audio._music_active)
	assert_eq(Audio.music_state, &"exploration")
	CommandBus.submit(ClearRun.new())
	assert_eq(Audio.music_state, &"exploration", "an empty run keeps the current track")

func test_buttons_play_a_click() -> void:
	watch_signals(Audio)
	var button: Button = Button.new()
	add_child_autofree(button)
	button.pressed.emit()
	assert_signal_emitted_with_parameters(Audio, "cue_played", ["ui_click", Vector3.INF])
