class_name JournalPanel
extends CanvasLayer
## The quest journal (campaign package K3): J opens and closes it. Active quests first, then
## finished and failed ones, each with its current text from QuestLog. A short note at the
## top of the screen tells when a quest starts or changes.

const NOTE_SECONDS: float = 3.5

var root: Control
var list_label: Label
var note: Label
var _note_left: float = 0.0
var _known: Dictionary = {}

func _ready() -> void:
	layer = 12
	_known = QuestLog.snapshot(Game.state)
	var overlay: Control = MenuTheme.design_root(self)
	note = MenuTheme.label(overlay, Rect2(560, 96, 800, 40), "", 24, MenuTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	note.name = "JournalNote"
	note.add_theme_constant_override("outline_size", 6)
	note.visible = false
	CommandBus.command_applied.connect(_on_command_applied)

func is_open() -> bool:
	return root != null

func toggle() -> void:
	if is_open():
		close()
	else:
		open()

func open() -> void:
	close()
	root = MenuTheme.design_root(self)
	var panel: Panel = MenuTheme.panel(root, Rect2(460, 120, 1000, 800))
	MenuTheme.label(panel, Rect2(40, 24, 920, 50), tr("JOURNAL_TITLE"), 34, MenuTheme.GOLD)
	list_label = MenuTheme.label(panel, Rect2(40, 90, 920, 620), text(Game.state), 21, MenuTheme.PAPER)
	list_label.name = "JournalText"
	var close_button: Button = MenuTheme.button(panel, Rect2(400, 728, 200, 48), tr("MENU_OK"), 20)
	close_button.pressed.connect(close)

func close() -> void:
	if root != null:
		root.queue_free()
		root = null

## The whole journal as text: active quests, then done and failed ones.
static func text(state: GameState) -> String:
	var snapshot: Dictionary = QuestLog.snapshot(state)
	if snapshot.is_empty():
		return TranslationServer.translate("JOURNAL_EMPTY")
	var parts: PackedStringArray = []
	for wanted: String in ["active", "done", "failed"]:
		for id: String in snapshot:
			if snapshot[id]["state"] != wanted:
				continue
			var title: String = TranslationServer.translate(String(QuestLog.load_quest(id)["title"]))
			if wanted != "active":
				title += "  ·  " + TranslationServer.translate("JOURNAL_" + wanted.to_upper())
			parts.append(title + "\n" + TranslationServer.translate(String(snapshot[id]["text"])))
	return "\n\n".join(parts)

func _on_command_applied(_command: Command, _result: Dictionary) -> void:
	var now: Dictionary = QuestLog.snapshot(Game.state)
	var changed: PackedStringArray = QuestLog.changed(_known, now)
	_known = now
	if changed.is_empty():
		return
	var titles: PackedStringArray = []
	for id: String in changed:
		titles.append(tr(String(QuestLog.load_quest(id)["title"])))
	note.text = tr("JOURNAL_UPDATED") % ", ".join(titles)
	note.visible = true
	_note_left = NOTE_SECONDS
	if is_open():
		list_label.text = text(Game.state)

func _process(delta: float) -> void:
	if _note_left > 0.0:
		_note_left -= delta
		note.modulate.a = clampf(_note_left / 0.6, 0.0, 1.0)
		note.visible = _note_left > 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_J:
		get_viewport().set_input_as_handled()
		toggle()
	elif is_open() and event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		close()
