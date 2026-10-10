class_name CharacterPanel
extends Panel
## Character sheet: abilities and saves, combat numbers with their sources, skills, features.
## Read-only projection of the hero record in Game.state.

signal close_requested()

const RECT: Rect2 = Rect2(40, 176, 1380, 640)

var actor_id: String = "hero"
var _name: Label
var _subtitle: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _abilities: RichTextLabel
var _combat: RichTextLabel
var _features: RichTextLabel
var _skills: RichTextLabel

func _init() -> void:
	position = RECT.position
	size = RECT.size
	add_theme_stylebox_override("panel", MenuStyle.box(MenuStyle.INK, MenuStyle.BORDER, 12))
	_name = MenuStyle.label(self, Rect2(28, 12, 700, 44), "", 30, MenuStyle.GOLD)
	_subtitle = MenuStyle.label(self, Rect2(28, 54, 700, 28), "", 18, MenuStyle.MUTED)
	var close: Button = MenuStyle.button(self, Rect2(RECT.size.x - 64, 14, 44, 40), "×", 24)
	close.tooltip_text = MenuStyle.text("INV_CLOSE")
	close.pressed.connect(func() -> void: close_requested.emit())
	_xp_bar = ProgressBar.new()
	_xp_bar.position = Vector2(760, 30)
	_xp_bar.size = Vector2(500, 14)
	_xp_bar.show_percentage = false
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_bar.add_theme_stylebox_override("background", MenuStyle.box(Color("1d2430"), Color("3a3428"), 6))
	_xp_bar.add_theme_stylebox_override("fill", MenuStyle.box(MenuStyle.GOLD, MenuStyle.GOLD, 6))
	add_child(_xp_bar)
	_xp_label = MenuStyle.label(self, Rect2(760, 48, 500, 26), "", 16, MenuStyle.MUTED)
	_abilities = _column(Rect2(20, 92, 430, 528), "SHEET_ABILITIES")
	_combat = _column(Rect2(466, 92, 440, 256), "SHEET_COMBAT")
	_features = _column(Rect2(466, 360, 440, 260), "SHEET_FEATURES")
	_skills = _column(Rect2(922, 92, 438, 528), "SHEET_SKILLS")

func _column(rect: Rect2, title_key: String) -> RichTextLabel:
	var area: Panel = MenuStyle.panel(self, rect)
	area.add_theme_stylebox_override("panel", MenuStyle.box(Color(1, 1, 1, 0.02), Color("3a3428"), 10))
	MenuStyle.label(area, Rect2(16, 8, rect.size.x - 32, 28), MenuStyle.text(title_key), 18, MenuStyle.MUTED)
	var body: RichTextLabel = RichTextLabel.new()
	body.bbcode_enabled = true
	body.scroll_active = false
	body.position = Vector2(16, 42)
	body.size = rect.size - Vector2(32, 50)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_font_size_override("normal_font_size", 17)
	body.add_theme_font_size_override("bold_font_size", 18)
	body.add_theme_color_override("default_color", MenuStyle.PAPER)
	area.add_child(body)
	return body

func update_state(state: GameState) -> void:
	if not state.actors.has(actor_id):
		return
	var actor: Dictionary = state.actors[actor_id]
	var class_id: String = String(actor.get("class_id", ""))
	var definition: ClassDefinition = null
	if not class_id.is_empty() and ResourceLoader.exists("res://data/classes/%s.tres" % class_id):
		definition = load("res://data/classes/%s.tres" % class_id) as ClassDefinition
	var level: int = int(actor.get("level", 1))
	_name.text = String(actor.get("display_name", MenuStyle.text(String(actor.get("name_key", "")))))
	_subtitle.text = MenuStyle.text("SHEET_SUBTITLE") % [level, MenuStyle.text("CLASS_" + class_id.to_upper()),
		MenuStyle.text("SHEET_SPECIES_" + String(actor.get("species", "human")).to_upper())]
	var xp: int = int(actor.get("xp", 0))
	if level < Progression.XP_THRESHOLDS.size():
		var low: int = Progression.XP_THRESHOLDS[level - 1]
		var high: int = Progression.XP_THRESHOLDS[level]
		_xp_bar.max_value = high - low
		_xp_bar.value = xp - low
		_xp_label.text = MenuStyle.text("SHEET_XP") % [xp, high, level + 1]
	else:
		_xp_bar.max_value = 1
		_xp_bar.value = 1
		_xp_label.text = MenuStyle.text("SHEET_XP_MAX") % xp
	var saves: Array[StringName] = []
	if definition != null:
		saves = definition.saving_throws.duplicate()
	_abilities.text = _ability_text(actor, saves)
	_combat.text = _combat_text(actor)
	_features.text = _feature_text(actor, definition, level)
	_skills.text = _skill_text(actor)

func _score(actor: Dictionary, ability: StringName) -> int:
	var scores: Dictionary = actor.get("ability_scores", {})
	return int(scores.get(ability, scores.get(String(ability), 10)))

