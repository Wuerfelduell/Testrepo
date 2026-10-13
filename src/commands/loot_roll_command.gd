class_name LootRollCommand
extends Command
## Rolls what a creature that just died leaves behind (data/items/loot_tables.json), via Rng.
## Submitted by the arena right after the death event; never by a client.

func validate(state: GameState) -> Error:
	if not state.actors.has(actor_id):
		return ERR_INVALID_PARAMETER
	var record: Dictionary = state.actors[actor_id]
	if CombatRules.alive(record) or record.has("loot") or String(record.get("team", "")) != "enemy":
		return ERR_ALREADY_IN_USE
	return OK

func apply(state: GameState) -> Dictionary:
	var record: Dictionary = state.actors[actor_id]
	record["loot"] = LootRules.roll(String(record.get("definition_id", record.get("id", ""))), Rng.rng)
	return {"events": [{"type": "loot_rolled", "actor_id": actor_id, "loot": record["loot"].duplicate(true)}]}

func to_dict() -> Dictionary:
	return {"type": "loot_roll", "actor_id": actor_id}
