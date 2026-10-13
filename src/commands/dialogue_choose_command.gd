class_name DialogueChooseCommand
extends Command
## Picks one answer of the open conversation's current node. A choice with a skill check
## rolls it once (Checks.skill_check, shown in the dice popup) and goes to its success or
## failure node; otherwise it goes to "next", or ends the conversation without one.

var choice_index: int = -1

func _init(p_choice_index: int = -1) -> void:
	super("hero")
	choice_index = p_choice_index

func validate(state: GameState) -> Error:
	if not DialogueEffects.can_talk(state) or not state.world.get("conversation") is Dictionary:
		return ERR_UNAVAILABLE
	var conversation: Dictionary = state.world["conversation"]
	var data: Dictionary = DialogueData.load_dialogue(String(conversation.get("id", "")))
	if data.is_empty():
		return ERR_DOES_NOT_EXIST
	return OK if choice_index in DialogueData.available_choices(data, String(conversation.get("node", "")), state) else ERR_INVALID_PARAMETER

func apply(state: GameState) -> Dictionary:
	var conversation: Dictionary = state.world["conversation"]
	var dialogue_id: String = String(conversation["id"])
	var node_id: String = String(conversation["node"])
	var data: Dictionary = DialogueData.load_dialogue(dialogue_id)
	var choice: Dictionary = data["nodes"][node_id]["choices"][choice_index]
	var key: String = DialogueData.check_key(dialogue_id, node_id, choice_index)
	var events: Array[Dictionary] = [{"type": "dialogue_choice", "dialogue_id": dialogue_id,
		"node_id": node_id, "choice": choice_index}]
	events.append_array(DialogueEffects.apply(state, choice.get("effects", {}), key))
	var next: String = String(choice.get("next", ""))
	if choice.has("check"):
		var check: Dictionary = choice["check"]
		var roll: Dictionary = roll_check(state.actors["hero"], String(check["skill"]), int(check["dc"]))
		var rolled: Dictionary = state.world.get("dialogue_checks", {})
		rolled[key] = bool(roll["success"])
		state.world["dialogue_checks"] = rolled
		events.append(roll)
		next = String(check["success" if bool(roll["success"]) else "failure"])
	if next.is_empty():
		events.append(DialogueEffects.finish(state, dialogue_id))
	else:
		events.append_array(DialogueEffects.enter(state, data, next))
	return {"events": events}

## The hero's skill check as a roll event for the dice popup.
static func roll_check(hero: Dictionary, skill: String, dc: int) -> Dictionary:
	var scores: Dictionary = {}
	var stored: Dictionary = hero.get("ability_scores", {})
	for ability: StringName in Abilities.IDS:
		scores[ability] = int(stored.get(ability, stored.get(String(ability), 10)))
	var proficient: bool = DialogueData.has_skill(hero, skill)
	var result: CheckResult = Checks.skill_check(StringName(skill), scores, dc, Rng.rng,
		clampi(int(hero.get("level", 1)), 1, 10), proficient, null,
		proficient and DialogueData.has_expertise(hero, skill))
	var event: Dictionary = {"type": "roll", "kind": "check", "actor_id": "hero", "skill": skill,
		"dc": dc, "success": result.success}
	if result.roll != null:
		event["roll"] = CombatRules.serialize_roll(result.roll)
	return event

func to_dict() -> Dictionary:
	return {"type": "dialogue_choose", "actor_id": actor_id, "choice": choice_index}

func from_dict(data: Dictionary) -> Error:
	if data.get("type") != "dialogue_choose" or data.size() != 3 or data.get("actor_id") != "hero" or \
			not (data.get("choice") is int or data.get("choice") is float):
		return ERR_INVALID_DATA
	choice_index = int(data["choice"])
	return OK
