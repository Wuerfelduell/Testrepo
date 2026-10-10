class_name DeathScreen
extends CanvasLayer
## docs/UI.md section 6: the screen bleeds to dark red while the hero's death animation
## plays, then shows who died, how, and the XP earned. Only exit: MAIN MENU.

signal main_menu_requested

const FADE_SECONDS: float = 1.6
const DETAIL_DELAY: float = 2.0

var shade: ColorRect
var content: Control
var title: Label
var detail: Label
var menu_button: Button
var _elapsed: float = 0.0

## info: name, class_id, level, killer_name, round, xp
func setup(info: Dictionary) -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root: Control = MenuTheme.design_root(self)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	shade = ColorRect.new()
	shade.color = Color(MenuTheme.BLOOD, 0.0)
	shade.size = Vector2(1920, 1080)
	root.add_child(shade)
	content = Control.new()
	content.size = Vector2(1920, 1080)
	content.modulate.a = 0.0
	root.add_child(content)
	title = MenuTheme.label(content, Rect2(360, 300, 1200, 100), tr("DEATH_TITLE"), 72, MenuTheme.RED, HORIZONTAL_ALIGNMENT_CENTER)
	var lines: PackedStringArray = [
		String(info.get("name", "")),
		tr("DEATH_CLASS_LEVEL") % [tr("CREATION_CLASS_" + String(info.get("class_id", "")).to_upper()), int(info.get("level", 1))],
	]
	if String(info.get("killer_name", "")).is_empty():
		lines.append(tr("DEATH_CAUSE_UNKNOWN") % int(info.get("round", 1)))
	else:
		lines.append(tr("DEATH_CAUSE") % [String(info["killer_name"]), int(info.get("round", 1))])
	lines.append(tr("DEATH_XP") % int(info.get("xp", 0)))
	detail = MenuTheme.label(content, Rect2(460, 430, 1000, 220), "\n".join(lines), 28, MenuTheme.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	MenuTheme.label(content, Rect2(460, 660, 1000, 40), tr("DEATH_SAVE_DELETED"), 20, MenuTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	menu_button = MenuTheme.button(content, Rect2(780, 740, 360, 76), tr("DEATH_MAIN_MENU"), 28)
	menu_button.pressed.connect(func() -> void: main_menu_requested.emit())

## Skips the fade (used by captures and tests).
func finish_fade() -> void:
	_elapsed = DETAIL_DELAY + 1.0
	_process(0.0)

func _process(delta: float) -> void:
	_elapsed += delta
	shade.color.a = 0.82 * smoothstep(0.0, FADE_SECONDS, _elapsed)
	content.modulate.a = smoothstep(DETAIL_DELAY, DETAIL_DELAY + 0.8, _elapsed)
	if content.modulate.a >= 1.0 and not menu_button.has_focus():
		menu_button.grab_focus()
