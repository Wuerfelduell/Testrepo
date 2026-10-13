class_name PartyRules
extends RefCounted
## The party (campaign package 4): the hero plus up to three companions. Companions are
## ordinary actors with team "hero", so initiative, rests and spells already treat them as
## allies. The order lives in GameState.world["party"] (hero first). A companion who left
## waits as a plain record in world["companions"] and comes back exactly as they were.
## Companion definitions: data/companions/companions.json (placeholders until the owner
## decides who the three Overcity companions are).

const MAX_SIZE: int = 4
const DATA_PATH: String = "res://data/companions/companions.json"
const ID_PREFIX: String = "companion_"
## Follow formation behind the leader, as (sideways, back) in metres. Extra candidates are
## tried when a spot is blocked or off the navigation mesh.
const FOLLOW_OFFSETS: Array[Vector2] = [Vector2(-1.1, 1.2), Vector2(1.1, 1.2), Vector2(0.0, 2.3),
	Vector2(-1.6, 0.0), Vector2(1.6, 0.0), Vector2(-1.1, 2.4), Vector2(1.1, 2.4), Vector2(0.0, 3.4)]
## Living actors closer than this block a follow or join spot.
const SPOT_CLEARANCE_M: float = 0.85

static var _definitions: Dictionary = {}

# Definitions ---------------------------------------------------------------------------

