extends Node3D
## An asset inspection room only. Foundation/gameplay follows the coordinator's next prompts.

const ACTOR_SCRIPT: Script = preload("res://src/showcase/preview_actor.gd")
const CLIPS: PackedStringArray = ["Idle", "Walk", "Sprint", "Sword_Attack", "Spell_Simple_Shoot", "Hit_Chest", "Death01"]
const CLIP_KEYS: PackedStringArray = ["GALLERY_ANIMATION_IDLE", "GALLERY_ANIMATION_WALK", "GALLERY_ANIMATION_RUN", "GALLERY_ANIMATION_MELEE", "GALLERY_ANIMATION_CAST", "GALLERY_ANIMATION_HIT", "GALLERY_ANIMATION_DEATH"]
const MODELS: Array[String] = ["superhero_male_fullbody", "superhero_female_fullbody", "male_peasant", "female_peasant", "male_ranger", "female_ranger"]
const MODEL_KEYS: PackedStringArray = ["GALLERY_BASE_MALE", "GALLERY_BASE_FEMALE", "GALLERY_PEASANT_MALE", "GALLERY_PEASANT_FEMALE", "GALLERY_RANGER_MALE", "GALLERY_RANGER_FEMALE"]
const SAMPLE_POSITIONS: Array[Vector3] = [Vector3(2.2, 0, 2.8), Vector3(-3.6, 0, 0.2), Vector3(-0.7, 0, 0.2), Vector3(2.2, 0, 0.2), Vector3(-3.6, 0, 2.8), Vector3(-0.7, 0, 2.8)]
# Prompt 07 (M1 art): enemies and the boss in one row, hero looks in the next, weapons in front.
const M1_ENEMIES: Array[String] = ["enemy_guard", "enemy_bandit", "enemy_cultist", "boss_cult_priest"]
const M1_ENEMY_KEYS: PackedStringArray = ["ACTOR_GUARD", "ACTOR_BANDIT", "ACTOR_CULTIST", "ACTOR_CULT_PRIEST"]
const M1_HEROES: Array[String] = ["hero_fighter_male", "hero_fighter_female", "hero_wizard_male_hood", "hero_wizard_female_hood", "hero_wizard_male_hat", "hero_wizard_female_hat"]
const M1_HERO_KEYS: PackedStringArray = ["LOOK_FIGHTER_PLATE", "LOOK_FIGHTER_PLATE", "LOOK_WIZARD_HOOD", "LOOK_WIZARD_HOOD", "LOOK_WIZARD_HAT", "LOOK_WIZARD_HAT"]
const M1_WEAPONS: PackedStringArray = ["sword", "axe", "dagger", "scimitar", "sickle", "mace", "spear", "staff", "staff_priest", "shortbow", "light_crossbow", "shield_heater", "shield_round"]
const M1_ENEMY_ROW_Z: float = 5.2
const M1_HERO_ROW_Z: float = 7.6
const M1_WEAPON_ROW_Z: float = 9.4

var actors: Array[PreviewActor] = []
var m1_enemies: Array[PreviewActor] = []
var m1_heroes: Array[PreviewActor] = []
var m1_weapons: Array[Node3D] = []
var camera: Camera3D
var environment: Environment
var selector: OptionButton
var angle: float = 0.65
var distance: float = 18.0
var animation_names: PackedStringArray = []
var studio_lighting: bool = false
var torch_lights: Array[OmniLight3D] = []
var capture_frames: int = -1
var camera_focus: Vector3 = Vector3(0, 0.6, 0)
var camera_elevation: float = 11.4
var hit_demo_pending: bool = false

func _ready() -> void:
	TranslationServer.add_translation(load("res://assets/enemy_test_strings.en.translation") as Translation)
	_build_environment()
	_build_room()
	_build_actors()
	_build_ui()
	_update_camera()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_frames = 90
		elif argument == "--enemy-closeup":
			_focus_enemy()
		elif argument == "--m1-enemies":
			_focus_m1(0)
		elif argument == "--m1-heroes":
			_focus_m1(1)
		elif argument == "--m1-weapons":
			_focus_m1(2)
		elif argument == "--m1-overview":
			_focus_m1(3)
		elif argument == "--m1-hits":
			_focus_m1(0)
			hit_demo_pending = true
		elif argument.begins_with("--clip="):
			_select_animation(animation_names.find(argument.trim_prefix("--clip=")))

