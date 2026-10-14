class_name NonlethalFights
extends RefCounted
## Fights started from a conversation (owner's dialogues, 14-10-2026): Garrik's guards
## breaking knees, a brawl in the inn, Kael's duel. While world["nonlethal"] names the
## encounter, nobody dies: a creature at 0 HP is knocked out (event "knocked_out" instead of
## "death"). The fight ends when the hero or every enemy is down; then everyone knocked out
## stands up with 1 HP (whoever died earlier stays dead), the enemies go back to where the
## level placed them (no loot, no XP) and flag "<encounter>_fight" says "won" or "lost" so conversations can branch on it.

static func active(state: GameState) -> bool:
	return state.world.get("nonlethal") is Dictionary

## The event for a creature that just dropped to 0 HP: knocked out in a nonlethal fight,
## otherwise dead.
static func fall_event(state: GameState, target_id: String, killer_id: String) -> Dictionary:
	if not active(state):
		return {"type": "death", "actor_id": target_id, "killer_id": killer_id}
	state.actors[target_id]["knocked_out"] = true
	return {"type": "knocked_out", "actor_id": target_id, "killer_id": killer_id}

## Called from CombatRules.check_combat_end while a nonlethal fight runs.
static func check_end(state: GameState) -> Array[Dictionary]:
	var encounter_id: String = String(state.world["nonlethal"].get("encounter", ""))
	var hero_down: bool = not CombatRules.alive(state.actors.get("hero", {}))
	var enemy_standing: bool = false
	for id: String in state.actors:
		var actor: Dictionary = state.actors[id]
		if actor.get("team") == "enemy" and CombatRules.alive(actor):
			enemy_standing = true
	if not hero_down and enemy_standing:
		return []
	var winner: String = "enemy" if hero_down else "party"
	var returned: Array[String] = _return_enemies(state, encounter_id)
	for id: String in state.actors:
		var actor: Dictionary = state.actors[id]
		if bool(actor.get("knocked_out", false)):
			actor["hp"] = 1
			actor.erase("knocked_out")
	var flags: Dictionary = state.world.get("flags", {})
	flags[encounter_id + "_fight"] = "won" if winner == "party" else "lost"
	state.world["flags"] = flags
	state.world.erase("nonlethal")
	state.mode = &"exploration"
	state.pending = {}
	ClassKits.on_combat_end(state)
	return [{"type": "nonlethal_end", "encounter_id": encounter_id, "winner": winner, "returned": returned,
		"flags": {encounter_id + "_fight": flags[encounter_id + "_fight"]}},
		{"type": "combat_end", "mode": "exploration", "nonlethal": winner}]

## The encounter's members leave the fight and wait again as the level placed them, so the
## same conversation (and fight) can happen again.
static func _return_enemies(state: GameState, encounter_id: String) -> Array[String]:
	var returned: Array[String] = []
	for id: String in state.actors.keys():
		if state.actors[id].get("team") == "enemy":
			state.actors.erase(id)
			returned.append(id)
	var encounter: Dictionary = EncounterData.encounter(
		EncounterData.load_level(String(state.world.get("data_path", EncounterData.CRYPT_PATH))), encounter_id)
	var members: Dictionary = {}
	for member: Dictionary in encounter.get("members", []):
		members[String(member["id"])] = EncounterData.member_record(member, encounter_id)
	if not members.is_empty():
		var dormant: Dictionary = state.world.get("dormant", {})
		dormant[encounter_id] = members
		state.world["dormant"] = dormant
		(state.world.get("triggered", []) as Array).erase(encounter_id)
	returned.sort()
	return returned
