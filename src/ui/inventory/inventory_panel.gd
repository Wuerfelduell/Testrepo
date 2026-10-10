class_name InventoryPanel
extends Panel
## Equipment paper doll on the left, bag grid on the right. A passive projection of
## Game.state: clicks only request commands, the state changes through CommandBus.

signal command_requested(command: Command)
signal close_requested()

const RECT: Rect2 = Rect2(40, 176, 1380, 640)
const COLUMNS: int = 8
const ROWS: int = 5
const BAG_SLOT: float = 88.0
const GAP: float = 8.0

var actor_id: String = "hero"
var tooltip: ItemTooltip
var equipment_slots: Dictionary = {}
var bag_slots: Array[ItemSlot] = []
var _state: GameState
var _stats: RichTextLabel
var _footer: Label
var _hovered: ItemSlot

func _init() -> void:
	position = RECT.position
	size = RECT.size
	add_theme_stylebox_override("panel", MenuStyle.box(MenuStyle.INK, MenuStyle.BORDER, 12))
	MenuStyle.label(self, Rect2(28, 14, 600, 40), MenuStyle.text("INV_TITLE"), 28, MenuStyle.GOLD)
	var close: Button = MenuStyle.button(self, Rect2(RECT.size.x - 64, 14, 44, 40), "×", 24)
	close.tooltip_text = MenuStyle.text("INV_CLOSE")
	close.pressed.connect(func() -> void: close_requested.emit())
	_build_equipment()
	_build_bag()
	_footer = MenuStyle.label(self, Rect2(28, RECT.size.y - 50, RECT.size.x - 56, 32), "", 17, MenuStyle.MUTED)

