extends GutTest
## Bard, Sorcerer and Warlock (class kits): creation, level-ups to 10 with every choice,
## Pact Magic, Bardic Inspiration, Metamagic, Eldritch Blast beams, Hex and Hold Person.

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

const SORCERER_KIT: GDScript = preload("res://src/rules/classes/sorcerer_kit.gd")
const WARLOCK_KIT: GDScript = preload("res://src/rules/classes/warlock_kit.gd")

var events: Array[Dictionary] = []

func hero(class_id: StringName, position: Vector3 = Vector3.ZERO, xp: int = 0) -> Dictionary:
	var record: Dictionary = HeroKit.create(class_id, position)
	var definition: ClassDefinition = load("res://data/classes/%s.tres" % class_id) as ClassDefinition
	assert_true(EquipmentRules.initialize(record, String(class_id), EquipmentRules.Training.from_class(definition)))
	record["xp"] = xp
	return record

func enemy(position: Vector3, hp: int = 60) -> Dictionary:
	return {"team": "enemy", "position": position, "hp": hp, "max_hp": hp, "ac": 5, "dex": 10,
		"speed_m": 9.0, "move_left": 9.0, "action_available": true, "bonus_available": true,
		"reaction_available": true, "disengaged": false, "conditions": [], "effects": [],
		"ability_scores": {&"str": 10, &"dex": 10, &"con": 10, &"int": 10, &"wis": 1, &"cha": 10},
		"weapon": {"ranged": false, "reach": 1.5, "attack_bonus": 4, "damage_dice": "1d4",
			"damage_bonus": 0, "damage_type": "slashing"}}

func start(actors: Dictionary, mode: StringName = &"combat") -> void:
	var state: GameState = GameState.new()
	state.mode = mode
	state.actors = actors
	var order: Array[String] = []
	for id: String in ["hero", "ally", "a"]:
		if actors.has(id):
			order.append(id)
	state.turn_order = order
	CommandBus.submit(Setup.new(state))

func current() -> Dictionary:
	return Game.state.actors["hero"]

func before_each() -> void:
	CombatSpace.active = null
	Rng.set_seed(777)
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
		if Game.state.pending.is_empty() or Game.state.pending.get("type") == "reaction":
			return
		CommandBus.submit(AdvanceCombatCommand.new(0.1))

## Valid choices for the next level: average HP, +2 Charisma at ASI levels, the first
## options of every pick.
func choices_for(record: Dictionary) -> Dictionary:
	var next: Dictionary = ProgressionRules.plan(record)
	var result: Dictionary = {"hp": "average"}
	if bool(next["asi"]):
		result["feat"] = "ability_score_improvement"
		result["ability_increases"] = {"cha": 2} if ProgressionRules.score(record, "cha") <= 18 else {"con": 2}
	if int(next["cantrip_count"]) > 0:
		result["cantrips"] = next["cantrip_options"].slice(0, int(next["cantrip_count"]))
	if not next["class_choices"].is_empty():
		var picks: Dictionary = {}
		for choice: Dictionary in next["class_choices"]:
			picks[String(choice["key"])] = choice["options"].slice(0, int(choice["count"]))
		result["class_choices"] = picks
	return result

func level_to_ten(class_id: StringName) -> void:
	start({"hero": hero(class_id, Vector3.ZERO, 64000)}, &"exploration")
	for step: int in 9:
		var choices: Dictionary = choices_for(current())
		assert_eq(ProgressionRules.validate(current(), choices), "", "%s level %d" % [class_id, step + 2])
		assert_eq(CommandBus.submit(LevelUpCommand.new("hero", choices)), OK)
	assert_eq(int(current()["level"]), 10)
	for spell_id: Variant in current()["spells"]:
		assert_not_null(SpellBook.get_spell(String(spell_id)), String(spell_id))

