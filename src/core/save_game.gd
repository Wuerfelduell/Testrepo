class_name SaveGame
extends RefCounted
## Ironman save: exactly one slot. Written only when the player quits to the menu or
## closes the game, deleted when the hero dies. The file is versioned JSON produced by
## JSON.from_native without objects, so a tampered file can never instantiate code.

const VERSION: int = 1
const FORMAT: String = "the_rpg_ironman"
const DEFAULT_PATH: String = "user://ironman.save"

## Overridable by tests; the game always uses DEFAULT_PATH.
static var path: String = DEFAULT_PATH
## True while a run started from the menu is in progress. Only such runs are saved,
## so test scenes and captures never write an ironman file.
static var run_active: bool = false

class LoadResult extends RefCounted:
	## "" on success, otherwise "missing", "corrupt" or "newer_version".
	var error: StringName = &""
	var version: int = 0
	var state: GameState = null
	var rng_state: int = 0

	func is_valid() -> bool:
		return error == &""

	## Translation key of the message shown instead of crashing.
	func message_key() -> String:
		match error:
			&"newer_version": return "SAVE_ERROR_NEWER_VERSION"
			&"corrupt": return "SAVE_ERROR_CORRUPT"
			&"missing": return "SAVE_ERROR_MISSING"
		return ""

static func exists() -> bool:
	return FileAccess.file_exists(path)

## A dead hero is never saved: the slot is deleted instead (permadeath).
static func save(state: GameState, rng_state: int = 0) -> Error:
	if state == null:
		return ERR_INVALID_PARAMETER
	if state.mode == &"defeat":
		delete()
		return ERR_UNAVAILABLE
	var data: Dictionary = {"format": FORMAT, "version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"rng_state": rng_state, "state": state.to_dict()}
	var text: String = JSON.stringify(JSON.from_native(data))
	# Write next to the slot first: a crash while writing never destroys the old save.
	var temporary: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return DirAccess.rename_absolute(temporary, path)

static func load_save() -> LoadResult:
	var result: LoadResult = LoadResult.new()
	if not exists():
		result.error = &"missing"
		return result
	var text: String = FileAccess.get_file_as_string(path)
	var parser: JSON = JSON.new()
	if text.is_empty() or parser.parse(text) != OK or not parser.data is Dictionary:
		result.error = &"corrupt"
		return result
	# Read the header before decoding values: newer formats may contain types we do not know.
	var header: Dictionary = _header(parser.data)
	if header.get("format") != FORMAT or not header.get("version") is int:
		result.error = &"corrupt"
		return result
	result.version = header["version"]
	if result.version > VERSION:
		result.error = &"newer_version"
		return result
	if result.version < 1:
		result.error = &"corrupt"
		return result
	var decoded: Variant = _decode(parser.data)
	if not decoded is Dictionary or not decoded.get("state") is Dictionary or \
			not decoded.get("rng_state") is int:
		result.error = &"corrupt"
		return result
	result.state = GameState.from_dict(decoded["state"])
	if result.state == null or not result.state.actors.has("hero"):
		result.error = &"corrupt"
		result.state = null
		return result
	result.rng_state = decoded["rng_state"]
	return result

static func delete() -> void:
	for file: String in [path, path + ".tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)

## format/version are stored as "s:..." / "i:..." by JSON.from_native.
static func _header(raw: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var args: Variant = raw.get("args")
	if raw.get("type") != "Dictionary" or not args is Array or (args as Array).size() % 2 != 0:
		return result
	for index: int in range(0, (args as Array).size(), 2):
		var key: Variant = args[index]
		var value: Variant = args[index + 1]
		if key is String and key in ["s:format", "s:version"] and value is String:
			var parsed: Variant = _decode(value)
			result[String(key).trim_prefix("s:")] = parsed
	return result

static func _decode(raw: Variant) -> Variant:
	# Objects are refused: such a file is reported as corrupt, never instantiated.
	if _contains_object(raw):
		return null
	return JSON.to_native(raw, false)

static func _contains_object(raw: Variant) -> bool:
	if raw is Dictionary:
		if raw.get("type") == "Object" or raw.has("__gdtype"):
			return true
		for value: Variant in raw.values():
			if _contains_object(value):
				return true
	elif raw is Array:
		for value: Variant in raw:
			if _contains_object(value):
				return true
	return false