## Companion id -> definition from data/companions/companions.json.
static func definitions() -> Dictionary:
	if _definitions.is_empty() and FileAccess.file_exists(DATA_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary and parsed.get("companions") is Array:
			for entry: Variant in parsed["companions"]:
				if entry is Dictionary and entry.get("id") is String:
					_definitions[String(entry["id"])] = entry
	return _definitions

static func definition(companion_id: String) -> Dictionary:
	return definitions().get(companion_id, {})

## Everything wrong with the definitions file, as readable lines (empty = valid).
static func problems() -> PackedStringArray:
	var found: PackedStringArray = []
	if definitions().is_empty():
		found.append("no companions in " + DATA_PATH)
	for id: String in definitions():
		var entry: Dictionary = definitions()[id]
		if not id.begins_with(ID_PREFIX) or not id.is_valid_identifier():
			found.append("%s: ids start with %s and are identifiers" % [id, ID_PREFIX])
		if not entry.get("name") is String or String(entry["name"]).is_empty():
			found.append(id + ": name is required")
		if not HeroFactory.is_playable(String(entry.get("class_id", ""))):
			found.append(id + ": class_id must be a playable class " + str(HeroFactory.PLAYABLE))
		if not ResourceLoader.exists(String(entry.get("model", ""))):
			found.append(id + ": model does not exist")
		if create_record(id).is_empty():
			found.append(id + ": record could not be built")
	return found

## A fresh level-1 companion record (class kit, standard array, starting gear), or {}.
static func create_record(companion_id: String, position: Vector3 = Vector3.ZERO) -> Dictionary:
	var entry: Dictionary = definition(companion_id)
	if entry.is_empty():
		return {}
	var record: Dictionary = HeroFactory.build_record(String(entry.get("class_id", "")),
		{"scene": String(entry.get("model", ""))}, String(entry.get("name", "")), entry.get("colors", {}))
	if record.is_empty():
		return {}
	record["id"] = companion_id
	record["companion_id"] = companion_id
	record["position"] = position
	record = HeroKit.activate(record)
	EquipmentRules.initialize(record, String(record["class_id"]), InventoryCommand.training_for(record))
	return record

# Members -------------------------------------------------------------------------------

## Party actor ids in order, hero first. Saves from before companions are just ["hero"].
static func members(state: GameState) -> Array[String]:
	var result: Array[String] = []
	if state.actors.has("hero"):
		result.append("hero")
	for id: Variant in state.world.get("party", []):
		if String(id) != "hero" and state.actors.has(String(id)) and not String(id) in result:
			result.append(String(id))
	return result

static func living_members(state: GameState) -> Array[String]:
	return members(state).filter(func(id: String) -> bool: return CombatRules.alive(state.actors[id]))

static func is_member(state: GameState, actor_id: String) -> bool:
	return not actor_id.is_empty() and actor_id in members(state)

static func has_room(state: GameState) -> bool:
	return members(state).size() < MAX_SIZE

## "" when the companion may join now, otherwise the translation key of the reason.
static func recruit_reason(state: GameState, companion_id: String) -> String:
	if definition(companion_id).is_empty():
		return "PARTY_REASON_UNKNOWN"
	if is_member(state, companion_id):
		return "PARTY_REASON_MEMBER"
	if not has_room(state):
		return "PARTY_REASON_FULL"
	if not state.actors.has("hero") or not CombatRules.alive(state.actors["hero"]):
		return "PARTY_REASON_NO_HERO"
	return ""

## Adds a companion next to the hero. Only called from commands (dialogue effects).
static func recruit(state: GameState, companion_id: String) -> Array[Dictionary]:
	var reason: String = recruit_reason(state, companion_id)
	if not reason.is_empty():
		return [{"type": "party_refused", "actor_id": companion_id, "reason_key": reason}]
	var waiting: Dictionary = state.world.get("companions", {})
	var record: Dictionary = waiting.get(companion_id, {})
	waiting.erase(companion_id)
	state.world["companions"] = waiting
	if record.is_empty():
		record = create_record(companion_id)
	record["position"] = free_spot(state, state.actors["hero"]["position"], Vector3.FORWARD)
	record["move_left"] = float(record.get("speed_m", 9.0))
	state.actors[companion_id] = record
	var order: Array = state.world.get("party", ["hero"]).duplicate()
	if not "hero" in order:
		order.push_front("hero")
	order.append(companion_id)
	state.world["party"] = order
	return [{"type": "party_joined", "actor_id": companion_id, "party": members(state)}]

## A companion leaves: their record waits in world["companions"], the actor disappears.
static func dismiss(state: GameState, companion_id: String) -> Array[Dictionary]:
	if companion_id == "hero" or not is_member(state, companion_id):
		return [{"type": "party_refused", "actor_id": companion_id, "reason_key": "PARTY_REASON_NOT_MEMBER"}]
	var waiting: Dictionary = state.world.get("companions", {})
	waiting[companion_id] = state.actors[companion_id]
	state.world["companions"] = waiting
	state.actors.erase(companion_id)
	var order: Array = state.world.get("party", []).duplicate()
	order.erase(companion_id)
	state.world["party"] = order
	return [{"type": "party_left", "actor_id": companion_id, "party": members(state)}]

# Placement -----------------------------------------------------------------------------

## Follow destinations for the other living members when `leader_id` walks to
## `destination`: the formation behind the leader, facing along the walk.
static func follow_spots(state: GameState, leader_id: String, destination: Vector3) -> Dictionary:
	var result: Dictionary = {}
	var start: Vector3 = state.actors[leader_id]["position"]
	var forward: Vector3 = Vector3(destination.x - start.x, 0.0, destination.z - start.z)
	forward = forward.normalized() if forward.length() > 0.05 else Vector3.FORWARD
	var taken: Array[Vector3] = [destination]
	for id: String in living_members(state):
		if id == leader_id:
			continue
		var spot: Vector3 = _spot(state, id, destination, forward, taken)
		if spot.is_finite():
			result[id] = spot
			taken.append(spot)
	return result

## A free point near `center` on walkable ground (never on another living actor).
static func free_spot(state: GameState, center: Vector3, forward: Vector3) -> Vector3:
	var spot: Vector3 = _spot(state, "", center, forward, [center])
	return spot if spot.is_finite() else center

static func _spot(state: GameState, actor_id: String, center: Vector3, forward: Vector3, taken: Array[Vector3]) -> Vector3:
	var side: Vector3 = forward.cross(Vector3.UP).normalized()
	var space: CombatSpace = CombatSpace.current()
	for offset: Vector2 in FOLLOW_OFFSETS:
		var wanted: Vector3 = center + side * offset.x - forward * offset.y
		var candidate: Vector3 = space.closest_point(wanted)
		if not candidate.is_finite() or Vector2(candidate.x - wanted.x, candidate.z - wanted.z).length() > 0.3:
			continue
		if _occupied(state, actor_id, candidate, taken):
			continue
		if not actor_id.is_empty() and CombatRules.movement_path(state, actor_id, candidate).is_empty():
			continue
		return candidate
	return Vector3.INF

static func _occupied(state: GameState, actor_id: String, point: Vector3, taken: Array[Vector3]) -> bool:
	for other: Vector3 in taken:
		if other.distance_to(point) < SPOT_CLEARANCE_M:
			return true
	for id: String in state.actors:
		var actor: Dictionary = state.actors[id]
		if id != actor_id and CombatRules.alive(actor) and (actor["position"] as Vector3).distance_to(point) < SPOT_CLEARANCE_M:
			return true
	return false

# Experience ----------------------------------------------------------------------------

## Every living companion receives the same XP as the hero (BG3 style). Returns one entry
## per companion: {"actor_id", "total_xp", "level_up_available"}.
static func share_xp(state: GameState, amount: int, reason_key: String) -> Array[Dictionary]:
	var shared: Array[Dictionary] = []
	if amount <= 0:
		return shared
	for id: String in living_members(state):
		if id == "hero":
			continue
		var actor: Dictionary = state.actors[id]
		var sheet: CharacterSheet = AwardVictoryXpCommand.rebuild_sheet(actor)
		if sheet == null or not sheet.grant_xp(amount, reason_key).is_valid():
			continue
		actor["xp"] = sheet.xp
		actor["xp_history"] = sheet.xp_history()
		shared.append({"actor_id": id, "total_xp": sheet.xp, "level_up_available": ProgressionRules.can_level_up(actor)})
	return shared
