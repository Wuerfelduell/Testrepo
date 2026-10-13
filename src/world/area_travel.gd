class_name AreaTravel
extends RefCounted
## Campaign package K3: several areas in one run. Only the current area lives in
## GameState.world's level keys and in GameState.actors; every area the hero left is kept
## as plain data in world["areas"][level id] and comes back exactly as it was (dead
## enemies, open encounters, sprung trap, ground loot). Flags, dialogue results and quest
## progress are global and never stashed.

## world keys that belong to one area.
const AREA_KEYS: Array[String] = ["level", "data_path", "dormant", "triggered", "trap_sprung", "rest_used"]

## A fresh area's world keys from its level file: every encounter dormant.
static func fresh_area(level: Dictionary, path: String) -> Dictionary:
	var dormant: Dictionary = {}
	for encounter: Dictionary in level.get("encounters", []):
		var members: Dictionary = {}
		for member: Dictionary in encounter["members"]:
			members[String(member["id"])] = EncounterData.member_record(member, String(encounter["id"]))
		dormant[String(encounter["id"])] = members
	return {"level": String(level["level"]), "data_path": path, "dormant": dormant,
		"triggered": [], "trap_sprung": false, "rest_used": false}

## Actors that travel with the hero: the hero and everyone on the hero's team.
static func travellers(state: GameState) -> Array[String]:
	var result: Array[String] = []
	var team: String = String(state.actors.get("hero", {}).get("team", "hero"))
	for id: String in state.actors:
		if id == "hero" or String(state.actors[id].get("team", "")) == team:
			result.append(id)
	return result

## Moves the run into another area. The current area is stashed; the target is restored
## from its stash or built fresh. Travellers stand around the arrival point.
static func move(state: GameState, target_path: String, arrive: Vector3) -> void:
	var current: String = String(state.world.get("level", ""))
	var going: Array[String] = travellers(state)
	var areas: Dictionary = state.world.get("areas", {})
	if not current.is_empty():
		var stash: Dictionary = {"actors": {}, "loot_piles": state.loot_piles.duplicate(true)}
		for key: String in AREA_KEYS:
			if state.world.has(key):
				stash[key] = state.world[key]
		for id: String in state.actors:
			if not id in going:
				stash["actors"][id] = state.actors[id]
		areas[current] = stash
	var level: Dictionary = EncounterData.load_level(target_path)
	var target_id: String = String(level["level"])
	var restored: Dictionary = areas.get(target_id, {})
	areas.erase(target_id)
	var actors: Dictionary = {}
	for index: int in range(going.size()):
		var actor: Dictionary = state.actors[going[index]]
		actor["position"] = arrive + _offset(index)
		actors[going[index]] = actor
	var area: Dictionary = restored if not restored.is_empty() else fresh_area(level, target_path)
	for id: Variant in area.get("actors", {}):
		actors[String(id)] = area["actors"][id]
	for key: String in AREA_KEYS:
		state.world.erase(key)
		if area.has(key):
			state.world[key] = area[key]
	state.world["data_path"] = target_path
	state.world["areas"] = areas
	var flags: Dictionary = state.world.get("flags", {})
	flags["visited_" + target_id] = true
	state.world["flags"] = flags
	state.actors = actors
	state.loot_piles = (area.get("loot_piles", {}) as Dictionary).duplicate(true)

## Party members line up behind the hero instead of standing inside each other.
static func _offset(index: int) -> Vector3:
	if index == 0:
		return Vector3.ZERO
	var angle: float = TAU * float(index - 1) / 3.0
	return Vector3(cos(angle), 0.0, sin(angle)) * 1.2

## The level's exit by id, or {}.
static func exit_by_id(level: Dictionary, exit_id: String) -> Dictionary:
	for exit: Dictionary in level.get("exits", []):
		if String(exit.get("id", "")) == exit_id:
			return exit
	return {}
