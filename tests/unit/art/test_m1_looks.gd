extends GutTest
## Prompt 07: enemies use their own models and weapons; bandits swap weapons per attack.


func test_each_enemy_role_has_its_own_model_and_weapon_models() -> void:
	var seen: Dictionary = {}
	for role: String in ["guard", "bandit", "cultist"]:
		var definition: MonsterDefinition = load("res://data/monsters/%s.tres" % role) as MonsterDefinition
		assert_true(definition.is_valid(), role)
		assert_false(seen.has(definition.model), "Not the shared 01b test model: " + role)
		assert_true(ResourceLoader.exists(definition.model), role)
		seen[definition.model] = true
		for attack: Dictionary in definition.attacks:
			assert_true(ResourceLoader.exists(String(attack.get("model", ""))), role + " " + String(attack["id"]))


func test_ranged_bandit_draws_scimitar_for_melee() -> void:
	var definition: MonsterDefinition = load("res://data/monsters/bandit.tres") as MonsterDefinition
	var actor: CombatActor = CombatActor.new()
	add_child_autofree(actor)
	var record: Dictionary = definition.create_actor("bandit", Vector3.ZERO)
	actor.setup_actor(record)
	assert_eq(actor.weapon_scene, "res://assets/weapons/light_crossbow.glb")
	assert_eq(actor.weapon_attachment.bone_name, "hand_l", "Crossbow in the extended release hand")
	var scimitar: Dictionary = definition.attacks.filter(func(a: Dictionary) -> bool: return a["id"] == "scimitar")[0]
	actor.update_actor(record, {"type": "attack", "actor_id": "bandit", "target_id": "hero",
		"weapon": scimitar, "duration": 0.8, "impact_time": 0.43, "elapsed": 0.1}, 0.016)
	assert_eq(actor.weapon_scene, "res://assets/weapons/scimitar.glb")
	assert_eq(actor.weapon_attachment.bone_name, "hand_r")


func test_cult_priest_uses_the_srd_priest_stat_block() -> void:
	# Package 10: the boss fights with the SRD 5.2 Priest (CR 2) numbers.
	var priest: MonsterDefinition = load("res://data/monsters/cult_priest.tres") as MonsterDefinition
	assert_true(ResourceLoader.exists(priest.model))
	assert_true(priest.is_valid())
	assert_eq(priest.srd_name, "Priest")
	assert_eq([priest.hit_points, priest.armor_class, priest.experience], [38, 13, 450])
	for attack: Dictionary in priest.attacks:
		assert_true(CombatRules.weapon_valid(attack), String(attack["id"]))