func test_every_new_class_is_playable_with_its_starting_spells() -> void:
	for class_id: String in ["bard", "sorcerer", "warlock"]:
		assert_true(class_id in HeroFactory.playable(), class_id)
		var record: Dictionary = HeroKit.create(StringName(class_id))
		assert_false(record.is_empty(), class_id)
		assert_eq(int(record["spell_modifier"]), 2, class_id + ": Charisma 15")
		for spell_id: Variant in record["spells"]:
			assert_not_null(SpellBook.get_spell(String(spell_id)), String(spell_id))
	assert_eq(HeroKit.create(&"bard")["spell_slots"], [2])
	assert_eq(HeroKit.create(&"sorcerer")["spell_slots"], [2])
	assert_eq(HeroKit.create(&"warlock")["spell_slots"], [1])
	assert_true("eldritch_blast" in HeroKit.create(&"warlock")["spells"])

func test_pact_slots_are_all_of_one_level() -> void:
	assert_eq(SpellRules.pact_slots(1), [1])
	assert_eq(SpellRules.pact_slots(2), [2])
	assert_eq(SpellRules.pact_slots(5), [0, 0, 2])
	assert_eq(SpellRules.pact_slots(10), [0, 0, 0, 0, 2])

func test_bard_levels_to_ten() -> void:
	level_to_ten(&"bard")
	var bard: Dictionary = current()
	assert_eq(int(bard["features"]["bardic_inspiration"]["die"]), 10)
	assert_eq(String(bard["features"]["bardic_inspiration"]["recharge"]), "short", "Font of Inspiration")
	assert_eq(bard["skill_expertise"].size(), 4, "Expertise at 2 and 9")
	assert_eq(bard["features"]["magical_secrets"]["spells"].size(), 2)
	for spell_id: Variant in bard["features"]["magical_secrets"]["spells"]:
		assert_true(String(spell_id) in bard["spells"], String(spell_id))
	assert_true("bardic_inspiration" in bard["spells"])

func test_sorcerer_levels_to_ten() -> void:
	level_to_ten(&"sorcerer")
	var sorcerer: Dictionary = current()
	assert_eq(int(sorcerer["features"]["sorcery_points"]["max"]), 10)
	assert_eq(SORCERER_KIT.known_metamagic(sorcerer).size(), 4, "two at level 2, two at level 10")
	assert_true(sorcerer["features"].has("sorcery_incarnate"))

func test_warlock_levels_to_ten() -> void:
	level_to_ten(&"warlock")
	var warlock: Dictionary = current()
	assert_eq(warlock["spell_slots_max"], [0, 0, 0, 0, 2])
	assert_eq(WARLOCK_KIT.invocations(warlock).size(), 7)
	assert_true(warlock["features"].has("magical_cunning"))

func test_warlock_pact_slots_come_back_on_a_short_rest() -> void:
	var warlock: Dictionary = hero(&"warlock")
	warlock["spell_slots"] = [0]
	start({"hero": warlock}, &"exploration")
	assert_eq(CommandBus.submit(ShortRestCommand.new("hero")), OK)
	assert_eq(current()["spell_slots"], [1])

func test_bardic_inspiration_is_a_bonus_action_on_an_ally_and_spends_a_use() -> void:
	var ally: Dictionary = hero(&"fighter", Vector3(2, 0, 0))
	ally["id"] = "ally"
	start({"hero": hero(&"bard"), "ally": ally, "a": enemy(Vector3(0, 0, -20))})
	assert_eq(CommandBus.submit(CastSpellCommand.new("hero", "bardic_inspiration", ["a"])), ERR_INVALID_PARAMETER,
		"never on an enemy")
	assert_eq(CommandBus.submit(CastSpellCommand.new("hero", "bardic_inspiration", ["ally"])), OK)
	finish()
	assert_false(bool(current()["bonus_available"]))
	assert_true(bool(current()["action_available"]))
	assert_eq(int(current()["features"]["bardic_inspiration"]["uses"]), 1, "two uses with Charisma 15")
	assert_true(ActiveEffects.has_kind(Game.state.actors["ally"], "bardic_inspiration"))

