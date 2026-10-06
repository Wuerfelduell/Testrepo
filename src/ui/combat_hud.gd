class_name CombatHUD
extends CanvasLayer
## Passive state projection. All decisions leave the HUD as command requests.

signal action_requested(kind: String)
signal actor_selected(actor_id: String)
signal skip_roll()
signal rolls_finished()

const GOLD: Color = Color("dab776")
const INK: Color = Color(0.025, 0.035, 0.05, 0.92)
const PAPER: Color = Color("eee9dd")
const RED: Color = Color("ed867d")
const GREEN: Color = Color("9ed5ac")

class Portrait extends Control:
	var actor: Dictionary = {}
	var active: bool = false

	func _draw() -> void:
		var dim: bool = int(actor.get("hp", 0)) <= 0
		var friendly: bool = String(actor.get("team", "enemy")) in ["hero", "player", "party"]
		var tint: Color = Color("cba660") if friendly else Color("9d595a")
		var personality: String = String(actor.get("personality", "brute"))
		if not friendly and personality == "coward":
			tint = Color("8b709e")
		elif not friendly and personality == "archer":
			tint = Color("a07d57")
		if dim:
			tint = Color("555966")
		var center: Vector2 = size * 0.5
		var radius: float = minf(size.x, size.y) * 0.44
		draw_circle(center, radius, Color("101624"))
		draw_arc(center, radius, 0, TAU, 64, Color("f3d38a") if active else tint, 3.0 if active else 1.5, true)
		var hood: bool = bool(actor.get("weapon", {}).get("ranged", false)) or personality == "coward"
		var skin: Color = Color("c6a88b") if friendly else Color("89957e")
		if dim:
			skin = Color("575d64")
		var unit: float = radius / 36.0
		# Hand-drawn, actor-specific busts: armor, hood, face and eyes remain legible at 64 px.
		var shoulders: PackedVector2Array = [Vector2(-29, 28), Vector2(-24, 15), Vector2(-10, 9), Vector2(10, 9), Vector2(24, 15), Vector2(29, 28)]
		for index: int in range(shoulders.size()):
			shoulders[index] = center + shoulders[index] * unit
		draw_colored_polygon(shoulders, tint.darkened(0.25))
		draw_circle(center + Vector2(0, -4) * unit, 18 * unit, tint.darkened(0.4) if hood else Color("626e7a"))
		var face: PackedVector2Array = [Vector2(-12, -15), Vector2(11, -15), Vector2(13, 0), Vector2(8, 12), Vector2(0, 16), Vector2(-8, 12), Vector2(-13, 0)]
		for index: int in range(face.size()):
			face[index] = center + face[index] * unit
		draw_colored_polygon(face, skin)
		if hood:
			var hood_top: PackedVector2Array = [center + Vector2(-19,-3)*unit, center + Vector2(-15,-19)*unit, center + Vector2(0,-26)*unit, center + Vector2(15,-19)*unit, center + Vector2(19,-3)*unit, center + Vector2(0,-16)*unit]
			draw_colored_polygon(hood_top, tint.darkened(0.1))
		else:
			draw_rect(Rect2(center + Vector2(-15, -20) * unit, Vector2(30, 8) * unit), Color("83909c"))
			draw_line(center + Vector2(0, -23)*unit, center + Vector2(0,-11)*unit, tint, 3 * unit)
		var eyes: Color = Color("342d28") if friendly else Color("da8d56")
		draw_line(center + Vector2(-9,-3)*unit, center + Vector2(-3,-2)*unit, eyes, 2.5*unit)
		draw_line(center + Vector2(3,-2)*unit, center + Vector2(9,-3)*unit, eyes, 2.5*unit)
		draw_line(center + Vector2(-4,8)*unit, center + Vector2(4,8)*unit, skin.darkened(0.4), 1.5*unit)