func _build_equipment() -> void:
	var area: Panel = MenuStyle.panel(self, Rect2(20, 62, 500, 518))
	area.add_theme_stylebox_override("panel", MenuStyle.box(Color(1, 1, 1, 0.02), Color("3a3428"), 10))
	MenuStyle.label(area, Rect2(18, 8, 460, 30), MenuStyle.text("INV_EQUIPPED"), 18, MenuStyle.MUTED)
	var layout: Dictionary = {"armor": Vector2(198, 40), "main_hand": Vector2(70, 170), "off_hand": Vector2(326, 170)}
	for slot_name: String in layout:
		var slot: ItemSlot = ItemSlot.new(slot_name)
		slot.position = layout[slot_name]
		slot.size = Vector2(104, 104)
		area.add_child(slot)
		MenuStyle.label(area, Rect2(slot.position.x - 38, slot.position.y + 106, 180, 24),
			MenuStyle.text("INV_SLOT_" + slot_name.to_upper()), 16, MenuStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		_wire(slot)
		equipment_slots[slot_name] = slot
	_stats = RichTextLabel.new()
	_stats.bbcode_enabled = true
	_stats.position = Vector2(18, 316)
	_stats.size = Vector2(464, 196)
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.add_theme_font_size_override("normal_font_size", 19)
	_stats.add_theme_color_override("default_color", MenuStyle.PAPER)
	area.add_child(_stats)

func _build_bag() -> void:
	var left: float = 548.0
	MenuStyle.label(self, Rect2(left, 62, 400, 30), MenuStyle.text("INV_BAG"), 18, MenuStyle.MUTED)
	for index: int in range(COLUMNS * ROWS):
		var slot: ItemSlot = ItemSlot.new()
		slot.position = Vector2(left + (index % COLUMNS) * (BAG_SLOT + GAP), 98 + floori(index / float(COLUMNS)) * (BAG_SLOT + GAP))
		slot.size = Vector2(BAG_SLOT, BAG_SLOT)
		add_child(slot)
		_wire(slot)
		bag_slots.append(slot)

func _wire(slot: ItemSlot) -> void:
	slot.clicked.connect(_on_clicked)
	slot.hovered.connect(_on_hovered)
	slot.unhovered.connect(func(left_slot: ItemSlot) -> void:
		if _hovered == left_slot:
			_hovered = null
			if tooltip != null:
				tooltip.hide_tooltip())

func update_state(state: GameState) -> void:
	_state = state
	if not state.actors.has(actor_id) or not EquipmentRules.has_inventory(state.actors[actor_id]):
		return
	var actor: Dictionary = state.actors[actor_id]
	for slot_name: String in equipment_slots:
		var item_id: String = String(actor["equipment"].get(slot_name, ""))
		var reason: String = "" if item_id.is_empty() else EquipmentRules.unequip_reason(state, actor_id, slot_name)
		(equipment_slots[slot_name] as ItemSlot).set_item(item_id, 1, not reason.is_empty() and reason != "INV_REASON_KEEP_WEAPON")
	var entries: Array = actor["inventory"]
	for index: int in range(bag_slots.size()):
		if index < entries.size():
			var item_id: String = String(entries[index]["item"])
			bag_slots[index].set_item(item_id, int(entries[index]["count"]), not _action_reason(item_id).is_empty())
		else:
			bag_slots[index].set_item("")
	_stats.text = _stat_text(actor)
	_footer.text = MenuStyle.text("INV_FOOTER") % [EquipmentRules.total_weight_kg(actor), int(actor.get("gold", 0))]
	if _hovered != null and tooltip != null and tooltip.visible:
		_on_hovered(_hovered)

func _stat_text(actor: Dictionary) -> String:
	var weapon: Dictionary = actor.get("weapon", {})
	var damage: String = String(weapon.get("damage_dice", ""))
	if int(weapon.get("damage_bonus", 0)) != 0:
		damage += "%+d" % int(weapon["damage_bonus"])
	var lines: PackedStringArray = [
		"[color=#f3d38a]%s[/color]" % (MenuStyle.text("INV_STAT_AC") % int(actor.get("ac", 10))),
		MenuStyle.text("INV_STAT_ATTACK") % [MenuStyle.text(String(weapon.get("name_key", ""))),
			int(weapon.get("attack_bonus", 0)), damage, MenuStyle.text("DAMAGE_" + String(weapon.get("damage_type", "")).to_upper())],
		MenuStyle.text("INV_STAT_SPEED") % float(actor.get("speed_m", 9.0)),
	]
	if bool(weapon.get("two_handed_grip", false)):
		lines.append("[color=#9aa1ad]%s[/color]" % MenuStyle.text("INV_STAT_TWO_HANDED_GRIP"))
	if bool(actor.get("armor_untrained", false)):
		lines.append("[color=#ed867d]%s[/color]" % MenuStyle.text("ITEM_UNTRAINED_ARMOR"))
	if _state != null and _state.mode == &"combat":
		lines.append("[color=#9aa1ad]%s[/color]" % MenuStyle.text("INV_COMBAT_RULES"))
	return "\n".join(lines)

func _action_reason(item_id: String) -> String:
	if _state == null:
		return "INV_REASON_BUSY"
	if String(ItemCatalog.get_item(item_id).get("type", "")) == "consumable":
		return EquipmentRules.use_reason(_state, actor_id, item_id)
	return EquipmentRules.equip_reason(_state, actor_id, item_id)

func _on_clicked(slot: ItemSlot) -> void:
	if _state == null:
		return
	if not slot.slot_name.is_empty():
		if EquipmentRules.unequip_reason(_state, actor_id, slot.slot_name).is_empty():
			command_requested.emit(UnequipItemCommand.new(actor_id, slot.slot_name))
	elif _action_reason(slot.item_id).is_empty():
		if String(ItemCatalog.get_item(slot.item_id).get("type", "")) == "consumable":
			command_requested.emit(UseItemCommand.new(actor_id, slot.item_id))
		else:
			command_requested.emit(EquipItemCommand.new(actor_id, slot.item_id))

func _on_hovered(slot: ItemSlot) -> void:
	_hovered = slot
	if tooltip == null or _state == null or slot.item_id.is_empty():
		if tooltip != null:
			tooltip.hide_tooltip()
		return
	var actor: Dictionary = _state.actors[actor_id]
	var item: Dictionary = ItemCatalog.get_item(slot.item_id)
	var hint: String = ""
	var reason: String = ""
	if not slot.slot_name.is_empty():
		reason = EquipmentRules.unequip_reason(_state, actor_id, slot.slot_name)
		hint = MenuStyle.text("INV_CLICK_UNEQUIP")
	elif String(item.get("type", "")) == "consumable":
		reason = _action_reason(slot.item_id)
		hint = MenuStyle.text("INV_CLICK_USE")
	else:
		reason = _action_reason(slot.item_id)
		hint = MenuStyle.text("INV_CLICK_EQUIP")
		if ItemCatalog.slot_for(item) == "main_hand":
			hint += " · " + MenuStyle.text("INV_FREE_SWAP")
	tooltip.show_item(item, actor, InventoryCommand.training_for(actor), hint if reason.is_empty() else "",
		MenuStyle.text(reason) if not reason.is_empty() else "", slot.get_global_rect())
