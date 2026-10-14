extends GutTest
## 2024 Cleric, Paladin and Druid spells (DivineSpellEffects): smites, zones, follow-up
## spells, curses, wards and Dispel Magic.

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

const NEW_SPELLS: Array[String] = ["toll_the_dead", "word_of_radiance", "thorn_whip", "bane", "command", "heroism",
	"protection_from_evil_and_good", "ice_knife", "searing_smite", "thunderous_smite", "wrathful_smite",
	"compelled_duel", "spiritual_weapon", "prayer_of_healing", "blindness_deafness", "moonbeam", "flame_blade",
	"heat_metal", "shining_smite", "magic_weapon", "silence", "beacon_of_hope", "bestow_curse", "dispel_magic",
	"sleet_storm", "blinding_smite", "crusaders_mantle", "aura_of_vitality", "elemental_weapon", "banishment",
	"death_ward", "stoneskin", "greater_restoration", "insect_plague", "contagion", "wrath_of_nature",
	"sanctuary", "charm_person", "flaming_sphere", "gust_of_wind", "remove_curse", "freedom_of_movement",
	"aura_of_life", "aura_of_purity", "fire_shield", "fount_of_moonlight"]

func before_each() -> void:
	CombatSpace.active = null
	Rng.set_seed(4242)

func after_each() -> void:
	CommandBus.submit(Setup.new(GameState.new()))
	CombatSpace.active = null

func hero(class_id: StringName, level: int, position: Vector3 = Vector3.ZERO, spells: Array = []) -> Dictionary:
	var record: Dictionary = HeroKit.create(class_id, position)
	for next: int in range(2, level + 1):
		record["level"] = next
		ClassFeatures.advance(record, next)
		ProgressionRules.refresh_derived(record)
	record["spells"].append_array(spells)
	return record

func dummy(position: Vector3, hp: int = 200) -> Dictionary:
	var record: Dictionary = HeroKit.create(&"fighter", position)
	record["team"] = "enemy"
	record["hp"] = hp
	record["max_hp"] = 200
	return record

func start(actors: Dictionary, order: Array[String]) -> void:
	var state: GameState = GameState.new()
	state.mode = &"combat"
	state.actors = actors
	state.turn_order = order
	CommandBus.submit(Setup.new(state))

func finish() -> void:
	for step: int in 80:
		if Game.state.pending.is_empty():
			return
		CommandBus.submit(AdvanceCombatCommand.new(0.1))

func cast(caster_id: String, spell_id: String, targets: Array = [], point: Vector3 = Vector3.INF) -> Error:
	var result: Error = CommandBus.submit(CastSpellCommand.new(caster_id, spell_id, targets, point))
	finish()
	return result

func test_every_new_spell_is_valid_and_on_a_class_list() -> void:
	var lists: Array[String] = []
	for class_id: String in ["cleric", "paladin", "druid"]:
		lists.append_array(ClassSpellcasting.spell_list(class_id))
	for spell_id: String in NEW_SPELLS:
		var spell: SpellDefinition = SpellBook.get_spell(spell_id)
		assert_not_null(spell, spell_id)
		assert_true(spell.is_valid(), spell_id)
		assert_true(spell_id in lists, spell_id)
		assert_ne(tr(String(spell.name_key)), String(spell.name_key), spell_id)
	for spell_id: String in ["spiritual_weapon_strike", "flame_blade_strike", "heat_metal_repeat", "aura_of_vitality_heal",
			"flaming_sphere_move"]:
		assert_true(SpellBook.get_spell(spell_id).is_feature(), spell_id)

func test_toll_the_dead_rings_louder_for_the_wounded() -> void:
	var spell: SpellDefinition = SpellBook.get_spell("toll_the_dead")
	assert_eq(DivineSpellEffects.damage_expression(spell, {"hp": 10, "max_hp": 10}, "1d8"), "1d8")
	assert_eq(DivineSpellEffects.damage_expression(spell, {"hp": 4, "max_hp": 10}, "2d8"), "2d12")

func test_bane_lowers_attacks_and_saves() -> void:
	var foe: Dictionary = dummy(Vector3.ZERO)
	ActiveEffects.add(foe, {"kind": "bane", "until": "concentration", "source_id": "cleric"})
	var attack: Array[RuleModifier] = ClassEffects.attack_modifiers(foe, Rng.rng, foe["weapon"])
	assert_eq(attack.size(), 1)
	assert_lt(attack[0].amount, 0)
	var state: GameState = GameState.new()
	state.actors = {"foe": foe}
	assert_lt(ClassEffects.save_modifiers(state, "foe", Rng.rng)[0].amount, 0)

