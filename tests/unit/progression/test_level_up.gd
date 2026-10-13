extends GutTest
## Prompt 08: level-up from XP thresholds, hit points, ASI/feats, Wizard spells,
## Fighter features to level 5 (Action Surge, Extra Attack), codec and save/load.

class ClearPending extends Command:
	func validate(_state: GameState) -> Error:
		return OK
	func apply(state: GameState) -> Dictionary:
		state.pending = {}
		return {}

class BeginTurn extends Command:
	func validate(_state: GameState) -> Error:
		return OK
	func apply(state: GameState) -> Dictionary:
		CombatRules.begin_turn(state, "hero")
		return {}

class Setup extends Command:
	var fixture: GameState
	func _init(value: GameState) -> void:
		fixture = value
	func validate(_state: GameState) -> Error:
		return OK
	func apply(state: GameState) -> Dictionary:
		state.actors = fixture.actors.duplicate(true)
		state.pending = fixture.pending.duplicate(true)
		state.turn_order = fixture.turn_order.duplicate()
		state.turn_index = fixture.turn_index
		state.round_number = fixture.round_number
		state.mode = fixture.mode
		return {}

const TEST_SAVE: String = "user://test_level_up_save.json"

func hero(class_id: StringName, xp: int = 0, with_kit: bool = true) -> Dictionary:
	var record: Dictionary = HeroKit.create(class_id, Vector3.ZERO)
	if with_kit:
		var definition: ClassDefinition = load("res://data/classes/%s.tres" % class_id) as ClassDefinition
		assert_true(EquipmentRules.initialize(record, String(class_id), EquipmentRules.Training.from_class(definition)))
	record["xp"] = xp
	return record

func enemy(position: Vector3) -> Dictionary:
	return {"team": "enemy", "position": position, "hp": 60, "max_hp": 60, "ac": 5, "dex": 10,
		"speed_m": 9.0, "move_left": 9.0, "action_available": true, "bonus_available": true,
		"reaction_available": true, "disengaged": false, "conditions": [],
		"ability_scores": {&"str": 10, &"dex": 10, &"con": 10, &"int": 10, &"wis": 10, &"cha": 10},
		"weapon": {"ranged": false, "reach": 1.5, "attack_bonus": 4, "damage_dice": "1d4", "damage_bonus": 0, "damage_type": "slashing"}}

func use(record: Dictionary, mode: StringName = &"exploration") -> void:
	var state: GameState = GameState.new()
	state.mode = mode
	state.actors = {"hero": record, "enemy": enemy(Vector3(1, 0, 0) if mode == &"combat" else Vector3(80, 0, 80))}
	state.turn_order = ["hero", "enemy"]
	CommandBus.submit(Setup.new(state))
	Rng.set_seed(4242)

func level(choices: Dictionary) -> Error:
	return CommandBus.submit(LevelUpCommand.new("hero", choices))

func current() -> Dictionary:
	return Game.state.actors["hero"]

func before_each() -> void:
	CombatSpace.active = null
	SaveGame.path = TEST_SAVE
	SaveGame.delete()

func after_each() -> void:
	CommandBus.submit(Setup.new(GameState.new()))
	SaveGame.delete()
	SaveGame.path = SaveGame.DEFAULT_PATH

func test_level_up_becomes_available_exactly_at_the_threshold() -> void:
	assert_false(ProgressionRules.can_level_up(hero(&"fighter", 299)))
	assert_true(ProgressionRules.can_level_up(hero(&"fighter", 300)))
	var record: Dictionary = hero(&"fighter", 2700)
	assert_eq(ProgressionRules.xp_level(record), 4)
	use(hero(&"fighter", 299))
	assert_eq(level({"hp": "average"}), ERR_UNAVAILABLE, "no level without the XP")
	assert_eq(current()["level"], 1)

func test_xp_award_makes_the_level_available_but_never_applies_it() -> void:
	var record: Dictionary = hero(&"fighter", 250)
	var defeated: Dictionary = enemy(Vector3(80, 0, 80))
	defeated["hp"] = 0
	defeated["experience"] = 100
	var state: GameState = GameState.new()
	state.actors = {"hero": record, "enemy": defeated}
	record["xp_history"] = [{"amount": 250, "reason": "test"}]
	var event: Dictionary = AwardVictoryXpCommand.new().apply(state)["events"][0]
	assert_eq(event["gained_levels"], [2])
	assert_true(bool(event["level_up_available"]))
	assert_eq(state.actors["hero"]["level"], 1, "the player levels up through the screen")

