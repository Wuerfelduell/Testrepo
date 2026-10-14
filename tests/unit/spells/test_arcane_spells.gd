extends GutTest
## SRD 5.2 arcane spells added for Bard, Sorcerer, Warlock and Wizard: chosen damage types,
## Misty Step, Invisibility, Haste and Slow, Vampiric Touch, Hideous Laughter, False Life
## and Mage Armor.

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

const NEW_SPELLS: Array[String] = ["sorcerous_burst", "chromatic_orb", "ray_of_sickness", "color_spray", "grease",
	"hideous_laughter", "false_life", "mage_armor", "blur", "invisibility", "web", "misty_step", "haste", "slow",
	"hypnotic_pattern", "fear", "vampiric_touch", "greater_invisibility", "black_tentacles", "dimension_door"]

var events: Array[Dictionary] = []

## A level-7 Sorcerer who knows `spell_id`, with slots up to level 4.
func caster(spell_id: String, position: Vector3 = Vector3.ZERO) -> Dictionary:
	var record: Dictionary = HeroKit.create(&"sorcerer", position)
	record["level"] = 7
	record["spell_slots"] = [4, 3, 3, 1]
	record["spell_slots_max"] = [4, 3, 3, 1]
	record["spells"].append(spell_id)
	return record

func enemy(position: Vector3, hp: int = 60) -> Dictionary:
	return {"team": "enemy", "position": position, "hp": hp, "max_hp": hp, "ac": 5, "dex": 10,
		"speed_m": 9.0, "move_left": 9.0, "action_available": true, "bonus_available": true,
		"reaction_available": true, "disengaged": false, "conditions": [], "effects": [],
		"ability_scores": {&"str": 1, &"dex": 1, &"con": 1, &"int": 1, &"wis": 1, &"cha": 1},
		"weapon": {"ranged": false, "reach": 1.5, "attack_bonus": 4, "damage_dice": "1d4",
			"damage_bonus": 0, "damage_type": "slashing"}}

func ally(position: Vector3) -> Dictionary:
	var record: Dictionary = HeroKit.create(&"fighter", position)
	record["id"] = "ally"
	return record

func start(actors: Dictionary) -> void:
	var state: GameState = GameState.new()
	state.mode = &"combat"
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
	Rng.set_seed(4711)
	events.clear()
	CommandBus.command_applied.connect(_collect)

func after_each() -> void:
	CommandBus.command_applied.disconnect(_collect)
	CommandBus.submit(Setup.new(GameState.new()))
	CombatSpace.active = null

func _collect(_command: Command, result: Dictionary) -> void:
	for event: Dictionary in result.get("events", []):
		events.append(event)