func test_command_drops_the_target_and_takes_its_turn() -> void:
	var cleric: Dictionary = hero(&"cleric", 1, Vector3.ZERO, ["command"])
	var foe: Dictionary = dummy(Vector3(0, 0, -4))
	foe["ability_scores"][&"wis"] = 1
	start({"cleric": cleric, "foe": foe}, ["cleric", "foe"])
	for attempt: int in 5:
		if ActiveEffects.has_kind(Game.state.actors["foe"], "command"):
			break
		var snapshot: GameState = Game.state
		snapshot.actors["cleric"]["action_available"] = true
		snapshot.actors["cleric"]["spell_slots"] = [2]
		CommandBus.submit(Setup.new(snapshot))
		assert_eq(cast("cleric", "command", ["foe"]), OK)
	var target: Dictionary = Game.state.actors["foe"]
	assert_true(ActiveEffects.has_kind(target, "command"))
	assert_true("prone" in target["conditions"])
	assert_false(CombatRules.conditions_for(target).can_act())
	var snapshot: GameState = Game.state
	ActiveEffects.on_turn_end(snapshot, "foe", Rng.rng)
	assert_false(ActiveEffects.has_kind(snapshot.actors["foe"], "command"))

func test_searing_smite_rides_the_next_melee_hit_and_burns() -> void:
	var paladin: Dictionary = hero(&"paladin", 2, Vector3.ZERO, ["searing_smite"])
	start({"paladin": paladin, "foe": dummy(Vector3(0, 0, -1))}, ["paladin", "foe"])
	assert_eq(cast("paladin", "searing_smite"), OK)
	assert_eq(Game.state.actors["paladin"]["spell_slots"], [1])
	var snapshot: GameState = Game.state
	var events: Array[Dictionary] = []
	var riders: Array[Dictionary] = DivineSpellEffects.weapon_riders(snapshot, "paladin", "foe",
		snapshot.actors["paladin"]["weapon"], Rng.rng, events)
	assert_eq(riders.size(), 1)
	assert_eq(String(riders[0]["dice"]), "1d6")
	assert_eq(String(riders[0]["type"]), "fire")
	assert_true(ActiveEffects.has_kind(snapshot.actors["foe"], "searing"))
	assert_false(ActiveEffects.has_kind(snapshot.actors["paladin"], "smite"), "Spent on the hit")
	var before: int = int(snapshot.actors["foe"]["hp"])
	DivineSpellEffects.on_turn_end(snapshot, "foe", Rng.rng)
	assert_lt(int(snapshot.actors["foe"]["hp"]), before)

func test_spiritual_weapon_leaves_a_strike_while_concentrating() -> void:
	var cleric: Dictionary = hero(&"cleric", 3, Vector3.ZERO, ["spiritual_weapon"])
	start({"cleric": cleric, "foe": dummy(Vector3(0, 0, -6))}, ["cleric", "foe"])
	assert_eq(cast("cleric", "spiritual_weapon", ["foe"]), OK)
	var after: Dictionary = Game.state.actors["cleric"]
	assert_true("spiritual_weapon_strike" in after["spells"])
	var strike: SpellDefinition = SpellBook.get_spell("spiritual_weapon_strike")
	var snapshot: GameState = Game.state
	snapshot.actors["cleric"]["bonus_available"] = true
	assert_eq(SpellResolver.availability_reason(snapshot, "cleric", strike), "")
	ActiveEffects.end_concentration(snapshot, "cleric", "test")
	assert_eq(SpellResolver.availability_reason(snapshot, "cleric", strike), "FEATURE_NO_USES")

