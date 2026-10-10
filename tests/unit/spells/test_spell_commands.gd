extends GutTest
## CastSpellCommand, timeline impacts, Shield reaction, concentration and Sleep.

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

class WallSpace extends CombatSpace:
	## Total cover for anything beyond x = 3.
	func cover(_from: Vector3, to: Vector3) -> int:
		return 99 if to.x > 3.0 else 0

var events: Array[Dictionary] = []

func enemy(position: Vector3, hp: int = 30) -> Dictionary:
	return {"team": "enemy", "position": position, "hp": hp, "max_hp": hp, "ac": 12, "dex": 10,
		"speed_m": 9.0, "move_left": 9.0, "action_available": true, "bonus_available": true,
		"reaction_available": true, "disengaged": false, "conditions": [], "effects": [],
		"ability_scores": {&"str": 10, &"dex": 10, &"con": 10, &"int": 10, &"wis": 10, &"cha": 10},
		"weapon": {"ranged": false, "reach": 1.5, "attack_bonus": 4, "damage_dice": "1d4",
			"damage_bonus": 0, "damage_type": "slashing"}}

func wizard(position: Vector3 = Vector3.ZERO) -> Dictionary:
	return HeroKit.create(&"wizard", position)

func start(actors: Dictionary, order: Array[String] = ["hero", "a", "b"]) -> void:
	var state: GameState = GameState.new()
	state.mode = &"combat"
	state.actors = actors
	var turn_order: Array[String] = []
	for id: String in order:
		if actors.has(id):
			turn_order.append(id)
	state.turn_order = turn_order
	CommandBus.submit(Setup.new(state))

func before_each() -> void:
	CombatSpace.active = null
	Rng.set_seed(1234)
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
	for step: int in 40:
		if Game.state.pending.is_empty() or Game.state.pending.get("type") == "reaction":
			return
		CommandBus.submit(AdvanceCombatCommand.new(0.1))

func test_magic_missile_spends_a_slot_and_hits_automatically_when_the_darts_arrive() -> void:
	start({"hero": wizard(), "a": enemy(Vector3(0, 0, -10), 40)})
	var before_rng: int = Rng.rng.state
	assert_eq(CommandBus.submit(CastSpellCommand.new("hero", "magic_missile", ["a", "a", "a"])), OK)
	assert_eq(Game.state.actors["hero"]["spell_slots"], [1])
	assert_false(bool(Game.state.actors["hero"]["action_available"]))
	assert_eq(Game.state.actors["a"]["hp"], 40, "no damage at cast time")
	assert_eq(Rng.rng.state, before_rng, "no RNG at cast time")
	finish()
	assert_true(of_type("roll", "attack").is_empty(), "Magic Missile never rolls to hit")
	var damage: Array[Dictionary] = of_type("damage")
	assert_eq(damage.size(), 1)
	assert_between(int(damage[0]["amount"]), 6, 15, "3d4+3")
	assert_eq(Game.state.actors["a"]["hp"], 40 - int(damage[0]["amount"]))

func test_magic_missile_can_split_darts_and_needs_the_right_dart_count() -> void:
	start({"hero": wizard(), "a": enemy(Vector3(0, 0, -6), 40), "b": enemy(Vector3(3, 0, -6), 40)})
	assert_eq(CommandBus.submit(CastSpellCommand.new("hero", "magic_missile", ["a", "b"])), ERR_INVALID_PARAMETER)
	assert_eq(CommandBus.submit(CastSpellCommand.new("hero", "magic_missile", ["a", "b", "b"])), OK)
	finish()
	assert_eq(of_type("damage").size(), 2)

func test_no_slot_left_rejects_level_one_spells_but_not_cantrips() -> void:
	var caster: Dictionary = wizard()
	caster["spell_slots"] = [0]
	start({"hero": caster, "a": enemy(Vector3(0, 0, -6))})
	assert_eq(CommandBus.submit(CastSpellCommand.new("hero", "magic_missile", ["a", "a", "a"])), ERR_UNAVAILABLE)
	assert_eq(CommandBus.submit(CastSpellCommand.new("hero", "fire_bolt", ["a"])), OK)

