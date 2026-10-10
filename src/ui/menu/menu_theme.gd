class_name MenuTheme
extends RefCounted
## Shared look for menu screens: dark stone panels, gold accents, readable paper text
## (docs/UI.md principle 4). Same palette as the combat HUD.

const GOLD: Color = Color("dab776")
const INK: Color = Color(0.025, 0.035, 0.05, 0.92)
const PAPER: Color = Color("eee9dd")
const MUTED: Color = Color("8d8f98")
const RED: Color = Color("ed867d")
const BLOOD: Color = Color(0.22, 0.015, 0.025)

## Fixed 1920x1080 design space, scaled and letterboxed to the window like the HUD.
class DesignRoot extends Control:
	func _enter_tree() -> void:
		size = Vector2(1920, 1080)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not get_viewport().size_changed.is_connected(_fit):
			get_viewport().size_changed.connect(_fit)
		_fit()

	func _fit() -> void:
		MenuTheme.fit(self)

static func design_root(parent: Node) -> Control:
	var root: DesignRoot = DesignRoot.new()
	parent.add_child(root)
	return root

static func fit(root: Control) -> void:
	var available: Vector2 = root.get_viewport().get_visible_rect().size
	var factor: float = minf(available.x / 1920.0, available.y / 1080.0)
	root.scale = Vector2.ONE * factor
	root.position = (available - Vector2(1920, 1080) * factor) * 0.5

static func panel(parent: Node, rect: Rect2, color: Color = INK) -> Panel:
	var result: Panel = Panel.new()
	result.position = rect.position
	result.size = rect.size
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.57, 0.46, 0.29, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	result.add_theme_stylebox_override("panel", style)
	parent.add_child(result)
	return result

static func label(parent: Node, rect: Rect2, text: String, font_size: int,
		color: Color = PAPER, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var result: Label = Label.new()
	# Wrap before sizing: otherwise the unwrapped minimum width widens the label.
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.text = text
	result.position = rect.position
	result.size = rect.size
	result.horizontal_alignment = align
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	result.add_theme_constant_override("outline_size", 4 if font_size >= 28 else 0)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

static func button(parent: Node, rect: Rect2, text: String, font_size: int = 24) -> Button:
	var result: Button = Button.new()
	result.position = rect.position
	result.size = rect.size
	result.text = text
	result.focus_mode = Control.FOCUS_ALL
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", PAPER)
	result.add_theme_color_override("font_hover_color", Color("fff3d2"))
	result.add_theme_color_override("font_pressed_color", GOLD)
	result.add_theme_color_override("font_focus_color", PAPER)
	result.add_theme_color_override("font_disabled_color", Color("5c616c"))
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = {"normal": Color(0.08, 0.11, 0.15, 0.9), "hover": Color("394038"),
			"pressed": Color("4a4130"), "disabled": Color(0.06, 0.07, 0.09, 0.75),
			"focus": Color(0, 0, 0, 0)}[state]
		style.border_color = GOLD if state in ["hover", "pressed", "focus"] else Color("665b46")
		style.set_border_width_all(2 if state == "focus" else 1)
		style.set_corner_radius_all(6)
		style.draw_center = state != "focus"
		result.add_theme_stylebox_override(state, style)
	parent.add_child(result)
	return result

## A toggle button that shows its pressed state in gold (class list, body choice).
static func toggle(parent: Node, rect: Rect2, text: String, font_size: int = 22) -> Button:
	var result: Button = button(parent, rect, text, font_size)
	result.toggle_mode = true
	var pressed: StyleBoxFlat = StyleBoxFlat.new()
	pressed.bg_color = Color("4a4130")
	pressed.border_color = GOLD
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(6)
	result.add_theme_stylebox_override("pressed", pressed)
	result.add_theme_stylebox_override("hover_pressed", pressed)
	return result

static func line_edit(parent: Node, rect: Rect2, placeholder: String) -> LineEdit:
	var result: LineEdit = LineEdit.new()
	result.position = rect.position
	result.size = rect.size
	result.placeholder_text = placeholder
	result.add_theme_font_size_override("font_size", 24)
	result.add_theme_color_override("font_color", PAPER)
	result.add_theme_color_override("font_placeholder_color", MUTED)
	for state: String in ["normal", "focus"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(0.05, 0.06, 0.08, 0.95)
		style.border_color = GOLD if state == "focus" else Color("665b46")
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		style.content_margin_left = 12
		result.add_theme_stylebox_override(state, style)
	parent.add_child(result)
	return result
