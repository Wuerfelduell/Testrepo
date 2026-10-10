class_name DicePopup
extends Control
## A FIFO of immutable roll descriptions. Neither animation nor skipping rolls RNG.

signal roll_started(event: Dictionary)
signal roll_finished(event: Dictionary)
signal rolls_finished()

var speed: float = 1.0
var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _elapsed: float = 0.0
var _settle: Array[Basis] = []
var _dice: Array[DiceMesh] = []
var _panel: PanelContainer
var _title: Label
var _values: Label
var _modifiers: Label
var _outcome: Label
var _hint: Label
var _viewport: SubViewport
var _viewport_container: SubViewportContainer
var _dice_root: Node3D
var _camera: Camera3D
var _style: StyleBoxFlat

func _ready() -> void:
	custom_minimum_size = Vector2(800, 390)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.025, 0.031, 0.052, 0.96)
	_style.border_color = Color("b99859")
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(18)
	_style.shadow_color = Color(0, 0, 0, 0.6)
	_style.shadow_size = 20
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_theme_stylebox_override("panel", _style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_title = _label(Vector2(20, 16), Vector2(760, 32), 22)
	_title.add_theme_color_override("font_color", Color("e7cca0"))
	_viewport_container = SubViewportContainer.new()
	_viewport_container.position = Vector2(48, 50)
	_viewport_container.size = Vector2(704, 170)
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_viewport_container)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(704, 170)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport_container.add_child(_viewport)
	_dice_root = Node3D.new()
	_viewport.add_child(_dice_root)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.8
	_camera.position = Vector3(0, 0, 6)
	_camera.current = true
	_viewport.add_child(_camera)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.light_energy = 2.0
	_viewport.add_child(light)
	var fill: OmniLight3D = OmniLight3D.new()
	fill.position = Vector3(2, 2, 4)
	fill.light_energy = 2.5
	fill.omni_range = 12
	_viewport.add_child(fill)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b5c8e8")
	environment.environment.ambient_light_energy = 0.5
	_viewport.add_child(environment)
	_values = _label(Vector2(20, 217), Vector2(760, 34), 23)
	_modifiers = _label(Vector2(24, 252), Vector2(752, 52), 18)
	_modifiers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_outcome = _label(Vector2(20, 310), Vector2(760, 42), 30)
	_hint = _label(Vector2(20, 358), Vector2(760, 24), 16)
	_hint.text = tr("COMBAT_ROLL_SKIP")
	_hint.modulate = Color("979dab")
	visible = false
	gui_input.connect(_on_gui_input)

func enqueue(event: Dictionary) -> void:
	_queue.append(event.duplicate(true))
	if _current.is_empty():
		_next()

func is_busy() -> bool:
	return not _current.is_empty() or not _queue.is_empty()

func skip() -> void:
	if _current.is_empty():
		return
	# A first click lands the dice so the result remains readable; a second advances.
	if _elapsed < 1.0:
		_elapsed = 1.05
		for die: DiceMesh in _dice:
			die.land()
		_reveal()
	else:
		_finish()

func _process(delta: float) -> void:
	if _current.is_empty():
		return
	_elapsed += delta * maxf(0.1, speed)
	var roll: Dictionary = _current.get("roll", {})
	var dramatic: bool = bool(roll.get("natural_20", false)) or bool(roll.get("natural_1", false))
	if _elapsed < 0.65:
		for index: int in range(_dice.size()):
			_dice[index].tumble(_elapsed, float(index) * 1.8)
	elif _elapsed < 1.0:
		if _settle.is_empty():
			for die: DiceMesh in _dice:
				_settle.append(die.basis.orthonormalized())
		var weight: float = smoothstep(0.65, 1.0, _elapsed)
		for index: int in range(_dice.size()):
			_dice[index].basis = _settle[index].slerp(_dice[index].landing_basis, weight)
			_dice[index].position.y = lerpf(_dice[index].position.y, 0.0, weight)
	else:
		for die: DiceMesh in _dice:
			die.land()
		_reveal()
		if dramatic:
			_style.shadow_size = int(18.0 + 10.0 * absf(sin(_elapsed * 5.0)))
	if _elapsed >= (2.4 if dramatic else 1.9):
		_finish()

