class_name RestoreSaveCommand
extends Command
## Internal: loads an ironman snapshot into a fresh game. Never accepted from CommandCodec.

var snapshot: GameState = null

func _init(p_snapshot: GameState = null) -> void:
	super("game")
	snapshot = p_snapshot

func validate(state: GameState) -> Error:
	if snapshot == null or not snapshot.actors.has("hero"):
		return ERR_INVALID_DATA
	if snapshot.mode == &"defeat":
		return ERR_UNAVAILABLE
	return OK if state.actors.is_empty() else ERR_ALREADY_IN_USE

func apply(state: GameState) -> Dictionary:
	var source: GameState = snapshot.copy()
	state.actors = source.actors
	state.pending = source.pending
	state.turn_order = source.turn_order
	state.turn_index = source.turn_index
	state.round_number = source.round_number
	state.mode = source.mode
	return {"events": [{"type": "save_restored"}]}

func to_dict() -> Dictionary:
	return {"type": "restore_save", "actor_id": actor_id}
