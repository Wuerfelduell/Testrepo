class_name WeaponMasteries
extends RefCounted
## SRD 5.2 Weapon Mastery properties for kit classes (Barbarian, Ranger ...). Graze and
## Sap already live in CombatRules/ActiveEffects. Here: Vex, Slow, Topple and Cleave.
## Push and Nick are not built yet (no forced movement, no off-hand attacks).
## A mastery works only with the weapon kinds in features["weapon_mastery"]["weapons"].

const BUILT: Array[String] = ["graze", "sap", "vex", "slow", "topple", "cleave"]

## Weapon ids (items.json) whose mastery the actor can use.
static func known(actor: Dictionary) -> Array:
	return actor.get("features", {}).get("weapon_mastery", {}).get("weapons", [])

static func mastery_of(actor: Dictionary, weapon: Dictionary) -> String:
	var item_id: String = String(weapon.get("item_id", weapon.get("id", "")))
	if not weapon.get("spell_id", "") in ["", null] or not item_id in known(actor):
		return ""
	return String(weapon.get("mastery", ""))

## Melee and ranged weapons in the catalog the actor could pick for Weapon Mastery.
static func options(actor: Dictionary, weapon_categories: Array) -> Array[String]:
	var result: Array[String] = []
	for item_id: String in ItemCatalog.ids():
		var item: Dictionary = ItemCatalog.get_item(item_id)
		if String(item.get("type", "")) == "weapon" and String(item.get("mastery", "")) in BUILT and \
				StringName(String(item.get("category", ""))) in weapon_categories and not item_id in known(actor):
			result.append(item_id)
	return result

static func ability_modifier(weapon: Dictionary) -> int:
	for modifier: Dictionary in weapon.get("damage_modifiers", []):
		if String(modifier.get("source", "")) in ["str", "dex"]:
			return int(modifier.get("amount", 0))
	return 0

## Vex: advantage on the attacker's next attack roll against that creature before the
## end of the attacker's next turn.
static func attack_advantages(state: GameState, attacker_id: String, target_id: String) -> Array[StringName]:
	var vex: Dictionary = state.actors.get(attacker_id, {}).get("mastery_vex", {})
	if String(vex.get("target_id", "")) == target_id:
		return [&"vex"]
	return []

static func on_turn_start(state: GameState, actor_id: String) -> void:
	var actor: Dictionary = state.actors[actor_id]
	actor.erase("cleave_used")

## Vex set on an earlier turn ends with this turn.
static func on_turn_end(state: GameState, actor_id: String) -> void:
	var actor: Dictionary = state.actors[actor_id]
	var vex: Dictionary = actor.get("mastery_vex", {})
	if vex.is_empty():
		return
	if bool(vex.get("fresh", false)):
		vex["fresh"] = false
	else:
		actor.erase("mastery_vex")

static func after_attack(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		hit: bool, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var attacker: Dictionary = state.actors[attacker_id]
	# Any attack roll against the vexed creature uses up the advantage.
	if String(attacker.get("mastery_vex", {}).get("target_id", "")) == target_id:
		attacker.erase("mastery_vex")
	var mastery: String = mastery_of(attacker, weapon)
	var target: Dictionary = state.actors.get(target_id, {})
	if not hit or mastery.is_empty() or target.is_empty():
		return events
	match mastery:
		"vex":
			attacker["mastery_vex"] = {"target_id": target_id, "fresh": true}
			events.append({"type": "effect", "actor_id": target_id, "source_id": attacker_id, "kind": "vex"})
		"slow":
			if CombatRules.alive(target):
				ActiveEffects.remove_where(target, func(effect: Dictionary) -> bool:
					return String(effect.get("kind", "")) == "speed_penalty" and String(effect.get("source_id", "")) == attacker_id \
						and String(effect.get("mastery", "")) == "slow")
				ActiveEffects.add(target, {"kind": "speed_penalty", "amount": 3.0, "source_id": attacker_id,
					"turn_of": attacker_id, "until": "start_of_turn", "mastery": "slow"})
				events.append({"type": "effect", "actor_id": target_id, "source_id": attacker_id, "kind": "slow"})
		"topple":
			if CombatRules.alive(target) and not CombatRules.conditions_for(target).has(&"prone"):
				var dc: int = 8 + ability_modifier(weapon) + int(attacker.get("proficiency_bonus", 2))
				var save: Dictionary = SpellRules.roll_save(target, &"con", dc, rng)
				events.append(ActiveEffects.save_event(attacker_id, target_id, "topple", save))
				if not bool(save["success"]):
					# Prone until the start of its next turn; standing up costs half its Speed then.
					ActiveEffects.add(target, {"kind": "topple", "condition": "prone", "source_id": attacker_id,
						"turn_of": target_id, "until": "start_of_turn"})
					ActiveEffects.add(target, {"kind": "speed_penalty", "amount": float(target.get("speed_m", 9.0)) * 0.5,
						"source_id": attacker_id, "turn_of": attacker_id, "until": "start_of_turn"})
					events.append({"type": "condition", "actor_id": target_id, "condition": "prone", "source_id": attacker_id})
		"cleave":
			events.append_array(_cleave(state, attacker_id, target_id, weapon, rng))
	return events

## Cleave: once per turn, after a melee hit, one attack against a second creature within
## 1.5 m of the first and within reach; no ability modifier to its damage unless negative.
static func _cleave(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var attacker: Dictionary = state.actors[attacker_id]
	if bool(attacker.get("cleave_used", false)) or bool(weapon.get("ranged", false)) or bool(weapon.get("cleave", false)):
		return []
	var first: Dictionary = state.actors[target_id]
	var best: String = ""
	var best_distance: float = INF
	var ids: Array = state.actors.keys()
	ids.sort()
	for id: String in ids:
		var other: Dictionary = state.actors[id]
		if id == target_id or id == attacker_id or other.get("team") == attacker.get("team") or not CombatRules.alive(other):
			continue
		if not other.get("position") is Vector3 or not first.get("position") is Vector3:
			continue
		if (other["position"] as Vector3).distance_to(first["position"]) > 1.5 + CombatRules.EPSILON:
			continue
		var distance: float = (other["position"] as Vector3).distance_to(attacker["position"])
		if distance < best_distance:
			best = id
			best_distance = distance
	if best.is_empty():
		return []
	attacker["cleave_used"] = true
	var swing: Dictionary = weapon.duplicate(true)
	swing["cleave"] = true
	var kept: Array = []
	for modifier: Dictionary in swing.get("damage_modifiers", []):
		if not String(modifier.get("source", "")) in ["str", "dex"] or int(modifier.get("amount", 0)) < 0:
			kept.append(modifier)
	swing["damage_modifiers"] = kept
	var events: Array[Dictionary] = [{"type": "feature", "actor_id": attacker_id, "feature_id": "cleave", "target_id": best}]
	if not bool(CombatRules.attack_preview(state, attacker_id, best, Vector3.INF, swing)["legal"]):
		return []
	events.append_array(CombatRules.resolve_attack(state, attacker_id, best, swing, rng))
	return events