func _process(delta: float) -> void:
	angle += (Input.get_action_strength("gallery_rotate_right") - Input.get_action_strength("gallery_rotate_left")) * delta
	_update_camera()
	if capture_frames > 0:
		# Effects start a few frames before the capture so sprays are mid-flight.
		if hit_demo_pending and capture_frames == 3:
			show_hit_effects()
		capture_frames -= 1
		if capture_frames == 0:
			_capture()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("gallery_next"):
		_select_animation((selector.selected + 1) % animation_names.size())
	elif event.is_action_pressed("gallery_previous"):
		_select_animation(posmod(selector.selected - 1, animation_names.size()))
	elif event.is_action_pressed("gallery_reset"):
		_reset_view()
	elif event.is_action_pressed("gallery_toggle_lighting"):
		_toggle_lighting()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		angle -= (event as InputEventMouseMotion).relative.x * 0.006
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(10.0, distance - 0.8)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(28.0, distance + 0.8)

func _build_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("090e17")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("9baed4")
	environment.ambient_light_energy = 0.35
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_radius = 1.2
	environment.ssao_intensity = 1.6
	environment.glow_enabled = true
	environment.glow_intensity = 0.65
	environment.fog_enabled = true
	environment.fog_light_color = Color("344051")
	environment.fog_density = 0.012
	environment.fog_sky_affect = 0.0
	environment.volumetric_fog_enabled = RenderingServer.get_current_rendering_method() == "forward_plus"
	environment.volumetric_fog_density = 0.008
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, -28, 0)
	key.light_color = Color("b6ccec")
	key.light_energy = 0.8
	key.shadow_enabled = true
	add_child(key)
	var fill: OmniLight3D = OmniLight3D.new()
	fill.position = Vector3(0, 4.5, 3)
	fill.light_color = Color("ffd8a2")
	fill.light_energy = 0.8
	fill.omni_range = 13.0
	add_child(fill)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = distance
	camera.current = true
	add_child(camera)

func _place_asset(name: String, at: Vector3, yaw: float = 0.0) -> Node3D:
	var wrapper: Node3D = Node3D.new()
	var scene: PackedScene = load("res://assets/dungeon/" + name + ".glb") as PackedScene
	assert(scene != null, "Missing dungeon asset " + name)
	var model: Node3D = scene.instantiate()
	wrapper.add_child(model)
	var bounds: AABB = _model_bounds(model)
	model.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z)
	wrapper.position = at
	wrapper.rotation.y = yaw
	add_child(wrapper)
	return wrapper

func _model_bounds(model: Node3D) -> AABB:
	var first: bool = true
	var result: AABB
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var transform_to_root: Transform3D = Transform3D.IDENTITY
		var current: Node3D = mesh
		while current != model:
			transform_to_root = current.transform * transform_to_root
			current = current.get_parent() as Node3D
		var local_bounds: AABB = transform_to_root * mesh.get_aabb()
		result = local_bounds if first else result.merge(local_bounds)
		first = false
	assert(not first, "Model has no geometry")
	return result

func _build_room() -> void:
	for x: int in 4:
		for z: int in 5:
			_place_asset("SM_TileFloor", Vector3(-4.5 + x * 3.0, 0, -3.0 + z * 3.0))
	for x: int in 4:
		_place_asset("SM_DoorWay" if x == 2 else "SM_Wall", Vector3(-4.5 + x * 3.0, 0, -4.5))
	for z: int in 5:
		_place_asset("SM_Wall", Vector3(-6.0, 0, -3.0 + z * 3.0), PI / 2)
	for x: float in [-5.8, 5.8]:
		_place_asset("SM_WallEnders", Vector3(x, 0, -4.5))
	_place_asset("SM_Stairs", Vector3(4.3, 0, -2.5), PI / 2)
	_place_asset("SM_FullBookShelf", Vector3(-2.7, 0.06, -3.85))
	_place_asset("SM_WoodenTable", Vector3(-3.4, 0.07, -1.6))
	_place_asset("SM_Stool", Vector3(-2.2, 0.07, -1.0))
	_place_asset("SM_HealthPotion", Vector3(-3.8, 0.73, -1.6))
	_place_asset("SM_ManaPotion", Vector3(-3.0, 0.73, -1.6))
	_place_asset("SM_WoodenBarrel", Vector3(-5.0, 0.07, -3.4))
	_place_asset("SM_WoodenBarrel", Vector3(-4.0, 0.07, -3.3))
	_place_asset("SM_Shield", Vector3(-4.7, 1.0, -4.0))
	for x: float in [-4.7, 0.0, 4.7]:
		_place_asset("SM_WallTorch", Vector3(x, 1.5, -4.0))
		var light: OmniLight3D = OmniLight3D.new()
		light.position = Vector3(x, 2.2, -3.7)
		light.light_color = Color("ffad60")
		light.light_energy = 2.8
		light.omni_range = 7.0
		light.shadow_enabled = true
		add_child(light)
		torch_lights.append(light)

