class_name GameMenus
extends CanvasLayer
## In-game windows: inventory [I] and character sheet [C]. Sits below the combat HUD
## (layer 10) so dice rolls stay on top, and keeps clear of the HUD's bars and log.

signal command_requested(command: Command)

const BUTTON_RECT: Rect2 = Rect2(1406, 958, 484, 80)

var inventory: InventoryPanel
var character: CharacterPanel
var tooltip: ItemTooltip
var _root: Control
var _inventory_button: Button
var _character_button: Button
var _capture_hover: bool = false

func _ready() -> void:
	layer = 9
	_root = Control.new()
	_root.size = Vector2(1920, 1080)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var bar: Panel = MenuStyle.panel(_root, BUTTON_RECT)
	_inventory_button = MenuStyle.button(bar, Rect2(12, 12, 224, 56), MenuStyle.text("INV_BUTTON"))
	_character_button = MenuStyle.button(bar, Rect2(248, 12, 224, 56), MenuStyle.text("SHEET_BUTTON"))
	_inventory_button.pressed.connect(toggle_inventory)
	_character_button.pressed.connect(toggle_character)
	inventory = InventoryPanel.new()
	inventory.visible = false
	_root.add_child(inventory)
	character = CharacterPanel.new()
	character.visible = false
	_root.add_child(character)
	tooltip = ItemTooltip.new()
	_root.add_child(tooltip)
	inventory.tooltip = tooltip
	inventory.command_requested.connect(func(command: Command) -> void: command_requested.emit(command))
	inventory.close_requested.connect(close_all)
	character.close_requested.connect(close_all)
	EventBus.state_changed.connect(_refresh)
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--ui-open=inventory":
			_open_for_capture.call_deferred(true)
		elif argument == "--ui-open=character":
			_open_for_capture.call_deferred(false)

## Screenshot hook for CI (tests/integration/capture_ui.sh): opens a window and shows
## the tooltip of the first bag item, so the capture proves the full layout.
func _open_for_capture(open_inventory: bool) -> void:
	if open_inventory:
		_capture_hover = true
		toggle_inventory()
	else:
		toggle_character()

func is_open() -> bool:
	return inventory.visible or character.visible

func toggle_inventory() -> void:
	var opening: bool = not inventory.visible
	close_all()
	inventory.visible = opening
	_refresh()

func toggle_character() -> void:
	var opening: bool = not character.visible
	close_all()
	character.visible = opening
	_refresh()

func close_all() -> void:
	inventory.visible = false
	character.visible = false
	tooltip.hide_tooltip()
	_update_buttons()

func _refresh() -> void:
	var state: GameState = Game.state
	if inventory.visible:
		inventory.update_state(state)
		if _capture_hover and not inventory.bag_slots[0].item_id.is_empty():
			_capture_hover = false
			inventory._on_hovered(inventory.bag_slots[0])
	if character.visible:
		character.update_state(state)
	_update_buttons()

func _update_buttons() -> void:
	for pair: Array in [[_inventory_button, inventory], [_character_button, character]]:
		var button: Button = pair[0]
		button.add_theme_color_override("font_color", MenuStyle.GOLD_BRIGHT if (pair[1] as Control).visible else MenuStyle.PAPER)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_I:
			toggle_inventory()
		KEY_C:
			toggle_character()
		KEY_ESCAPE:
			if not is_open():
				return
			close_all()
		_:
			return
	get_viewport().set_input_as_handled()