func test_no_level_up_during_combat() -> void:
	use(hero(&"fighter", 300), &"combat")
	assert_eq(level({"hp": "average"}), ERR_UNAVAILABLE)

func test_average_hit_points_and_proficiency() -> void:
	var record: Dictionary = hero(&"fighter", 300)
	record["hp"] = 5
	use(record)
	assert_eq(level({"hp": "average"}), OK)
	var fighter: Dictionary = current()
	assert_eq(fighter["level"], 2)
	assert_eq(fighter["max_hp"], 12 + 6 + 2, "d10 fixed value 6 + Con 2")
	assert_eq(fighter["hp"], 5 + 8, "current hit points rise by the same amount")
	assert_eq(fighter["hp_gains"], [6])
	assert_eq(fighter["hit_dice"], {"die": 10, "max": 2, "left": 2})

func test_rolled_hit_points_use_the_hit_die_and_show_a_roll() -> void:
	use(hero(&"wizard", 300))
	var events: Array = []
	var listener: Callable = func(_command: Command, result: Dictionary) -> void: events.append_array(result.get("events", []))
	CommandBus.command_applied.connect(listener)
	assert_eq(level({"hp": "roll", "expertise": "arcana", "prepared": ["magic_missile", "burning_hands", "shield", "sleep"]}), OK)
	CommandBus.command_applied.disconnect(listener)
	var roll: Dictionary = events.filter(func(event: Dictionary) -> bool: return event["type"] == "roll")[0]
	assert_eq(roll["kind"], "hit_points")
	assert_eq(roll["roll"]["groups"][0]["sides"], 6)
	var die: int = int(roll["roll"]["groups"][0]["values"][0])
	assert_eq(current()["hp_gains"], [die])
	assert_eq(current()["max_hp"], 8 + maxi(1, die + 2))

func test_ability_score_improvement_is_capped_at_twenty() -> void:
	var record: Dictionary = hero(&"fighter", 2700)
	record["level"] = 3
	record["ability_scores"][&"str"] = 19
	assert_eq(ProgressionRules.validate(record, {"hp": "average", "feat": "ability_score_improvement",
		"ability_increases": {"str": 2}}), "LEVELUP_REASON_ASI_CAP")
	assert_eq(ProgressionRules.validate(record, {"hp": "average", "feat": "ability_score_improvement",
		"ability_increases": {"str": 1}}), "LEVELUP_REASON_ASI", "both points must be spent")
	assert_eq(ProgressionRules.validate(record, {"hp": "average", "feat": "ability_score_improvement",
		"ability_increases": {"str": 1, "dex": 1, "con": 1}}), "LEVELUP_REASON_ASI")
	assert_eq(ProgressionRules.validate(record, {"hp": "average"}), "LEVELUP_REASON_FEAT", "level 4 asks for the choice")
	use(record)
	assert_eq(level({"hp": "average", "feat": "ability_score_improvement", "ability_increases": {"str": 1, "con": 1}}), OK)
	var fighter: Dictionary = current()
	assert_eq(ProgressionRules.score(fighter, "str"), 20)
	assert_eq(ProgressionRules.score(fighter, "con"), 15)
	assert_eq(fighter["weapon"]["attack_modifiers"][0]["amount"], 5, "STR 20 reaches the weapon")
	assert_eq(fighter["max_hp"], 12 + 3 * 8, "Con 15 keeps +2 per level")
	assert_eq(fighter["features"]["second_wind"]["max"], 3, "Second Wind: three uses from level 4")

func test_constitution_raise_increases_every_level() -> void:
	var record: Dictionary = hero(&"fighter", 2700)
	record["level"] = 3
	record["hp_gains"] = [6, 6]
	record["max_hp"] = ProgressionRules.maximum_hp(record)
	record["hp"] = record["max_hp"]
	assert_eq(record["max_hp"], 28)
	use(record)
	assert_eq(level({"hp": "average", "feat": "ability_score_improvement", "ability_increases": {"con": 2}}), OK)
	assert_eq(current()["max_hp"], (10 + 3) + 3 * (6 + 3), "Con 16 (+3) applies to all four levels")