func _build_actors() -> void:
	for i: int in MODELS.size():
		var location: Vector3 = SAMPLE_POSITIONS[i]
		_place_asset("SM_ShortWallEnders", location)
		var actor: PreviewActor = ACTOR_SCRIPT.new() as PreviewActor
		actor.position = location + Vector3(0, 0.64, 0)
		add_child(actor)
		actor.setup("res://assets/characters/" + MODELS[i] + "/model.glb", "ENEMY_TEST_HERO" if i == 0 else MODEL_KEYS[i])
		actors.append(actor)
	actors[0].equip_weapon("res://assets/weapons/sword.glb")
	var location: Vector3 = Vector3(4.6, 0, 2.8)
	_place_asset("SM_ShortWallEnders", location)
	var cultist: PreviewActor = ACTOR_SCRIPT.new() as PreviewActor
	cultist.name = "UndeadCultist"
	cultist.position = location + Vector3(0, 0.64, 0)
	add_child(cultist)
	cultist.setup("res://assets/characters/undead_cultist/model.glb", "GALLERY_CULTIST")
	cultist.equip_weapon("res://assets/weapons/axe.glb")
	actors.append(cultist)
	_build_m1()
	animation_names = CLIPS.duplicate()
	for clip: String in actors[0].available:
		if not animation_names.has(clip):
			animation_names.append(clip)

func _build_m1() -> void:
	for i: int in M1_ENEMIES.size():
		var actor: PreviewActor = _m1_actor(M1_ENEMIES[i], M1_ENEMY_KEYS[i], Vector3(-4.2 + i * 2.6, 0, M1_ENEMY_ROW_Z))
		m1_enemies.append(actor)
	for i: int in M1_HEROES.size():
		var actor: PreviewActor = _m1_actor(M1_HEROES[i], M1_HERO_KEYS[i], Vector3(-4.6 + i * 1.84, 0, M1_HERO_ROW_Z))
		m1_heroes.append(actor)
	# Weapons stand upright on their grip so length and silhouette compare directly.
	for i: int in M1_WEAPONS.size():
		var scene_path: String = PreviewActor.weapon_scene_for(M1_WEAPONS[i])
		var stand: Node3D = Node3D.new()
		stand.name = "Weapon_" + M1_WEAPONS[i]
		stand.position = Vector3(-5.1 + i * 0.85, 0.95, M1_WEAPON_ROW_Z)
		add_child(stand)
		var model: Node3D = (load(scene_path) as PackedScene).instantiate() as Node3D
		stand.add_child(model)
		if M1_WEAPONS[i].begins_with("shield"):
			model.position.y = -0.35
		elif M1_WEAPONS[i] in ["spear", "staff", "staff_priest"]:
			model.position.y = -0.15
			model.scale = Vector3.ONE * 0.62
		var label: Label3D = Label3D.new()
		label.text = tr("GALLERY_WEAPON_" + M1_WEAPONS[i].to_upper())
		label.position = Vector3(0, -0.75, 0.35)
		label.font_size = 30
		label.pixel_size = 0.0042
		label.modulate = Color("d9c9a3")
		label.outline_modulate = Color("0d1421")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		stand.add_child(label)
		m1_weapons.append(stand)

func _m1_actor(folder: String, key: String, location: Vector3) -> PreviewActor:
	var actor: PreviewActor = ACTOR_SCRIPT.new() as PreviewActor
	actor.name = folder.to_pascal_case()
	actor.position = location
	add_child(actor)
	var scene_path: String = "res://assets/characters/" + folder + "/model.glb"
	actor.setup(scene_path, key)
	actor.equip_look_weapon(scene_path)
	for label: Label3D in actor.find_children("*", "Label3D", false, false):
		label.font_size = 30
	actors.append(actor)
	return actor

func _label(key: String, size: int, color: Color = Color("e8e2d6")) -> Label:
	var label: Label = Label.new()
	label.text = tr(key)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 32)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(margin)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(layout)
	layout.add_child(_label("GALLERY_TITLE", 38, Color("e4c78d")))
	layout.add_child(_label("ENEMY_TEST_SUBTITLE", 18, Color("a9b3c6")))
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(spacer)
	layout.add_child(_label("GALLERY_HEADER", 28, Color("e4c78d")))
	layout.add_child(_label("ENEMY_TEST_DESCRIPTION", 17, Color("bfc7d5")))
	var toolbar: HBoxContainer = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 12)
	layout.add_child(toolbar)
	selector = OptionButton.new()
	selector.custom_minimum_size = Vector2(320, 42)
	for i: int in animation_names.size():
		selector.add_item(tr(CLIP_KEYS[i]) if i < CLIP_KEYS.size() else animation_names[i])
	selector.item_selected.connect(_select_animation)
	toolbar.add_child(selector)
	_button(toolbar, "GALLERY_PREVIOUS", func() -> void: _select_animation(posmod(selector.selected - 1, animation_names.size())))
	_button(toolbar, "GALLERY_NEXT", func() -> void: _select_animation((selector.selected + 1) % animation_names.size()))
	_button(toolbar, "GALLERY_RESET", _reset_view)
	_button(toolbar, "GALLERY_LIGHTING", _toggle_lighting)
	_button(toolbar, "ENEMY_TEST_CLOSEUP", _focus_enemy)
	_button(toolbar, "GALLERY_M1_ENEMIES", func() -> void: _focus_m1(0))
	_button(toolbar, "GALLERY_M1_HEROES", func() -> void: _focus_m1(1))
	_button(toolbar, "GALLERY_M1_WEAPONS", func() -> void: _focus_m1(2))
	_button(toolbar, "GALLERY_M1_HITS", func() -> void:
		_focus_m1(0)
		show_hit_effects())
	layout.add_child(_label("GALLERY_CONTROLS", 15, Color("a4aec0")))