var dice_popup: DicePopup
var _root: Control
var _state: GameState
var _initiative: HBoxContainer
var _round_label: Label
var _mode_label: Label
var _name_label: Label
var _stats_label: Label
var _resource_label: Label
var _conditions: Label
var _hp_bar: ProgressBar
var _move_bar: ProgressBar
var _move_label: Label
var _party: HBoxContainer
var _buttons: Dictionary = {}
var _end_button: Button
var _target_panel: Panel
var _target_title: Label
var _target_detail: Label
var _target_reasons: Label
var _path_label: Label
var _log: RichTextLabel
var _log_panel: Panel
var _log_button: Button
var _log_expanded: bool = false
var _lines: PackedStringArray = []
var _debug: Panel
var _debug_text: RichTextLabel
var _death: Control
var _death_detail: Label
var _death_killer: String = ""
var _portrait_signature: int = -1
var _glow_time: float = 0.0
var _can_end: bool = false
var _action_left: bool = false

func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.size = Vector2(1920, 1080)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_initiative()
	_build_resources()
	_build_hotbar()
	_build_log()
	_build_target()
	_build_debug()
	dice_popup = DicePopup.new()
	dice_popup.position = Vector2(560, 310)
	dice_popup.size = Vector2(800, 390)
	_root.add_child(dice_popup)
	dice_popup.rolls_finished.connect(func() -> void: rolls_finished.emit())
	_build_death()
	get_viewport().size_changed.connect(_resize)
	_resize()

func update_state(state: GameState) -> void:
	_state = state.copy()
	_round_label.text = tr("COMBAT_ROUND") % state.round_number
	_mode_label.text = tr("COMBAT_MODE_" + String(state.mode).to_upper())
	(_initiative.get_parent() as Control).visible = state.mode == &"combat" and not state.turn_order.is_empty()
	var current_id: String = state.current_actor_id()
	var hero: Dictionary = {}
	for actor_id: String in state.actors:
		if _friendly(state.actors[actor_id]):
			hero = state.actors[actor_id]
			break
	var signature_data: Array = [current_id, state.turn_order]
	for actor_id: String in state.actors:
		var record: Dictionary = state.actors[actor_id]
		signature_data.append([actor_id, record.get("name_key"), record.get("hp"), record.get("max_hp"), record.get("conditions"), record.get("team"), record.get("weapon", {}).get("ranged", false)])
	var signature: int = hash(signature_data)
	if signature != _portrait_signature:
		_portrait_signature = signature
		_rebuild_portraits(state, current_id)
	_name_label.text = _actor_name(hero)
	_stats_label.text = tr("COMBAT_HP_AC") % [int(hero.get("hp", 0)), int(hero.get("max_hp", 1)), int(hero.get("ac", 10))]
	_hp_bar.max_value = maxf(1, float(hero.get("max_hp", 1)))
	_hp_bar.value = float(hero.get("hp", 0))
	_move_bar.max_value = maxf(0.1, float(hero.get("speed_m", 9.0)))
	_move_bar.value = float(hero.get("move_left", 0.0))
	_move_label.text = tr("COMBAT_FREE_MOVEMENT") if state.mode == &"exploration" else tr("COMBAT_MOVEMENT") % [float(hero.get("move_left", 0.0)), float(hero.get("speed_m", 0.0))]
	_resource_label.text = tr("COMBAT_RESOURCES") % [_pip(bool(hero.get("action_available", false))), _pip(bool(hero.get("bonus_available", false))), _pip(bool(hero.get("reaction_available", false)))]
	_conditions.text = tr("COMBAT_DISENGAGED") if bool(hero.get("disengaged", false)) else _condition_text(hero)
	var active: Dictionary = state.actors.get(current_id, {})
	var pending: Dictionary = state.get("pending") as Dictionary
	var player_turn: bool = state.mode == &"combat" and _friendly(active) and pending.is_empty()
	_action_left = bool(active.get("action_available", false))
	_can_end = player_turn
	for kind: String in _buttons:
		var button: Button = _buttons[kind]
		button.disabled = not player_turn or not _action_left
		button.tooltip_text = tr("COMBAT_COST_ACTION") if not button.disabled else tr("COMBAT_NO_ACTION" if player_turn else "COMBAT_WAIT_TURN")
	_end_button.disabled = not player_turn
	_death.visible = state.mode == &"defeat" and not dice_popup.is_busy()
	if state.mode == &"defeat":
		_death_detail.text = tr("COMBAT_DEATH_DETAIL") % [_actor_name(hero), tr("CLASS_FIGHTER"), int(hero.get("level", 1)), _death_killer if not _death_killer.is_empty() else tr("COMBAT_UNKNOWN_ACTOR"), state.round_number, int(hero.get("xp", 0))]

