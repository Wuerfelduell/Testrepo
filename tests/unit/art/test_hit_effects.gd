extends GutTest
## Prompt 07: which combat event shows which hit effect, and that effects clean up.


func test_physical_damage_bleeds_and_critical_bleeds_harder() -> void:
	var damage: Dictionary = {"type": "damage", "target_id": "a", "amount": 5, "damage_type": "slashing"}
	assert_eq(HitEffects.effect_for(damage, 1.2, false), HitEffects.BLOOD)
	assert_eq(HitEffects.effect_for(damage, 1.2, true), HitEffects.BLOOD_CRITICAL)
	damage["damage_type"] = "piercing"
	assert_eq(HitEffects.effect_for(damage, 20.0, false), HitEffects.BLOOD, "Crossbow bolts bleed too")


func test_spell_damage_and_zero_damage_do_not_bleed() -> void:
	assert_eq(HitEffects.effect_for({"type": "damage", "amount": 6, "damage_type": "fire"}, 1.0, false), HitEffects.NONE)
	assert_eq(HitEffects.effect_for({"type": "damage", "amount": 0, "damage_type": "slashing"}, 1.0, false), HitEffects.NONE)


func test_missed_melee_sparks_but_missed_ranged_does_not() -> void:
	var miss: Dictionary = {"type": "roll", "kind": "attack", "hit": false, "critical": false}
	assert_eq(HitEffects.effect_for(miss, 1.5, false), HitEffects.SPARKS)
	assert_eq(HitEffects.effect_for(miss, 9.0, false), HitEffects.NONE)
	miss["hit"] = true
	assert_eq(HitEffects.effect_for(miss, 1.5, false), HitEffects.NONE, "The damage event shows a hit")


func test_death_raises_dust() -> void:
	assert_eq(HitEffects.effect_for({"type": "death", "actor_id": "a"}, 1.0, false), HitEffects.DUST)


func test_effects_spawn_particles_and_free_themselves() -> void:
	var world: Node3D = Node3D.new()
	add_child_autofree(world)
	for effect: StringName in [HitEffects.BLOOD, HitEffects.BLOOD_CRITICAL, HitEffects.SPARKS, HitEffects.DUST]:
		var node: Node3D = HitEffects.spawn(world, effect, Vector3(0, 1.2, 0), Vector3.FORWARD)
		assert_not_null(node, String(effect))
		assert_gt(node.find_children("*", "CPUParticles3D", true, false).size(), 0, String(effect))
	assert_eq(world.find_children("BloodStain*", "MeshInstance3D", true, false).size(), 2, "Each hit leaves a floor stain")
	await wait_seconds(3.0)
	assert_eq(world.find_children("*", "CPUParticles3D", true, false).size(), 0, "Particles free themselves")


func test_combat_actor_shows_blood_where_the_attack_lands() -> void:
	var world: Node3D = Node3D.new()
	add_child_autofree(world)
	var guard: CombatActor = CombatActor.new()
	world.add_child(guard)
	guard.setup_actor({"id": "guard", "team": "enemy", "name_key": "ACTOR_GUARD", "hp": 11, "max_hp": 11,
		"model": "res://assets/characters/enemy_guard/model.glb", "position": Vector3.ZERO,
		"weapon": {"ranged": false, "model": "res://assets/weapons/spear.glb"}})
	var hero: CombatActor = CombatActor.new()
	world.add_child(hero)
	hero.setup_actor({"id": "hero", "team": "hero", "name_key": "ACTOR_FIGHTER", "hp": 12, "max_hp": 12,
		"model": "res://assets/characters/hero_fighter_male/model.glb", "position": Vector3(0, 0, 1.4),
		"weapon": {"ranged": false, "model": "res://assets/weapons/sword.glb"}})
	var actors: Dictionary = {"guard": guard, "hero": hero}
	assert_not_null(guard.offhand, "The guard look equips its shield")
	assert_not_null(hero.offhand, "The fighter look equips its shield")
	guard.react_to_event({"type": "roll", "kind": "attack", "actor_id": "hero", "target_id": "guard", "hit": true, "critical": true}, actors)
	guard.react_to_event({"type": "damage", "actor_id": "hero", "target_id": "guard", "amount": 9, "damage_type": "slashing", "hp": 2}, actors)
	var sprays: Array[Node] = world.find_children("BloodSpray", "Node3D", false, false)
	assert_eq(sprays.size(), 1)
	assert_gt((sprays[0] as Node3D).global_position.z, 0.0, "Blood leaves the side facing the attacker")
	assert_gt(sprays[0].find_children("*", "OmniLight3D", true, false).size(), 0, "A critical hit adds the heavy flash")
