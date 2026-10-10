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
	# HeroKit activates level-1 class features (spells, Second Wind) for any hero record.
	state.actors["hero"] = HeroKit.activate(_hero() if hero_record.is_empty() else hero_record)
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
	return HeroKit.create(&"fighter")
