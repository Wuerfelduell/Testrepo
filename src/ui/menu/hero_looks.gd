class_name HeroLooks
extends RefCounted
## Look variants for character creation. assets/characters/hero_looks.json (written by the
## art package) wins when it lists looks for a class and body; otherwise the existing human
## models are offered. New looks therefore appear without code changes.

const LOOKS_PATH: String = "res://assets/characters/hero_looks.json"
const FALLBACK: Dictionary = {
	"male": [
		{"id": "male_hero", "scene": "res://assets/characters/superhero_male_fullbody/model.glb"},
		{"id": "male_ranger", "scene": "res://assets/characters/male_ranger/model.glb"},
		{"id": "male_peasant", "scene": "res://assets/characters/male_peasant/model.glb"},
	],
	"female": [
		{"id": "female_hero", "scene": "res://assets/characters/superhero_female_fullbody/model.glb"},
		{"id": "female_ranger", "scene": "res://assets/characters/female_ranger/model.glb"},
		{"id": "female_peasant", "scene": "res://assets/characters/female_peasant/model.glb"},
	],
}

## Looks for one class and body ("male"/"female"), in file order.
static func for_class(class_id: String, body: String, path: String = LOOKS_PATH) -> Array[Dictionary]:
	var listed: Array[Dictionary] = []
	if FileAccess.file_exists(path):
		listed = parse(FileAccess.get_file_as_string(path))
	var result: Array[Dictionary] = []
	for look: Dictionary in listed:
		if (look["class"].is_empty() or look["class"] == class_id) and look["body"] == body:
			result.append(look)
	if result.is_empty():
		for look: Dictionary in FALLBACK.get(body, []):
			var entry: Dictionary = look.duplicate()
			entry["class"] = ""
			entry["body"] = body
			result.append(entry)
	return result

## Accepts an array of entries or {"looks": [...]}. Field names are read leniently so the
## art package's file format can grow: class|class_id, body|sex, id|look_id, scene|scene_path|model.
static func parse(text: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK:
		return result
	var entries: Variant = parser.data
	if entries is Dictionary:
		entries = entries.get("looks", [])
	if not entries is Array:
		return result
	for raw: Variant in entries:
		if not raw is Dictionary:
			continue
		var scene: String = String(_first(raw, ["scene", "scene_path", "model", "path"]))
		var body: String = _body(String(_first(raw, ["body", "sex", "gender"])))
		if body.is_empty() or not scene.begins_with("res://") or not ResourceLoader.exists(scene):
			continue
		result.append({"id": String(_first(raw, ["id", "look_id", "look"], scene.get_base_dir().get_file())),
			"class": String(_first(raw, ["class", "class_id"])).to_lower(), "body": body, "scene": scene})
	return result

static func _first(raw: Dictionary, keys: Array, fallback: Variant = "") -> Variant:
	for key: String in keys:
		if raw.has(key) and raw[key] != null:
			return raw[key]
	return fallback

static func _body(value: String) -> String:
	match value.to_lower():
		"m", "male", "man", "masculine": return "male"
		"f", "female", "woman", "feminine": return "female"
	return ""
