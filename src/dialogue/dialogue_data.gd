class_name DialogueData
extends RefCounted
## Conversation trees (campaign package 1). One JSON file per conversation in
## data/dialogue/<id>.json; the format is described in data/dialogue/README.md.
## Pure functions over plain data: the commands change state, the panel only shows it.
## Texts are English source strings passed through tr(), so a German translation can
## later be added as a catalogue keyed by these strings.

const DIRECTORY: String = "res://data/dialogue/"
const CONDITION_KEYS: Array[String] = ["flag", "is", "class", "proficient"]

static var _cache: Dictionary = {}

static func path_for(dialogue_id: String) -> String:
	return DIRECTORY + dialogue_id + ".json"

static func exists(dialogue_id: String) -> bool:
	return not dialogue_id.is_empty() and dialogue_id.is_valid_identifier() and FileAccess.file_exists(path_for(dialogue_id))

## The parsed tree, or {} when the file is missing or not a JSON object.
static func load_dialogue(dialogue_id: String) -> Dictionary:
	if _cache.has(dialogue_id):
		return _cache[dialogue_id]
	if not exists(dialogue_id):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path_for(dialogue_id)))
	var data: Dictionary = parsed if parsed is Dictionary else {}
	_cache[dialogue_id] = data
	return data

static func all_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for file: String in DirAccess.get_files_at(DIRECTORY):
		if file.ends_with(".json"):
			ids.append(file.get_basename())
	ids.sort()
	return ids

## Everything wrong with a tree, as readable lines (empty = valid).
static func problems(data: Dictionary) -> PackedStringArray:
	var found: PackedStringArray = []
	var nodes: Variant = data.get("nodes")
	if not data.get("id") is String or not data.get("speaker") is String:
		found.append("id and speaker are required strings")
	if not nodes is Dictionary or (nodes as Dictionary).is_empty():
		found.append("nodes must be a non-empty object")
		return found
	var start: Variant = data.get("start")
	if not start is Array or (start as Array).is_empty():
		found.append("start must be a non-empty list")
	else:
		for entry: Variant in start:
			if not entry is Dictionary or not nodes.has(String(entry.get("node", ""))):
				found.append("start entry points to a missing node: %s" % str(entry))
			else:
				found.append_array(condition_problems(entry.get("if", []), "start"))
	for node_id: Variant in nodes:
		var node: Variant = nodes[node_id]
		var where: String = "node %s" % node_id
		if not node is Dictionary or not node.get("text") is String:
			found.append(where + ": text is required")
			continue
		found.append_array(_effect_problems(node.get("effects", {}), where))
		var choices: Variant = node.get("choices", [])
		if not choices is Array:
			found.append(where + ": choices must be a list")
			continue
		for index: int in range((choices as Array).size()):
			var choice: Variant = choices[index]
			var at: String = "%s choice %d" % [where, index]
			if not choice is Dictionary or not choice.get("text") is String:
				found.append(at + ": text is required")
				continue
			found.append_array(condition_problems(choice.get("if", []), at))
			found.append_array(_effect_problems(choice.get("effects", {}), at))
			var check: Variant = choice.get("check")
			if check != null:
				if not check is Dictionary or not Abilities.SKILLS.has(StringName(String(check.get("skill", "")))):
					found.append(at + ": check needs a known skill")
				elif not (check.get("dc") is float or check.get("dc") is int) or int(check["dc"]) < 1 or int(check["dc"]) > 30:
					found.append(at + ": check dc must be 1-30")
				else:
					for outcome: String in ["success", "failure"]:
						if not nodes.has(String(check.get(outcome, ""))):
							found.append(at + ": check %s points to a missing node" % outcome)
			elif choice.has("next") and not nodes.has(String(choice["next"])):
				found.append(at + ": next points to a missing node")
	return found

static func condition_problems(conditions: Variant, where: String) -> PackedStringArray:
	var found: PackedStringArray = []
	if not conditions is Array:
		return PackedStringArray([where + ": if must be a list"])
	for condition: Variant in conditions:
		if not condition is Dictionary or condition.is_empty():
			found.append(where + ": empty condition")
			continue
		for key: Variant in condition:
			if not String(key) in CONDITION_KEYS:
				found.append(where + ": unknown condition " + String(key))
		if condition.has("proficient") and not Abilities.SKILLS.has(StringName(String(condition["proficient"]))):
			found.append(where + ": unknown skill " + String(condition["proficient"]))
	return found

static func _effect_problems(effects: Variant, where: String) -> PackedStringArray:
	if not effects is Dictionary:
		return PackedStringArray([where + ": effects must be an object"])
	var found: PackedStringArray = []
	for key: Variant in effects:
		if not String(key) in ["flags", "xp"]:
			found.append(where + ": unknown effect " + String(key))
	if effects.has("flags") and not effects["flags"] is Dictionary:
		found.append(where + ": flags must be an object")
	if effects.has("xp") and (not (effects["xp"] is float or effects["xp"] is int) or int(effects["xp"]) < 0):
		found.append(where + ": xp must be a positive number")
	return found

# Conditions ------------------------------------------------------------------------------

static func flags(state: GameState) -> Dictionary:
	return state.world.get("flags", {})

## All conditions must hold. {"flag": f} needs the flag set; add "is": false for unset,
## or "is": <value> for an exact value. {"class": id}, {"proficient": skill} test the hero.
static func conditions_met(conditions: Variant, state: GameState) -> bool:
	if not conditions is Array:
		return false
	var hero: Dictionary = state.actors.get("hero", {})
	for condition: Dictionary in conditions:
		if condition.has("flag"):
			var value: Variant = flags(state).get(String(condition["flag"]), false)
			var wanted: Variant = condition.get("is", true)
			if wanted is bool:
				if bool(value) != wanted:
					return false
			elif str(value) != str(wanted):
				return false
		if condition.has("class") and String(hero.get("class_id", "")) != String(condition["class"]):
			return false
		if condition.has("proficient") and not has_skill(hero, String(condition["proficient"])):
			return false
	return true

static func has_skill(hero: Dictionary, skill: String) -> bool:
	for owned: Variant in hero.get("skill_proficiencies", []):
		if String(owned) == skill:
			return true
	return false

static func has_expertise(hero: Dictionary, skill: String) -> bool:
	for owned: Variant in hero.get("skill_expertise", []):
		if String(owned) == skill:
			return true
	return false

## The first start entry whose conditions hold, or "" if none does.
static func start_node(data: Dictionary, state: GameState) -> String:
	for entry: Dictionary in data.get("start", []):
		if conditions_met(entry.get("if", []), state):
			return String(entry["node"])
	return ""

## Key under which a check's result is remembered: every check is rolled only once.
static func check_key(dialogue_id: String, node_id: String, index: int) -> String:
	return "%s/%s/%d" % [dialogue_id, node_id, index]

## Indices into the node's choices that the hero may pick right now: conditions hold and
## a skill check has not been rolled before (a failed persuasion cannot be retried).
static func available_choices(data: Dictionary, node_id: String, state: GameState) -> Array[int]:
	var result: Array[int] = []
	var node: Dictionary = data.get("nodes", {}).get(node_id, {})
	var choices: Array = node.get("choices", [])
	var rolled: Dictionary = state.world.get("dialogue_checks", {})
	for index: int in range(choices.size()):
		var choice: Dictionary = choices[index]
		if not conditions_met(choice.get("if", []), state):
			continue
		if choice.has("check") and rolled.has(check_key(String(data.get("id", "")), node_id, index)):
			continue
		result.append(index)
	return result