func test_skilled_feat_adds_three_skills() -> void:
	var record: Dictionary = hero(&"wizard", 2700)
	record["level"] = 3
	use(record)
	assert_eq(level({"hp": "average", "feat": "skilled", "skills": ["stealth", "stealth", "insight"]}), ERR_INVALID_PARAMETER)
	assert_eq(level({"hp": "average", "feat": "skilled", "skills": ["stealth", "insight", "medicine"],
		"cantrips": ["acid_splash"], "spellbook": ["shatter"]}), OK)
	var skills: Array = current()["skill_proficiencies"].map(func(skill: Variant) -> String: return String(skill))
	for skill: String in ["stealth", "insight", "medicine"]:
		assert_has(skills, skill)
	assert_eq(current()["feats"], ["skilled"])

func test_fighter_levels_one_to_five_with_every_choice() -> void:
	use(hero(&"fighter", 6500))
	assert_eq(level({"hp": "average"}), OK)
	assert_eq(current()["features"]["action_surge"], {"uses": 1, "max": 1}, "level 2: Action Surge")
	assert_eq(level({"hp": "roll"}), OK)
	assert_eq(level({"hp": "average", "feat": "ability_score_improvement", "ability_increases": {"str": 2}}), OK)
	assert_eq(level({"hp": "average"}), OK)
	var fighter: Dictionary = current()
	assert_eq(fighter["level"], 5)
	assert_eq(fighter["proficiency_bonus"], 3)
	assert_eq(fighter["features"]["extra_attack"]["attacks"], 2)
	assert_true(fighter["features"].has("tactical_shift"))
	assert_eq(fighter["features"]["fighting_style"], "great_weapon_fighting", "the style survives every level")
	assert_eq(fighter["weapon"]["attack_bonus"], 4 + 3, "STR 18 and proficiency +3")
	assert_eq(fighter["level_choices"].size(), 4)
	assert_eq(fighter["hit_dice"]["max"], 5)
	assert_eq(level({"hp": "average"}), ERR_UNAVAILABLE, "6500 XP is level 5")

func test_extra_attack_gives_two_attacks_per_action_and_action_surge_another_action() -> void:
	var fighter: Dictionary = hero(&"fighter", 6500)
	use(fighter)
	for step: int in 4:
		var choices: Dictionary = {"hp": "average"}
		if step == 2:
			choices = {"hp": "average", "feat": "ability_score_improvement", "ability_increases": {"str": 2}}
		assert_eq(level(choices), OK)
	var record: Dictionary = current().duplicate(true)
	record["position"] = Vector3.ZERO
	use(record, &"combat")
	CommandBus.submit(BeginTurn.new())
	assert_eq(CommandBus.submit(AttackCommand.new("hero", "enemy")), OK)
	CommandBus.submit(ClearPending.new())
	assert_false(bool(current()["action_available"]))
	assert_eq(current()["attacks_left"], 1)
	assert_eq(CommandBus.submit(AttackCommand.new("hero", "enemy")), OK, "second attack of the same action")
	CommandBus.submit(ClearPending.new())
	assert_eq(CommandBus.submit(AttackCommand.new("hero", "enemy")), ERR_UNAVAILABLE)
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "action_surge")), OK)
	assert_true(bool(current()["action_available"]))
	assert_eq(current()["features"]["action_surge"]["uses"], 0)
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "action_surge")), ERR_UNAVAILABLE)
	CommandBus.submit(BeginTurn.new())
	assert_eq(current()["attacks_left"], 0, "unused attacks do not carry over")

func test_action_surge_waits_until_the_action_is_spent() -> void:
	use(hero(&"fighter", 300))
	assert_eq(level({"hp": "average"}), OK)
	var record: Dictionary = current().duplicate(true)
	use(record, &"combat")
	CommandBus.submit(BeginTurn.new())
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "action_surge")), ERR_UNAVAILABLE)

