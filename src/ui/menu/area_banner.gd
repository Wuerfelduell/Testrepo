class_name AreaBanner
extends CanvasLayer
## "Area cleared" with the XP award and its reason; fades out by itself.

const SHOW_SECONDS: float = 4.5

var panel: Panel
var title: Label
var detail: Label
var _elapsed: float = 0.0

func setup(event: Dictionary) -> void:
	layer = 15
	var root: Control = MenuTheme.design_root(self)
	panel = MenuTheme.panel(root, Rect2(560, 150, 800, 170))
	title = MenuTheme.label(panel, Rect2(0, 18, 800, 60), tr("AREA_CLEARED"), 48, MenuTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var names: PackedStringArray = []
	for key: Variant in event.get("defeated", []):
		names.append(tr(String(key)))
	var text: String = tr("AREA_XP") % [int(event.get("amount", 0)), tr(String(event.get("reason_key", ""))), ", ".join(names)]
	if not (event.get("gained_levels", []) as Array).is_empty():
		text += "\n" + tr("AREA_LEVEL_UP") % int(event.get("level", 1))
	detail = MenuTheme.label(panel, Rect2(30, 88, 740, 70), text, 22, MenuTheme.PAPER, HORIZONTAL_ALIGNMENT_CENTER)

func _process(delta: float) -> void:
	_elapsed += delta
	panel.modulate.a = smoothstep(0.0, 0.4, _elapsed) * (1.0 - smoothstep(SHOW_SECONDS - 0.8, SHOW_SECONDS, _elapsed))
	if _elapsed >= SHOW_SECONDS:
		queue_free()
