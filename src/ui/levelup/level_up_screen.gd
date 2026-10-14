class_name LevelUpScreen
extends CanvasLayer
## The level-up moment: what the next level gives (hit points, proficiency, features,
## spell slots) and every choice it asks for. Reads ProgressionRules.plan, never
## changes state itself: Confirm emits one LevelUpCommand.

signal command_requested(command: Command)
signal closed()

const PANEL: Rect2 = Rect2(230, 60, 1460, 960)
const ROW_HEIGHT: int = 46

var actor_id: String = "hero"
var plan: Dictionary = {}
var _actor: Dictionary = {}
var _choices: Dictionary = {}
var _root: Control
var _panel: Panel
var _gains: RichTextLabel
var _list: VBoxContainer
var _reason: Label
var _confirm: Button
var _hp_buttons: Dictionary = {}
var _feat_buttons: Dictionary = {}
var _feat_details: VBoxContainer
var _prepared_box: VBoxContainer
var _pick_buttons: Dictionary = {}

func setup(actor: Dictionary, p_actor_id: String = "hero") -> void:
	layer = 18
	actor_id = p_actor_id
	_actor = actor.duplicate(true)
	plan = ProgressionRules.plan(_actor)
	_choices = {"hp": "average"}
	if bool(plan["asi"]):
		_choices["feat"] = "ability_score_improvement"
		_choices["ability_increases"] = {}
	for key: String in ["spellbook", "cantrips"]:
		if int(plan[_count_key(key)]) > 0:
			_choices[key] = []
	if not plan["class_choices"].is_empty():
		_choices["class_choices"] = {}
		for choice: Dictionary in plan["class_choices"]:
			_choices["class_choices"][String(choice["key"])] = []
	_build()
	_refresh()

