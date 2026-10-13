extends GutTest
## Cult Priest (SRD 5.2 "Priest"): Multiattack with mace or Radiant Flame, Spirit Guardians
## (1/day) and Healing Word (3/day) as uses per day, and the AI that picks among them.

class Setup extends Command:
	var fixture: GameState
	func _init(value: GameState) -> void:
		fixture = value
	func validate(_state: GameState) -> Error:
		return OK
	func apply(state: GameState) -> Dictionary:
		state.actors = fixture.actors.duplicate(true)
		state.pending = {}
		state.turn_order = fixture.turn_order.duplicate()
		state.turn_index = fixture.turn_index
		state.round_number = fixture.round_number
		state.mode = fixture.mode
		return {}

var events: Array[Dictionary] = []

func priest(position: Vector3 = Vector3.ZERO) -> Dictionary:
	return (load("res://data/monsters/cult_priest.tres") as MonsterDefinition).create_actor("priest", position)

func hero(position: Vector3) -> Dictionary:
	var record: Dictionary = HeroKit.create(&"fighter", position)
	record["hp"] = 60
	record["max_hp"] = 60
	return record

func start(actors: Dictionary, order: Array[String] = ["priest", "hero"]) -> void:
	var state: GameState = GameState.new()
	state.mode = &"combat"
	state.actors = actors
	state.turn_order = order
	CommandBus.submit(Setup.new(state))

func before_each() -> void:
	CombatSpace.active = null
	Rng.set_seed(4242)
	events.clear()
	CommandBus.command_applied.connect(_collect)

func after_each() -> void:
	CommandBus.command_applied.disconnect(_collect)
	CommandBus.submit(Setup.new(GameState.new()))
	CombatSpace.active = null

func _collect(_command: Command, result: Dictionary) -> void:
	for event: Dictionary in result.get("events", []):
		events.append(event)