func test_tactical_shift_adds_half_speed_without_opportunity_attacks() -> void:
	var record: Dictionary = hero(&"fighter", 6500)
	record["level"] = 5
	ClassFeatures.advance(record, 5)
	record["hp"] = 10
	use(record, &"combat")
	CommandBus.submit(BeginTurn.new())
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "second_wind")), OK)
	assert_almost_eq(float(current()["move_left"]), 13.5, 0.001)
	assert_true(bool(current()["disengaged"]))

func test_fighter_without_a_style_picks_great_weapon_fighting() -> void:
	var record: Dictionary = hero(&"fighter", 300)
	record["features"].erase("fighting_style")
	var plan: Dictionary = ProgressionRules.plan(record)
	assert_true(bool(plan["fighting_style"]))
	assert_eq(plan["fighting_style_options"], ["great_weapon_fighting"])
	assert_eq(ProgressionRules.validate(record, {"hp": "average"}), "LEVELUP_REASON_STYLE")
	use(record)
	assert_eq(level({"hp": "average", "fighting_style": "great_weapon_fighting"}), OK)
	var greatsword: Dictionary = {"ranged": false, "properties": ["heavy", "two_handed"]}
	assert_eq(CombatRules.damage_die_minimum(current(), greatsword), 3)

func test_great_weapon_fighting_as_a_feat_only_without_a_style() -> void:
	var record: Dictionary = hero(&"fighter", 2700)
	record["level"] = 3
	assert_false("great_weapon_fighting" in ProgressionRules.plan(record)["feat_options"], "already has the style")
	record["features"].erase("fighting_style")
	assert_true("great_weapon_fighting" in ProgressionRules.plan(record)["feat_options"])
	assert_eq(ProgressionRules.validate(record, {"hp": "average", "feat": "great_weapon_fighting"}), "")

func test_great_weapon_fighting_raises_ones_and_twos() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	for attempt: int in 40:
		var roll: DiceResult = Dice.roll("2d6", rng, [], false, 3)
		for value: int in roll.groups[0].values:
			assert_true(value >= 3, "1 and 2 count as 3")
		for index: int in roll.groups[0].raised_indices:
			assert_true(roll.groups[0].rolled[index] <= 2)

func test_wizard_spell_choices_follow_the_rules() -> void:
	var record: Dictionary = hero(&"wizard", 300)
	var plan: Dictionary = ProgressionRules.plan(record)
	assert_eq(plan["spellbook_count"], 0, "no unknown level-1 spells exist yet")
	assert_eq(plan["prepared_limit"], 5)
	assert_eq(ProgressionRules.validate(record, {"hp": "average", "expertise": "arcana", "spellbook": ["shatter"]}),
		"LEVELUP_REASON_SPELLBOOK", "a level-2 spell needs a level-2 slot")
	use(record)
	assert_eq(level({"hp": "average"}), ERR_INVALID_PARAMETER, "Scholar asks for its skill")
	assert_eq(level({"hp": "average", "expertise": "arcana"}), OK)
	record = current()
	record["xp"] = 900
	plan = ProgressionRules.plan(record)
	assert_eq(plan["spellbook_options"], ["shatter"])
	assert_eq(plan["spellbook_count"], 1)
	assert_eq(ProgressionRules.validate(record, {"hp": "average", "spellbook": ["sleep"]}), "LEVELUP_REASON_SPELLBOOK",
		"a spell already in the book")
	assert_eq(ProgressionRules.validate(record, {"hp": "average", "spellbook": ["shatter"],
		"prepared": ["magic_missile", "burning_hands", "shield", "sleep", "shatter", "shatter"]}), "LEVELUP_REASON_PREPARED")
	assert_eq(ProgressionRules.validate(record, {"hp": "average", "spellbook": ["shatter"],
		"prepared": ["magic_missile", "burning_hands", "shield", "sleep", "shatter", "fireball"]}), "LEVELUP_REASON_PREPARED")
	use(record)
	assert_eq(level({"hp": "average", "spellbook": ["shatter"]}), OK)
	var wizard: Dictionary = current()
	assert_eq(wizard["spell_slots_max"], [4, 2])
	assert_eq(wizard["spell_slots"], [4, 2], "new slots arrive full; spent ones stay spent")
	assert_has(wizard["spellbook"], "shatter")
	assert_has(wizard["spells"], "shatter", "prepared by default while the limit allows")
	assert_eq(wizard["spell_save_dc"], 8 + 2 + 2)

