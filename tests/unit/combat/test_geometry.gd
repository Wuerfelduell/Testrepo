extends GutTest

class TestSpace extends CombatSpace:
	var cover_value: int = 0
	var supplied_path: PackedVector3Array = PackedVector3Array()

	func cover(_from: Vector3, _to: Vector3) -> int:
		return cover_value

	func query_path(from: Vector3, to: Vector3) -> PackedVector3Array:
		return supplied_path if not supplied_path.is_empty() else PackedVector3Array([from, to])

var space: TestSpace
var state: GameState

func actor(team: String, position: Vector3, ranged: bool = false) -> Dictionary:
	return {"team": team, "position": position, "hp": 20, "max_hp": 20, "ac": 15,
		"reaction_available": true, "action_available": true, "disengaged": false,
		"speed_m": 9.0, "move_left": 9.0, "dex": 14,
		"weapon": {"ranged": ranged, "reach": 1.5, "range": 12.0, "long_range": 36.0,
			"attack_bonus": 5, "damage_dice": "1d8", "damage_bonus": 3, "damage_type": "piercing"}}

func before_each() -> void:
	space = TestSpace.new()
	CombatSpace.active = space
	state = GameState.new()
	state.actors = {"hero": actor("hero", Vector3.ZERO, true),
		"enemy": actor("enemy", Vector3(6, 0, 0))}

func after_each() -> void:
	CombatSpace.active = null

func test_path_cost_is_actual_three_dimensional_route_not_endpoint_distance() -> void:
	var path: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3(3, 4, 0), Vector3(3, 4, 2)])
	assert_almost_eq(CombatRules.path_length(path), 7.0, 0.00001)
	assert_lt(CombatRules.position_on_path(path, 6.0).distance_to(Vector3(3, 4, 1)), 0.00001)

func test_half_and_three_quarters_cover_raise_ac_without_disadvantage() -> void:
	var clear: Dictionary = CombatRules.attack_preview(state, "hero", "enemy")
	assert_almost_eq(float(clear["chance"]), 0.55, 0.00001)
	space.cover_value = 2
	var half: Dictionary = CombatRules.attack_preview(state, "hero", "enemy")
	assert_eq(half["armor_class"], 17)
	assert_almost_eq(float(half["chance"]), 0.45, 0.00001)
	assert_eq(half["advantage"], 0)
	space.cover_value = 5
	assert_almost_eq(float(CombatRules.attack_preview(state, "hero", "enemy")["chance"]), 0.30, 0.00001)
	space.cover_value = 99
	assert_false(bool(CombatRules.attack_preview(state, "hero", "enemy")["legal"]))

func test_height_advantage_cancels_long_range_disadvantage() -> void:
	state.actors["hero"]["position"] = Vector3(0, 2, 0)
	var high: Dictionary = CombatRules.attack_preview(state, "hero", "enemy")
	assert_eq(high["advantage"], 1)
	assert_almost_eq(float(high["chance"]), 1.0 - 0.45 * 0.45, 0.00001)
	state.actors["enemy"]["position"] = Vector3(15, 0, 0)
	assert_eq(CombatRules.attack_preview(state, "hero", "enemy")["advantage"], 0)
	state.actors["enemy"]["position"] = Vector3(40, 0, 0)
	assert_false(bool(CombatRules.attack_preview(state, "hero", "enemy")["legal"]))

func test_ranged_close_hostile_disadvantages_attack_on_a_different_target() -> void:
	state.actors["nearby"] = actor("enemy", Vector3(1, 0, 0))
	assert_eq(CombatRules.attack_preview(state, "hero", "enemy")["advantage"], -1)
	state.actors["nearby"]["hp"] = 0
	assert_eq(CombatRules.attack_preview(state, "hero", "enemy")["advantage"], 0)

func test_chance_preview_and_geometry_consume_no_rng() -> void:
	Rng.set_seed(504)
	var before: int = Rng.rng.state
	for index: int in range(50):
		CombatRules.attack_preview(state, "hero", "enemy")
		CombatRules.movement_path(state, "hero", Vector3.ONE)
	assert_eq(Rng.rng.state, before)