func _rebuild_portraits(state: GameState, current_id: String) -> void:
	for child: Node in _initiative.get_children():
		_initiative.remove_child(child)
		child.queue_free()
	for actor_id: String in state.turn_order:
		if not state.actors.has(actor_id):
			continue
		var actor: Dictionary = state.actors[actor_id]
		var column: VBoxContainer = VBoxContainer.new()
		column.custom_minimum_size = Vector2(76, 100)
		var portrait: Portrait = _portrait(actor, actor_id == current_id, Vector2(84, 84) if actor_id == current_id else Vector2(72, 72))
		column.add_child(portrait)
		var hp: Label = _new_label(tr("COMBAT_HP_SHORT") % [int(actor.get("hp", 0)), int(actor.get("max_hp", 0))], 16)
		hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(hp)
		column.modulate.a = 0.35 if int(actor.get("hp", 0)) <= 0 else 1.0
		_initiative.add_child(column)
	for child: Node in _party.get_children():
		_party.remove_child(child)
		child.queue_free()
	for actor_id: String in state.actors:
		var member: Dictionary = state.actors[actor_id]
		if not _friendly(member):
			continue
		var portrait: Portrait = _portrait(member, actor_id == current_id, Vector2(78, 78))
		portrait.mouse_filter = Control.MOUSE_FILTER_STOP
		portrait.gui_input.connect(_party_clicked.bind(actor_id))
		_party.add_child(portrait)

func set_attack_mode(active: bool) -> void:
	var button: Button = _buttons["attack"]
	button.toggle_mode = true
	button.set_pressed_no_signal(active)
	button.tooltip_text = tr("COMBAT_SELECT_ATTACK") if active else tr("COMBAT_COST_ACTION")

func show_target(preview: Dictionary, enemy: Dictionary) -> void:
	_target_panel.visible = true
	_target_title.text = _actor_name(enemy)
	var attacker: Dictionary = _state.actors.get(_state.current_actor_id(), {}) if _state != null else {}
	var weapon: Dictionary = attacker.get("weapon", {})
	var modifier_total: int = 0
	for item: Variant in weapon.get("damage_modifiers", []):
		modifier_total += int((item as Dictionary).get("amount", 0))
	var damage: String = String(weapon.get("damage_dice", ""))
	if modifier_total != 0:
		damage += "%+d" % modifier_total
	_target_detail.text = tr("COMBAT_TARGET_PREVIEW") % [tr(String(weapon.get("name_key", "COMBAT_ATTACK"))), roundi(float(preview.get("chance", 0.0)) * 100.0), damage, tr("DAMAGE_" + String(weapon.get("damage_type", "slashing")).to_upper()), int(preview.get("armor_class", enemy.get("ac", 10)))]
	for component: Variant in weapon.get("extra_damage", []):
		var extra: Dictionary = component as Dictionary
		_target_detail.text += " " + tr("COMBAT_EXTRA_DAMAGE") % [int(extra.get("amount", 0)), tr("DAMAGE_" + String(extra.get("damage_type", "")).to_upper())]
	var reasons: PackedStringArray = []
	if not bool(preview.get("legal", false)):
		reasons.append(tr("COMBAT_OUT_OF_RANGE"))
	if not bool(attacker.get("action_available", false)):
		reasons.append(tr("COMBAT_NO_ACTION"))
	for source: Variant in preview.get("advantages", []):
		reasons.append(tr("COMBAT_ADVANTAGE_REASON") % DicePopup.source_name(String(source)))
	for source: Variant in preview.get("disadvantages", []):
		reasons.append(tr("COMBAT_DISADVANTAGE_REASON") % DicePopup.source_name(String(source)))
	if int(preview.get("cover", 0)) > 0:
		reasons.append(tr("COMBAT_COVER") % int(preview["cover"]))
	if reasons.is_empty():
		reasons.append(tr("COMBAT_COST_ACTION"))
	_target_reasons.text = "\n".join(reasons)
	_target_reasons.tooltip_text = _target_reasons.text

