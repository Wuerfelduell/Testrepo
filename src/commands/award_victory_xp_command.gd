class_name AwardVictoryXpCommand
extends Command
## Internal: after an area is cleared, every defeated enemy's SRD experience goes to the
## hero through CharacterSheet.grant_xp. Each enemy pays out once.

const REASON_KEY: String = "XP_REASON_AREA_CLEARED"

func _init() -> void:
	super("hero")

func validate(state: GameState) -> Error:
	if state.mode != &"exploration" or not state.pending.is_empty():
		return ERR_UNAVAILABLE
	if not state.actors.has("hero") or not CombatRules.alive(state.actors["hero"]):
		return ERR_UNAVAILABLE
	var any_defeated: bool = false
	for id: String in state.actors:
		var actor: Dictionary = state.actors[id]
		if actor.get("team") != "enemy":
			continue
		if CombatRules.alive(actor):
			return ERR_UNAVAILABLE
		any_defeated = any_defeated or not bool(actor.get("xp_awarded", false))
	if not any_defeated:
		return ERR_ALREADY_EXISTS
	return OK if rebuild_sheet(state.actors["hero"]) != null else ERR_INVALID_DATA

func apply(state: GameState) -> Dictionary:
	var hero: Dictionary = state.actors["hero"]
	var amount: int = 0
	var defeated: Array[String] = []
	var ids: Array = state.actors.keys()
	ids.sort()
	for id: String in ids:
		var actor: Dictionary = state.actors[id]
		if actor.get("team") == "enemy" and not bool(actor.get("xp_awarded", false)):
			amount += maxi(0, int(actor.get("experience", 0)))
			defeated.append(String(actor.get("name_key", "")))
			actor["xp_awarded"] = true
	var sheet: CharacterSheet = rebuild_sheet(hero)
	var award: Progression.Award = sheet.grant_xp(amount, REASON_KEY)
	hero["xp"] = sheet.xp
	hero["level"] = sheet.level
	hero["xp_history"] = sheet.xp_history()
	return {"events": [{"type": "xp_awarded", "actor_id": "hero", "amount": amount,
		"reason_key": REASON_KEY, "defeated": defeated, "total_xp": award.total_xp,
		"level": award.level, "gained_levels": award.gained_levels}]}

func to_dict() -> Dictionary:
	return {"type": "award_victory_xp", "actor_id": actor_id}

## The hero record is plain data; its sheet is rebuilt by replaying the XP history.
static func rebuild_sheet(hero: Dictionary) -> CharacterSheet:
	var path: String = "res://data/classes/%s.tres" % String(hero.get("class_id", ""))
	if not ResourceLoader.exists(path) or not hero.get("ability_scores") is Dictionary:
		return null
	var sheet: CharacterSheet = CharacterSheet.create(load(path) as ClassDefinition, 1, hero["ability_scores"])
	if sheet == null:
		return null
	for entry: Variant in hero.get("xp_history", []):
		if not entry is Dictionary or not sheet.grant_xp(int(entry.get("amount", -1)), String(entry.get("reason", ""))).is_valid():
			return null
	return sheet