func of_type(kind: String, roll_kind: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in events:
		if event["type"] == kind and (roll_kind.is_empty() or event.get("kind") == roll_kind):
			result.append(event)
	return result

func finish() -> void:
	for step: int in 60:
		if Game.state.pending.is_empty():
			return
		CommandBus.submit(AdvanceCombatCommand.new(0.1))

func test_stat_block_has_multiattack_and_spells_per_day() -> void:
	var record: Dictionary = priest()
	assert_eq(ClassFeatures.attacks_per_action(record), 2)
	assert_true(bool(record["chooses_attack"]))
	assert_eq(record["spell_uses"], {"healing_word": 3, "spirit_guardians": 1})
	assert_eq(int(record["spell_save_dc"]), 13)
	for spell_id: String in record["spells"]:
		assert_not_null(SpellBook.get_spell(spell_id), spell_id)

func test_multiattack_mixes_mace_and_radiant_flame() -> void:
	start({"priest": priest(), "hero": hero(Vector3(0, 0, -1.2))})
	assert_eq(CommandBus.submit(AttackCommand.new("priest", "hero", "priest_mace")), OK)
	finish()
	assert_eq(int(Game.state.actors["priest"]["attacks_left"]), 1)
	assert_eq(CommandBus.submit(AttackCommand.new("priest", "hero", "radiant_flame")), OK)
	finish()
	assert_eq(CommandBus.submit(AttackCommand.new("priest", "hero")), ERR_UNAVAILABLE, "only two attacks")
	assert_eq(CommandBus.submit(AttackCommand.new("priest", "hero", "longbow")), ERR_UNAVAILABLE)
	var weapons: Array = of_type("start_attack").map(func(event: Dictionary) -> String: return String(event["weapon"].get("id", "")))
	assert_eq(weapons, ["priest_mace", "radiant_flame"])

func test_attack_command_round_trips_its_weapon_choice() -> void:
	var command: AttackCommand = AttackCommand.new("priest", "hero", "radiant_flame")
	var copy: AttackCommand = AttackCommand.new()
	assert_eq(copy.from_dict(command.to_dict()), OK)
	assert_eq(copy.weapon_id, "radiant_flame")
	assert_eq(AttackCommand.new("a", "b").to_dict().size(), 3, "old records keep their shape")

func test_healing_word_is_a_bonus_action_with_three_uses() -> void:
	var record: Dictionary = priest()
	record["hp"] = 10
	start({"priest": record, "hero": hero(Vector3(0, 0, -8))})
	assert_eq(CommandBus.submit(CastSpellCommand.new("priest", "healing_word", ["priest"])), OK)
	finish()
	var actor: Dictionary = Game.state.actors["priest"]
	assert_true(bool(actor["action_available"]), "bonus action only")
	assert_eq(int(actor["spell_uses"]["healing_word"]), 2)
	assert_between(int(actor["hp"]), 15, 21, "2d4 + 3")
	assert_eq(of_type("heal").size(), 1)
	assert_eq(CommandBus.submit(CastSpellCommand.new("priest", "healing_word", ["hero"])), ERR_UNAVAILABLE,
		"bonus action already spent")

func test_healing_word_cannot_heal_an_enemy_and_uses_run_out() -> void:
	var record: Dictionary = priest()
	record["spell_uses"]["healing_word"] = 0
	start({"priest": record, "hero": hero(Vector3(0, 0, -3))})
	assert_eq(CommandBus.submit(CastSpellCommand.new("priest", "healing_word", ["priest"])), ERR_UNAVAILABLE)
	record["spell_uses"]["healing_word"] = 1
	start({"priest": record, "hero": hero(Vector3(0, 0, -3))})
	assert_eq(CommandBus.submit(CastSpellCommand.new("priest", "healing_word", ["hero"])), ERR_INVALID_PARAMETER)

func test_spirit_guardians_hurts_slows_and_saves_once_per_turn() -> void:
	start({"priest": priest(), "hero": hero(Vector3(0, 0, -3))})
	assert_eq(CommandBus.submit(CastSpellCommand.new("priest", "spirit_guardians", [], Vector3(0, 0, -3))), OK)
	finish()
	assert_eq(String(Game.state.actors["priest"]["concentration"]["spell_id"]), "spirit_guardians")
	assert_eq(int(Game.state.actors["priest"]["spell_uses"]["spirit_guardians"]), 0)
	assert_eq(of_type("roll", "save").size(), 1, "the hero inside saves when the aura appears")
	assert_lt(int(Game.state.actors["hero"]["hp"]), 60)
	events.clear()
	assert_eq(CommandBus.submit(EndTurnCommand.new("priest")), OK)
	assert_almost_eq(float(Game.state.actors["hero"]["move_left"]), 4.5, 0.01, "speed halved inside the aura")
	# Moving inside the aura on the hero's own turn triggers once; ending the turn there is the same turn.
	assert_eq(CommandBus.submit(MoveCommand.new("hero", Vector3(1, 0, -2.5))), OK)
	finish()
	assert_eq(of_type("roll", "save").size(), 1)
	assert_eq(CommandBus.submit(EndTurnCommand.new("hero")), OK)
	assert_eq(of_type("roll", "save").size(), 1, "only one save per turn")

func test_ending_a_turn_far_away_is_safe() -> void:
	start({"priest": priest(), "hero": hero(Vector3(0, 0, -3))})
	CommandBus.submit(CastSpellCommand.new("priest", "spirit_guardians", [], Vector3(0, 0, -3)))
	finish()
	CommandBus.submit(EndTurnCommand.new("priest"))
	assert_eq(CommandBus.submit(MoveCommand.new("hero", Vector3(0, 0, -7.4))), OK, "walk out at half speed")
	finish()
	events.clear()
	CommandBus.submit(EndTurnCommand.new("hero"))
	assert_true(of_type("roll", "save").is_empty())

func test_ai_casts_spirit_guardians_when_the_hero_is_close() -> void:
	start({"priest": priest(), "hero": hero(Vector3(0, 0, -1.4))})
	var command: Command = UtilityAI.choose(Game.state, "priest")
	assert_true(command is CastSpellCommand, "the aura beats a single mace swing")
	assert_eq((command as CastSpellCommand).spell_id, "spirit_guardians")

func test_ai_uses_radiant_flame_out_of_reach_and_heals_when_hurt() -> void:
	var record: Dictionary = priest()
	record["move_left"] = 0.0
	record["hp"] = 12
	record["spell_uses"]["spirit_guardians"] = 0
	start({"priest": record, "hero": hero(Vector3(0, 0, -10))})
	var options: Array[Dictionary] = UtilityAI.consider(Game.state, "priest")
	var attacks: Array[Dictionary] = options.filter(func(option: Dictionary) -> bool: return option["kind"] == &"attack")
	assert_false(attacks.is_empty())
	assert_eq(String(attacks[0]["weapon_id"]), "radiant_flame")
	var heals: Array[Dictionary] = options.filter(func(option: Dictionary) -> bool:
		return option["kind"] == &"cast_spell" and option["spell_id"] == "healing_word")
	assert_false(heals.is_empty(), "a priest at 12 of 38 HP considers Healing Word")
	assert_gt(float(heals[0]["score"]), 0.0)

