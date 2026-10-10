class_name PauseMenu
extends CanvasLayer
## Esc in the arena. Ironman: leaving is the only way the run is saved.

signal resume_requested
signal save_and_quit_to_menu
signal save_and_quit_game

var root: Control
var options: OptionsMenu

func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = MenuTheme.design_root(self)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.size = Vector2(1920, 1080)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(shade)
	MenuTheme.panel(root, Rect2(710, 280, 500, 520))
	MenuTheme.label(root, Rect2(710, 310, 500, 60), tr("PAUSE_TITLE"), 40, MenuTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var y: float = 400.0
	for entry: Array in [["PAUSE_RESUME", resume_requested], ["MENU_OPTIONS", null],
			["PAUSE_SAVE_MENU", save_and_quit_to_menu], ["PAUSE_SAVE_QUIT", save_and_quit_game]]:
		var button: Button = MenuTheme.button(root, Rect2(760, y, 400, 64), tr(entry[0]), 24)
		button.name = String(entry[0])
		if entry[1] == null:
			button.pressed.connect(_open_options)
		else:
			button.pressed.connect((entry[1] as Signal).emit)
		y += 84.0
	MenuTheme.label(root, Rect2(730, 735, 460, 50), tr("PAUSE_IRONMAN_HINT"), 17, MenuTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	(root.get_node("PAUSE_RESUME") as Button).grab_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") and options == null:
		get_viewport().set_input_as_handled()
		resume_requested.emit()

func _open_options() -> void:
	options = OptionsMenu.new()
	root.add_child(options)
	options.closed.connect(func() -> void: options = null)