func test_cantrip_range_and_line_of_sight() -> void:
	CombatSpace.active = WallSpace.new()
	start({"hero": wizard(), "a": enemy(Vector3(0, 0, -20)), "b": enemy(Vector3(5, 0, -2))})
	assert_eq(CommandBus.submit(CastSpellCommand.new("hero", "ray_of_frost", ["a"])), ERR_INVALID_PARAMETER, "18 m range")
	assert_eq(CommandBus.submit(CastSpellCommand.new("hero", "fire_bolt", ["b"])), ERR_INVALID_PARAMETER, "behind total cover")
	assert_eq(CommandBus.submit(CastSpellCommand.new("hero", "fire_bolt", ["a"])), OK, "36 m range")

func test_fire_bolt_rolls_a_spell_attack_with_int_and_proficiency() -> void:
	start({"hero": wizard(), "a": enemy(Vector3(0, 0, -6))})
	CommandBus.submit(CastSpellCommand.new("hero", "fire_bolt", ["a"]))
	finish()
	var attack: Array[Dictionary] = of_type("roll", "attack")
	assert_eq(attack.size(), 1)
	var sources: Array = []
	for modifier: Dictionary in attack[0]["roll"]["modifiers"]:
		sources.append([modifier["source"], modifier["amount"]])
	assert_eq(sources, [["int", 2], ["proficiency", 2]])
	assert_eq(attack[0]["spell_id"], "fire_bolt")

func test_ray_of_frost_hit_reduces_speed_until_casters_next_turn() -> void:
	var caster: Dictionary = wizard()
	caster["spell_attack_modifiers"] = [{"amount": 40, "source": "int"}]
	start({"hero": caster, "a": enemy(Vector3(0, 0, -6), 200)})
	CommandBus.submit(CastSpellCommand.new("hero", "ray_of_frost", ["a"]))
	finish()
	assert_true(ActiveEffects.has_kind(Game.state.actors["a"], "speed_penalty"))
	CommandBus.submit(EndTurnCommand.new("hero"))
	assert_almost_eq(float(Game.state.actors["a"]["move_left"]), 6.0, 0.001)
	CommandBus.submit(EndTurnCommand.new("a"))
	assert_false(ActiveEffects.has_kind(Game.state.actors["a"], "speed_penalty"))

func test_burning_hands_cone_hits_who_is_inside_including_allies() -> void:
	var ally: Dictionary = enemy(Vector3(-1, 0, -2), 40)
	ally["team"] = "hero"
	start({"hero": wizard(), "a": enemy(Vector3(0, 0, -3), 40), "b": enemy(Vector3(0, 0, 4), 40),
		"c": enemy(Vector3(4, 0, -1), 40), "ally": ally})
	var aim: Vector3 = Vector3(0, 0, -4)
	var preview: Dictionary = SpellResolver.preview(Game.state, "hero", "burning_hands", 0, [], aim)
	var ids: Array = []
	for target: Dictionary in preview["targets"]:
		ids.append(target["id"])
	ids.sort()
	assert_eq(ids, ["a", "ally"], "in front: enemy and ally; behind and beside: no")
	assert_eq(CommandBus.submit(CastSpellCommand.new("hero", "burning_hands", [], aim)), OK)
	finish()
	assert_eq(of_type("roll", "damage").size(), 1, "one damage roll for the whole area")
	assert_eq(of_type("roll", "save").size(), 2)
	for save: Dictionary in of_type("roll", "save"):
		assert_eq(save["dc"], 12)
		assert_eq(save["ability"], "dex")
	assert_lt(int(Game.state.actors["ally"]["hp"]), 40)
	assert_eq(Game.state.actors["b"]["hp"], 40)
	assert_eq(Game.state.actors["c"]["hp"], 40)