func test_opportunity_attack_detects_enter_then_exit_even_with_both_endpoints_outside() -> void:
	state.actors["hero"]["position"] = Vector3.ZERO
	state.actors["enemy"]["position"] = Vector3(3, 0, 0)
	var path: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3(6, 0, 0)])
	var exits: Array[Dictionary] = CombatRules.opportunity_crossings(state, "hero", path)
	assert_eq(exits.size(), 1)
	assert_almost_eq(float(exits[0]["distance"]), 4.5, 0.00001)
	assert_eq(exits[0]["position"], Vector3(4.5, 0, 0))

func test_ending_at_reach_is_safe_but_leaving_at_next_segment_provokes() -> void:
	state.actors["enemy"]["position"] = Vector3.ZERO
	var stop: PackedVector3Array = PackedVector3Array([Vector3(1, 0, 0), Vector3(1.5, 0, 0)])
	assert_eq(CombatRules.opportunity_crossings(state, "hero", stop).size(), 0)
	stop.append(Vector3(2, 0, 0))
	var exits: Array[Dictionary] = CombatRules.opportunity_crossings(state, "hero", stop)
	assert_eq(exits.size(), 1)
	assert_almost_eq(float(exits[0]["distance"]), 0.5, 0.00001)

func test_disengage_spent_reaction_and_no_sight_prevent_opportunity_attacks() -> void:
	state.actors["enemy"]["position"] = Vector3(1, 0, 0)
	var path: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3(5, 0, 0)])
	state.actors["hero"]["disengaged"] = true
	assert_eq(CombatRules.opportunity_crossings(state, "hero", path).size(), 0)
	state.actors["hero"]["disengaged"] = false
	state.actors["enemy"]["reaction_available"] = false
	assert_eq(CombatRules.opportunity_crossings(state, "hero", path).size(), 0)
	state.actors["enemy"]["reaction_available"] = true
	space.cover_value = 99
	assert_eq(CombatRules.opportunity_crossings(state, "hero", path).size(), 0)

func test_malformed_nav_paths_are_rejected() -> void:
	space.supplied_path = PackedVector3Array([Vector3.ONE, Vector3(5, 0, 0)])
	assert_true(CombatRules.movement_path(state, "hero", Vector3(5, 0, 0)).is_empty())
	space.supplied_path = PackedVector3Array([Vector3.ZERO, Vector3(NAN, 0, 0), Vector3(5, 0, 0)])
	assert_true(CombatRules.movement_path(state, "hero", Vector3(5, 0, 0)).is_empty())
	space.supplied_path = PackedVector3Array([Vector3.ZERO, Vector3(3, 0, 0)])
	assert_true(CombatRules.movement_path(state, "hero", Vector3(5, 0, 0)).is_empty())

func test_opportunity_attack_uses_melee_sidearm_when_primary_weapon_is_ranged() -> void:
	state.actors["enemy"]["position"] = Vector3(1, 0, 0)
	var sword: Dictionary = state.actors["enemy"]["weapon"].duplicate(true)
	state.actors["enemy"]["weapon"]["ranged"] = true
	state.actors["enemy"]["attacks"] = [state.actors["enemy"]["weapon"].duplicate(true), sword]
	var path: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3(5, 0, 0)])
	var crossings: Array[Dictionary] = CombatRules.opportunity_crossings(state, "hero", path)
	assert_eq(crossings.size(), 1)
	assert_false(bool(crossings[0]["weapon"]["ranged"]))

func test_invalid_weapon_statistics_fail_closed_without_rng_or_type_errors() -> void:
	for invalid: Dictionary in [
		{"damage_dice": "invalid"}, {"range": NAN}, {"reach": -1.0},
		{"attack_modifiers": ["forged"]}, {"damage_modifiers": [{"source": "str", "amount": "3"}]},
		{"extra_damage": [{"amount": -1, "damage_type": "necrotic", "source": "ritual_sickle"}]}]:
		var weapon: Dictionary = actor("hero", Vector3.ZERO, true)["weapon"]
		weapon.merge(invalid, true)
		state.actors["hero"]["weapon"] = weapon
		assert_false(bool(CombatRules.attack_preview(state, "hero", "enemy")["legal"]))