func test_moonbeam_stays_where_it_was_cast_and_burns_who_ends_a_turn_there() -> void:
	var druid: Dictionary = hero(&"druid", 3, Vector3.ZERO, ["moonbeam"])
	var foe: Dictionary = dummy(Vector3(0, 0, -6))
	start({"druid": druid, "foe": foe}, ["druid", "foe"])
	assert_eq(cast("druid", "moonbeam", [], Vector3(0, 0, -6)), OK)
	var hurt: int = 200 - int(Game.state.actors["foe"]["hp"])
	assert_gt(hurt, 0, "Caught at the cast")
	var snapshot: GameState = Game.state
	assert_eq(snapshot.actors["druid"]["concentration"]["point"], Vector3(0, 0, -6))
	assert_true(ActiveEffects.in_aura(snapshot.actors["druid"], SpellBook.get_spell("moonbeam"), Vector3(0, 0, -6)))
	assert_false(ActiveEffects.in_aura(snapshot.actors["druid"], SpellBook.get_spell("moonbeam"), Vector3.ZERO))
	snapshot.round_number += 1
	var events: Array[Dictionary] = ActiveEffects.aura_triggers(snapshot, "foe", Rng.rng, false)
	assert_false(events.is_empty(), "Ending a later turn inside burns again")

func test_silence_stops_spellcasting_inside() -> void:
	var cleric: Dictionary = hero(&"cleric", 3, Vector3.ZERO, ["silence"])
	var foe: Dictionary = dummy(Vector3(0, 0, -8))
	start({"cleric": cleric, "foe": foe}, ["cleric", "foe"])
	assert_eq(cast("cleric", "silence", [], Vector3(0, 0, -8)), OK)
	var snapshot: GameState = Game.state
	assert_true(DivineSpellEffects.silenced(snapshot, "foe"))
	assert_false(DivineSpellEffects.silenced(snapshot, "cleric"))
	snapshot.actors["foe"]["spells"] = ["sacred_flame"]
	assert_eq(SpellResolver.availability_reason(snapshot, "foe", SpellBook.get_spell("sacred_flame"), 0, true),
		"SPELL_REASON_SILENCED")

func test_death_ward_keeps_a_creature_standing_once() -> void:
	var ally: Dictionary = HeroKit.create(&"fighter", Vector3.ZERO)
	ActiveEffects.add(ally, {"kind": "death_ward", "until": "long_rest"})
	var state: GameState = GameState.new()
	state.actors = {"ally": ally}
	ClassEffects.lose_hp(state, "ally", 999, Rng.rng)
	assert_eq(int(ally["hp"]), 1)
	ClassEffects.lose_hp(state, "ally", 999, Rng.rng)
	assert_eq(int(ally["hp"]), 0)

func test_stoneskin_resists_weapons() -> void:
	var ally: Dictionary = HeroKit.create(&"fighter", Vector3.ZERO)
	ActiveEffects.add(ally, {"kind": "stoneskin", "until": "concentration"})
	assert_true(&"slashing" in CombatRules.defenses_for(ally).resistances)
	assert_false(&"fire" in CombatRules.defenses_for(ally).resistances)

func test_dispel_magic_ends_hold_person_on_an_ally() -> void:
	var cleric: Dictionary = hero(&"cleric", 5, Vector3.ZERO, ["dispel_magic"])
	var ally: Dictionary = HeroKit.create(&"fighter", Vector3(0, 0, -2))
	ActiveEffects.add(ally, {"kind": "hold", "spell_id": "hold_person", "source_id": "foe", "until": "concentration"})
	assert_false(CombatRules.conditions_for(ally).can_act())
	start({"cleric": cleric, "ally": ally, "foe": dummy(Vector3(0, 0, -9))}, ["cleric", "ally", "foe"])
	assert_eq(cast("cleric", "dispel_magic", ["ally"]), OK)
	assert_false(ActiveEffects.has_kind(Game.state.actors["ally"], "hold"))
	assert_true(CombatRules.conditions_for(Game.state.actors["ally"]).can_act())

func test_banished_creatures_cannot_be_attacked() -> void:
	var fighter: Dictionary = HeroKit.create(&"fighter", Vector3.ZERO)
	var foe: Dictionary = dummy(Vector3(0, 0, -1))
	ActiveEffects.add(foe, {"kind": "banishment", "source_id": "cleric", "until": "concentration"})
	var state: GameState = GameState.new()
	state.actors = {"fighter": fighter, "foe": foe}
	assert_false(bool(CombatRules.attack_preview(state, "fighter", "foe")["legal"]))
	assert_false(CombatRules.conditions_for(foe).can_act())

