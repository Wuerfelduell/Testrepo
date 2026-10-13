class_name LevelSetupCommand
extends Command
## Internal: starts a level run (package 10). The hero stands at the level's spawn; every
## encounter waits as plain data in GameState.world["dormant"] until it notices the hero.
## Only triggered encounters become GameState actors, so initiative and the end of a
## fight only ever involve the enemies of that encounter.

var level_path: String = EncounterData.CRYPT_PATH
## Optional hero record from character creation (HeroFactory); empty = test Fighter.
var hero_record: Dictionary = {}

func _init(p_hero_record: Dictionary = {}, p_level_path: String = EncounterData.CRYPT_PATH) -> void:
	super("level")
	hero_record = p_hero_record.duplicate(true)
	level_path = p_level_path

func validate(state: GameState) -> Error:
	if not state.actors.is_empty() or state.mode != &"exploration" or \
			not state.turn_order.is_empty() or not state.pending.is_empty():
		return ERR_ALREADY_IN_USE
	var level: Dictionary = EncounterData.load_level(level_path)
	if level.is_empty() or not EncounterData.problems(level).is_empty():
		return ERR_INVALID_DATA
	if not hero_record.is_empty():
		return OK if HeroFactory.valid_record(hero_record) else ERR_INVALID_DATA
	return OK

func apply(state: GameState) -> Dictionary:
	var level: Dictionary = EncounterData.load_level(level_path)
	var hero: Dictionary = HeroKit.activate(HeroKit.create(&"fighter") if hero_record.is_empty() else hero_record)
	hero["position"] = EncounterData.vector(level["hero_spawn"])
	state.actors = {"hero": hero}
	var dormant: Dictionary = {}
	for encounter: Dictionary in level["encounters"]:
		var members: Dictionary = {}
		for member: Dictionary in encounter["members"]:
			members[String(member["id"])] = EncounterData.member_record(member, String(encounter["id"]))
		dormant[String(encounter["id"])] = members
	state.world = {"level": String(level["level"]), "data_path": level_path,
		"dormant": dormant, "triggered": [], "trap_sprung": false, "rest_used": false}
	state.mode = &"exploration"
	state.turn_order.clear()
	state.turn_index = 0
	state.round_number = 1
	state.pending = {}
	return {"events": [{"type": "level_ready", "level": String(level["level"])}], "actor_ids": state.actors.keys()}

func to_dict() -> Dictionary:
	return {"type": "level_setup", "actor_id": actor_id}
