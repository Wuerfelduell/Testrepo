class_name TravelCommand
extends Command
## The hero takes one of the current level's exits ("exits" in data/encounters/*.json)
## into another area (campaign package K3). Only out of combat and within reach; the
## presentation changes the scene after the "travel" event (RunFlow.enter_area).

const REACH_M: float = 2.5

var exit_id: String = ""

func _init(p_exit_id: String = "") -> void:
	super("hero")
	exit_id = p_exit_id

func validate(state: GameState) -> Error:
	if not DialogueEffects.can_talk(state) or state.world.has("conversation"):
		return ERR_UNAVAILABLE
	var level: Dictionary = EncounterData.load_level(String(state.world.get("data_path", "")))
	var exit: Dictionary = AreaTravel.exit_by_id(level, exit_id)
	if exit.is_empty():
		return ERR_DOES_NOT_EXIST
	if not DialogueData.conditions_met(exit.get("if", []), state):
		return ERR_UNAVAILABLE
	var target: Dictionary = EncounterData.load_level(String(exit.get("to", "")))
	if target.is_empty() or not EncounterData.problems(target).is_empty():
		return ERR_INVALID_DATA
	var hero: Vector3 = state.actors["hero"]["position"]
	var door: Vector3 = EncounterData.vector(exit["position"])
	return OK if Vector2(hero.x - door.x, hero.z - door.z).length() <= REACH_M else ERR_PARAMETER_RANGE_ERROR

func apply(state: GameState) -> Dictionary:
	var level: Dictionary = EncounterData.load_level(String(state.world["data_path"]))
	var exit: Dictionary = AreaTravel.exit_by_id(level, exit_id)
	var from: String = String(level["level"])
	AreaTravel.move(state, String(exit["to"]), EncounterData.vector(exit["arrive"]))
	return {"events": [{"type": "travel", "from": from, "to": String(state.world["level"]), "exit_id": exit_id}]}

func to_dict() -> Dictionary:
	return {"type": "travel", "actor_id": actor_id, "exit_id": exit_id}

func from_dict(data: Dictionary) -> Error:
	if data.get("type") != "travel" or data.size() != 3 or data.get("actor_id") != "hero" or \
			not data.get("exit_id") is String:
		return ERR_INVALID_DATA
	exit_id = data["exit_id"]
	return OK