func show_path(cost: float, remaining: float, danger: bool) -> void:
	_path_label.visible = true
	var cursor: Vector2 = _root.get_local_mouse_position() + Vector2(24, 26)
	_path_label.position = Vector2(clampf(cursor.x, 20, 1300), clampf(cursor.y, 180, 838))
	_path_label.text = tr("COMBAT_PATH_FREE") % cost if remaining == INF else tr("COMBAT_PATH") % [cost, remaining]
	if danger:
		_path_label.text += "   " + tr("COMBAT_OPPORTUNITY_DANGER")
	_path_label.add_theme_color_override("font_color", RED if remaining < -0.001 or danger else GREEN)

func clear_target() -> void:
	_target_panel.visible = false
	_path_label.visible = false

func consume_events(events: Array[Dictionary]) -> void:
	for event: Dictionary in events:
		var actor: Dictionary = _state.actors.get(String(event.get("actor_id", "")), {}) if _state != null else {}
		var target: Dictionary = _state.actors.get(String(event.get("target_id", "")), {}) if _state != null else {}
		match String(event.get("type", "")):
			"roll":
				var description: Dictionary = event.duplicate(true)
				description["actor_name_key"] = actor.get("name_key", "COMBAT_UNKNOWN_ACTOR")
				dice_popup.enqueue(description)
				var roll: Dictionary = event.get("roll", {})
				var kind: String = String(event.get("kind", "attack"))
				var total: int = int(roll.get("total", 0))
				var detail: String = tr("COMBAT_LOG_ROLL") % [_actor_name(actor), tr("COMBAT_ROLL_" + kind.to_upper()), total]
				if kind == "attack":
					detail += " · " + tr("COMBAT_LOG_HIT") % [_actor_name(target), tr("COMBAT_HIT" if bool(event.get("hit", false)) else "COMBAT_MISS")]
				_append_log(detail)
			"damage":
				_append_log(tr("COMBAT_LOG_DAMAGE") % [_actor_name(target), int(event.get("amount", 0)), tr("DAMAGE_" + String(event.get("damage_type", "slashing")).to_upper())])
			"death":
				_append_log(tr("COMBAT_LOG_DEATH") % _actor_name(actor))
				if _friendly(actor):
					var killer: Dictionary = _state.actors.get(String(event.get("killer_id", "")), {})
					_death_killer = _actor_name(killer)
					_death_detail.text = tr("COMBAT_DEATH_DETAIL") % [_actor_name(actor), tr("CLASS_FIGHTER"), int(actor.get("level", 1)), _death_killer, _state.round_number, int(actor.get("xp", 0))]
			"combat_end":
				_append_log(tr("COMBAT_DEFEAT" if String(event.get("mode", "")) == "defeat" else "COMBAT_VICTORY"))
			"start_attack":
				if bool(event.get("opportunity", false)):
					_append_log(tr("COMBAT_LOG_OPPORTUNITY") % [_actor_name(actor), _actor_name(target)])

func set_ai_options(options: Array[Dictionary]) -> void:
	var rows: PackedStringArray = []
	for index: int in range(mini(8, options.size())):
		var option: Dictionary = options[index]
		rows.append(tr("COMBAT_AI_SCORE") % [float(option.get("score", 0)), tr(String(option.get("reason_key", "AI_END_TURN")))])
		var breakdown: Dictionary = option.get("breakdown", {})
		var details: PackedStringArray = []
		for key: String in breakdown:
			details.append(tr("COMBAT_AI_COMPONENT") % [tr("AI_FACTOR_" + key.to_upper()), float(breakdown[key])])
		if not details.is_empty():
			rows.append("  " + " · ".join(details))
	_debug_text.text = "\n".join(rows)

func toggle_debug() -> void:
	_debug.visible = not _debug.visible

func is_roll_busy() -> bool:
	return dice_popup != null and dice_popup.is_busy()

func rolls_busy() -> bool:
	return is_roll_busy()

func _process(delta: float) -> void:
	_glow_time += delta
	if _state != null:
		_death.visible = _state.mode == &"defeat" and not dice_popup.is_busy()
	if _end_button != null:
		_end_button.modulate = Color(1, 1, 1).lerp(GOLD, 0.25 + sin(_glow_time * 2.0) * 0.15) if _can_end and _action_left else Color.WHITE