func test_successful_save_halves_burning_hands_damage() -> void:
	var tough: Dictionary = enemy(Vector3(0, 0, -2), 100)
	tough["saving_throws"] = {&"dex": 40}
	start({"hero": wizard(), "a": tough})
	CommandBus.submit(CastSpellCommand.new("hero", "burning_hands", [], Vector3(0, 0, -4)))
	finish()
	var rolled: int = int(of_type("roll", "damage")[0]["amount"])
	assert_true(bool(of_type("roll", "save")[0]["success"]))
	assert_eq(Game.state.actors["a"]["hp"], 100 - floori(rolled / 2.0))

func shield_setup() -> void:
	var caster: Dictionary = wizard(Vector3.ZERO)
	var attacker: Dictionary = enemy(Vector3(1, 0, 0))
	start({"hero": caster, "a": attacker}, ["a", "hero"])

func roll_until_shield_offer() -> bool:
	# Find a seed where the hit misses with +5 AC (AC 12, +4: totals 12-16).
	for seed_value: int in range(1, 200):
		shield_setup()
		Rng.set_seed(seed_value)
		events.clear()
		CommandBus.submit(AttackCommand.new("a", "hero"))
		finish()
		if Game.state.pending.get("type") == "reaction":
			return true
	return false

func test_shield_is_offered_on_a_hit_before_damage_and_turns_it_into_a_miss() -> void:
	assert_true(roll_until_shield_offer())
	assert_eq(of_type("reaction_offer").size(), 1)
	assert_true(of_type("damage").is_empty(), "no damage while the reaction is pending")
	assert_eq(of_type("roll", "attack").size(), 0, "the attack shows after the decision")
	var hp: int = Game.state.actors["hero"]["hp"]
	assert_eq(CommandBus.submit(AdvanceCombatCommand.new(0.1)), ERR_BUSY, "time waits for the decision")
	assert_eq(CommandBus.submit(CastReactionCommand.new("a", true)), ERR_UNAUTHORIZED)
	assert_eq(CommandBus.submit(CastReactionCommand.new("hero", true)), OK)
	assert_eq(Game.state.actors["hero"]["hp"], hp)
	assert_eq(Game.state.actors["hero"]["spell_slots"], [1])
	assert_false(bool(Game.state.actors["hero"]["reaction_available"]))
	var attack: Array[Dictionary] = of_type("roll", "attack")
	assert_eq(attack.size(), 1)
	assert_false(bool(attack[0]["hit"]))
	assert_eq(attack[0]["armor_class"], int(Game.state.actors["hero"]["ac"]) + 5)
	finish()
	assert_true(Game.state.pending.is_empty())
	# +5 AC lasts until the start of the wizard's next turn.
	var base_ac: int = int(Game.state.actors["hero"]["ac"])
	assert_eq(int(CombatRules.attack_preview(Game.state, "a", "hero")["armor_class"]), base_ac + 5)
	CommandBus.submit(EndTurnCommand.new("a"))
	assert_eq(int(CombatRules.attack_preview(Game.state, "a", "hero")["armor_class"]), base_ac)

func test_declining_shield_applies_the_hit() -> void:
	assert_true(roll_until_shield_offer())
	var hp: int = Game.state.actors["hero"]["hp"]
	assert_eq(CommandBus.submit(CastReactionCommand.new("hero", false)), OK)
	assert_true(bool(of_type("roll", "attack")[0]["hit"]))
	assert_lt(int(Game.state.actors["hero"]["hp"]), hp)
	assert_eq(Game.state.actors["hero"]["spell_slots"], [2])

func test_shield_is_not_offered_without_slot_or_when_it_cannot_help() -> void:
	shield_setup()
	var state: GameState = Game.state
	state.actors["hero"]["spell_slots"] = [0]
	CommandBus.submit(Setup.new(state))
	for seed_value: int in range(1, 40):
		Rng.set_seed(seed_value)
		var current: GameState = Game.state
		current.actors["a"]["action_available"] = true
		current.actors["hero"]["hp"] = 8
		CommandBus.submit(Setup.new(current))
		CommandBus.submit(AttackCommand.new("a", "hero"))
		finish()
		assert_ne(Game.state.pending.get("type"), "reaction")
	shield_setup()
	var strong: GameState = Game.state
	strong.actors["a"]["weapon"]["attack_bonus"] = 30
	CommandBus.submit(Setup.new(strong))
	CommandBus.submit(AttackCommand.new("a", "hero"))
	finish()
	assert_ne(Game.state.pending.get("type"), "reaction", "+5 AC cannot stop a total of 31+")