func _next() -> void:
	if _queue.is_empty():
		_current.clear()
		visible = false
		rolls_finished.emit()
		return
	_current = _queue.pop_front()
	_elapsed = 0.0
	_settle.clear()
	for die: DiceMesh in _dice:
		_dice_root.remove_child(die)
		die.queue_free()
	_dice.clear()
	visible = true
	var roll: Dictionary = _current.get("roll", {})
	var kind: String = String(_current.get("kind", "attack"))
	var actor_name: String = tr(String(_current.get("actor_name_key", "COMBAT_UNKNOWN_ACTOR")))
	_title.text = tr("COMBAT_ROLL_TITLE") % [actor_name, String(_current.get("title_kind", tr("COMBAT_ROLL_" + kind.to_upper())))]
	_style.border_color = Color("b99859")
	_style.shadow_color = Color(0, 0, 0, 0.6)
	_style.shadow_size = 20
	_outcome.text = ""
	_modifiers.text = ""
	_values.text = tr("COMBAT_ROLLING")
	var groups: Array = roll.get("groups", [])
	for group_variant: Variant in groups:
		var group: Dictionary = group_variant as Dictionary
		if int(group.get("sides", 0)) != 20:
			continue
		var values: Array = group.get("values", [])
		var kept: Array = group.get("kept_indices", [])
		for index: int in range(values.size()):
			var die: DiceMesh = DiceMesh.new()
			_dice_root.add_child(die)
			die.configure(int(values[index]), not kept.has(index))
			_dice.append(die)
	for index: int in range(_dice.size()):
		_dice[index].position.x = (float(index) - float(_dice.size() - 1) * 0.5) * 2.6
	_camera.size = maxf(2.8, float(_dice.size()) * 0.7)
	_viewport_container.visible = not _dice.is_empty()
	if _dice.is_empty():
		# Non-d20 groups retain every rolled value, including doubled critical dice.
		_values.position.y = 100
		_values.size.y = 130
		_values.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		_values.position.y = 217
		_values.size.y = 34
	roll_started.emit(_current.duplicate(true))

func _reveal() -> void:
	var roll: Dictionary = _current.get("roll", {})
	var group_texts: PackedStringArray = []
	var groups: Array = roll.get("groups", [])
	for group_variant: Variant in groups:
		var group: Dictionary = group_variant as Dictionary
		var values: Array = group.get("values", [])
		var kept: Array = group.get("kept_indices", [])
		var die_texts: PackedStringArray = []
		for index: int in range(values.size()):
			var value_text: String = str(values[index])
			if not kept.has(index):
				value_text = tr("COMBAT_DIE_DROPPED") % value_text
			die_texts.append(value_text)
		group_texts.append(tr("COMBAT_DICE_GROUP") % [str(group.get("sides", 20)), " · ".join(die_texts)])
	_values.text = "     ".join(group_texts)
	var modifier_texts: PackedStringArray = []
	var modifiers: Array = roll.get("modifiers", [])
	for modifier_variant: Variant in modifiers:
		var modifier: Dictionary = modifier_variant as Dictionary
		modifier_texts.append("%+d %s" % [int(modifier.get("amount", 0)), source_name(String(modifier.get("source", "")))])
	var mode: String = String(roll.get("mode", "normal"))
	if mode != "normal":
		modifier_texts.append(tr("COMBAT_" + mode.to_upper()))
	for source_variant: Variant in roll.get("advantage_sources", []):
		modifier_texts.append(tr("COMBAT_ADVANTAGE_REASON") % source_name(String(source_variant)))
	for source_variant: Variant in roll.get("disadvantage_sources", []):
		modifier_texts.append(tr("COMBAT_DISADVANTAGE_REASON") % source_name(String(source_variant)))
	_modifiers.text = "   ".join(modifier_texts)
	var kind: String = String(_current.get("kind", "attack"))
	var total: int = int(roll.get("total", 0))
	if kind == "attack":
		var result_key: String = "COMBAT_HIT" if bool(_current.get("hit", false)) else "COMBAT_MISS"
		if bool(roll.get("natural_20", false)):
			result_key = "COMBAT_CRITICAL"
			_style.border_color = Color("ffda6d")
			_style.shadow_color = Color(0.96, 0.65, 0.1, 0.55)
		elif bool(roll.get("natural_1", false)):
			result_key = "COMBAT_FUMBLE"
			_style.border_color = Color("fa6761")
			_style.shadow_color = Color(0.9, 0.1, 0.1, 0.5)
		_outcome.text = tr("COMBAT_ROLL_VS_AC") % [total, int(_current.get("armor_class", 10)), tr(result_key)]
	elif kind == "save":
		# Saving throws read like attacks: the target's roll against the caster's DC.
		var saved: bool = bool(_current.get("success", false))
		if bool(_current.get("automatic", false)):
			_outcome.text = tr("COMBAT_SAVE_AUTOMATIC") % source_name(String(_current.get("reason", "unconscious")))
		else:
			_outcome.text = tr("COMBAT_ROLL_VS_DC") % [total, int(_current.get("dc", 10)), tr("COMBAT_SAVE_SUCCESS" if saved else "COMBAT_SAVE_FAIL")]
		_style.border_color = Color("9ed5ac") if saved else Color("ed867d")
	else:
		_outcome.text = tr("COMBAT_ROLL_TOTAL") % total
	_outcome.add_theme_color_override("font_color", _style.border_color)

func _finish() -> void:
	var finished: Dictionary = _current.duplicate(true)
	_current.clear()
	roll_finished.emit(finished)
	_next()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		skip()
		accept_event()

func _label(at: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label: Label = Label.new()
	label.position = at
	label.size = dimensions
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("f2f0e8"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

static func source_name(source: String) -> String:
	# Rules use semantic source ids; translation keys form the presentation boundary.
	var key: String = "ROLL_SOURCE_" + source.to_upper().replace("-", "_").replace(" ", "_")
	return TranslationServer.translate(key)
