class_name EncounterData
extends RefCounted
## Level and encounter data (data/encounters/*.json): pure loading and validation.
## Commands turn the members into plain actor records; geometry stays in the level builder.

const CRYPT_PATH: String = "res://data/encounters/crypt.json"
const POSES: Array[String] = ["sleeping", "guarding", "praying", "patrol"]
## Exploration clips for each pose (assets/animations/universal.glb).
const POSE_CLIPS: Dictionary = {"sleeping": "Sitting_Idle", "guarding": "Sword_Idle",
	"praying": "Spell_Simple_Idle", "patrol": ""}
## Walking speed of patrols while nobody has noticed the hero.
const PATROL_SPEED_M: float = 1.1

static var _cache: Dictionary = {}

## Parsed level dictionary, or {} if the file is missing or not valid JSON.
static func load_level(path: String = CRYPT_PATH) -> Dictionary:
	if _cache.has(path):
		return (_cache[path] as Dictionary).duplicate(true)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	_cache[path] = parsed
	return (parsed as Dictionary).duplicate(true)

## Every problem in a level file as readable text; an empty list means valid.
static func problems(level: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = []
	if String(level.get("level", "")).is_empty():
		result.append("level id missing")
	if not ResourceLoader.exists(String(level.get("scene", ""))):
		result.append("scene missing: " + String(level.get("scene", "")))
	if not vector(level.get("hero_spawn")).is_finite():
		result.append("hero_spawn is not a position")
	var ids: Dictionary = {"hero": true}
	var encounter_ids: Dictionary = {}
	for encounter: Variant in level.get("encounters", []):
		if not encounter is Dictionary:
			result.append("encounter is not an object")
			continue
		var encounter_id: String = String(encounter.get("id", ""))
		if encounter_id.is_empty() or encounter_ids.has(encounter_id):
			result.append("encounter id empty or duplicated: " + encounter_id)
		encounter_ids[encounter_id] = true
		var members: Array = encounter.get("members", [])
		if members.is_empty():
			result.append(encounter_id + ": no members")
		for member: Variant in members:
			if not member is Dictionary:
				result.append(encounter_id + ": member is not an object")
				continue
			var member_id: String = String(member.get("id", ""))
			if member_id.is_empty() or ids.has(member_id):
				result.append(encounter_id + ": actor id empty or duplicated: " + member_id)
			ids[member_id] = true
			var definition: MonsterDefinition = monster(String(member.get("monster", "")))
			if member.has("companion"):
				if PartyRules.definition(String(member["companion"])).is_empty():
					result.append(member_id + ": unknown companion " + String(member["companion"]))
			elif definition == null or not definition.is_valid():
				result.append(member_id + ": monster has no valid SRD stat block: " + String(member.get("monster", "")))
			if not vector(member.get("position")).is_finite():
				result.append(member_id + ": position missing")
			var pose: String = String(member.get("pose", ""))
			if not pose in POSES:
				result.append(member_id + ": unknown pose " + pose)
			if pose == "patrol" and patrol_route(member).size() < 2:
				result.append(member_id + ": patrol needs two points")
	for exit: Variant in level.get("exits", []):
		if not exit is Dictionary or String(exit.get("id", "")).is_empty():
			result.append("exit without id")
			continue
		if not vector(exit.get("position")).is_finite() or not vector(exit.get("arrive")).is_finite():
			result.append(String(exit["id"]) + ": exit needs position and arrive")
		if not FileAccess.file_exists(String(exit.get("to", ""))):
			result.append(String(exit["id"]) + ": exit target missing: " + String(exit.get("to", "")))
	for encounter: Variant in level.get("encounters", []):
		if encounter is Dictionary:
			for joiner: Variant in encounter.get("joins", []):
				if not encounter_ids.has(String(joiner)) or String(joiner) == String(encounter.get("id", "")):
					result.append(String(encounter.get("id", "")) + ": joins unknown encounter " + String(joiner))
	return result

static func monster(monster_id: String) -> MonsterDefinition:
	var path: String = "res://data/monsters/%s.tres" % monster_id
	if monster_id.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as MonsterDefinition

## Plain actor record for one member, still unaware (dormant) of the hero.
static func member_record(member: Dictionary, encounter_id: String) -> Dictionary:
	var record: Dictionary = {}
	if member.has("companion"):
		# A companion before they joined (Kael's duel): their own sheet and gear, as an opponent.
		record = PartyRules.create_record(String(member["companion"]), vector(member["position"]))
		if not record.is_empty():
			record["id"] = String(member["id"])
			record["team"] = "enemy"
			record.erase("companion_id")
	else:
		var definition: MonsterDefinition = monster(String(member.get("monster", "")))
		if definition == null:
			return {}
		record = definition.create_actor(String(member["id"]), vector(member["position"]))
	if record.is_empty():
		return record
	record["encounter_id"] = encounter_id
	record["pose"] = String(member.get("pose", "guarding"))
	record["facing"] = vector(member.get("facing", [0.0, 0.0, 1.0]))
	# Encounter design may change how a creature fights (e.g. a zealous cultist), never its stats.
	if String(member.get("personality", "")) in ["brute", "archer", "coward"]:
		record["personality"] = String(member["personality"])
	if record["pose"] == "patrol":
		record["patrol"] = patrol_route(member)
	# A named person fighting with a stat block (Garrik as a Guard): name and look only.
	if member.get("name_key") is String:
		record["name_key"] = String(member["name_key"])
	if member.get("model") is String and ResourceLoader.exists(String(member["model"])):
		record["model"] = String(member["model"])
	# This member is a dialogue hook's figure: no separate dormant figure stands next to it.
	if member.get("hook") is String:
		record["hook"] = String(member["hook"])
	# Flags set when the party defeats this member (AwardVictoryXpCommand), e.g. vaelor_outcome.
	if member.get("defeat_flags") is Dictionary:
		record["defeat_flags"] = (member["defeat_flags"] as Dictionary).duplicate()
	return record

static func patrol_route(member: Dictionary) -> Array[Vector3]:
	var route: Array[Vector3] = []
	for point: Variant in member.get("patrol", []):
		var value: Vector3 = vector(point)
		if value.is_finite():
			route.append(value)
	return route

## Where a patrol is after walking for `seconds` (back and forth along its route).
static func patrol_position(route: Array, seconds: float) -> Vector3:
	if route.is_empty():
		return Vector3.INF
	if route.size() == 1:
		return route[0]
	var lengths: Array[float] = []
	var total: float = 0.0
	for index: int in range(1, route.size()):
		var length: float = (route[index] as Vector3).distance_to(route[index - 1])
		lengths.append(length)
		total += length
	if total <= 0.0:
		return route[0]
	var travelled: float = fposmod(seconds * PATROL_SPEED_M, total * 2.0)
	if travelled > total:
		travelled = total * 2.0 - travelled
	for index: int in lengths.size():
		if travelled <= lengths[index]:
			return (route[index] as Vector3).lerp(route[index + 1], travelled / maxf(lengths[index], 0.0001))
		travelled -= lengths[index]
	return route[-1]

## Shortest horizontal distance from a point to the patrol route.
static func distance_to_route(route: Array, point: Vector3) -> float:
	if route.size() == 1:
		return (route[0] as Vector3).distance_to(point)
	var best: float = INF
	for index: int in range(1, route.size()):
		var from: Vector3 = route[index - 1]
		var to: Vector3 = route[index]
		var segment: Vector3 = to - from
		var weight: float = clampf((point - from).dot(segment) / maxf(segment.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, (from + segment * weight).distance_to(point))
	return best

static func vector(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() == 3:
		for part: Variant in value:
			if not (part is float or part is int):
				return Vector3.INF
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.INF

## True when the point lies inside the room's floor area (x_min, z_min, x_max, z_max).
static func in_room(level: Dictionary, room_id: String, point: Vector3) -> bool:
	for room: Variant in level.get("rooms", []):
		if room is Dictionary and String(room.get("id", "")) == room_id:
			var area: Array = room.get("area", [])
			return area.size() == 4 and point.x >= float(area[0]) and point.x <= float(area[2]) and \
				point.z >= float(area[1]) and point.z <= float(area[3])
	return false

## Perception (exploration and joins): sleepers only notice the hero right next to them;
## the awake notice him in their own room or nearby. Line of sight is checked by the caller.
static func notices(level: Dictionary, encounter_id: String, record: Dictionary, position: Vector3, hero: Vector3) -> bool:
	# Encounters marked "on_dialogue" only fight when a conversation says so ("fight" effect).
	if bool(encounter(level, encounter_id).get("on_dialogue", false)):
		return false
	var distance: float = position.distance_to(hero)
	if String(record.get("pose", "")) == "sleeping":
		return distance <= float(level.get("sleep_notice_m", 4.0))
	if distance > float(level.get("notice_m", 12.0)):
		return false
	var room_id: String = String(encounter(level, encounter_id).get("room", ""))
	return in_room(level, room_id, hero) or distance <= float(level.get("near_notice_m", 5.0))

static func encounter(level: Dictionary, encounter_id: String) -> Dictionary:
	for entry: Variant in level.get("encounters", []):
		if entry is Dictionary and String(entry.get("id", "")) == encounter_id:
			return entry
	return {}
