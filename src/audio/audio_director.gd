class_name AudioDirector
extends Node
## Autoload "Audio" (package 11). Presentation only: it listens to CommandBus/EventBus and to
## UI nodes entering the tree, and never changes game state. Mapping lives in SoundLibrary.
## Missing sound files are skipped silently, so the game runs before every file exists.

signal music_state_changed(music_state: StringName)
signal cue_played(cue: String, position: Vector3)

const SFX_VOICES: int = 12
const SFX_3D_VOICES: int = 16
## Positional sounds: full volume inside this radius, fading out towards max_distance.
const UNIT_SIZE: float = 6.0
const MAX_DISTANCE: float = 45.0
const DRIP_INTERVAL: Vector2 = Vector2(3.5, 11.0)
## The dice popup tumbles until this point of its own timeline, then the dice hit the table.
const DICE_LAND_AT: float = 0.65

var music_state: StringName = &""
var _music_players: Array[AudioStreamPlayer] = []
var _music_active: int = 0
var _music_tween: Tween
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_3d: Array[AudioStreamPlayer3D] = []
var _sfx_next: int = 0
var _sfx_3d_next: int = 0
var _room_tone: AudioStreamPlayer
var _whispers: AudioStreamPlayer3D
var _drip_timer: float = 0.0
var _streams: Dictionary = {}
var _random: RandomNumberGenerator = RandomNumberGenerator.new()
## actor_id -> metres walked at the last footstep of the current move.
var _step_marks: Dictionary = {}
## The cast that is waiting for its impact: {"spell_id", "point"}.
var _pending_spell: Dictionary = {}
## Registered by levels: [{"box": AABB, "surface": String}].
var _surfaces: Array[Dictionary] = []
var _dice_popups: Array[Control] = []
var _dice_landed: Dictionary = {}
## False with the dummy audio driver (headless CI, machines without sound): nothing would be
## heard, and streams still held by the AudioServer at quit are reported as leaks, which CI
## treats as errors. Cues, music states and signals work the same either way.
var _audible: bool = AudioServer.get_driver_name() != "Dummy"

func _ready() -> void:
	# Cosmetic randomness only (which variation plays); never the game's Rng.
	_random.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index: int in range(2):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = "Music"
		player.volume_db = -80.0
		player.finished.connect(_on_music_finished.bind(index))
		add_child(player)
		_music_players.append(player)
	for index: int in range(SFX_VOICES):
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(voice)
		_sfx.append(voice)
	for index: int in range(SFX_3D_VOICES):
		var voice_3d: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		_configure_3d(voice_3d)
		add_child(voice_3d)
		_sfx_3d.append(voice_3d)
	_room_tone = AudioStreamPlayer.new()
	_room_tone.bus = "Ambience"
	add_child(_room_tone)
	_whispers = AudioStreamPlayer3D.new()
	_configure_3d(_whispers)
	_whispers.bus = "Ambience"
	_whispers.unit_size = 4.0
	_whispers.max_distance = 22.0
	add_child(_whispers)
	CommandBus.command_applied.connect(_on_command_applied)
	EventBus.state_changed.connect(_on_state_changed)
	get_tree().node_added.connect(_on_node_added)

# --- public API -------------------------------------------------------------------------

