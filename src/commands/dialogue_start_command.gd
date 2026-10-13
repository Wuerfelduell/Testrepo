class_name DialogueStartCommand
extends Command
## Opens a conversation (data/dialogue/<id>.json) at its first start node whose
## conditions hold. Only out of combat, and only one conversation at a time.

var dialogue_id: String = ""

func _init(p_dialogue_id: String = "") -> void:
	super("hero")
	dialogue_id = p_dialogue_id

func validate(state: GameState) -> Error:
	if not DialogueEffects.can_talk(state) or state.world.has("conversation"):
		return ERR_UNAVAILABLE
	var data: Dictionary = DialogueData.load_dialogue(dialogue_id)
	if data.is_empty() or not DialogueData.problems(data).is_empty():
		return ERR_DOES_NOT_EXIST
	return OK if not DialogueData.start_node(data, state).is_empty() else ERR_UNAVAILABLE

func apply(state: GameState) -> Dictionary:
	var data: Dictionary = DialogueData.load_dialogue(dialogue_id)
	var events: Array[Dictionary] = [{"type": "dialogue_start", "dialogue_id": dialogue_id}]
	events.append_array(DialogueEffects.enter(state, data, DialogueData.start_node(data, state)))
	return {"events": events}

func to_dict() -> Dictionary:
	return {"type": "dialogue_start", "actor_id": actor_id, "dialogue_id": dialogue_id}

func from_dict(data: Dictionary) -> Error:
	if data.get("type") != "dialogue_start" or data.size() != 3 or data.get("actor_id") != "hero" or \
			not data.get("dialogue_id") is String:
		return ERR_INVALID_DATA
	dialogue_id = data["dialogue_id"]
	return OK
