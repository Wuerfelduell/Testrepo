class_name MenuStyle
extends RefCounted
## Shared look of the in-game menus: dark stone panels, gold for the player (docs/UI.md 1.4).

const GOLD: Color = Color("dab776")
const GOLD_BRIGHT: Color = Color("f3d38a")
const INK: Color = Color(0.025, 0.035, 0.05, 0.95)
const SLOT: Color = Color("121a26")
const PAPER: Color = Color("eee9dd")
const MUTED: Color = Color("9aa1ad")
const RED: Color = Color("ed867d")
const GREEN: Color = Color("9ed5ac")
const BORDER: Color = Color(0.57, 0.46, 0.29, 0.8)

static func box(bg: Color = INK, border: Color = BORDER, radius: int = 10, width: int = 1) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style

static func panel(parent: Node, rect: Rect2) -> Panel:
	var result: Panel = Panel.new()
	result.position = rect.position
	result.size = rect.size
	result.add_theme_stylebox_override("panel", box())
	parent.add_child(result)
	return result

static func label(parent: Node, rect: Rect2, text: String, font_size: int = 18,
		color: Color = PAPER, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var result: Label = Label.new()
	result.position = rect.position
	result.size = rect.size
	result.text = text
	result.horizontal_alignment = align
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.clip_text = true
	parent.add_child(result)
	return result

static func button(parent: Node, rect: Rect2, text: String, font_size: int = 20) -> Button:
	var result: Button = Button.new()
	result.position = rect.position
	result.size = rect.size
	result.text = text
	result.focus_mode = Control.FOCUS_NONE
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", PAPER)
	result.add_theme_color_override("font_hover_color", GOLD_BRIGHT)
	result.add_theme_color_override("font_pressed_color", GOLD_BRIGHT)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var border: Color = GOLD if state in ["hover", "pressed"] else Color("665b46")
		result.add_theme_stylebox_override(state, box(Color("151e2a") if state == "normal" else Color("263042"), border, 6))
	parent.add_child(result)
	return result

## Falls back to a readable name while a key is not in localization/strings.csv yet.
static func text(key: String) -> String:
	var translated: String = TranslationServer.translate(key)
	if translated != key:
		return translated
	var words: PackedStringArray = key.split("_")
	if words.size() > 1 and words[0] in ["FEATURE", "CLASS", "ITEM", "WEAPON"]:
		words.remove_at(0)
	return " ".join(words).capitalize()
