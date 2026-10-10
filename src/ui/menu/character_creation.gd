class_name CharacterCreation
extends Control
## docs/UI.md section 5 (M1): class, body, look, name, rotatable 3D preview, class
## description and key stats. "Begin" states permadeath once, then hands over the record.

signal back_requested
signal begin_requested(record: Dictionary)

const PREVIEW_RECT: Rect2 = Rect2(760, 90, 640, 640)

var class_id: String = "fighter"
var body: String = "male"
var look_index: int = 0
var looks: Array[Dictionary] = []
var class_buttons: Dictionary = {}
var body_buttons: Dictionary = {}
var name_edit: LineEdit
var look_label: Label
var description: Label
var stats: Label
var begin_button: Button
var confirm: Control
var preview_viewport: SubViewport
var preview_pivot: Node3D
var preview_actor: PreviewActor
var _dragging: bool = false

func _ready() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_PASS
	MenuTheme.label(self, Rect2(80, 20, 900, 60), tr("CREATION_TITLE"), 40, MenuTheme.GOLD)
	MenuTheme.panel(self, Rect2(80, 90, 620, 900))
	MenuTheme.label(self, Rect2(110, 105, 560, 34), tr("CREATION_CLASS"), 22, MenuTheme.GOLD)
	var group: ButtonGroup = ButtonGroup.new()
	for index: int in HeroFactory.CLASS_ORDER.size():
		var id: String = HeroFactory.CLASS_ORDER[index]
		var playable: bool = HeroFactory.is_playable(id)
		var rect: Rect2
		if playable:
			rect = Rect2(110 + HeroFactory.PLAYABLE.find(id) * 285, 145, 275, 56)
		else:
			var slot: int = index - HeroFactory.PLAYABLE.size()
			rect = Rect2(110 + (slot % 2) * 285, 215 + floori(slot / 2.0) * 46, 275, 40)
		var text: String = tr("CREATION_CLASS_" + id.to_upper())
		if not playable:
			text = tr("CREATION_COMING_LATER") % text
		var button: Button = MenuTheme.toggle(self, rect, text, 22 if playable else 17)
		button.button_group = group
		button.disabled = not playable
		button.tooltip_text = tr("CREATION_COMING_LATER_HINT") if not playable else ""
		button.pressed.connect(select_class.bind(id))
		class_buttons[id] = button
	MenuTheme.label(self, Rect2(110, 505, 560, 34), tr("CREATION_BODY"), 22, MenuTheme.GOLD)
	var body_group: ButtonGroup = ButtonGroup.new()
	for index: int in 2:
		var id: String = ["male", "female"][index]
		var button: Button = MenuTheme.toggle(self, Rect2(110 + index * 285, 545, 275, 52),
			tr("CREATION_BODY_" + id.to_upper()))
		button.button_group = body_group
		button.pressed.connect(select_body.bind(id))
		body_buttons[id] = button
	MenuTheme.label(self, Rect2(110, 620, 560, 34), tr("CREATION_LOOK"), 22, MenuTheme.GOLD)
	var previous: Button = MenuTheme.button(self, Rect2(110, 660, 70, 52), "<")
	previous.pressed.connect(cycle_look.bind(-1))
	look_label = MenuTheme.label(self, Rect2(190, 668, 400, 40), "", 24, MenuTheme.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	var next: Button = MenuTheme.button(self, Rect2(600, 660, 70, 52), ">")
	next.pressed.connect(cycle_look.bind(1))
	MenuTheme.label(self, Rect2(110, 735, 560, 34), tr("CREATION_NAME"), 22, MenuTheme.GOLD)
	name_edit = MenuTheme.line_edit(self, Rect2(110, 775, 560, 56), tr("CREATION_NAME_PLACEHOLDER"))
	name_edit.max_length = HeroFactory.MAX_NAME_LENGTH
	name_edit.text_changed.connect(func(_text: String) -> void: _refresh_begin())
	MenuTheme.label(self, Rect2(110, 850, 560, 120), tr("CREATION_M1_NOTE"), 17, MenuTheme.MUTED)
	_build_preview()
	MenuTheme.panel(self, Rect2(760, 750, 1080, 240))
	description = MenuTheme.label(self, Rect2(790, 765, 640, 210), "", 20)
	stats = MenuTheme.label(self, Rect2(1450, 765, 370, 210), "", 20, MenuTheme.PAPER)
	var back: Button = MenuTheme.button(self, Rect2(1440, 1000, 190, 60), tr("MENU_BACK"))
	back.pressed.connect(func() -> void: back_requested.emit())
	begin_button = MenuTheme.button(self, Rect2(1650, 1000, 190, 60), tr("CREATION_BEGIN"), 26)
	begin_button.pressed.connect(request_begin)
	class_buttons[class_id].button_pressed = true
	body_buttons[body].button_pressed = true
	_refresh()

func _build_preview() -> void:
	var frame: Panel = MenuTheme.panel(self, PREVIEW_RECT.grow(6), Color(0.03, 0.035, 0.05, 0.6))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var container: SubViewportContainer = SubViewportContainer.new()
	container.position = PREVIEW_RECT.position
	container.size = PREVIEW_RECT.size
	container.stretch = true
	container.gui_input.connect(_preview_input)
	add_child(container)
	preview_viewport = SubViewport.new()
	preview_viewport.own_world_3d = true
	preview_viewport.transparent_bg = true
	preview_viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(preview_viewport)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8fa3c4")
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	preview_viewport.add_child(world)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.1
	key.light_color = Color("ffe2b8")
	preview_viewport.add_child(key)
	var rim: OmniLight3D = OmniLight3D.new()
	rim.position = Vector3(-1.4, 2.2, -1.6)
	rim.light_color = Color("ff9d4d")
	rim.light_energy = 2.2
	rim.omni_range = 5.0
	preview_viewport.add_child(rim)
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0, 1.05, 3.1)
	camera.rotation_degrees = Vector3(-4, 0, 0)
	camera.fov = 40.0
	preview_viewport.add_child(camera)
	preview_pivot = Node3D.new()
	preview_viewport.add_child(preview_pivot)
	var rotate_left: Button = MenuTheme.button(self, Rect2(PREVIEW_RECT.position + Vector2(16, PREVIEW_RECT.size.y - 66), Vector2(56, 50)), "⟲")
	rotate_left.pressed.connect(func() -> void: preview_pivot.rotation.y -= 0.5)
	var rotate_right: Button = MenuTheme.button(self, Rect2(PREVIEW_RECT.end - Vector2(72, 66), Vector2(56, 50)), "⟳")
	rotate_right.pressed.connect(func() -> void: preview_pivot.rotation.y += 0.5)

