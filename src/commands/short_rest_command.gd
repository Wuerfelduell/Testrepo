class_name ShortRestCommand
extends Command
## Short Rest outside combat with no enemy nearby: spend Hit Point Dice (each roll is
## shown in the dice popup), recharge short-rest features, optional Arcane Recovery
## (slot levels) and Memorize Spell ([prepared spell, spellbook spell]).

var hit_dice: int = 0
var arcane_slots: Array[int] = []
var memorize: Array[String] = []

func _init(p_actor_id: String = "", p_hit_dice: int = 0, p_arcane_slots: Array[int] = [],
		p_memorize: Array[String] = []) -> void:
	actor_id = p_actor_id
	hit_dice = p_hit_dice
	arcane_slots = p_arcane_slots.duplicate()
	memorize = p_memorize.duplicate()

func validate(state: GameState) -> Error:
	match RestRules.short_rest_reason(state, actor_id, hit_dice, arcane_slots, memorize):
		"":
			return OK
		"REST_REASON_UNKNOWN":
			return ERR_INVALID_PARAMETER
		"REST_REASON_HIT_DICE", "REST_REASON_ARCANE", "REST_REASON_MEMORIZE":
			return ERR_INVALID_PARAMETER
	return ERR_UNAVAILABLE

func apply(state: GameState) -> Dictionary:
	return {"events": RestRules.short_rest(state.actors[actor_id], actor_id, hit_dice, arcane_slots, memorize, Rng.rng)}

func to_dict() -> Dictionary:
	return {"type": "short_rest", "actor_id": actor_id, "hit_dice": hit_dice,
		"arcane_slots": arcane_slots.duplicate(), "memorize": memorize.duplicate()}

func from_dict(data: Dictionary) -> Error:
	if data.size() != 5 or data.get("type") != "short_rest" or not data.get("actor_id") is String or \
			String(data["actor_id"]).is_empty() or not (data.get("hit_dice") is int or data.get("hit_dice") is float) or \
			not data.get("arcane_slots") is Array or not data.get("memorize") is Array:
		return ERR_INVALID_DATA
	var dice: float = float(data["hit_dice"])
	if dice != floorf(dice) or dice < 0.0 or dice > 20.0 or data["arcane_slots"].size() > 9 or data["memorize"].size() > 2:
		return ERR_INVALID_DATA
	var slots: Array[int] = []
	for value: Variant in data["arcane_slots"]:
		if not (value is int or value is float) or float(value) != floorf(float(value)) or int(value) < 1 or int(value) > 9:
			return ERR_INVALID_DATA
		slots.append(int(value))
	var swap: Array[String] = []
	for value: Variant in data["memorize"]:
		if not value is String or String(value).length() > 64:
			return ERR_INVALID_DATA
		swap.append(String(value))
	actor_id = data["actor_id"]
	hit_dice = int(dice)
	arcane_slots = slots
	memorize = swap
	return OK