func _ability_text(actor: Dictionary, saves: Array[StringName]) -> String:
	var proficiency: int = int(actor.get("proficiency_bonus", 2))
	var lines: PackedStringArray = []
	for ability: StringName in Abilities.IDS:
		var score: int = _score(actor, ability)
		var modifier: int = Abilities.modifier(score)
		var proficient: bool = ability in saves
		var save: int = modifier + (proficiency if proficient else 0)
		lines.append("[font_size=24][color=#f3d38a]%s[/color][/font_size]  [font_size=24]%d[/font_size]  [color=#dab776]%+d[/color]" % [
			String(ability).to_upper(), score, modifier])
		lines.append("[color=#9aa1ad]%s · %s[/color]" % [MenuStyle.text("ROLL_SOURCE_" + String(ability).to_upper()),
			(MenuStyle.text("SHEET_SAVE_PROFICIENT") if proficient else MenuStyle.text("SHEET_SAVE")) % save])
	return "\n".join(lines)

func _combat_text(actor: Dictionary) -> String:
	var breakdown: PackedStringArray = []
	for part: Dictionary in actor.get("ac_breakdown", []):
		breakdown.append("%s %d" % [_source_name(String(part["source"])), int(part["amount"])])
	var weapon: Dictionary = actor.get("weapon", {})
	var damage: String = String(weapon.get("damage_dice", ""))
	if int(weapon.get("damage_bonus", 0)) != 0:
		damage += "%+d" % int(weapon["damage_bonus"])
	var lines: PackedStringArray = [
		MenuStyle.text("SHEET_HP") % [int(actor.get("hp", 0)), int(actor.get("max_hp", 0))],
		MenuStyle.text("SHEET_AC") % int(actor.get("ac", 10)) + \
			("  [color=#9aa1ad](%s)[/color]" % " + ".join(breakdown) if not breakdown.is_empty() else ""),
		MenuStyle.text("SHEET_SPEED") % float(actor.get("speed_m", 9.0)),
		MenuStyle.text("SHEET_INITIATIVE") % Abilities.modifier(_score(actor, &"dex")),
		MenuStyle.text("SHEET_PROFICIENCY") % int(actor.get("proficiency_bonus", 2)),
		MenuStyle.text("SHEET_PASSIVE_PERCEPTION") % int(actor.get("passive_perception", 10)),
		MenuStyle.text("INV_STAT_ATTACK") % [MenuStyle.text(String(weapon.get("name_key", ""))),
			int(weapon.get("attack_bonus", 0)), damage, MenuStyle.text("DAMAGE_" + String(weapon.get("damage_type", "")).to_upper())],
	]
	return "\n".join(lines)

func _source_name(source: String) -> String:
	var item_key: String = "ITEM_" + source.to_upper()
	if ArmorRules.ARMOR.has(StringName(source)) and source != "none":
		for item_id: String in ItemCatalog.ids():
			if String(ItemCatalog.get_item(item_id).get("armor_id", "")) == source:
				return MenuStyle.text(String(ItemCatalog.get_item(item_id)["name_key"]))
	if source == "none":
		return MenuStyle.text("SHEET_UNARMORED")
	if source == "dex":
		return MenuStyle.text("ROLL_SOURCE_DEX")
	return MenuStyle.text(item_key)

func _feature_text(actor: Dictionary, definition: ClassDefinition, level: int) -> String:
	if definition == null:
		return ""
	var lines: PackedStringArray = []
	var active: bool = bool(actor.get("class_features_active", true))
	for feature: Dictionary in definition.features:
		var feature_level: int = int(feature["level"])
		if feature_level > level + 1:
			continue
		var key: String = String(feature.get("name_key", ""))
		var title: String = TranslationServer.translate(key)
		if title == key:
			title = String(feature.get("name", MenuStyle.text(key)))
		if feature_level <= level:
			lines.append("• " + title + ("" if active else "  [color=#9aa1ad]%s[/color]" % MenuStyle.text("SHEET_NOT_ACTIVE")))
		else:
			lines.append("[color=#6f7682]%s[/color]" % (MenuStyle.text("SHEET_NEXT_LEVEL") % [feature_level, title]))
	return "\n".join(lines)

func _skill_text(actor: Dictionary) -> String:
	var proficiency: int = int(actor.get("proficiency_bonus", 2))
	var proficient: Array = []
	for skill: Variant in actor.get("skill_proficiencies", []):
		proficient.append(String(skill))
	var names: Array[String] = []
	for skill: StringName in Abilities.SKILLS:
		names.append(String(skill))
	names.sort()
	var lines: PackedStringArray = []
	for skill: String in names:
		var ability: StringName = Abilities.SKILLS[StringName(skill)]
		var is_proficient: bool = skill in proficient
		var bonus: int = Abilities.modifier(_score(actor, ability)) + (proficiency if is_proficient else 0)
		var marker: String = "[color=#f3d38a]●[/color]" if is_proficient else "[color=#4a505c]○[/color]"
		lines.append("%s %s [color=#9aa1ad]%s[/color]  [color=#dab776]%+d[/color]" % [marker,
			MenuStyle.text("SHEET_SKILL_" + skill.to_upper()), String(ability).to_upper(), bonus])
	return "\n".join(lines)
