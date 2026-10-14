class_name DialogueEffects
extends RefCounted
## State changes of a conversation, used only from inside the dialogue commands.

const XP_REASON_KEY: String = "XP_REASON_DIALOGUE"

## Sets flags and counters, grants XP, moves money and items, hurts the hero, changes the
## party. XP is paid once per reward key, so revisiting a node or repeating a choice does
## not farm experience. Format: data/dialogue/README.md.
static func apply(state: GameState, effects: Dictionary, reward_key: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var flags: Dictionary = state.world.get("flags", {})
	var changed: Dictionary = {}
	for name: Variant in effects.get("flags", {}):
		flags[String(name)] = effects["flags"][name]
		changed[String(name)] = effects["flags"][name]
	# Counters (owner's flag list, 14-10-2026: relationship, trust, reputation): unset = 0.
	for name: Variant in effects.get("add", {}):
		var total: int = DialogueData.number(flags.get(String(name), 0)) + int(effects["add"][name])
		flags[String(name)] = total
		changed[String(name)] = total
	state.world["flags"] = flags
	if not changed.is_empty():
		events.append({"type": "flags_changed", "flags": changed})
	var amount: int = int(effects.get("xp", 0))
	var rewarded: Dictionary = state.world.get("dialogue_rewards", {})
	if amount > 0 and not rewarded.has(reward_key):
		var hero: Dictionary = state.actors["hero"]
		var sheet: CharacterSheet = AwardVictoryXpCommand.rebuild_sheet(hero)
		if sheet != null:
			rewarded[reward_key] = amount
			state.world["dialogue_rewards"] = rewarded
			var award: Progression.Award = sheet.grant_xp(amount, XP_REASON_KEY)
			hero["xp"] = sheet.xp
			hero["xp_history"] = sheet.xp_history()
			events.append({"type": "xp_awarded", "actor_id": "hero", "amount": amount,
				"reason_key": XP_REASON_KEY, "title_key": "DIALOGUE_XP_TITLE", "defeated": [],
				"total_xp": award.total_xp, "level": award.level, "gained_levels": award.gained_levels,
				"level_up_available": ProgressionRules.can_level_up(hero),
				"shared": PartyRules.share_xp(state, amount, XP_REASON_KEY)})
	var hero_record: Dictionary = state.actors.get("hero", {})
	if effects.has("money") and int(effects["money"]) != 0 and Money.change(hero_record, int(effects["money"])):
		events.append({"type": "money_changed", "actor_id": "hero", "amount": int(effects["money"]),
			"money": Money.copper(hero_record)})
	for item_id: Variant in effects.get("item", {}):
		var count: int = int(effects["item"][item_id])
		if count > 0:
			EquipmentRules.add_item(hero_record, String(item_id), count)
		elif count < 0 and not EquipmentRules.remove_item(hero_record, String(item_id), -count):
			continue
		events.append({"type": "item_changed", "actor_id": "hero", "item": String(item_id), "count": count})
	if effects.has("damage"):
		events.append_array(_damage(state, effects["damage"], reward_key))
	# Party (package K4): companions join or leave through conversations.
	if effects.has("recruit"):
		events.append_array(PartyRules.recruit(state, String(effects["recruit"])))
	if effects.has("dismiss"):
		events.append_array(PartyRules.dismiss(state, String(effects["dismiss"])))
	# Companions in the party comment and their loyalty moves; too little and they leave.
	if effects.has("react"):
		events.append_array(PartyRules.react(state, effects["react"], reward_key))
	events.append_array(PartyRules.loyalty_departures(state))
	return events

## A blow or a curse in a conversation: hurts the hero but never below 1 HP, so talking
## can never end the run (permadeath belongs to fights).
static func _damage(state: GameState, damage: Dictionary, source: String) -> Array[Dictionary]:
	var hero: Dictionary = state.actors["hero"]
	var result: DamageRules.Result = DamageRules.roll(String(damage["dice"]), StringName(String(damage["type"])),
		Rng.rng, [], false, CombatRules.defenses_for(hero))
	var amount: int = mini(result.total, maxi(0, int(hero["hp"]) - 1))
	hero["hp"] = int(hero["hp"]) - amount
	var dialogue_id: String = source.get_slice("/", 0)
	return [{"type": "roll", "kind": "damage", "actor_id": dialogue_id, "target_id": "hero",
			"roll": CombatRules.serialize_roll(result.roll), "damage_type": String(damage["type"]), "amount": amount},
		{"type": "damage", "actor_id": dialogue_id, "target_id": "hero", "amount": amount,
			"damage_type": String(damage["type"]), "hp": hero["hp"]}]

## Moves the open conversation to a node and applies that node's own effects.
static func enter(state: GameState, data: Dictionary, node_id: String) -> Array[Dictionary]:
	var dialogue_id: String = String(data["id"])
	state.world["conversation"] = {"id": dialogue_id, "node": node_id}
	var node: Dictionary = data["nodes"][node_id]
	var events: Array[Dictionary] = [{"type": "dialogue_node", "dialogue_id": dialogue_id, "node_id": node_id}]
	events.append_array(apply(state, node.get("effects", {}), "%s/%s" % [dialogue_id, node_id]))
	return events

static func finish(state: GameState, dialogue_id: String) -> Dictionary:
	state.world.erase("conversation")
	return {"type": "dialogue_end", "dialogue_id": dialogue_id}

## Valid only while the hero can talk: alive, out of combat, nothing pending.
static func can_talk(state: GameState) -> bool:
	return state.mode == &"exploration" and state.pending.is_empty() and \
		state.actors.has("hero") and CombatRules.alive(state.actors["hero"])