func _build_initiative() -> void:
	var panel: Panel = _panel(Rect2(566, 20, 788, 145))
	_round_label = _label(panel, Rect2(15, 8, 758, 26), "", 20)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initiative = HBoxContainer.new()
	_initiative.position = Vector2(18, 35)
	_initiative.size = Vector2(752, 106)
	_initiative.alignment = BoxContainer.ALIGNMENT_CENTER
	_initiative.add_theme_constant_override("separation", 18)
	panel.add_child(_initiative)
	_mode_label = _label(_root, Rect2(30, 24, 410, 34), tr("COMBAT_MODE_EXPLORATION"), 24)
	_mode_label.add_theme_color_override("font_color", GOLD)
	_label(_root, Rect2(30, 62, 420, 58), tr("COMBAT_CONTROLS"), 16)

func _build_resources() -> void:
	var panel: Panel = _panel(Rect2(26, 826, 474, 226))
	_party = HBoxContainer.new()
	_party.position = Vector2(12, 12)
	_party.size = Vector2(90, 85)
	panel.add_child(_party)
	_name_label = _label(panel, Rect2(108, 14, 346, 32), "", 23)
	_stats_label = _label(panel, Rect2(108, 49, 346, 28), "", 19)
	_hp_bar = _bar(panel, Rect2(108, 81, 342, 10), RED)
	_resource_label = _label(panel, Rect2(18, 106, 438, 34), "", 17)
	_move_label = _label(panel, Rect2(18, 144, 438, 26), "", 18)
	_move_bar = _bar(panel, Rect2(18, 176, 432, 9), GOLD)
	_conditions = _label(panel, Rect2(18, 189, 438, 26), "", 16)
	_conditions.add_theme_color_override("font_color", GOLD)

func _build_hotbar() -> void:
	var panel: Panel = _panel(Rect2(523, 940, 862, 112))
	var actions: Array[String] = ["attack", "dash", "disengage"]
	for index: int in range(actions.size()):
		var kind: String = actions[index]
		var button: Button = _button(panel, Rect2(14 + index * 185, 16, 174, 80), tr("COMBAT_HOTKEY_ACTION") % [str(index + 1), tr("COMBAT_" + kind.to_upper())])
		button.pressed.connect(func() -> void: action_requested.emit(kind))
		_buttons[kind] = button
	_end_button = _button(panel, Rect2(578, 16, 268, 80), tr("COMBAT_END_TURN"))
	_end_button.pressed.connect(func() -> void: action_requested.emit("end_turn"))
	_end_button.tooltip_text = tr("COMBAT_END_TURN_HINT")

func _build_log() -> void:
	_log_panel = _panel(Rect2(1440, 180, 452, 292))
	_log_button = _button(_log_panel, Rect2(12, 10, 428, 36), tr("COMBAT_LOG_EXPAND"))
	_log_button.pressed.connect(_toggle_log)
	_log = RichTextLabel.new()
	_log.position = Vector2(18, 58)
	_log.size = Vector2(416, 218)
	_log.bbcode_enabled = false
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 18)
	_log.add_theme_color_override("default_color", PAPER)
	_log_panel.add_child(_log)

func _build_target() -> void:
	_target_panel = _panel(Rect2(26, 174, 472, 235))
	_target_title = _label(_target_panel, Rect2(18, 14, 436, 32), "", 24)
	_target_title.add_theme_color_override("font_color", GOLD)
	_target_detail = _label(_target_panel, Rect2(18, 52, 436, 86), "", 19)
	_target_reasons = _label(_target_panel, Rect2(18, 144, 436, 83), "", 16)
	_target_reasons.add_theme_color_override("font_color", GOLD)
	_target_panel.visible = false
	_path_label = _label(_root, Rect2(525, 200, 870, 60), "", 22)
	_path_label.size = Vector2(590, 64)
	_path_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_path_label.visible = false

func _build_debug() -> void:
	_debug = _panel(Rect2(1397, 495, 495, 543))
	_label(_debug, Rect2(16, 12, 462, 30), tr("COMBAT_AI_TITLE"), 20)
	_debug_text = RichTextLabel.new()
	_debug_text.position = Vector2(16, 52)
	_debug_text.size = Vector2(462, 475)
	_debug_text.add_theme_font_size_override("normal_font_size", 16)
	_debug_text.add_theme_color_override("default_color", PAPER)
	_debug.add_child(_debug_text)
	_debug.visible = false