func test_shield_blocks_magic_missile() -> void:
	var target_wizard: Dictionary = wizard(Vector3(0, 0, -6))
	target_wizard["team"] = "enemy"
	target_wizard["id"] = "a"
	start({"hero": wizard(), "a": target_wizard})
	CommandBus.submit(CastSpellCommand.new("hero", "magic_missile", ["a", "a", "a"]))
	finish()
	assert_eq(Game.state.pending.get("type"), "reaction")
	assert_eq(CommandBus.submit(CastReactionCommand.new("a", true)), OK)
	finish()
	assert_eq(of_type("spell_blocked").size(), 1)
	assert_true(of_type("damage").is_empty())
	assert_eq(Game.state.actors["a"]["hp"], Game.state.actors["a"]["max_hp"])

func test_sleep_affects_only_enemies_in_the_sphere_and_needs_concentration() -> void:
	var ally: Dictionary = enemy(Vector3(0.5, 0, -8), 40)
	ally["team"] = "hero"
	var drowsy: Dictionary = enemy(Vector3(0, 0, -8), 40)
	drowsy["saving_throws"] = {&"wis": -30}
	start({"hero": wizard(), "a": drowsy, "b": enemy(Vector3(6, 0, -8)), "ally": ally})
	Rng.set_seed(5)
	assert_eq(CommandBus.submit(CastSpellCommand.new("hero", "sleep", [], Vector3(0, 0, -8))), OK)
	assert_eq(Game.state.actors["hero"]["concentration"]["spell_id"], "sleep")
	finish()
	var saves: Array[Dictionary] = of_type("roll", "save")
	assert_eq(saves.size(), 1, "only the enemy inside the sphere saves")
	assert_eq(saves[0]["target_id"], "a")
	assert_false(bool(saves[0]["success"]))
	assert_has(Game.state.actors["a"]["conditions"], "incapacitated")
	assert_false(CombatRules.can_use_action(Game.state.actors["a"]))

func sleeping_setup() -> void:
	var drowsy: Dictionary = enemy(Vector3(0, 0, -8), 40)
	drowsy["ability_scores"][&"wis"] = 1
	drowsy["saving_throws"] = {&"wis": -30}
	start({"hero": wizard(), "a": drowsy, "b": enemy(Vector3(1, 0, 0.5), 40)})
	CommandBus.submit(CastSpellCommand.new("hero", "sleep", [], Vector3(0, 0, -8)))
	finish()

func test_sleep_deepens_to_unconscious_after_a_second_failed_save() -> void:
	sleeping_setup()
	assert_has(Game.state.actors["a"]["conditions"], "incapacitated")
	CommandBus.submit(EndTurnCommand.new("hero"))
	CommandBus.submit(EndTurnCommand.new("a"))
	assert_has(Game.state.actors["a"]["conditions"], "unconscious")
	assert_does_not_have(Game.state.actors["a"]["conditions"], "incapacitated")

func test_damage_ends_sleep_on_that_creature() -> void:
	sleeping_setup()
	var state: GameState = Game.state
	state.actors["hero"]["action_available"] = true
	state.actors["hero"]["spell_attack_modifiers"] = [{"amount": 40, "source": "int"}]
	CommandBus.submit(Setup.new(state))
	CommandBus.submit(CastSpellCommand.new("hero", "fire_bolt", ["a"]))
	finish()
	assert_false(of_type("damage").is_empty())
	assert_does_not_have(Game.state.actors["a"]["conditions"], "incapacitated")
	assert_true(ActiveEffects.effects(Game.state.actors["a"]).is_empty())