## Plays one cue; a finite position makes it positional in the 3D world.
func play_cue(cue: String, position: Vector3 = Vector3.INF) -> void:
	if not SoundLibrary.CUES.has(cue):
		return
	var stream: AudioStream = _random_stream(SoundLibrary.cue_paths(cue))
	cue_played.emit(cue, position)
	if stream == null:
		return
	var definition: Dictionary = SoundLibrary.CUES[cue]
	var pitch: float = _random.randf_range(0.94, 1.06)
	if position.is_finite() and get_viewport().get_camera_3d() != null:
		var voice_3d: AudioStreamPlayer3D = _sfx_3d[_sfx_3d_next]
		_sfx_3d_next = (_sfx_3d_next + 1) % _sfx_3d.size()
		voice_3d.stream = stream
		voice_3d.bus = String(definition["bus"])
		voice_3d.volume_db = float(definition["volume_db"])
		voice_3d.pitch_scale = pitch
		voice_3d.global_position = position
		voice_3d.play()
		return
	var voice: AudioStreamPlayer = _sfx[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx.size()
	voice.stream = stream
	voice.bus = String(definition["bus"])
	voice.volume_db = float(definition["volume_db"])
	voice.pitch_scale = pitch
	voice.play()

## Crossfades to the track of a music state ("menu", "exploration", "combat", "boss",
## "victory", "death"). Same state again does nothing.
func set_music_state(next_state: StringName) -> void:
	if next_state == music_state or not SoundLibrary.MUSIC.has(next_state):
		return
	music_state = next_state
	music_state_changed.emit(music_state)
	var outgoing: AudioStreamPlayer = _music_players[_music_active]
	_music_active = 1 - _music_active
	var incoming: AudioStreamPlayer = _music_players[_music_active]
	var stream: AudioStream = _load(SoundLibrary.music_path(next_state))
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = bool(SoundLibrary.MUSIC[next_state]["loop"])
	if _music_tween != null:
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(outgoing, "volume_db", -80.0, SoundLibrary.CROSSFADE_SECONDS)
	incoming.stop()
	incoming.stream = stream
	if stream != null:
		incoming.volume_db = -80.0
		incoming.play()
		_music_tween.tween_property(incoming, "volume_db", SoundLibrary.MUSIC_VOLUME_DB,
			SoundLibrary.CROSSFADE_SECONDS).set_trans(Tween.TRANS_SINE)
	_music_tween.chain().tween_callback(outgoing.stop)

## Levels mark floor areas: "stone" (default), "dirt", "wood", "water".
func register_surface(box: AABB, surface: String) -> void:
	_surfaces.append({"box": box, "surface": surface})

func clear_surfaces() -> void:
	_surfaces.clear()

func surface_at(position: Vector3) -> String:
	for index: int in range(_surfaces.size() - 1, -1, -1):
		if (_surfaces[index]["box"] as AABB).grow(0.05).has_point(position):
			return String(_surfaces[index]["surface"])
	return SoundLibrary.DEFAULT_SURFACE

# --- hooks ------------------------------------------------------------------------------

func _on_command_applied(command: Command, result: Dictionary) -> void:
	var state: GameState = Game.state
	var path: String = command.get_script().resource_path if command.get_script() != null else ""
	for entry: Dictionary in SoundLibrary.cues_for_command(path, result, state):
		play_cue(String(entry["cue"]), entry["position"])
	for event: Variant in result.get("events", []):
		if not event is Dictionary:
			continue
		match String(event.get("type", "")):
			"start_spell":
				var point: Variant = event.get("point")
				_pending_spell = {"spell_id": String(event.get("spell_id", "")),
					"point": point if point is Vector3 else Vector3.INF}
			"start_move", "move_end":
				_step_marks.erase(String(event.get("actor_id", "")))
	_update_spell_impact(state)
	_update_footsteps(state)

func _on_state_changed() -> void:
	var state: GameState = Game.state
	if state.actors.is_empty():
		_step_marks.clear()
		_pending_spell = {}
	set_music_state(SoundLibrary.music_state_for(state, music_state))
	_update_ambience(state)

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(play_cue.bind("ui_click"))
	elif node is DicePopup:
		var popup: DicePopup = node
		_dice_popups.append(popup)
		popup.roll_started.connect(_on_roll_started.bind(popup))
		popup.tree_exiting.connect(func() -> void: _dice_popups.erase(popup))
	elif node is MainMenu:
		set_music_state(&"menu")
		_update_ambience(Game.state)
	elif node is DeathScreen:
		set_music_state(&"death")

func _on_roll_started(event: Dictionary, popup: DicePopup) -> void:
	_dice_landed[popup.get_instance_id()] = not _has_d20(event)
	if _has_d20(event):
		play_cue("dice_roll")

func _process(delta: float) -> void:
	for popup: Control in _dice_popups:
		_check_dice_landing(popup as DicePopup)
	if _room_tone.playing:
		_drip_timer -= delta
		if _drip_timer <= 0.0:
			_drip_timer = _random.randf_range(DRIP_INTERVAL.x, DRIP_INTERVAL.y)
			var listener: Camera3D = get_viewport().get_camera_3d()
			if listener != null:
				var offset: Vector3 = Vector3(_random.randf_range(-9.0, 9.0), _random.randf_range(0.5, 3.0), _random.randf_range(-9.0, 9.0))
				play_cue("amb_drip", listener.global_position + offset)

func _check_dice_landing(popup: DicePopup) -> void:
	var id: int = popup.get_instance_id()
	if bool(_dice_landed.get(id, true)):
		return
	# DicePopup has no landing signal and belongs to another package, so its timeline is read.
	if float(popup.get("_elapsed")) < DICE_LAND_AT:
		return
	_dice_landed[id] = true
	var current: Dictionary = popup.get("_current")
	var roll: Dictionary = current.get("roll", {})
	play_cue("dice_land")
	if bool(roll.get("natural_20", false)):
		play_cue("dice_crit")
	elif bool(roll.get("natural_1", false)):
		play_cue("dice_fumble")

static func _has_d20(event: Dictionary) -> bool:
	for group: Variant in event.get("roll", {}).get("groups", []):
		if group is Dictionary and int(group.get("sides", 0)) == 20:
			return true
	return false

func _update_spell_impact(state: GameState) -> void:
	if _pending_spell.is_empty():
		return
	# The impact has happened once the spell's pending record is impacted or gone.
	var pending: Dictionary = state.pending
	if pending.get("type") == "spell" and not bool(pending.get("impacted", false)):
		return
	play_cue(SoundLibrary.spell_cue(String(_pending_spell["spell_id"]), "impact"), _pending_spell["point"])
	_pending_spell = {}

func _update_footsteps(state: GameState) -> void:
	var pending: Dictionary = state.pending
	if pending.get("type") != "move":
		return
	var mover: String = String(pending.get("actor_id", ""))
	var walked: float = float(pending.get("distance", 0.0))
	var last: float = float(_step_marks.get(mover, 0.0))
	if walked - last < SoundLibrary.STEP_METRES:
		return
	_step_marks[mover] = walked
	var position: Vector3 = SoundLibrary.actor_position(state, mover)
	play_cue(SoundLibrary.footstep_cue(surface_at(position)), position)

func _update_ambience(state: GameState) -> void:
	var in_world: bool = not state.actors.is_empty() and state.mode != &"defeat"
	var in_menu: bool = get_tree().current_scene is MainMenu
	if in_world or in_menu:
		if not _room_tone.playing:
			var tone: AudioStream = _load(SoundLibrary.ambience_path("room_tone"))
			if tone is AudioStreamOggVorbis:
				(tone as AudioStreamOggVorbis).loop = true
			_room_tone.stream = tone
			_room_tone.volume_db = float(SoundLibrary.AMBIENCE["room_tone"]["volume_db"])
			if tone != null:
				_room_tone.play()
	else:
		_room_tone.stop()
	var boss: String = SoundLibrary.boss_id(state) if in_world else ""
	if boss.is_empty():
		_whispers.stop()
		return
	_whispers.global_position = SoundLibrary.actor_position(state, boss) + Vector3.UP * 1.6
	if not _whispers.playing:
		var whispers: AudioStream = _load(SoundLibrary.ambience_path("whispers"))
		if whispers is AudioStreamOggVorbis:
			(whispers as AudioStreamOggVorbis).loop = true
		_whispers.stream = whispers
		_whispers.volume_db = float(SoundLibrary.AMBIENCE["whispers"]["volume_db"])
		if whispers != null:
			_whispers.play()

func _on_music_finished(index: int) -> void:
	# Only the victory stinger ends on its own; afterwards exploration music returns.
	if index == _music_active and music_state == &"victory":
		set_music_state(&"exploration")

# --- helpers ----------------------------------------------------------------------------

func _configure_3d(player: AudioStreamPlayer3D) -> void:
	player.unit_size = UNIT_SIZE
	player.max_distance = MAX_DISTANCE
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.bus = "Effects"

func _random_stream(paths: PackedStringArray) -> AudioStream:
	var available: Array[AudioStream] = []
	for path: String in paths:
		var stream: AudioStream = _load(path)
		if stream != null:
			available.append(stream)
	if available.is_empty():
		return null
	return available[_random.randi_range(0, available.size() - 1)]

func _load(path: String) -> AudioStream:
	if path.is_empty() or not _audible:
		return null
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	return _streams[path]
