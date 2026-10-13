class_name QuestLog
extends RefCounted
## Quests (campaign package K3) are pure functions of the world flags: data/quests/<id>.json
## says when a quest starts, which stage text applies and when it is done or failed. No
## quest state is saved of its own; the flags already are (see data/quests/README.md).

const DIRECTORY: String = "res://data/quests/"

static var _cache: Dictionary = {}

static func all_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for file: String in DirAccess.get_files_at(DIRECTORY):
		if file.ends_with(".json"):
			ids.append(file.get_basename())
	ids.sort()
	return ids

static func load_quest(quest_id: String) -> Dictionary:
	if _cache.has(quest_id):
		return _cache[quest_id]
	var path: String = DIRECTORY + quest_id + ".json"
	if not quest_id.is_valid_identifier() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_cache[quest_id] = parsed if parsed is Dictionary else {}
	return _cache[quest_id]

static func problems(quest: Dictionary) -> PackedStringArray:
	var found: PackedStringArray = []
	if not quest.get("id") is String or not quest.get("title") is String:
		found.append("id and title are required strings")
	var stages: Variant = quest.get("stages")
	if not stages is Array or (stages as Array).is_empty():
		found.append("stages must be a non-empty list")
	else:
		for index: int in range((stages as Array).size()):
			var stage: Variant = stages[index]
			if not stage is Dictionary or not stage.get("text") is String:
				found.append("stage %d: text is required" % index)
			else:
				found.append_array(DialogueData.condition_problems(stage.get("if", []), "stage %d" % index))
	for key: String in ["start_if", "done_if", "failed_if"]:
		if quest.has(key):
			found.append_array(DialogueData.condition_problems(quest[key], key))
	for pair: Array in [["done_if", "done_text"], ["failed_if", "failed_text"]]:
		if quest.has(pair[0]) and not quest.get(pair[1]) is String:
			found.append("%s needs %s" % pair)
	if not quest.has("start_if"):
		found.append("start_if is required")
	return found

## {"state": "hidden" | "active" | "done" | "failed", "text": current journal text}.
## The latest stage whose conditions hold is the current one; failing wins over done.
static func status(quest: Dictionary, state: GameState) -> Dictionary:
	if not DialogueData.conditions_met(quest.get("start_if", []), state):
		return {"state": "hidden", "text": ""}
	if quest.has("failed_if") and DialogueData.conditions_met(quest["failed_if"], state):
		return {"state": "failed", "text": String(quest["failed_text"])}
	if quest.has("done_if") and DialogueData.conditions_met(quest["done_if"], state):
		return {"state": "done", "text": String(quest["done_text"])}
	var text: String = ""
	for stage: Dictionary in quest["stages"]:
		if DialogueData.conditions_met(stage.get("if", []), state):
			text = String(stage["text"])
	return {"state": "active", "text": text}

## Quest id -> status, for every visible quest. Used to notice journal changes.
static func snapshot(state: GameState) -> Dictionary:
	var result: Dictionary = {}
	for id: String in all_ids():
		var current: Dictionary = status(load_quest(id), state)
		if current["state"] != "hidden":
			result[id] = current
	return result

## Ids whose status differs between two snapshots (new, advanced, done or failed).
static func changed(before: Dictionary, after: Dictionary) -> PackedStringArray:
	var ids: PackedStringArray = []
	for id: String in after:
		if not before.has(id) or before[id] != after[id]:
			ids.append(id)
	return ids
