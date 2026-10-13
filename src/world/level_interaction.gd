class_name LevelInteraction
extends CanvasLayer
## Placeholder text for dialogue hooks and the rest point (package 10). The real dialogue
## system and texts come later from the owner; until then a hook shows "Dialogue: <id>".

signal closed

var root: Control
var text_label: Label

func show_text(text: String) -> void:
	layer = 14
	if root != null:
		root.queue_free()
	root = MenuTheme.design_root(self)
	var panel: Panel = MenuTheme.panel(root, Rect2(560, 760, 800, 170))
	text_label = MenuTheme.label(panel, Rect2(30, 24, 740, 70), text, 26, MenuTheme.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	text_label.name = "InteractionText"
	var ok: Button = MenuTheme.button(panel, Rect2(300, 104, 200, 48), tr("MENU_OK"), 20)
	ok.pressed.connect(close)
	visible = true

func is_open() -> bool:
	return visible and root != null

func close() -> void:
	visible = false
	if root != null:
		root.queue_free()
		root = null
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		close()
