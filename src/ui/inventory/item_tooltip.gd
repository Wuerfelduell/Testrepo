class_name ItemTooltip
extends PanelContainer
## Item details next to the hovered slot: name, type, numbers, what a click does or why not.

const WIDTH: float = 420.0

var _title: Label
var _type: Label
var _body: RichTextLabel

func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, 0)
	var style: StyleBoxFlat = MenuStyle.box(Color(0.02, 0.025, 0.04, 0.98), MenuStyle.GOLD, 8, 1)
	style.set_content_margin_all(16)
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	add_theme_stylebox_override("panel", style)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", MenuStyle.GOLD_BRIGHT)
	column.add_child(_title)
	_type = Label.new()
	_type.add_theme_font_size_override("font_size", 16)
	_type.add_theme_color_override("font_color", MenuStyle.MUTED)
	column.add_child(_type)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.custom_minimum_size = Vector2(WIDTH - 32, 0)
	_body.add_theme_font_size_override("normal_font_size", 18)
	_body.add_theme_color_override("default_color", MenuStyle.PAPER)
	column.add_child(_body)

func show_item(item: Dictionary, actor: Dictionary, training: EquipmentRules.Training,
		hint: String, reason: String, anchor: Rect2) -> void:
	_title.text = MenuStyle.text(String(item.get("name_key", "")))
	_type.text = ItemText.type_line(item)
	var lines: PackedStringArray = ItemText.stat_lines(item, actor, training)
	if not hint.is_empty():
		lines.append("[color=#dab776]%s[/color]" % hint)
	if not reason.is_empty():
		lines.append("[color=#ed867d]%s[/color]" % reason)
	_body.text = "\n".join(lines)
	size = Vector2(WIDTH, 0)
	visible = true
	reset_size()
	# Prefer the right side of the slot; flip left at the screen edge, stay on screen vertically.
	var target: Vector2 = Vector2(anchor.end.x + 12, anchor.position.y)
	if target.x + WIDTH > 1900:
		target.x = anchor.position.x - WIDTH - 12
	position = target
	_clamp.call_deferred()

func _clamp() -> void:
	# The rich text height is only known after layout.
	position.y = clampf(position.y, 20, maxf(20, 1060 - size.y))

func hide_tooltip() -> void:
	visible = false
