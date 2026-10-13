class_name DialoguePanel
extends CanvasLayer
## The conversation window (campaign package 1): speaker, line and numbered answers at
## the bottom of the screen. Skill-check answers show skill and DC like BG3; no answer is
## marked as right or wrong (docs/DESIGN.md, dialogue rules). Reads Game.state only;
## every answer is a DialogueChooseCommand, Escape a DialogueEndCommand.

signal closed

const MAX_CHOICES: int = 9

## Optional: answers wait while this popup still shows a check's dice.
var dice_popup: DicePopup
var root: Control
var speaker_label: Label
var text_label: Label
var choice_buttons: Array[Button] = []
var _choice_indices: Array[int] = []

func _ready() -> void:
	layer = 13
	visible = false
	CommandBus.command_applied.connect(_on_command_applied)

func is_open() -> bool:
	return visible and root != null

## Starts the conversation through the command bus; false if it was refused.
func open(dialogue_id: String) -> bool:
	if CommandBus.submit(DialogueStartCommand.new(dialogue_id)) != OK:
		return false
	refresh()
	return true

func refresh() -> void:
	var conversation: Variant = Game.state.world.get("conversation")
	if not conversation is Dictionary:
		_close_view()
		return
	var data: Dictionary = DialogueData.load_dialogue(String(conversation["id"]))
	var node_id: String = String(conversation["node"])
	var node: Dictionary = data["nodes"][node_id]
	_build()
	speaker_label.text = tr(String(data["speaker"]))
	text_label.text = tr(String(node["text"]))
	_choice_indices = DialogueData.available_choices(data, node_id, Game.state)
	var choices: Array = node.get("choices", [])
	var count: int = mini(_choice_indices.size(), MAX_CHOICES)
	for slot: int in range(maxi(count, 1)):
		var label: String
		if count == 0:
			label = tr("DIALOGUE_END")
		else:
			label = "%d. %s" % [slot + 1, choice_text(choices[_choice_indices[slot]])]
		var button: Button = MenuTheme.button(root.get_node("Panel"), Rect2(40, 176 + slot * 46, 1040, 42), label, 20)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.name = "Choice%d" % (slot + 1)
		button.pressed.connect(_pick.bind(slot))
		choice_buttons.append(button)
	(root.get_node("Panel") as Panel).size.y = 200 + maxi(count, 1) * 46
	(root.get_node("Panel") as Panel).position.y = 1060 - (root.get_node("Panel") as Panel).size.y
	visible = true
	_update_waiting()

## "[Persuasion DC 12] text" for checks, the plain text otherwise.
static func choice_text(choice: Dictionary) -> String:
	var text: String = TranslationServer.translate(String(choice["text"]))
	if choice.has("check"):
		var check: Dictionary = choice["check"]
		var skill: String = TranslationServer.translate("SHEET_SKILL_" + String(check["skill"]).to_upper())
		text = TranslationServer.translate("DIALOGUE_CHECK") % [skill, int(check["dc"])] + " " + text
	return text

func _build() -> void:
	if root != null:
		root.queue_free()
	choice_buttons.clear()
	root = MenuTheme.design_root(self)
	var panel: Panel = MenuTheme.panel(root, Rect2(400, 600, 1120, 440))
	panel.name = "Panel"
	speaker_label = MenuTheme.label(panel, Rect2(40, 22, 1040, 36), "", 26, MenuTheme.GOLD)
	speaker_label.name = "Speaker"
	text_label = MenuTheme.label(panel, Rect2(40, 66, 1040, 100), "", 22, MenuTheme.PAPER)
	text_label.name = "DialogueText"

func _pick(slot: int) -> void:
	if _waiting():
		return
	if _choice_indices.is_empty():
		CommandBus.submit(DialogueEndCommand.new())
	elif slot < _choice_indices.size():
		CommandBus.submit(DialogueChooseCommand.new(_choice_indices[slot]))

func _waiting() -> bool:
	return dice_popup != null and dice_popup.is_busy()

func _update_waiting() -> void:
	for button: Button in choice_buttons:
		button.disabled = _waiting()

func _process(_delta: float) -> void:
	if is_open():
		_update_waiting()

func _on_command_applied(command: Command, _result: Dictionary) -> void:
	if command is DialogueStartCommand or command is DialogueChooseCommand or command is DialogueEndCommand:
		refresh()

func _close_view() -> void:
	var was_open: bool = root != null
	visible = false
	if root != null:
		root.queue_free()
		root = null
	choice_buttons.clear()
	if was_open:
		closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		CommandBus.submit(DialogueEndCommand.new())
	elif event is InputEventKey and event.pressed and not event.echo:
		var number: int = int((event as InputEventKey).keycode) - KEY_1
		if number >= 0 and number < choice_buttons.size():
			get_viewport().set_input_as_handled()
			_pick(number)