func test_wizard_levels_one_to_five_with_cantrip_and_fireball() -> void:
	use(hero(&"wizard", 6500))
	assert_eq(level({"hp": "average", "expertise": "investigation"}), OK)
	assert_eq(level({"hp": "average", "spellbook": ["shatter"]}), OK)
	assert_eq(level({"hp": "roll", "feat": "ability_score_improvement", "ability_increases": {"int": 1, "con": 1}}),
		ERR_INVALID_PARAMETER, "level 4 also asks for a cantrip")
	assert_eq(level({"hp": "roll", "feat": "ability_score_improvement", "ability_increases": {"int": 1, "con": 1},
		"cantrips": ["acid_splash"]}), OK)
	assert_eq(level({"hp": "average", "spellbook": ["fireball"]}), OK)
	var wizard: Dictionary = current()
	assert_eq(wizard["level"], 5)
	assert_eq(wizard["spell_slots_max"], [4, 3, 2])
	assert_has(wizard["spells"], "acid_splash")
	assert_has(wizard["spells"], "fireball")
	assert_eq(ClassFeatures.prepared_spells(wizard).size(), 6)
	assert_true(wizard["features"].has("memorize_spell"))
	assert_eq(ProgressionRules.score(wizard, "int"), 16)
	assert_eq(wizard["spell_attack_bonus"], 3 + 3)
	assert_eq(SpellRules.cantrip_multiplier(int(wizard["level"])), 2, "cantrips grow at level 5")

func test_scholar_expertise_at_wizard_level_two() -> void:
	var record: Dictionary = hero(&"wizard", 300)
	var plan: Dictionary = ProgressionRules.plan(record)
	assert_true(bool(plan["expertise"]))
	assert_eq(plan["expertise_options"], ["arcana", "investigation"], "only Scholar skills the Wizard is proficient in")
	assert_eq(ProgressionRules.validate(record, {"hp": "average", "expertise": "history"}), "LEVELUP_REASON_EXPERTISE")
	use(record)
	assert_eq(level({"hp": "average", "expertise": "arcana"}), OK)
	assert_eq(current()["skill_expertise"], ["arcana"])

func test_level_up_choices_survive_save_and_load() -> void:
	use(hero(&"wizard", 900))
	assert_eq(level({"hp": "roll", "expertise": "arcana"}), OK)
	assert_eq(level({"hp": "average", "spellbook": ["shatter"]}), OK)
	assert_eq(SaveGame.save(Game.state), OK)
	var loaded: SaveGame.LoadResult = SaveGame.load_save()
	assert_true(loaded.is_valid())
	var wizard: Dictionary = loaded.state.actors["hero"]
	var before: Dictionary = current()
	for key: String in ["level", "hp_gains", "level_choices", "spellbook", "spells", "spell_slots_max",
			"max_hp", "hit_dice", "proficiency_bonus", "skill_expertise"]:
		assert_eq(wizard[key], before[key], key)
	assert_eq(ProgressionRules.maximum_hp(wizard), int(wizard["max_hp"]))

func test_codec_round_trip_and_strict_decoding() -> void:
	var command: LevelUpCommand = LevelUpCommand.new("hero", {"hp": "roll", "feat": "ability_score_improvement",
		"ability_increases": {"str": 1, "con": 1}, "spellbook": ["shatter"]})
	var json: Variant = JSON.parse_string(JSON.stringify(command.to_dict()))
	var decoded: Command = CommandCodec.decode(json)
	assert_true(decoded is LevelUpCommand)
	assert_eq((decoded as LevelUpCommand).choices["ability_increases"], {"str": 1, "con": 1})
	assert_eq(decoded.to_dict(), command.to_dict())
	assert_null(CommandCodec.decode({"type": "level_up", "actor_id": "hero", "choices": {"hp": "roll", "cheat": 1}}))
	assert_null(CommandCodec.decode({"type": "level_up", "actor_id": "hero", "choices": {"ability_increases": {"str": 1.5}}}))
	assert_null(CommandCodec.decode({"type": "level_up", "actor_id": "hero", "choices": {}, "extra": true}))