func _button(parent: Control, key: String, callback: Callable) -> void:
	var button: Button = Button.new()
	button.text = tr(key)
	button.custom_minimum_size = Vector2(100, 42)
	button.pressed.connect(callback)
	parent.add_child(button)

func _select_animation(index: int) -> void:
	selector.select(index)
	for actor: PreviewActor in actors:
		actor.play_clip(animation_names[index])

func _update_camera() -> void:
	camera.position = camera_focus + Vector3(sin(angle) * 15, camera_elevation, cos(angle) * 15)
	camera.size = distance
	camera.look_at(camera_focus)

func _reset_view() -> void:
	angle = 0.65
	distance = 18.0
	camera_focus = Vector3(0, 0.6, 0)
	camera_elevation = 11.4
	for actor: PreviewActor in actors:
		actor.visible = true
	for stand: Node3D in m1_weapons:
		stand.visible = true

func _focus_enemy() -> void:
	angle = 0.12
	distance = 5.4
	camera_focus = Vector3(3.4, 1.55, 2.8)
	camera_elevation = 6.0
	# Keep the inspection pair readable; unrelated outfit labels would fill the
	# foreground when zoomed in. Reset restores the complete seven-model gallery.
	for i: int in actors.size():
		actors[i].visible = i == 0 or i == 6
	for stand: Node3D in m1_weapons:
		stand.visible = false

## Blood (normal + critical), parry sparks and death dust on the enemy row.
func show_hit_effects() -> void:
	hit_demo_pending = false
	var effects: Array[StringName] = [HitEffects.BLOOD_CRITICAL, HitEffects.SPARKS, HitEffects.BLOOD, HitEffects.DUST]
	for i: int in m1_enemies.size():
		var actor: PreviewActor = m1_enemies[i]
		var at: Vector3 = actor.global_position + (Vector3.ZERO if effects[i] == HitEffects.DUST else Vector3(0, 1.3, 0.2))
		HitEffects.spawn(self, effects[i], at, Vector3(0.4, 0, -1))

## 0 enemies + boss, 1 hero looks, 2 weapons, 3 overview of all M1 art at normal zoom.
func _focus_m1(group: int) -> void:
	_reset_view()
	var focus: Array[Vector3] = [Vector3(-0.3, 1.2, M1_ENEMY_ROW_Z), Vector3(0, 1.1, M1_HERO_ROW_Z),
		Vector3(0, 0.9, M1_WEAPON_ROW_Z), Vector3(0, 0.8, M1_HERO_ROW_Z - 0.4)]
	var zoom: Array[float] = [6.0, 6.4, 6.4, 10.5]
	angle = 0.0 if group < 3 else 0.5
	distance = zoom[group]
	camera_focus = focus[group]
	camera_elevation = 6.5 if group < 3 else 11.4
	if group == 3:
		return
	for actor: PreviewActor in actors:
		actor.visible = (group == 0 and m1_enemies.has(actor)) or (group == 1 and m1_heroes.has(actor))
	for stand: Node3D in m1_weapons:
		stand.visible = group == 2

func _toggle_lighting() -> void:
	studio_lighting = not studio_lighting
	environment.ambient_light_energy = 1.2 if studio_lighting else 0.35
	environment.fog_enabled = not studio_lighting
	environment.volumetric_fog_enabled = not studio_lighting and RenderingServer.get_current_rendering_method() == "forward_plus"
	for light: OmniLight3D in torch_lights:
		light.light_energy = 1.0 if studio_lighting else 2.8

func _capture() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			var image: Image = get_viewport().get_texture().get_image()
			if image == null:
				push_error("Screenshot requires a graphical renderer; --headless uses dummy rendering")
				get_tree().quit(1)
				return
			var error: Error = image.save_png(argument.trim_prefix("--capture="))
			get_tree().quit(error)