func test_thorn_whip_pulls_the_target_closer() -> void:
	var state: GameState = GameState.new()
	state.actors = {"druid": HeroKit.create(&"druid", Vector3.ZERO), "foe": dummy(Vector3(0, 0, -8))}
	var events: Array[Dictionary] = DivineSpellEffects.spell_hit(state, "druid", "foe", {"spell_id": "thorn_whip"})
	assert_eq(events.size(), 1)
	assert_almost_eq((state.actors["foe"]["position"] as Vector3).z, -5.0, 0.01)
	state.actors["foe"]["position"] = Vector3(0, 0, -2)
	DivineSpellEffects.spell_hit(state, "druid", "foe", {"spell_id": "thorn_whip"})
	assert_almost_eq((state.actors["foe"]["position"] as Vector3).z, -1.5, 0.01, "Never closer than 1.5 m")

func test_heroism_grants_temporary_hit_points_and_courage() -> void:
	var ally: Dictionary = HeroKit.create(&"fighter", Vector3.ZERO)
	ActiveEffects.add(ally, {"kind": "heroism", "amount": 3, "until": "concentration"})
	var state: GameState = GameState.new()
	state.actors = {"ally": ally}
	DivineSpellEffects.on_turn_start(state, "ally")
	assert_eq(int(ally["temp_hp"]), 3)
	assert_true(ClassEffects.fear_immune(state, "ally"))

func test_beacon_of_hope_maximizes_healing() -> void:
	var ally: Dictionary = HeroKit.create(&"fighter", Vector3.ZERO)
	ActiveEffects.add(ally, {"kind": "beacon_of_hope", "until": "concentration"})
	var roll: DiceResult = Dice.roll("2d8", Rng.rng, [RuleModifier.new(3, &"spellcasting")])
	DivineSpellEffects.maximize_healing(ally, roll)
	assert_eq(roll.total, 19)
	assert_eq(DivineSpellEffects.save_advantages(ally, &"wis"), [&"beacon_of_hope"])

func test_magic_weapon_and_crusaders_mantle_on_weapon_hits() -> void:
	var paladin: Dictionary = hero(&"paladin", 9, Vector3.ZERO)
	var foe: Dictionary = dummy(Vector3(0, 0, -1))
	ActiveEffects.add(paladin, {"kind": "magic_weapon", "until": "rounds", "rounds_left": 600})
	paladin["concentration"] = {"spell_id": "crusaders_mantle", "rounds_left": 10, "slot_level": 3}
	var state: GameState = GameState.new()
	state.actors = {"paladin": paladin, "foe": foe}
	var weapon: Dictionary = paladin["weapon"]
	assert_eq(DivineSpellEffects.damage_modifiers(paladin, weapon)[0].amount, 1)
	assert_eq(ClassEffects.attack_modifiers(paladin, Rng.rng, weapon)[0].amount, 1)
	var events: Array[Dictionary] = []
	var riders: Array[Dictionary] = DivineSpellEffects.weapon_riders(state, "paladin", "foe", weapon, Rng.rng, events)
	assert_eq(String(riders[0]["source"]), "crusaders_mantle")

func test_greater_restoration_lifts_a_curse() -> void:
	var ally: Dictionary = HeroKit.create(&"fighter", Vector3.ZERO)
	ActiveEffects.add(ally, {"kind": "contagion", "spell_id": "contagion", "source_id": "foe", "until": "rounds", "rounds_left": 10})
	assert_true(CombatRules.conditions_for(ally).has(&"poisoned"))
	var state: GameState = GameState.new()
	state.actors = {"ally": ally}
	DivineSpellEffects.greater_restoration(state, "cleric", "ally")
	assert_false(CombatRules.conditions_for(ally).has(&"poisoned"))

func test_sanctuary_can_cost_an_attacker_its_attack() -> void:
	var fighter: Dictionary = HeroKit.create(&"fighter", Vector3.ZERO)
	var foe: Dictionary = dummy(Vector3(0, 0, -1))
	foe["ability_scores"][&"wis"] = 1
	ActiveEffects.add(fighter, {"kind": "sanctuary", "source_id": "cleric", "save_dc": 30, "until": "rounds", "rounds_left": 10})
	var state: GameState = GameState.new()
	state.mode = &"combat"
	state.actors = {"fighter": fighter, "foe": foe}
	var result: Dictionary = DivineSpellEffects.sanctuary(state, "foe", "fighter", Rng.rng)
	assert_true(bool(result["blocked"]))
	DivineSpellEffects.sanctuary(state, "fighter", "foe", Rng.rng)
	assert_false(ActiveEffects.has_kind(fighter, "sanctuary"), "Attacking ends the ward")

