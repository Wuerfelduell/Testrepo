class_name GameMenus
extends CanvasLayer
## In-game windows: inventory [I], character sheet [C] and searching a body [F]. Sits below the combat HUD
## (layer 10) so dice rolls stay on top, and keeps clear of the HUD's bars and log.

signal command_requested(command: Command)

const BUTTON_RECT: Rect2 = Rect2(1406, 958, 484, 80)
const LOOT_PROMPT_RECT: Rect2 = Rect2(1406, 890, 484, 58)

var inventory: InventoryPanel
var character: CharacterPanel
var loot: LootPanel
var tooltip: ItemTooltip
var _loot_prompt: Button
var _nearby_body: String = ""
var _slowed_badge: Label
## The body or pile under the mouse, and one the hero is walking to in order to search it.
var hovered_loot: String = ""
var _walk_to_loot: String = ""
var _root: Control
var _inventory_button: Button
var _character_button: Button
var _capture_hover: bool = false
## Party (package K4): the member whose bag, sheet and looting the windows show.
var actor_id: String = "hero"

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
	loot = LootPanel.new()
	loot.visible = false
	_root.add_child(loot)
	_loot_prompt = MenuStyle.button(_root, LOOT_PROMPT_RECT, "")
	_loot_prompt.visible = false
	_loot_prompt.add_theme_color_override("font_color", MenuStyle.GOLD_BRIGHT)
	_loot_prompt.pressed.connect(open_loot)
	tooltip = ItemTooltip.new()
	_root.add_child(tooltip)
	inventory.tooltip = tooltip
	loot.tooltip = tooltip
	loot.command_requested.connect(func(command: Command) -> void: command_requested.emit(command))
	loot.close_requested.connect(close_all)
	inventory.loot_dropped.connect(func(item_id: String) -> void:
		if loot.visible:
			loot.take(item_id))
	_slowed_badge = MenuStyle.label(_root, Rect2(1406, 838, 484, 42), "", 18, MenuStyle.RED)
	_slowed_badge.add_theme_stylebox_override("normal", MenuStyle.box(MenuStyle.INK, MenuStyle.RED, 8))
	_slowed_badge.visible = false
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

## The arena passes the member the player commands; open windows switch to them.
func set_actor(id: String) -> void:
	if id == actor_id:
		return
	actor_id = id
	inventory.actor_id = id
	character.actor_id = id
	loot.actor_id = id
	_walk_to_loot = ""
	if is_inside_tree():
		_refresh()

func is_open() -> bool:
	return inventory.visible or character.visible or loot.visible

## Opens the loot window for the body or pile next to the hero (F or the prompt button).
func open_loot(source_id: String = "") -> void:
	var target: String = source_id if not source_id.is_empty() else _nearby_body
	if target.is_empty():
		return
	close_all()
	# The bag stays visible to the right, so items can be dragged into it.
	inventory.visible = true
	loot.visible = true
	inventory.update_state(Game.state)
	loot.open(Game.state, target)
	_update_buttons()

## The arena reports what the mouse is over; the ring under it lights up.
func hover_loot(source_id: String) -> void:
	hovered_loot = source_id
	for markers: Node in get_tree().get_nodes_in_group("loot_markers"):
		(markers as LootMarkers).highlighted = source_id

## A click on a body or pile: search it now if in reach, else walk there and search on arrival.
func search_hovered_loot() -> bool:
	if hovered_loot.is_empty():
		return false
	var state: GameState = Game.state
	var reason: String = LootRules.take_reason(state, actor_id, hovered_loot, "", true)
	if reason != "LOOT_REASON_TOO_FAR":
		open_loot(hovered_loot)
		return true
	var target: Vector3 = LootRules.source(state, hovered_loot).get("position", Vector3.ZERO)
	if CommandBus.submit(MoveCommand.new(actor_id, target)) == OK:
		_walk_to_loot = hovered_loot
	return true

func toggle_inventory() -> void:
	var opening: bool = not inventory.visible or loot.visible
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
	loot.visible = false
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
	_nearby_body = LootRules.nearest(state, actor_id) if state.mode != &"defeat" else ""
	if not _walk_to_loot.is_empty() and state.pending.is_empty():
		var arrived: bool = LootRules.take_reason(state, actor_id, _walk_to_loot, "", true) != "LOOT_REASON_TOO_FAR"
		var walked_to: String = _walk_to_loot
		_walk_to_loot = ""
		if arrived and LootRules.lootable(LootRules.source(state, walked_to)):
			open_loot(walked_to)
	if loot.visible:
		# Close once the source is empty or the hero walked away.
		var reason: String = LootRules.take_reason(state, actor_id, loot.source_id, "", true)
		if reason in ["LOOT_REASON_NOTHING", "LOOT_REASON_TOO_FAR", "INV_REASON_DEAD"]:
			close_all()
		else:
			loot.update_state(state)
	_loot_prompt.visible = not _nearby_body.is_empty() and not loot.visible
	if _loot_prompt.visible:
		_loot_prompt.text = MenuStyle.text("LOOT_PROMPT_PILE") if LootRules.is_pile(_nearby_body) else \
			MenuStyle.text("LOOT_PROMPT") % MenuStyle.text(String(state.actors[_nearby_body].get("name_key", "")))
	var hero: Dictionary = state.actors.get(actor_id, {})
	var burden: int = int(hero.get("encumbrance", 0))
	_slowed_badge.visible = burden > 0 and state.mode != &"defeat"
	if _slowed_badge.visible:
		_slowed_badge.text = "  " + MenuStyle.text("INV_ENCUMBERED_%d" % burden) % EquipmentRules.ENCUMBRANCE_PENALTY_M[burden] + \
			"  (%.1f / %.0f kg)" % [EquipmentRules.total_weight_kg(hero), EquipmentRules.capacity_kg(hero)]
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
		KEY_F:
			if loot.visible:
				loot.take_all()
			elif not _nearby_body.is_empty():
				open_loot()
			else:
				return
		KEY_ESCAPE:
			if not is_open():
				return
			close_all()
		_:
			return
	get_viewport().set_input_as_handled()