func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		preview_pivot.rotation.y += event.relative.x * 0.01

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("cancel"):
		return
	get_viewport().set_input_as_handled()
	if confirm != null:
		_close_confirm()
	else:
		back_requested.emit()

func select_class(id: String) -> void:
	if not HeroFactory.is_playable(id):
		return
	class_id = id
	class_buttons[id].button_pressed = true
	look_index = 0
	_refresh()

func select_body(id: String) -> void:
	body = id
	body_buttons[id].button_pressed = true
	look_index = 0
	_refresh()

func cycle_look(step: int) -> void:
	if looks.is_empty():
		return
	look_index = posmod(look_index + step, looks.size())
	_refresh_look()

func set_hero_name(value: String) -> void:
	name_edit.text = value
	_refresh_begin()

func current_record() -> Dictionary:
	if looks.is_empty():
		return {}
	return HeroFactory.build_record(class_id, looks[look_index], name_edit.text)

func request_begin() -> void:
	if current_record().is_empty() or confirm != null:
		return
	confirm = Control.new()
	confirm.size = size
	confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(confirm)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.size = size
	confirm.add_child(shade)
	MenuTheme.panel(confirm, Rect2(560, 360, 800, 340))
	MenuTheme.label(confirm, Rect2(600, 400, 720, 60), tr("CREATION_PERMADEATH"), 34, MenuTheme.RED, HORIZONTAL_ALIGNMENT_CENTER)
	var detail: String = tr("CREATION_PERMADEATH_DETAIL")
	if SaveGame.exists():
		detail += "\n" + tr("CREATION_OVERWRITES_SAVE")
	MenuTheme.label(confirm, Rect2(600, 475, 720, 110), detail, 21, MenuTheme.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	var cancel: Button = MenuTheme.button(confirm, Rect2(640, 600, 300, 64), tr("MENU_BACK"))
	cancel.pressed.connect(_close_confirm)
	var accept: Button = MenuTheme.button(confirm, Rect2(980, 600, 300, 64), tr("CREATION_BEGIN"), 26)
	accept.name = "ConfirmBegin"
	accept.pressed.connect(confirm_begin)
	accept.grab_focus()

func confirm_begin() -> void:
	var record: Dictionary = current_record()
	if record.is_empty():
		return
	_close_confirm()
	begin_requested.emit(record)

func _close_confirm() -> void:
	if confirm != null:
		confirm.queue_free()
		confirm = null

func _refresh() -> void:
	looks = HeroLooks.for_class(class_id, body)
	look_index = clampi(look_index, 0, maxi(0, looks.size() - 1))
	var summary: Dictionary = HeroFactory.summary(class_id)
	description.text = "%s\n\n%s" % [tr("CREATION_CLASS_" + class_id.to_upper()).to_upper(),
		tr("CREATION_DESCRIPTION_" + class_id.to_upper())]
	var lines: PackedStringArray = [
		tr("CREATION_STAT_HP") % int(summary["hp"]),
		tr("CREATION_STAT_AC") % int(summary["ac"]),
		tr("CREATION_STAT_MAIN") % tr("CREATION_ABILITY_" + String(summary["main_ability"]).to_upper()),
	]
	var scores: PackedStringArray = []
	for ability: StringName in Abilities.IDS:
		scores.append("%s %d" % [String(ability).to_upper(), int(summary["scores"][ability])])
	lines.append(" · ".join(scores.slice(0, 3)))
	lines.append(" · ".join(scores.slice(3, 6)))
	var skills: PackedStringArray = []
	for skill: StringName in summary["skills"]:
		skills.append(String(skill).capitalize())
	lines.append(tr("CREATION_STAT_SKILLS") % ", ".join(skills))
	stats.text = "\n".join(lines)
	_refresh_look()

func _refresh_look() -> void:
	look_label.text = tr("CREATION_LOOK_COUNTER") % [look_index + 1, looks.size()] if not looks.is_empty() else "-"
	if preview_actor != null:
		preview_actor.queue_free()
		preview_actor = null
	if not looks.is_empty():
		preview_actor = PreviewActor.new()
		preview_pivot.add_child(preview_actor)
		preview_actor.setup(String(looks[look_index]["scene"]), "")
		var record: Dictionary = HeroFactory.build_record(class_id, looks[look_index], "preview")
		var weapon_model: String = String(record.get("weapon", {}).get("model", ""))
		if not weapon_model.is_empty():
			preview_actor.equip_weapon(weapon_model)
	_refresh_begin()

func _refresh_begin() -> void:
	if begin_button != null:
		begin_button.disabled = HeroFactory.clean_name(name_edit.text).is_empty() or looks.is_empty()
