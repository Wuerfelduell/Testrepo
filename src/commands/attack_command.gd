class_name AttackCommand
extends Command

var target_id: String = ""
## Which entry of the actor's "attacks" to use (Multiattack: mace or Radiant Flame).
## Empty uses the equipped weapon.
var weapon_id: String = ""

func _init(p_actor_id: String = "", p_target_id: String = "", p_weapon_id: String = "") -> void:
	actor_id = p_actor_id
	target_id = p_target_id
	weapon_id = p_weapon_id

static func weapon_for(actor: Dictionary, wanted_id: String) -> Dictionary:
	if wanted_id.is_empty():
		return actor.get("weapon", {})
	for attack: Variant in actor.get("attacks", []):
		if attack is Dictionary and String(attack.get("id", "")) == wanted_id:
			return attack
	return {}

func validate(state: GameState) -> Error:
	var reason: Error = CombatRules.valid_actor_turn(state, actor_id)
	if reason != OK:
		return reason
	var actor: Dictionary = state.actors[actor_id]
	if not CombatRules.can_use_action(actor) and \
			not (int(actor.get("attacks_left", 0)) > 0 and CombatRules.conditions_for(actor).can_act()):
		return ERR_UNAVAILABLE
	var weapon: Dictionary = weapon_for(actor, weapon_id)
	if weapon.is_empty():
		return ERR_INVALID_PARAMETER
	if not bool(CombatRules.attack_preview(state, actor_id, target_id, Vector3.INF, weapon)["legal"]):
		return ERR_INVALID_PARAMETER
	return OK

func apply(state: GameState) -> Dictionary:
	var actor: Dictionary = state.actors[actor_id]
	if bool(actor.get("action_available", false)):
		# Extra Attack (Fighter 5) and Multiattack: the Attack action holds more than one attack.
		actor["action_available"] = false
		actor["attacks_left"] = ClassFeatures.attacks_per_action(actor) - 1
	else:
		actor["attacks_left"] = int(actor["attacks_left"]) - 1
	var weapon: Dictionary = {} if weapon_id.is_empty() else weapon_for(actor, weapon_id)
	state.pending = CombatRules.attack_pending(actor_id, target_id, false, weapon)
	return {"events": [CombatRules.attack_start_event(state.pending)]}

func to_dict() -> Dictionary:
	var data: Dictionary = {"type": "attack", "actor_id": actor_id, "target_id": target_id}
	if not weapon_id.is_empty():
		data["weapon_id"] = weapon_id
	return data

func from_dict(data: Dictionary) -> Error:
	var has_weapon: bool = data.has("weapon_id")
	if data.size() != (4 if has_weapon else 3) or data.get("type") != "attack" or not data.get("actor_id") is String or \
			not data.get("target_id") is String or String(data["actor_id"]).is_empty() or String(data["target_id"]).is_empty():
		return ERR_INVALID_DATA
	if has_weapon and (not data["weapon_id"] is String or String(data["weapon_id"]).is_empty()):
		return ERR_INVALID_DATA
	actor_id = data["actor_id"]
	target_id = data["target_id"]
	weapon_id = String(data.get("weapon_id", ""))
	return OK
