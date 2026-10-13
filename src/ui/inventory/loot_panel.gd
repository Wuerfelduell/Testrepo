class_name LootPanel
extends Panel
## What a body or a pile holds. Opens together with the inventory and covers its equipment
## column, so the bag stays visible: click an item to take it, drag it into the bag, or take
## everything (F). Tooltips compare with what the hero has equipped.

signal command_requested(command: Command)
signal close_requested()

const RECT: Rect2 = Rect2(40, 176, 520, 640)
const COLUMNS: int = 4
const ROWS: int = 3
const SLOT: float = 100.0
const GAP: float = 10.0

var actor_id: String = "hero"
var source_id: String = ""
var tooltip: ItemTooltip
var slots: Array[ItemSlot] = []
var _state: GameState
var _title: Label
var _gold: Button
var _take_all: Button
var _forecast: Label
var _hovered: ItemSlot

func _init() -> void:
	position = RECT.position
	size = RECT.size
	add_theme_stylebox_override("panel", MenuStyle.box(Color("0d121b"), MenuStyle.GOLD, 12, 2))
	_title = MenuStyle.label(self, Rect2(24, 14, 420, 40), "", 26, MenuStyle.GOLD)
	var close: Button = MenuStyle.button(self, Rect2(RECT.size.x - 60, 14, 44, 40), "×", 24)
	close.tooltip_text = MenuStyle.text("INV_CLOSE")
	close.pressed.connect(func() -> void: close_requested.emit())
	for index: int in range(COLUMNS * ROWS):
		var slot: ItemSlot = ItemSlot.new()
		slot.position = Vector2(24 + (index % COLUMNS) * (SLOT + GAP), 70 + floori(index / float(COLUMNS)) * (SLOT + GAP))
		slot.size = Vector2(SLOT, SLOT)
		slot.drag_source = "loot"
		add_child(slot)
		slot.clicked.connect(func(clicked: ItemSlot) -> void: take(clicked.item_id))
		slot.hovered.connect(_on_hovered)
		slot.unhovered.connect(func(left: ItemSlot) -> void:
			if _hovered == left:
				_hovered = null
				if tooltip != null:
					tooltip.hide_tooltip())
		slots.append(slot)
	_gold = MenuStyle.button(self, Rect2(24, 414, 230, 52), "")
	_gold.pressed.connect(func() -> void: take("gold"))
	_take_all = MenuStyle.button(self, Rect2(266, 414, 230, 52), MenuStyle.text("LOOT_TAKE_ALL"))
	_take_all.pressed.connect(take_all)
	_forecast = MenuStyle.label(self, Rect2(24, 478, RECT.size.x - 48, 84), "", 17, MenuStyle.MUTED)
	_forecast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_forecast.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_forecast.clip_text = false
	var hint: Label = MenuStyle.label(self, Rect2(24, RECT.size.y - 66, RECT.size.x - 48, 52), MenuStyle.text("LOOT_HINT"), 15, MenuStyle.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.clip_text = false

func open(state: GameState, p_source_id: String) -> void:
	source_id = p_source_id
	update_state(state)

func update_state(state: GameState) -> void:
	_state = state
	var record: Dictionary = LootRules.source(state, source_id)
	if record.is_empty() or not state.actors.has(actor_id):
		return
	var actor: Dictionary = state.actors[actor_id]
	var loot: Dictionary = LootRules.remaining(record)
	_title.text = MenuStyle.text("LOOT_TITLE_PILE") if LootRules.is_pile(source_id) else \
		MenuStyle.text("LOOT_TITLE") % MenuStyle.text(String(record.get("name_key", "")))
	var ids: Array = (loot["items"] as Dictionary).keys()
	for index: int in range(slots.size()):
		if index < ids.size():
			var item_id: String = String(ids[index])
			slots[index].set_item(item_id, int(loot["items"][item_id]), not LootRules.take_reason(state, actor_id, source_id, item_id).is_empty())
		else:
			slots[index].set_item("")
	var gold: int = int(loot.get("gold", 0))
	_gold.text = MenuStyle.text("LOOT_GOLD") % gold if gold > 0 else MenuStyle.text("LOOT_NO_GOLD")
	_gold.disabled = gold <= 0 or not LootRules.take_reason(state, actor_id, source_id, "gold").is_empty()
	var reason: String = LootRules.take_reason(state, actor_id, source_id, "", true)
	_take_all.disabled = not reason.is_empty()
	_take_all.tooltip_text = MenuStyle.text(reason) if not reason.is_empty() else ""
	_forecast.text = _forecast_text(state, actor, loot, reason)
	if _hovered != null and tooltip != null and tooltip.visible:
		_on_hovered(_hovered)

## Combat cost and the weight after taking everything, against the hero's limit.
func _forecast_text(state: GameState, actor: Dictionary, loot: Dictionary, reason: String) -> String:
	var lines: PackedStringArray = []
	if state.mode == &"combat":
		lines.append(MenuStyle.text("LOOT_COMBAT_COST"))
	if not reason.is_empty():
		lines.append(MenuStyle.text(reason))
	var preview: Dictionary = actor.duplicate(true)
	for item_id: String in loot["items"]:
		EquipmentRules.add_item(preview, item_id, int(loot["items"][item_id]))
	var burden: int = EquipmentRules.encumbrance(preview)
	_forecast.add_theme_color_override("font_color", [MenuStyle.MUTED, Color("e8b45a"), MenuStyle.RED][burden])
	var weight_line: String = MenuStyle.text("LOOT_FORECAST") % [EquipmentRules.total_weight_kg(preview), EquipmentRules.capacity_kg(actor)]
	if burden > 0:
		weight_line += " " + MenuStyle.text("INV_ENCUMBERED_%d" % burden) % EquipmentRules.ENCUMBRANCE_PENALTY_M[burden]
	lines.append(weight_line)
	return "\n".join(lines)

func take_all() -> void:
	if _state != null and LootRules.take_reason(_state, actor_id, source_id, "", true).is_empty():
		command_requested.emit(LootTakeAllCommand.new(actor_id, source_id))

func take(item_id: String) -> void:
	if _state != null and LootRules.take_reason(_state, actor_id, source_id, item_id).is_empty():
		command_requested.emit(LootTakeCommand.new(actor_id, source_id, item_id))

func _on_hovered(slot: ItemSlot) -> void:
	_hovered = slot
	if tooltip == null or _state == null or slot.item_id.is_empty():
		if tooltip != null:
			tooltip.hide_tooltip()
		return
	var actor: Dictionary = _state.actors[actor_id]
	var reason: String = LootRules.take_reason(_state, actor_id, source_id, slot.item_id)
	var item: Dictionary = ItemCatalog.get_item(slot.item_id)
	var hint: String = ItemText.compare_line(item, actor, InventoryCommand.training_for(actor))
	if reason.is_empty():
		hint += ("\n" if not hint.is_empty() else "") + MenuStyle.text("LOOT_CLICK_TAKE")
	tooltip.show_item(item, actor, InventoryCommand.training_for(actor), hint,
		MenuStyle.text(reason) if not reason.is_empty() else "", slot.get_global_rect())