func test_concentration_breaks_on_a_failed_con_save_and_wakes_sleepers() -> void:
	sleeping_setup()
	var state: GameState = Game.state
	state.actors["hero"]["ability_scores"][&"con"] = 1
	state.actors["hero"]["hp"] = 100
	state.actors["hero"]["max_hp"] = 100
	state.actors["b"]["weapon"]["attack_bonus"] = 50
	state.actors["b"]["weapon"]["damage_dice"] = "1d2"
	state.turn_order = ["b", "hero", "a"]
	state.turn_index = 0
	CommandBus.submit(Setup.new(state))
	var broke: bool = false
	for attempt: int in 20:
		CommandBus.submit(AttackCommand.new("b", "hero"))
		finish()
		if Game.state.actors["hero"]["concentration"].is_empty():
			broke = true
			break
		var again: GameState = Game.state
		again.actors["b"]["action_available"] = true
		CommandBus.submit(Setup.new(again))
	assert_true(broke, "CON 1 eventually fails DC 10")
	var save: Array[Dictionary] = of_type("roll", "save").filter(func(event: Dictionary) -> bool: return bool(event.get("concentration", false)))
	assert_false(save.is_empty())
	assert_eq(save[0]["dc"], 10)
	assert_eq(of_type("concentration_end").size(), 1)
	assert_does_not_have(Game.state.actors["a"]["conditions"], "incapacitated")

func test_concentration_ends_when_the_duration_runs_out() -> void:
	sleeping_setup()
	for round_index: int in 10:
		CommandBus.submit(EndTurnCommand.new("hero"))
		CommandBus.submit(EndTurnCommand.new("a"))
		CommandBus.submit(EndTurnCommand.new("b"))
	assert_true(Game.state.actors["hero"]["concentration"].is_empty())
	assert_true(ActiveEffects.effects(Game.state.actors["a"]).is_empty())

func test_cast_spell_codec_round_trip_and_rejections() -> void:
	var command: CastSpellCommand = CastSpellCommand.new("hero", "burning_hands", [], Vector3(1, 0, 2), 1)
	var decoded: Command = CommandCodec.decode(JSON.parse_string(JSON.stringify(command.to_dict())))
	assert_true(decoded is CastSpellCommand)
	assert_eq((decoded as CastSpellCommand).point, Vector3(1, 0, 2))
	assert_eq((decoded as CastSpellCommand).slot_level, 1)
	assert_true(CommandCodec.decode(CastReactionCommand.new("hero", true).to_dict()) is CastReactionCommand)
	assert_null(CommandCodec.decode({"type": "cast_spell", "actor_id": "hero", "spell_id": "x", "slot_level": 1.5, "target_ids": [], "point": []}))
	assert_null(CommandCodec.decode({"type": "cast_spell", "actor_id": "hero", "spell_id": "x", "slot_level": 1, "target_ids": [3], "point": []}))
	assert_null(CommandCodec.decode({"type": "cast_reaction", "actor_id": "hero", "accept": "yes"}))
	assert_null(CommandCodec.decode({"type": "debug_swap_hero", "actor_id": "hero"}), "debug switch stays local")

func test_reaction_spells_cannot_be_cast_as_actions() -> void:
	start({"hero": wizard(), "a": enemy(Vector3(0, 0, -6))})
	assert_eq(CommandBus.submit(CastSpellCommand.new("hero", "shield", [])), ERR_INVALID_PARAMETER)

func test_debug_swap_switches_classes_only_outside_combat() -> void:
	start({"hero": HeroKit.create(&"fighter"), "a": enemy(Vector3(0, 0, -6))})
	assert_eq(CommandBus.submit(DebugSwapHeroCommand.new()), ERR_UNAVAILABLE)
	var state: GameState = Game.state
	state.mode = &"exploration"
	CommandBus.submit(Setup.new(state))
	assert_eq(CommandBus.submit(DebugSwapHeroCommand.new()), OK)
	assert_eq(Game.state.actors["hero"]["class_id"], "wizard")
	assert_eq(Game.state.actors["hero"]["position"], Vector3(0, 0, 7))
	assert_eq(CommandBus.submit(DebugSwapHeroCommand.new()), OK)
	assert_eq(Game.state.actors["hero"]["class_id"], "fighter")