func test_inspiration_turns_a_close_miss_into_a_success_and_is_used_up() -> void:
	var actor: Dictionary = {"effects": [{"kind": "bardic_inspiration", "die": 6, "until": "used"}]}
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var roll: DiceResult = Dice.roll("1d20", rng, [RuleModifier.new(30, &"test")])
	assert_true(ActiveEffects.inspire_roll(actor, roll, 10, rng).is_empty(), "already a success")
	var low: DiceResult = Dice.roll("1d20", rng, [RuleModifier.new(-100, &"test")])
	assert_true(ActiveEffects.inspire_roll(actor, low, 10, rng).is_empty(), "the die cannot save it")
	var close: DiceResult = Dice.roll("1d20+1", rng)
	var before: int = close.total
	assert_false(ActiveEffects.inspire_roll(actor, close, before + 1, rng).is_empty(), "one short: the die saves it")
	assert_gt(close.total, before)
	assert_false(ActiveEffects.has_kind(actor, "bardic_inspiration"))

func test_eldritch_blast_beams_scale_with_level() -> void:
	var blast: SpellDefinition = SpellBook.get_spell("eldritch_blast")
	assert_eq(SpellRules.dart_count(blast, 0, 1), 1)
	assert_eq(SpellRules.dart_count(blast, 0, 5), 2)
	assert_eq(SpellRules.dart_count(blast, 0, 10), 2)
	assert_eq(SpellRules.damage_expression(blast, 5, 0), "1d10", "each beam stays 1d10")

func test_eldritch_blast_rolls_one_attack_per_beam() -> void:
	var warlock: Dictionary = hero(&"warlock")
	warlock["level"] = 5
	start({"hero": warlock, "a": enemy(Vector3(0, 0, -10), 200)})
	assert_eq(CommandBus.submit(CastSpellCommand.new("hero", "eldritch_blast", ["a", "a"])), OK)
	finish()
	assert_eq(of_type("roll", "attack").size(), 2)

func test_hex_adds_necrotic_damage_on_hits() -> void:
	var warlock: Dictionary = hero(&"warlock")
	start({"hero": warlock, "a": enemy(Vector3(0, 0, -10), 200)})
	assert_eq(CommandBus.submit(CastSpellCommand.new("hero", "hex", ["a"])), OK)
	finish()
	assert_true(ActiveEffects.has_kind(Game.state.actors["a"], "hex"))
	assert_eq(String(current()["concentration"]["spell_id"]), "hex")
	var dice: Array = WARLOCK_KIT.extra_damage_dice(Game.state, "hero", "a", {}, false)
	assert_eq(dice, [{"dice": "1d6", "damage_type": "necrotic", "source": "hex"}])

func test_hold_person_paralyzes_on_a_failed_save() -> void:
	var bard: Dictionary = hero(&"bard")
	bard["level"] = 3
	bard["spell_slots"] = [4, 2]
	bard["spell_slots_max"] = [4, 2]
	bard["spells"].append("hold_person")
	start({"hero": bard, "a": enemy(Vector3(0, 0, -10))})
	assert_eq(CommandBus.submit(CastSpellCommand.new("hero", "hold_person", ["a"])), OK)
	finish()
	assert_true("paralyzed" in Game.state.actors["a"]["conditions"], "Wisdom 1 always fails")

func test_quickened_spell_makes_an_action_spell_a_bonus_action() -> void:
	var sorcerer: Dictionary = hero(&"sorcerer")
	sorcerer["level"] = 2
	sorcerer["features"]["sorcery_points"] = {"uses": 2, "max": 2, "recharge": "long"}
	sorcerer["features"]["metamagic"] = {"known": ["quickened", "distant"]}
	start({"hero": sorcerer, "a": enemy(Vector3(0, 0, -10), 200)})
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "metamagic_quickened")), OK)
	assert_eq(int(current()["features"]["sorcery_points"]["uses"]), 0)
	assert_eq(CommandBus.submit(CastSpellCommand.new("hero", "fire_bolt", ["a"])), OK)
	finish()
	assert_false(bool(current()["bonus_available"]))
	assert_true(bool(current()["action_available"]), "the action is still free")
	assert_false(current().has("metamagic"), "used up")
