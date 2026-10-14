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
## What the last answer changed (copper, items, damage), shown next to the speaker.
var notice_label: Label
var _notice: String = ""
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
	notice_label.text = _notice
	text_label.text = tr(String(node["text"]))
	# Longer lines (the owner's scenes mix narration and speech) grow the panel upwards.
	var top: float = 66.0 + maxf(100.0, _text_height(text_label.text, 22, 1040.0)) + 10.0
	text_label.size.y = top - 76.0
	_choice_indices = DialogueData.available_choices(data, node_id, Game.state)
	var choices: Array = node.get("choices", [])
	var count: int = mini(_choice_indices.size(), MAX_CHOICES)
	for slot: int in range(maxi(count, 1)):
		var label: String
		if count == 0:
			label = tr("DIALOGUE_END")
		else:
			label = "%d. %s" % [slot + 1, choice_text(choices[_choice_indices[slot]])]
		var height: float = maxf(42.0, _text_height(label, 20, 1000.0) + 14.0)
		var button: Button = MenuTheme.button(root.get_node("Panel"), Rect2(40, top, 1040, height), label, 20)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.name = "Choice%d" % (slot + 1)
		button.pressed.connect(_pick.bind(slot))
		choice_buttons.append(button)
		top += height + 4.0
	(root.get_node("Panel") as Panel).size.y = top + 20.0
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
	notice_label = MenuTheme.label(panel, Rect2(560, 26, 520, 30), "", 18, MenuTheme.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	notice_label.name = "Notice"
	text_label = MenuTheme.label(panel, Rect2(40, 66, 1040, 100), "", 22, MenuTheme.PAPER)
	text_label.name = "DialogueText"

static func _text_height(text: String, font_size: int, width: float) -> float:
	var font: Font = ThemeDB.fallback_font
	return font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y

## "-5 cp · Received: Wanted poster · 3 damage" from one answer's events.
static func notice_for(events: Array) -> String:
	var parts: PackedStringArray = []
	for event: Dictionary in events:
		match String(event.get("type", "")):
			"money_changed":
				var amount: int = int(event["amount"])
				parts.append(("+" if amount > 0 else "-") + Money.format(absi(amount)))
			"item_changed":
				var key: String = "DIALOGUE_ITEM_GAINED" if int(event["count"]) > 0 else "DIALOGUE_ITEM_LOST"
				parts.append(TranslationServer.translate(key) % TranslationServer.translate(
					String(ItemCatalog.get_item(String(event["item"])).get("name_key", event["item"]))))
			"damage":
				if String(event.get("target_id", "")) == "hero":
					parts.append(TranslationServer.translate("DIALOGUE_DAMAGE") % int(event["amount"]))
	return " · ".join(parts)

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

func _on_command_applied(command: Command, result: Dictionary) -> void:
	if command is DialogueStartCommand or command is DialogueChooseCommand or command is DialogueEndCommand:
		_notice = notice_for(result.get("events", []))
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
