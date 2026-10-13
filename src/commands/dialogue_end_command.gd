class_name DialogueEndCommand
extends Command
## Leaves the open conversation (Escape). Its flags and rolled checks stay.

func _init() -> void:
	super("hero")

func validate(state: GameState) -> Error:
	return OK if state.world.get("conversation") is Dictionary else ERR_UNAVAILABLE

func apply(state: GameState) -> Dictionary:
	var dialogue_id: String = String(state.world["conversation"].get("id", ""))
	return {"events": [DialogueEffects.finish(state, dialogue_id)]}

func to_dict() -> Dictionary:
	return {"type": "dialogue_end", "actor_id": actor_id}