func test_charmed_creatures_cannot_attack_the_charmer() -> void:
	var druid: Dictionary = HeroKit.create(&"druid", Vector3.ZERO)
	var foe: Dictionary = dummy(Vector3(0, 0, -1))
	ActiveEffects.add(foe, {"kind": "charm_person", "source_id": "druid", "until": "damage", "rounds_left": 600})
	var state: GameState = GameState.new()
	state.actors = {"druid": druid, "foe": foe}
	assert_false(bool(CombatRules.attack_preview(state, "foe", "druid")["legal"]))
	ClassEffects.lose_hp(state, "foe", 1, Rng.rng)
	assert_true(bool(CombatRules.attack_preview(state, "foe", "druid")["legal"]), "Damage breaks the charm")

func test_freedom_of_movement_stops_hold_person() -> void:
	var cleric: Dictionary = hero(&"cleric", 3, Vector3.ZERO)
	var ally: Dictionary = HeroKit.create(&"fighter", Vector3(0, 0, -2))
	ActiveEffects.add(ally, {"kind": "freedom_of_movement", "until": "rounds", "rounds_left": 600})
	var state: GameState = GameState.new()
	state.actors = {"cleric": cleric, "ally": ally}
	assert_eq(ClassEffects.apply_effect(state, "cleric", "ally", SpellBook.get_spell("hold_person"), 2), [])
	assert_true(CombatRules.conditions_for(ally).can_act())

func test_fire_shield_burns_melee_attackers() -> void:
	var druid: Dictionary = HeroKit.create(&"druid", Vector3.ZERO)
	var foe: Dictionary = dummy(Vector3(0, 0, -1))
	ActiveEffects.add(druid, {"kind": "fire_shield", "until": "rounds", "rounds_left": 100})
	var state: GameState = GameState.new()
	state.actors = {"druid": druid, "foe": foe}
	DivineSpellEffects.retaliation(state, "foe", "druid", foe["weapon"], Rng.rng)
	assert_lt(int(foe["hp"]), 200)
	assert_true(&"cold" in CombatRules.defenses_for(druid).resistances)

func test_flaming_sphere_moves_with_its_bonus_action() -> void:
	var druid: Dictionary = hero(&"druid", 3, Vector3.ZERO, ["flaming_sphere"])
	start({"druid": druid, "foe": dummy(Vector3(0, 0, -12))}, ["druid", "foe"])
	assert_eq(cast("druid", "flaming_sphere", [], Vector3(0, 0, -5)), OK)
	assert_true("flaming_sphere_move" in Game.state.actors["druid"]["spells"])
	assert_eq(cast("druid", "flaming_sphere_move", [], Vector3(0, 0, -12)), OK)
	assert_almost_eq((Game.state.actors["druid"]["concentration"]["point"] as Vector3).z, -12.0, 0.01)
	assert_lt(int(Game.state.actors["foe"]["hp"]), 200, "Rammed")

func test_gust_of_wind_pushes_those_who_fail() -> void:
	var state: GameState = GameState.new()
	state.actors = {"druid": HeroKit.create(&"druid", Vector3.ZERO), "foe": dummy(Vector3(0, 0, -3))}
	DivineSpellEffects.failed_save(state, "druid", "foe", SpellBook.get_spell("gust_of_wind"), 2)
	assert_almost_eq((state.actors["foe"]["position"] as Vector3).z, -7.5, 0.01)

func test_remove_curse_leaves_contagion() -> void:
	var ally: Dictionary = HeroKit.create(&"fighter", Vector3.ZERO)
	ActiveEffects.add(ally, {"kind": "bestow_curse", "spell_id": "bestow_curse", "source_id": "foe", "until": "concentration"})
	ActiveEffects.add(ally, {"kind": "contagion", "spell_id": "contagion", "source_id": "foe", "until": "rounds", "rounds_left": 10})
	var state: GameState = GameState.new()
	state.actors = {"ally": ally}
	DivineSpellEffects.greater_restoration(state, "cleric", "ally", DivineSpellEffects.PURE_CURSES)
	assert_false(ActiveEffects.has_kind(ally, "bestow_curse"))
	assert_true(ActiveEffects.has_kind(ally, "contagion"))
