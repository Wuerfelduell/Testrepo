class_name MainMenu
extends Node3D
## Main scene: a slow torchlit camera drift through the dungeon kit behind
## NEW GAME / CONTINUE / OPTIONS / QUIT. Character creation opens on top of it.

const CAMERA_PATH: Array[Vector3] = [Vector3(-7.5, 1.7, 9.5), Vector3(-4.0, 1.9, 2.5),
	Vector3(2.5, 2.3, -1.5), Vector3(7.5, 2.0, 4.0), Vector3(0.5, 1.8, 8.5)]
const LOOK_AT: Array[Vector3] = [Vector3(-3, 1.2, -6), Vector3(2, 1.0, -9), Vector3(6, 2.4, -8),
	Vector3(-4, 1.2, -6), Vector3(-6, 1.3, -1)]
const SECONDS_PER_LEG: float = 14.0

var camera: Camera3D
var ui: CanvasLayer
var root: Control
var main_page: Control
var buttons: Dictionary = {}
var creation: CharacterCreation
var options: OptionsMenu
var message: Control
var _time: float = 0.0
var _torches: Array[OmniLight3D] = []

func _ready() -> void:
	var dungeon: ArenaBuilder = ArenaBuilder.new()
	dungeon.name = "Dungeon"
	add_child(dungeon)
	for light: Node in dungeon.find_children("*", "OmniLight3D", true, false):
		_torches.append(light as OmniLight3D)
	# Night in the crypt: dim the arena's readability light so the torches carry the scene.
	for light: Node in dungeon.find_children("*", "DirectionalLight3D", true, false):
		(light as DirectionalLight3D).light_energy = 0.12
	for world: Node in dungeon.find_children("*", "WorldEnvironment", true, false):
		var environment: Environment = (world as WorldEnvironment).environment
		environment.ambient_light_energy = 0.12
		environment.background_color = Color("030407")
		environment.fog_density = 0.03
		environment.fog_light_color = Color("0b0d12")
	camera = Camera3D.new()
	camera.fov = 58.0
	camera.current = true
	add_child(camera)
	_place_camera(0.0)
	ui = CanvasLayer.new()
	add_child(ui)
	root = MenuTheme.design_root(ui)
	_build_main_page()
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--menu-open-creation":
			open_creation()

func _build_main_page() -> void:
	main_page = Control.new()
	main_page.size = Vector2(1920, 1080)
	main_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(main_page)
	var vignette: TextureRect = TextureRect.new()
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.85))
	gradient.set_color(1, Color(0, 0, 0, 0.0))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = Vector2(1, 0)
	vignette.texture = texture
	vignette.size = Vector2(1100, 1080)
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_page.add_child(vignette)
	MenuTheme.label(main_page, Rect2(140, 170, 900, 110), tr("MENU_TITLE"), 92, MenuTheme.GOLD)
	MenuTheme.label(main_page, Rect2(146, 285, 900, 40), tr("MENU_SUBTITLE"), 24, MenuTheme.PAPER)
	var entries: Array[String] = ["new_game", "continue", "options", "quit"]
	var y: float = 420.0
	for entry: String in entries:
		var button: Button = MenuTheme.button(main_page, Rect2(140, y, 420, 72), tr("MENU_" + entry.to_upper()), 30)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_menu.bind(entry))
		buttons[entry] = button
		y += 92.0
	MenuTheme.label(main_page, Rect2(140, 1000, 900, 40), tr("MENU_IRONMAN_HINT"), 18, MenuTheme.MUTED)
	refresh()

## CONTINUE is only offered while an ironman save exists.
func refresh() -> void:
	buttons["continue"].visible = SaveGame.exists()
	var y: float = 420.0
	for entry: String in ["new_game", "continue", "options", "quit"]:
		if buttons[entry].visible:
			buttons[entry].position.y = y
			y += 92.0
	buttons["continue" if SaveGame.exists() else "new_game"].grab_focus.call_deferred()

func _on_menu(entry: String) -> void:
	match entry:
		"new_game": open_creation()
		"continue": continue_game()
		"options": open_options()
		"quit": get_tree().quit()

func open_creation() -> void:
	if creation != null:
		return
	main_page.visible = false
	creation = CharacterCreation.new()
	root.add_child(creation)
	creation.back_requested.connect(close_creation)
	creation.begin_requested.connect(_begin)

func close_creation() -> void:
	if creation != null:
		creation.queue_free()
		creation = null
	main_page.visible = true
	refresh()

func open_options() -> void:
	if options != null:
		return
	options = OptionsMenu.new()
	root.add_child(options)
	options.closed.connect(func() -> void:
		options = null
		refresh())

func continue_game() -> void:
	var loaded: SaveGame.LoadResult = RunFlow.continue_saved(get_tree())
	if not loaded.is_valid():
		show_message(tr(loaded.message_key()))

func show_message(text: String) -> void:
	if message != null:
		message.queue_free()
	message = Control.new()
	message.size = Vector2(1920, 1080)
	message.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(message)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.size = message.size
	message.add_child(shade)
	MenuTheme.panel(message, Rect2(560, 380, 800, 300))
	var body: Label = MenuTheme.label(message, Rect2(600, 420, 720, 150), text, 24, MenuTheme.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	body.name = "MessageText"
	var ok: Button = MenuTheme.button(message, Rect2(810, 590, 300, 64), tr("MENU_OK"))
	ok.pressed.connect(func() -> void:
		message.queue_free()
		message = null)
	ok.grab_focus()

func _begin(record: Dictionary) -> void:
	if RunFlow.start_new(get_tree(), record) != OK:
		show_message(tr("CREATION_ERROR"))

func _process(delta: float) -> void:
	_time += delta
	_place_camera(_time)
	for index: int in _torches.size():
		var light: OmniLight3D = _torches[index]
		if not light.has_meta("base_energy"):
			light.set_meta("base_energy", light.light_energy)
		var flicker: float = 0.86 + 0.1 * sin(_time * 7.3 + index * 1.7) + 0.05 * sin(_time * 17.1 + index)
		light.light_energy = float(light.get_meta("base_energy")) * flicker

func _place_camera(time: float) -> void:
	var leg: float = time / SECONDS_PER_LEG
	var index: int = floori(leg) % CAMERA_PATH.size()
	var next: int = (index + 1) % CAMERA_PATH.size()
	var weight: float = smoothstep(0.0, 1.0, leg - floorf(leg))
	camera.position = CAMERA_PATH[index].lerp(CAMERA_PATH[next], weight)
	var target: Vector3 = LOOK_AT[index].lerp(LOOK_AT[next], weight)
	camera.look_at(target, Vector3.UP)
