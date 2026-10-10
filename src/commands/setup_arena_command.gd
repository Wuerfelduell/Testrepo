class_name SetupArenaCommand
extends Command
## Fixed technical test encounter. Not character creation, inventory or a revive command.

const MONSTERS: Array[String] = [
	"res://data/monsters/guard.tres",
	"res://data/monsters/bandit.tres",
	"res://data/monsters/cultist.tres",
]
const ENEMY_POSITIONS: Array[Vector3] = [Vector3(-5, 0, -5), Vector3(5, 2, -5), Vector3(0, 0, -9)]

## Optional hero record from character creation (HeroFactory); empty = test Fighter.
var hero_record: Dictionary = {}

func _init(p_hero_record: Dictionary = {}) -> void:
	super("arena")
	hero_record = p_hero_record.duplicate(true)

func validate(state: GameState) -> Error:
	if not state.actors.is_empty() or state.mode != &"exploration" or \
			not state.turn_order.is_empty() or not state.pending.is_empty():
		return ERR_ALREADY_IN_USE
	for path: String in MONSTERS:
		var monster: MonsterDefinition = load(path) as MonsterDefinition
		if monster == null or not monster.is_valid():
			return ERR_INVALID_DATA
	if not hero_record.is_empty():
		return OK if HeroFactory.valid_record(hero_record) else ERR_INVALID_DATA
	return OK if not _hero().is_empty() else ERR_INVALID_DATA

func apply(state: GameState) -> Dictionary:
	state.actors["hero"] = _hero() if hero_record.is_empty() else hero_record.duplicate(true)
	for index: int in MONSTERS.size():
		var definition: MonsterDefinition = load(MONSTERS[index]) as MonsterDefinition
		var id: String = String(definition.id)
		state.actors[id] = definition.create_actor(id, ENEMY_POSITIONS[index])
	state.mode = &"exploration"
	state.turn_order.clear()
	state.turn_index = 0
	state.round_number = 1
	state.pending = {}
	return {"events": [{"type": "arena_ready"}], "actor_ids": state.actors.keys()}

func to_dict() -> Dictionary:
	return {"type": "setup_arena", "actor_id": actor_id}

func from_dict(data: Dictionary) -> Error:
	if data.get("type") != "setup_arena" or data.get("actor_id") != "arena" or data.size() != 2:
		return ERR_INVALID_DATA
	return OK

static func _hero() -> Dictionary:
	var definition: ClassDefinition = load("res://data/classes/fighter.tres") as ClassDefinition
	var sheet: CharacterSheet = CharacterSheet.create(definition, 1, {
		&"str": 16, &"dex": 14, &"con": 14, &"int": 10, &"wis": 12, &"cha": 8,
	})
	if sheet == null or not sheet.equip(&"chain_mail", true):
		return {}
	# These explicit skills do not silently activate feats or deferred class features.
	if not sheet.select_class_skills([&"athletics", &"perception"]) or not sheet.select_human_skill(&"arcana"):
		return {}
	var strength: int = sheet.ability_modifier(&"str")
	var proficiency: int = sheet.proficiency_bonus()
	var sword: Dictionary = {
		"id": "longsword", "name_key": "WEAPON_LONGSWORD", "ranged": false,
		"reach": 1.5, "range": 0.0, "long_range": 0.0,
		"attack_bonus": strength + proficiency, "damage_dice": "1d8",
		"damage_bonus": strength, "damage_type": "slashing",
		"attack_modifiers": [{"amount": strength, "source": "str"},
			{"amount": proficiency, "source": "proficiency"}],
		"damage_modifiers": [{"amount": strength, "source": "str"}],
		"model": "res://assets/weapons/sword.glb",
	}
	return {
		"id": "hero", "team": "hero", "name_key": "ACTOR_FIGHTER",
		"position": Vector3(0, 0, 7), "hp": sheet.maximum_hp(), "max_hp": sheet.maximum_hp(),
		"ac": sheet.armor_class(), "dex": int(sheet.ability_scores()[&"dex"]),
		"speed_m": sheet.speed_m(), "move_left": sheet.speed_m(),
		"action_available": true, "bonus_available": true, "reaction_available": true,
		"disengaged": false, "weapon": sword, "attacks": [sword.duplicate(true)],
		"model": "res://assets/characters/superhero_male_fullbody/model.glb",
		"model_is_provisional": true, "personality": "", "conditions": [],
		"class_id": String(sheet.class_id), "level": sheet.level, "species": String(sheet.species),
		"ability_scores": sheet.ability_scores(), "proficiency_bonus": proficiency,
		"skill_proficiencies": sheet.skill_proficiencies(), "passive_perception": sheet.passive_perception(),
		"armor": String(sheet.armor), "shield": sheet.shield,
		"pending_character_choices": sheet.pending_choices(), "class_features_active": false,
	}
