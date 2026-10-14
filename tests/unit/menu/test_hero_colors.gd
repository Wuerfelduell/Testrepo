extends GutTest
## Per-piece hero colours (hero_colors.json): slots per look, cleaning, material overrides,
## the record and the save keep the choice.

func _model(scene: String) -> Node3D:
	var model: Node3D = (load(scene) as PackedScene).instantiate()
	add_child_autofree(model)
	return model

func _overrides(model: Node, material_name: String) -> Array[Material]:
	var result: Array[Material] = []
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface: int in mesh.mesh.get_surface_count():
			if mesh.mesh.surface_get_material(surface).resource_name == material_name:
				result.append(mesh.get_surface_override_material(surface))
	return result

func test_slots_follow_the_look() -> void:
	assert_eq(HeroColors.slots_for(_model("res://assets/characters/hero_fighter_male/model.glb")),
		["tunic", "leather", "plate", "mail"] as Array[String])
	assert_eq(HeroColors.slots_for(_model("res://assets/characters/hero_wizard_female_hat/model.glb")),
		["robe", "hat", "wizard_leather"] as Array[String])
	assert_eq(HeroColors.slots_for(_model("res://assets/characters/hero_wizard_male_hood/model.glb")),
		["robe", "wizard_leather"] as Array[String])
	assert_eq(HeroColors.slots_for(_model("res://assets/characters/hero_rogue_female/model.glb")),
		["rogue_cloth", "scarf", "rogue_leather"] as Array[String])

func test_every_slot_has_its_default_in_the_palette() -> void:
	for slot: String in HeroColors.data()["slots"]:
		assert_false(HeroColors.entry(slot, HeroColors.default_id(slot)).is_empty(), slot)
		assert_true(slot in HeroColors.data()["order"], slot)
	for spec: Dictionary in HeroColors.data()["materials"].values():
		if spec.has("mask"):
			assert_true(ResourceLoader.exists(spec["mask"]), spec["mask"])

func test_clean_drops_defaults_unknown_and_foreign_slots() -> void:
	var colors: Dictionary = {"tunic": "blood", "plate": "steel", "robe": "nope", "cape": "black", "mail": "brass"}
	assert_eq(HeroColors.clean(colors), {"tunic": "blood", "mail": "brass"})
	assert_eq(HeroColors.clean(colors, ["tunic"] as Array[String]), {"tunic": "blood"})
	assert_eq(HeroColors.clean("garbage"), {})
	assert_eq(HeroColors.signature({"mail": "brass", "tunic": "blood"}), "mail=brass,tunic=blood")

func test_apply_overrides_only_chosen_pieces_and_resets() -> void:
	var model: Node3D = _model("res://assets/characters/hero_fighter_male/model.glb")
	HeroColors.apply(model, {"tunic": "forest", "plate": "blackened"})
	for material: Material in _overrides(model, "FighterCloth"):
		assert_true(material is ShaderMaterial)
		assert_eq(material.get_shader_parameter("cloth_amount"), 1.0)
		assert_eq(material.get_shader_parameter("leather_amount"), 0.0, "Leather keeps its colour")
	for material: Material in _overrides(model, "FighterPlate"):
		assert_true((material as StandardMaterial3D).albedo_color.is_equal_approx(Color(0.26, 0.26, 0.28)))
	for material: Material in _overrides(model, "FighterMail"):
		assert_null(material, "Unchosen pieces keep the built material")
	HeroColors.apply(model, {})
	for material: Material in _overrides(model, "FighterCloth") + _overrides(model, "FighterPlate"):
		assert_null(material)

func test_record_and_save_keep_the_colours() -> void:
	var look: Dictionary = HeroLooks.for_class("fighter", "female")[0]
	var record: Dictionary = HeroFactory.build_record("fighter", look, "Brea", {"tunic": "wine", "plate": "steel"})
	assert_eq(record["colors"], {"tunic": "wine"})
	assert_eq(HeroFactory.build_record("fighter", look, "Brea")["colors"], {})
	var state: GameState = GameState.new()
	SetupArenaCommand.new(record).apply(state)
	var restored: GameState = GameState.from_dict(JSON.to_native(JSON.parse_string(JSON.stringify(JSON.from_native(state.to_dict())))))
	assert_eq(restored.actors["hero"]["colors"], {"tunic": "wine"})
