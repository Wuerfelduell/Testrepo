extends GutTest
## Integration against real imported clips, not mock animations.

var actor: CombatActor


func before_each() -> void:
	actor = CombatActor.new()
	add_child_autofree(actor)
	actor.setup_actor(_record())


func _record() -> Dictionary:
	return {"id": "test_hero", "team": "hero", "name_key": "GALLERY_BASE_MALE",
		"model": "res://assets/characters/superhero_male_fullbody/model.glb",
		"position": Vector3.ZERO, "hp": 12, "max_hp": 12,
		"weapon": {"ranged": false, "model": "res://assets/weapons/sword.glb"}}


func test_combat_states_use_real_rigged_animation_tracks() -> void:
	for clip: String in ["Idle", "Walk", "Jog_Fwd", "Sprint", "Sword_Attack", "Hit_Chest", "Death01", "Spell_Simple_Shoot"]:
		assert_true(actor.player.has_animation(clip), clip)
		assert_gt(actor.player.get_animation(clip).get_track_count(), 0, clip)
	assert_false(actor.available.has("A_TPose"))
	assert_not_null(actor.weapon_attachment)
	assert_eq(actor.weapon_attachment.bone_name, "hand_r")


func test_authoritative_impact_clock_seeks_the_actual_sword_sweep() -> void:
	var pending: Dictionary = {"type": "attack", "actor_id": "test_hero", "target_id": "enemy",
		"elapsed": 0.4, "impact_time": 0.4, "duration": 0.8}
	actor.update_actor(_record(), pending, 0.016)
	assert_eq(actor.animation_state, "attack")
	assert_eq(actor.player.current_animation, "Sword_Attack")
	assert_almost_eq(actor.player.current_animation_position, CombatActor.SWORD_CONTACT_SECONDS, 0.0001)
	assert_eq(int(_record()["hp"]), 12, "Presentation does not apply damage")


func test_movement_drives_gait_and_stopping_returns_to_idle() -> void:
	var record: Dictionary = _record()
	record["position"] = Vector3(0.0, 0.0, 0.093)
	actor.update_actor(record, {"type": "move", "actor_id": "test_hero"}, 0.1)
	assert_eq(actor.animation_state, "walk")
	assert_almost_eq(actor.player.current_animation_position, 0.1, 0.001)
	assert_eq(actor.global_position, record["position"])
	actor.update_actor(record, {}, 0.1)
	assert_eq(actor.animation_state, "idle")
	record["position"] = Vector3(0.0, 0.0, 0.543)
	actor.update_actor(record, {}, 0.1)
	assert_eq(actor.animation_state, "sprint")


func test_opportunity_sidearm_uses_melee_clip_and_empty_override_uses_primary_weapon() -> void:
	var record: Dictionary = _record()
	record["weapon"] = {"ranged": true}
	var pending: Dictionary = {"type": "attack", "actor_id": "test_hero", "target_id": "enemy",
		"opportunity": true, "weapon": {"ranged": false, "name_key": "WEAPON_SCIMITAR"},
		"elapsed": 0.4, "impact_time": 0.4, "duration": 0.8}
	actor.update_actor(record, pending, 0.016)
	assert_eq(actor.player.current_animation, "Sword_Attack", "An opportunity sidearm must not use the primary ranged gesture")
	assert_almost_eq(actor.player.current_animation_position, CombatActor.SWORD_CONTACT_SECONDS, 0.0001)
	pending["weapon"] = {}
	actor.update_actor(record, pending, 0.016)
	assert_eq(actor.player.current_animation, "Spell_Simple_Shoot", "An empty override falls back to the primary ranged weapon")
	assert_almost_eq(actor.player.current_animation_position, CombatActor.RANGED_RELEASE_SECONDS, 0.0001)


func test_death_holds_the_final_pose_without_restarting_or_tpose() -> void:
	var record: Dictionary = _record()
	record["hp"] = 0
	actor.update_actor(record, {}, 0.1)
	for index: int in range(40):
		actor.update_actor(record, {}, 0.1)
	assert_eq(actor.animation_state, "death")
	assert_eq(actor.player.assigned_animation, "Death01")
	assert_false(actor.player.is_playing())
	assert_almost_eq(actor.player.current_animation_position, actor.player.get_animation("Death01").length, 0.0001)
	assert_eq((actor.get_node("ActorPick") as Area3D).collision_layer, 0)


func test_model_front_faces_attack_target() -> void:
	actor.aim_at(Vector3(3.0, 5.0, 0.0))
	assert_gt(actor.global_basis.z.dot(Vector3.RIGHT), 0.999)
	assert_almost_eq(actor.rotation.x, 0.0, 0.0001, "A higher target must not tilt the whole body")


func test_overkill_displays_full_damage_once_instead_of_clamped_hp_loss() -> void:
	var record: Dictionary = _record()
	record["hp"] = 1
	actor.update_actor(record, {}, 0.016)
	assert_eq(_damage_numbers().size(), 0, "State sync alone must not invent damage events")
	actor.react_to_event({"type": "damage", "actor_id": "enemy", "target_id": "test_hero",
		"amount": 10, "damage_type": "slashing", "hp": 0})
	record["hp"] = 0
	actor.update_actor(record, {}, 0.016)
	var labels: Array[Label3D] = _damage_numbers()
	assert_eq(labels.size(), 1, "The event and subsequent state update must not duplicate the number")
	assert_eq(labels[0].text, tr("COMBAT_DAMAGE_NUMBER") % 10)
	assert_eq(actor.animation_state, "death")


func test_mixed_damage_events_keep_separate_amounts_colors_and_positions() -> void:
	actor.react_to_event({"type": "damage", "actor_id": "cultist", "target_id": "test_hero",
		"amount": 1, "damage_type": "necrotic", "hp": 11})
	actor.react_to_event({"type": "damage", "actor_id": "cultist", "target_id": "test_hero",
		"amount": 6, "damage_type": "slashing", "hp": 5})
	var record: Dictionary = _record()
	record["hp"] = 5
	actor.update_actor(record, {}, 0.016)
	var labels: Array[Label3D] = _damage_numbers()
	assert_eq(labels.size(), 2)
	assert_eq(labels[0].text, tr("COMBAT_DAMAGE_NUMBER") % 1)
	assert_eq(labels[1].text, tr("COMBAT_DAMAGE_NUMBER") % 6)
	assert_eq(labels[0].modulate, Color("b482e9"))
	assert_eq(labels[1].modulate, Color("ffddd3"))
	assert_ne(labels[0].position, labels[1].position)
	assert_eq(actor.animation_state, "hit")


func _damage_numbers() -> Array[Label3D]:
	var result: Array[Label3D] = []
	for child: Node in actor.get_children():
		if child is Label3D and child.has_meta("damage_amount"):
			result.append(child as Label3D)
	return result