func _build() -> void:
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_root = MenuTheme.design_root(self)
	_panel = MenuTheme.panel(_root, PANEL)
	var class_name_text: String = tr("CLASS_" + String(plan["class_id"]).to_upper())
	MenuTheme.label(_panel, Rect2(0, 22, PANEL.size.x, 60), tr("LEVELUP_TITLE") % [int(plan["level"]), class_name_text],
		44, MenuTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	MenuTheme.label(_panel, Rect2(40, 100, 620, 36), tr("LEVELUP_GAINS"), 24, MenuTheme.GOLD)
	_gains = RichTextLabel.new()
	_gains.bbcode_enabled = true
	_gains.position = Vector2(40, 140)
	_gains.size = Vector2(620, 520)
	_gains.add_theme_font_size_override("normal_font_size", 21)
	_gains.add_theme_color_override("default_color", MenuTheme.PAPER)
	_gains.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gains.text = _gains_text()
	_panel.add_child(_gains)
	MenuTheme.label(_panel, Rect2(40, 670, 620, 36), tr("LEVELUP_HIT_POINTS"), 24, MenuTheme.GOLD)
	var die: int = int(plan["hit_die"])
	var constitution: int = int(plan["con_modifier"])
	_hp_buttons["roll"] = MenuTheme.toggle(_panel, Rect2(40, 712, 300, 64), tr("LEVELUP_HP_ROLL") % [die, constitution])
	_hp_buttons["average"] = MenuTheme.toggle(_panel, Rect2(360, 712, 300, 64),
		tr("LEVELUP_HP_AVERAGE") % [int(plan["average"]), constitution])
	for mode: String in _hp_buttons:
		(_hp_buttons[mode] as Button).pressed.connect(_set_hp.bind(mode))
	MenuTheme.label(_panel, Rect2(40, 784, 620, 60), tr("LEVELUP_HP_NOTE"), 18, MenuTheme.MUTED)
	MenuTheme.label(_panel, Rect2(720, 100, 700, 36), tr("LEVELUP_CHOICES"), 24, MenuTheme.GOLD)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(720, 140)
	scroll.size = Vector2(700, 690)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(680, 0)
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	_build_choices()
	_reason = MenuTheme.label(_panel, Rect2(40, 860, 820, 70), "", 20, MenuTheme.RED)
	var cancel: Button = MenuTheme.button(_panel, Rect2(900, 866, 230, 66), tr("LEVELUP_LATER"))
	cancel.pressed.connect(close)
	_confirm = MenuTheme.button(_panel, Rect2(1150, 866, 270, 66), tr("LEVELUP_CONFIRM"), 26)
	_confirm.pressed.connect(confirm)

func _gains_text() -> String:
	var lines: PackedStringArray = []
	var before: int = int(plan["proficiency_before"])
	var after: int = int(plan["proficiency_after"])
	lines.append(tr("LEVELUP_PROFICIENCY") % [before, after] if after != before else tr("LEVELUP_PROFICIENCY_SAME") % after)
	lines.append(tr("LEVELUP_HIT_DIE") % int(plan["hit_die"]))
	for feature: Dictionary in plan["features"]:
		var key: String = String(feature["name_key"])
		var title: String = tr(key)
		var tag: String = tr("LEVELUP_FEATURE_ACTIVE") if bool(feature["active"]) else tr("LEVELUP_FEATURE_DATA_ONLY")
		lines.append("[color=#dab776]•[/color] %s  [color=#8d8f98]%s[/color]" % [title, tag])
		var hint_key: String = key + "_HINT_LEVELUP"
		if tr(hint_key) != hint_key:
			lines.append("   [color=#b9b4a8]%s[/color]" % tr(hint_key))
	var slots_after: Array = plan["slots_after"]
	if not slots_after.is_empty() and slots_after != plan["slots_before"]:
		var parts: PackedStringArray = []
		for index: int in slots_after.size():
			parts.append(tr("LEVELUP_SLOT_ENTRY") % [index + 1, int(slots_after[index])])
		lines.append(tr("LEVELUP_SLOTS") % " · ".join(parts))
	if int(plan["prepared_limit"]) > 0:
		lines.append(tr("LEVELUP_PREPARED_LIMIT") % int(plan["prepared_limit"]))
	return "\n".join(lines)

func _section(title: String, note: String = "") -> void:
	var heading: Label = Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", MenuTheme.GOLD)
	_list.add_child(heading)
	if not note.is_empty():
		var detail: Label = Label.new()
		detail.text = note
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.custom_minimum_size = Vector2(660, 0)
		detail.add_theme_font_size_override("font_size", 18)
		detail.add_theme_color_override("font_color", MenuTheme.MUTED)
		_list.add_child(detail)

func _grid(parent: Node) -> GridContainer:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	return grid

func _toggle(parent: Node, text: String) -> Button:
	var button: Button = MenuTheme.toggle(parent, Rect2(0, 0, 330, ROW_HEIGHT), text, 19)
	button.custom_minimum_size = Vector2(330, ROW_HEIGHT)
	button.clip_text = true
	return button

func _build_choices() -> void:
	var any: bool = false
	if bool(plan["asi"]):
		any = true
		_section(tr("LEVELUP_SECTION_FEAT"), tr("LEVELUP_SECTION_FEAT_NOTE"))
		var grid: GridContainer = _grid(_list)
		for feat: String in plan["feat_options"]:
			var button: Button = _toggle(grid, tr("FEAT_" + feat.to_upper()))
			button.tooltip_text = tr("FEAT_%s_HINT" % feat.to_upper())
			button.pressed.connect(_set_feat.bind(feat))
			_feat_buttons[feat] = button
		_feat_details = VBoxContainer.new()
		_feat_details.add_theme_constant_override("separation", 8)
		_list.add_child(_feat_details)
		_build_feat_details()
	if bool(plan["fighting_style"]):
		any = true
		_section(tr("LEVELUP_SECTION_STYLE"))
		_pick_section("fighting_style", plan["fighting_style_options"], 1, "FEAT_")
	if bool(plan["expertise"]):
		any = true
		_section(tr("LEVELUP_SECTION_EXPERTISE"), tr("LEVELUP_SECTION_EXPERTISE_NOTE"))
		_pick_section("expertise", plan["expertise_options"], 1, "SHEET_SKILL_")
	if int(plan["cantrip_count"]) > 0:
		any = true
		_section(tr("LEVELUP_SECTION_CANTRIPS") % int(plan["cantrip_count"]))
		_pick_section("cantrips", plan["cantrip_options"], int(plan["cantrip_count"]), "")
	if ClassSpellcasting.is_caster(String(plan["class_id"])):
		any = true
		if ClassSpellcasting.uses_spellbook(String(plan["class_id"])):
			var count: int = int(plan["spellbook_count"])
			_section(tr("LEVELUP_SECTION_SPELLBOOK") % count,
				tr("LEVELUP_SPELLBOOK_NONE") if count == 0 else (tr("LEVELUP_SPELLBOOK_FEWER") if count < ClassSpellcasting.new_spells_per_level(String(plan["class_id"])) else ""))
			if count > 0:
				_pick_section("spellbook", plan["spellbook_options"], count, "")
		_section(tr("LEVELUP_SECTION_PREPARED") % int(plan["prepared_limit"]), tr("LEVELUP_SECTION_PREPARED_NOTE"))
		_prepared_box = VBoxContainer.new()
		_list.add_child(_prepared_box)
		_choices["prepared"] = ProgressionRules.default_prepared(_actor, _choices.get("spellbook", []))
		_build_prepared()
	# Class kit picks (ClassKits.level_choices), e.g. new spells or Weapon Mastery.
	for choice: Dictionary in plan["class_choices"]:
		any = true
		_section(tr(String(choice.get("title_key", "LEVELUP_SECTION_CLASS_CHOICE"))) % int(choice["count"]),
			tr(String(choice.get("note_key", ""))) if choice.has("note_key") else "")
		_pick_section("class:" + String(choice["key"]), choice["options"], int(choice["count"]),
			String(choice.get("option_prefix", "")))
	if not any:
		_section(tr("LEVELUP_NO_CHOICES"))

## Toggles for "pick N of these". Spells are labelled with their level and effect.
func _pick_section(key: String, options: Array, count: int, prefix: String) -> void:
	var grid: GridContainer = _grid(_list)
	for option: Variant in options:
		var id: String = String(option)
		var button: Button = _toggle(grid, _option_text(id, prefix))
		button.tooltip_text = _option_hint(id)
		button.toggled.connect(_on_pick.bind(key, id, count))
		_pick_buttons[key + ":" + id] = button

func _option_text(id: String, prefix: String) -> String:
	if not prefix.is_empty():
		return tr(prefix + id.to_upper())
	var spell: SpellDefinition = SpellBook.get_spell(id)
	if spell == null:
		return id
	var level_text: String = tr("SPELL_CANTRIP") if spell.is_cantrip() else tr("LEVELUP_SPELL_LEVEL") % spell.level
	return "%s · %s" % [tr(String(spell.name_key)), level_text]

func _option_hint(id: String) -> String:
	var spell: SpellDefinition = SpellBook.get_spell(id)
	if spell == null:
		return ""
	var parts: PackedStringArray = []
	if not spell.damage_dice.is_empty():
		parts.append("%s %s" % [spell.damage_dice, tr("DAMAGE_" + String(spell.damage_type).to_upper())])
	if spell.resolution == "save":
		parts.append(tr("LEVELUP_SPELL_SAVE") % tr("ABILITY_" + String(spell.save_ability).to_upper()))
	elif spell.resolution == "attack":
		parts.append(tr("LEVELUP_SPELL_ATTACK"))
	if spell.area != "none":
		parts.append(tr("LEVELUP_SPELL_AREA_" + spell.area.to_upper()) % spell.area_size_m)
	if spell.range_m > 0.0:
		parts.append(tr("LEVELUP_SPELL_RANGE") % spell.range_m)
	return " · ".join(parts)

func _on_pick(pressed: bool, key: String, id: String, count: int) -> void:
	if count == 1 and key in ["fighting_style", "expertise"]:
		for other: String in _pick_buttons:
			if other.begins_with(key + ":") and other != key + ":" + id:
				(_pick_buttons[other] as Button).set_pressed_no_signal(false)
		if pressed:
			_choices[key] = id
		else:
			_choices.erase(key)
		_refresh()
		return
	var class_key: String = key.trim_prefix("class:") if key.begins_with("class:") else ""
	var picks: Array = (_choices["class_choices"].get(class_key, []) if not class_key.is_empty() \
		else _choices.get(key, [])).duplicate()
	if pressed and not id in picks:
		if picks.size() >= count:
			(_pick_buttons[key + ":" + id] as Button).set_pressed_no_signal(false)
			return
		picks.append(id)
	elif not pressed:
		picks.erase(id)
	if not class_key.is_empty():
		_choices["class_choices"][class_key] = picks
	else:
		_choices[key] = picks
	if key == "spellbook":
		_choices["prepared"] = ProgressionRules.default_prepared(_actor, picks)
		_build_prepared()
	_refresh()

func _build_prepared() -> void:
	if _prepared_box == null:
		return
	for child: Node in _prepared_box.get_children():
		_prepared_box.remove_child(child)
		child.queue_free()
	var book: Array[String] = ProgressionRules.preparable_after(_actor, _choices.get("spellbook", []))
	var grid: GridContainer = _grid(_prepared_box)
	for spell_id: String in book:
		var button: Button = _toggle(grid, _option_text(spell_id, ""))
		button.tooltip_text = _option_hint(spell_id)
		button.set_pressed_no_signal(spell_id in _choices["prepared"])
		button.toggled.connect(func(pressed: bool) -> void:
			var prepared: Array = _choices["prepared"]
			if pressed and prepared.size() >= int(plan["prepared_limit"]):
				button.set_pressed_no_signal(false)
				return
			if pressed:
				prepared.append(spell_id)
			else:
				prepared.erase(spell_id)
			_refresh())

func _build_feat_details() -> void:
	for child: Node in _feat_details.get_children():
		_feat_details.remove_child(child)
		child.queue_free()
	for key: String in _pick_buttons.keys():
		if key.begins_with("skills:"):
			_pick_buttons.erase(key)
	match String(_choices.get("feat", "")):
		"ability_score_improvement":
			var note: Label = Label.new()
			note.text = tr("LEVELUP_ASI_NOTE")
			note.add_theme_font_size_override("font_size", 18)
			note.add_theme_color_override("font_color", MenuTheme.MUTED)
			_feat_details.add_child(note)
			var grid: GridContainer = _grid(_feat_details)
			for ability: StringName in Abilities.IDS:
				var button: Button = _toggle(grid, "")
				button.name = "asi_" + String(ability)
				button.pressed.connect(_bump.bind(String(ability)))
			_update_asi_buttons()
		"skilled":
			var count: int = int(plan["skilled_count"])
			var note: Label = Label.new()
			note.text = tr("LEVELUP_SKILLED_NOTE") % count
			note.add_theme_font_size_override("font_size", 18)
			note.add_theme_color_override("font_color", MenuTheme.MUTED)
			_feat_details.add_child(note)
			var grid: GridContainer = _grid(_feat_details)
			for skill: Variant in plan["skill_options"]:
				var id: String = String(skill)
				var button: Button = _toggle(grid, tr("SHEET_SKILL_" + id.to_upper()))
				button.toggled.connect(_on_pick.bind("skills", id, count))
				_pick_buttons["skills:" + id] = button
		"great_weapon_fighting":
			var note: Label = Label.new()
			note.text = tr("FEAT_GREAT_WEAPON_FIGHTING_HINT")
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.custom_minimum_size = Vector2(660, 0)
			note.add_theme_font_size_override("font_size", 18)
			note.add_theme_color_override("font_color", MenuTheme.MUTED)
			_feat_details.add_child(note)

## Each click adds +1 while the two points last and the score stays at or below 20;
## clicking a raised score again (when no point can be added) resets it.
func _bump(ability: String) -> void:
	var increases: Dictionary = _choices.get("ability_increases", {})
	var spent: int = 0
	for value: Variant in increases.values():
		spent += int(value)
	var current: int = int(increases.get(ability, 0))
	var score: int = ProgressionRules.score(_actor, ability) + current
	if spent < 2 and current < 2 and score < ProgressionRules.ABILITY_CAP:
		increases[ability] = current + 1
	else:
		increases.erase(ability)
	_choices["ability_increases"] = increases
	_update_asi_buttons()
	_refresh()

func _update_asi_buttons() -> void:
	var increases: Dictionary = _choices.get("ability_increases", {})
	for ability: StringName in Abilities.IDS:
		var button: Button = _feat_details.find_child("asi_" + String(ability), true, false) as Button
		if button == null:
			continue
		var base: int = ProgressionRules.score(_actor, String(ability))
		var bonus: int = int(increases.get(String(ability), 0))
		button.text = tr("LEVELUP_ASI_ENTRY") % [tr("ABILITY_" + String(ability).to_upper()), base] + \
			(tr("LEVELUP_ASI_RAISED") % (base + bonus) if bonus > 0 else "")
		button.set_pressed_no_signal(bonus > 0)
		button.disabled = base >= ProgressionRules.ABILITY_CAP

func _set_hp(mode: String) -> void:
	_choices["hp"] = mode
	_refresh()

func _set_feat(feat: String) -> void:
	_choices["feat"] = feat
	_choices.erase("ability_increases")
	_choices.erase("skills")
	match feat:
		"ability_score_improvement": _choices["ability_increases"] = {}
		"skilled": _choices["skills"] = []
	_build_feat_details()
	_refresh()

## Choices as LevelUpCommand expects them: only the keys this level asks for.
func current_choices() -> Dictionary:
	var result: Dictionary = _choices.duplicate(true)
	for key: String in ["spellbook", "cantrips"]:
		if int(plan[_count_key(key)]) == 0:
			result.erase(key)
	if result.get("feat", "") == "great_weapon_fighting":
		result.erase("fighting_style")
	return result

func _count_key(key: String) -> String:
	return "spellbook_count" if key == "spellbook" else "cantrip_count"

func _refresh() -> void:
	for mode: String in _hp_buttons:
		(_hp_buttons[mode] as Button).set_pressed_no_signal(_choices.get("hp") == mode)
	for feat: String in _feat_buttons:
		(_feat_buttons[feat] as Button).set_pressed_no_signal(_choices.get("feat") == feat)
	var reason: String = ProgressionRules.validate(_actor, current_choices())
	_confirm.disabled = not reason.is_empty()
	_reason.text = "" if reason.is_empty() else tr(reason)

func confirm() -> void:
	if not ProgressionRules.validate(_actor, current_choices()).is_empty():
		return
	command_requested.emit(LevelUpCommand.new(actor_id, current_choices()))
	close()

func close() -> void:
	closed.emit()
	queue_free()

## Test helpers: the same paths a click takes.
func choose_hp(mode: String) -> void:
	_set_hp(mode)

func choose_feat(feat: String) -> void:
	_set_feat(feat)

func raise(ability: String) -> void:
	_bump(ability)

func pick(key: String, id: String) -> void:
	var button: Button = _pick_buttons.get(key + ":" + id) as Button
	if button != null:
		button.button_pressed = not button.button_pressed

func is_confirmable() -> bool:
	return not _confirm.disabled