func of_type(kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in events:
		if event["type"] == kind:
			result.append(event)
	return result

func finish() -> void:
	for step: int in 60:
		if Game.state.pending.is_empty() or Game.state.pending.get("type") == "reaction":
			return
		CommandBus.submit(AdvanceCombatCommand.new(0.1))

func cast(spell_id: String, targets: Array = [], point: Vector3 = Vector3.INF) -> void:
	assert_eq(CommandBus.submit(CastSpellCommand.new("hero", spell_id, targets, point)), OK, spell_id)
	finish()

func test_every_new_spell_loads_and_is_on_a_class_list() -> void:
	var listed: Array = []
	for class_id: String in ["bard", "sorcerer", "warlock", "wizard"]:
		listed.append_array(ClassSpellcasting.spell_list(class_id))
	for spell_id: String in NEW_SPELLS:
		assert_not_null(SpellBook.get_spell(spell_id), spell_id)
		assert_true(spell_id in listed, spell_id)
		assert_ne(tr("SPELL_" + spell_id.to_upper()), "SPELL_" + spell_id.to_upper(), spell_id)

func test_chosen_damage_type_avoids_resistance_and_finds_vulnerability() -> void:
	var orb: SpellDefinition = SpellBook.get_spell("chromatic_orb")
	var target: Dictionary = enemy(Vector3(0, 0, -5))
	start({"hero": caster("chromatic_orb"), "a": target})
	assert_eq(SpellResolver.best_damage_type(Game.state, orb, "a"), &"acid")
	target["resistances"] = ["acid", "cold"]
	start({"hero": caster("chromatic_orb"), "a": target})
	assert_eq(SpellResolver.best_damage_type(Game.state, orb, "a"), &"fire")
	target["vulnerabilities"] = ["thunder"]
	start({"hero": caster("chromatic_orb"), "a": target})
	assert_eq(SpellResolver.best_damage_type(Game.state, orb, "a"), &"thunder")

func test_misty_step_teleports_as_a_bonus_action() -> void:
	start({"hero": caster("misty_step"), "a": enemy(Vector3(0, 0, -20))})
	cast("misty_step", [], Vector3(5, 0, 0))
	assert_almost_eq(current()["position"].x, 5.0, 0.5)
	assert_false(bool(current()["bonus_available"]))
	assert_true(bool(current()["action_available"]))
	start({"hero": caster("misty_step"), "a": enemy(Vector3(0, 0, -20))})
	assert_false(bool(SpellResolver.preview(Game.state, "hero", "misty_step", 0, [], Vector3(30, 0, 0))["legal"]),
		"beyond 9 metres")

func test_invisibility_gives_advantage_and_ends_on_an_attack() -> void:
	start({"hero": caster("invisibility"), "ally": ally(Vector3(1, 0, 0)), "a": enemy(Vector3(0, 0, -5))})
	cast("invisibility", ["ally"])
	var buddy: Dictionary = Game.state.actors["ally"]
	assert_true(ActiveEffects.has_kind(buddy, "invisibility"))
	assert_true(&"invisible" in ActiveEffects.attack_advantages(buddy) or not ActiveEffects.attack_advantages(buddy).is_empty())
	assert_false(ActiveEffects.incoming_disadvantages(buddy).is_empty(), "attackers cannot see the target")
	ActiveEffects.consume_attack_riders(buddy)
	assert_false(ActiveEffects.has_kind(buddy, "invisibility"))

func test_haste_and_slow_change_armor_class_and_speed() -> void:
	start({"hero": caster("haste"), "ally": ally(Vector3(1, 0, 0)), "a": enemy(Vector3(0, 0, -5))})
	var before: int = ClassEffects.armor_class(Game.state.actors["ally"])
	cast("haste", ["ally"])
	var buddy: Dictionary = Game.state.actors["ally"]
	assert_eq(ClassEffects.armor_class(buddy), before + 2)
	assert_lt(ActiveEffects.speed_penalty(buddy), 0.0, "double speed")
	start({"hero": caster("slow"), "a": enemy(Vector3(0, 0, -10))})
	cast("slow", ["a"], Vector3(0, 0, -10))
	var foe: Dictionary = Game.state.actors["a"]
	assert_true(ActiveEffects.has_kind(foe, "slow"), "Wisdom 1 fails")
	assert_eq(ClassEffects.armor_class(foe), 5 - 2)
	assert_almost_eq(ActiveEffects.speed_penalty(foe), 4.5, 0.01)

func test_vampiric_touch_heals_half_the_damage() -> void:
	var record: Dictionary = caster("vampiric_touch")
	record["hp"] = 1
	start({"hero": record, "a": enemy(Vector3(0, 0, -1.2), 200)})
	cast("vampiric_touch", ["a"])
	var dealt: int = 200 - int(Game.state.actors["a"]["hp"])
	assert_gt(dealt, 0, "AC 5 is hit")
	assert_eq(int(current()["hp"]), mini(int(current()["max_hp"]), 1 + dealt / 2))

func test_hideous_laughter_knocks_prone_and_incapacitates() -> void:
	start({"hero": caster("hideous_laughter"), "a": enemy(Vector3(0, 0, -5))})
	cast("hideous_laughter", ["a"])
	var foe: Dictionary = Game.state.actors["a"]
	assert_true(ActiveEffects.has_kind(foe, "hideous_laughter"))
	var granted: Array[String] = []
	for effect: Dictionary in foe["effects"]:
		granted.append_array(ClassEffects.granted_conditions(effect))
	assert_true("prone" in granted)
	assert_true("incapacitated" in granted)

func test_false_life_and_mage_armor() -> void:
	start({"hero": caster("false_life"), "a": enemy(Vector3(0, 0, -20))})
	cast("false_life")
	assert_eq(int(current().get("temp_hp", 0)), 9)
	var record: Dictionary = caster("mage_armor")
	record["armor"] = "none"
	start({"hero": record, "a": enemy(Vector3(0, 0, -20))})
	cast("mage_armor", ["hero"])
	assert_eq(ClassEffects.armor_class(current()), maxi(int(current()["ac"]), 13 + Abilities.modifier(int(current()["dex"]))))
	assert_gt(ClassEffects.armor_class(current()), int(current()["ac"]), "better than unarmoured")
