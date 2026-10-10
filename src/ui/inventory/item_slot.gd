class_name ItemSlot
extends Control
## One square in the bag or an equipment slot. Hover shows the tooltip, left click acts.

signal clicked(slot: ItemSlot)
signal hovered(slot: ItemSlot)
signal unhovered(slot: ItemSlot)

var item_id: String = ""
var count: int = 0
var slot_name: String = ""
var blocked: bool = false
var _icon: ItemIcon
var _count_label: Label
var _hover: bool = false

func _init(p_slot_name: String = "") -> void:
	slot_name = p_slot_name
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_icon = ItemIcon.new()
	add_child(_icon)
	# Anchored, so the layout also holds for sizes set before the slot enters the tree.
	_icon.anchor_right = 1.0
	_icon.anchor_bottom = 1.0
	_icon.offset_left = 10
	_icon.offset_top = 10
	_icon.offset_right = -10
	_icon.offset_bottom = -10
	_count_label = MenuStyle.label(self, Rect2(), "", 16, MenuStyle.PAPER, HORIZONTAL_ALIGNMENT_RIGHT)
	_count_label.anchor_left = 0.0
	_count_label.anchor_top = 1.0
	_count_label.anchor_right = 1.0
	_count_label.anchor_bottom = 1.0
	_count_label.offset_left = 4
	_count_label.offset_top = -26
	_count_label.offset_right = -8
	_count_label.offset_bottom = -4
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw()
		hovered.emit(self))
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw()
		unhovered.emit(self))

func set_item(p_item_id: String, p_count: int = 1, p_blocked: bool = false) -> void:
	item_id = p_item_id
	count = p_count
	blocked = p_blocked
	_icon.item_id = item_id
	_icon.dimmed = blocked
	_count_label.text = "×%d" % count if count > 1 else ""
	mouse_default_cursor_shape = Control.CURSOR_ARROW if item_id.is_empty() or blocked else Control.CURSOR_POINTING_HAND
	queue_redraw()

func _draw() -> void:
	var border: Color = Color("3a3428")
	if not item_id.is_empty():
		border = MenuStyle.BORDER
	if _hover and not item_id.is_empty():
		border = MenuStyle.RED if blocked else MenuStyle.GOLD_BRIGHT
	draw_style_box(MenuStyle.box(MenuStyle.SLOT, border, 8, 2 if _hover else 1), Rect2(Vector2.ZERO, size))
	if item_id.is_empty() and not slot_name.is_empty():
		# Faint outline of what belongs here, like an empty paper-doll slot.
		draw_arc(size * 0.5, size.x * 0.22, 0, TAU, 32, Color(1, 1, 1, 0.07), 2.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if not item_id.is_empty():
			clicked.emit(self)
