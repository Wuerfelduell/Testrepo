class_name LevelTrapCommand
extends Command
## Internal: the hero stepped on the level's pressure plate (package 10). Dexterity
## saving throw against the trap's DC; on a failure the darts deal their damage.
## Provisional numbers (see data/encounters/crypt.json), not an SRD trap stat block.

func _init(p_trap_id: String = "") -> void:
	super(p_trap_id)

func validate(state: GameState) -> Error:
	var trap: Dictionary = _trap(state)
	if trap.is_empty() or String(trap["id"]) != actor_id or bool(state.world.get("trap_sprung", false)):
		return ERR_UNAVAILABLE
	if not state.actors.has("hero") or not CombatRules.alive(state.actors["hero"]) or state.mode == &"defeat":
		return ERR_UNAVAILABLE
	return OK if inside(trap, state.actors["hero"]["position"]) else ERR_INVALID_PARAMETER

func apply(state: GameState) -> Dictionary:
	var trap: Dictionary = _trap(state)
	var hero: Dictionary = state.actors["hero"]
	state.world["trap_sprung"] = true
	var save: Dictionary = SpellRules.roll_save(hero, StringName(trap["save_ability"]), int(trap["save_dc"]), Rng.rng)
	var events: Array[Dictionary] = [{"type": "trap_sprung", "trap_id": actor_id, "target_id": "hero"},
		ActiveEffects.save_event(actor_id, "hero", "", save)]
	if bool(save["success"]):
		return {"events": events}
	var damage: DamageRules.Result = DamageRules.roll(String(trap["damage_dice"]), StringName(trap["damage_type"]),
		Rng.rng, [], false, CombatRules.defenses_for(hero))
	hero["hp"] = maxi(0, int(hero["hp"]) - damage.total)
	events.append({"type": "roll", "kind": "damage", "actor_id": actor_id, "target_id": "hero",
		"roll": CombatRules.serialize_roll(damage.roll), "damage_type": String(trap["damage_type"]), "amount": damage.total})
	events.append({"type": "damage", "actor_id": actor_id, "target_id": "hero",
		"amount": damage.total, "damage_type": String(trap["damage_type"]), "hp": hero["hp"]})
	if int(hero["hp"]) <= 0:
		events.append({"type": "death", "actor_id": "hero", "killer_id": actor_id})
		state.mode = &"defeat"
		state.pending = {}
		events.append({"type": "combat_end", "mode": "defeat"})
	return {"events": events}

func to_dict() -> Dictionary:
	return {"type": "level_trap", "actor_id": actor_id}

static func inside(trap: Dictionary, position: Vector3) -> bool:
	var low: Vector3 = EncounterData.vector(trap.get("min"))
	var high: Vector3 = EncounterData.vector(trap.get("max"))
	return low.is_finite() and high.is_finite() and position.x >= low.x and position.x <= high.x and \
		position.y >= low.y and position.y <= high.y and position.z >= low.z and position.z <= high.z

static func _trap(state: GameState) -> Dictionary:
	var level: Dictionary = EncounterData.load_level(String(state.world.get("data_path", "")))
	var trap: Dictionary = level.get("trap", {})
	return trap if String(trap.get("id", "")) != "" else {}