func _build_death() -> void:
	_death = Control.new()
	_death.size = Vector2(1920, 1080)
	_death.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_death)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.08, 0.015, 0.023, 0.94)
	shade.size = _death.size
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.add_child(shade)
	var title: Label = _label(_death, Rect2(450, 285, 1020, 75), tr("COMBAT_DEATH_TITLE"), 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", RED)
	_death_detail = _label(_death, Rect2(510, 380, 900, 180), "", 24)
	_death_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var menu: Button = _button(_death, Rect2(780, 620, 360, 76), tr("COMBAT_MAIN_MENU"))
	menu.pressed.connect(func() -> void: action_requested.emit("main_menu"))
	_death.visible = false

func _append_log(line: String) -> void:
	_lines.append(line)
	if _lines.size() > 200:
		_lines.remove_at(0)
	_refresh_log()

func _toggle_log() -> void:
	_log_expanded = not _log_expanded
	_log_panel.size.y = 570 if _log_expanded else 292
	_log.size.y = 496 if _log_expanded else 218
	_log_button.text = tr("COMBAT_LOG_COLLAPSE" if _log_expanded else "COMBAT_LOG_EXPAND")
	_refresh_log()

func _refresh_log() -> void:
	var first: int = 0 if _log_expanded else maxi(0, _lines.size() - 6)
	_log.text = "\n\n".join(_lines.slice(first))

func _portrait(actor: Dictionary, active: bool, dimensions: Vector2) -> Portrait:
	var portrait: Portrait = Portrait.new()
	portrait.actor = actor.duplicate(true)
	portrait.active = active
	portrait.custom_minimum_size = dimensions
	portrait.tooltip_text = tr("COMBAT_PORTRAIT_HINT") % [_actor_name(actor), int(actor.get("hp", 0)), int(actor.get("max_hp", 0)), _condition_text(actor)]
	return portrait

func _party_clicked(event: InputEvent, actor_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		actor_selected.emit(actor_id)

func _condition_text(actor: Dictionary) -> String:
	var conditions: PackedStringArray = []
	var raw: Variant = actor.get("conditions", {})
	if raw is Dictionary:
		for condition: Variant in raw:
			conditions.append(tr("CONDITION_" + String(condition).to_upper()))
	elif raw is Array:
		for condition: Variant in raw:
			conditions.append(tr("CONDITION_" + String(condition).to_upper()))
	return " · ".join(conditions) if not conditions.is_empty() else tr("COMBAT_NO_CONDITIONS")

func _actor_name(actor: Dictionary) -> String:
	return tr(String(actor.get("name_key", "COMBAT_UNKNOWN_ACTOR")))

func _friendly(actor: Dictionary) -> bool:
	return String(actor.get("team", "")) in ["hero", "player", "party"]

func _pip(available: bool) -> String:
	return "●" if available else "○"

func _resize() -> void:
	var available: Vector2 = get_viewport().get_visible_rect().size
	var factor: float = minf(available.x / 1920.0, available.y / 1080.0)
	_root.scale = Vector2.ONE * factor
	_root.position = (available - Vector2(1920, 1080) * factor) * 0.5

func _panel(rect: Rect2) -> Panel:
	var panel: Panel = Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = INK
	style.border_color = Color(0.57, 0.46, 0.29, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)
	return panel

func _new_label(text: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", PAPER)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _label(parent: Node, rect: Rect2, text: String, font_size: int) -> Label:
	var label: Label = _new_label(text, font_size)
	label.position = rect.position
	label.size = rect.size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, rect: Rect2, text: String) -> Button:
	var button: Button = Button.new()
	button.position = rect.position
	button.size = rect.size
	button.text = text
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_color_override("font_disabled_color", Color("666c78"))
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color("151e2a") if state != "hover" else Color("394038")
		style.border_color = GOLD if state == "hover" else Color("665b46")
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		button.add_theme_stylebox_override(state, style)
	parent.add_child(button)
	return button

func _bar(parent: Node, rect: Rect2, color: Color) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.position = rect.position
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = Color("313443")
	background.set_corner_radius_all(4)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	# Applying size before hiding percentage text clamps it to the default font's
	# minimum height. Godot does not shrink it again after the theme is replaced.
	bar.size = rect.size
	return bar
