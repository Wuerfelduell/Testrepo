class_name RestPanel
extends CanvasLayer
## "Short rest" outside combat: choose how many Hit Point Dice to spend and, for a
## Wizard, which slots Arcane Recovery brings back. The rolls play in the dice popup.
## open_long_rest() is the confirm dialog a rest point (package 10) can show.

signal command_requested(command: Command)

const BUTTON_RECT: Rect2 = Rect2(1418, 882, 470, 64)
const DIALOG_RECT: Rect2 = Rect2(560, 220, 800, 600)

var hud: CombatHUD
var actor_id: String = "hero"
var button: Button
var dialog: Panel
var _root: Control
var _hit_dice: int = 0
var _arcane: Array[int] = []
var _long: bool = false
var _dice_label: Label
var _detail: Label
var _reason: Label
var _confirm: Button
var _slot_buttons: Array[Button] = []
var _toast: Label
var _toast_time: float = 0.0
var _rest_reason: String = ""

func _ready() -> void:
	layer = 6
	_root = MenuTheme.design_root(self)
	button = MenuTheme.button(_root, BUTTON_RECT, tr("REST_SHORT_BUTTON"), 24)
	button.pressed.connect(open_short_rest)
	_toast = MenuTheme.label(_root, Rect2(560, 150, 800, 50), "", 24, MenuTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	EventBus.state_changed.connect(refresh)
	CommandBus.command_applied.connect(_on_command)
	refresh()

func _actor() -> Dictionary:
	return Game.state.actors.get(actor_id, {})

func refresh() -> void:
	if button == null:
		return
	var state: GameState = Game.state
	button.visible = state.mode == &"exploration" and dialog == null and not _actor().is_empty() and \
		ClassFeatures.is_active_class(_actor())
	var reason: String = RestRules.rest_reason(state, actor_id)
	_rest_reason = reason
	button.disabled = not reason.is_empty() or (hud != null and hud.rolls_busy())
	button.tooltip_text = tr(reason) if not reason.is_empty() else tr("REST_SHORT_HINT")
	if dialog != null:
		_update_dialog()

func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	if button != null and button.visible and hud != null:
		button.disabled = hud.rolls_busy() or not _rest_reason.is_empty()

func open_short_rest() -> void:
	_open(false)

func open_long_rest() -> void:
	_open(true)

func _open(long_rest: bool) -> void:
	if dialog != null or not RestRules.rest_reason(Game.state, actor_id).is_empty():
		return
	_long = long_rest
	var actor: Dictionary = _actor()
	var missing: int = int(actor.get("max_hp", 0)) - int(actor.get("hp", 0))
	var die: int = ProgressionRules.hit_die(actor)
	# Suggest enough dice to cover the missing hit points on average.
	_hit_dice = 0 if long_rest else mini(RestRules.hit_dice_left(actor), ceili(float(missing) / maxf(1.0, die / 2.0 + 0.5 + Abilities.modifier(ProgressionRules.score(actor, "con")))))
	_arcane.clear()
	dialog = MenuTheme.panel(_root, DIALOG_RECT)
	MenuTheme.label(dialog, Rect2(0, 22, DIALOG_RECT.size.x, 50), tr("REST_LONG_TITLE" if long_rest else "REST_SHORT_TITLE"),
		38, MenuTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_detail = MenuTheme.label(dialog, Rect2(50, 90, 700, 120), "", 21)
	if not long_rest:
		_dice_label = MenuTheme.label(dialog, Rect2(50, 220, 460, 60), "", 24)
		var minus: Button = MenuTheme.button(dialog, Rect2(530, 220, 90, 60), "−", 30)
		minus.pressed.connect(func() -> void: set_hit_dice(_hit_dice - 1))
		var plus: Button = MenuTheme.button(dialog, Rect2(640, 220, 90, 60), "+", 30)
		plus.pressed.connect(func() -> void: set_hit_dice(_hit_dice + 1))
		if RestRules.arcane_recovery_available(actor):
			MenuTheme.label(dialog, Rect2(50, 300, 700, 40), tr("REST_ARCANE_TITLE") % SpellRules.arcane_recovery_budget(int(actor.get("level", 1))), 22, MenuTheme.GOLD)
			var maximum: Array = actor.get("spell_slots_max", [])
			for index: int in mini(maximum.size(), 5):
				var slot_button: Button = MenuTheme.toggle(dialog, Rect2(50 + index * 140, 345, 130, 54), tr("REST_ARCANE_SLOT") % (index + 1), 20)
				slot_button.pressed.connect(_toggle_slot.bind(index + 1))
				_slot_buttons.append(slot_button)
	_reason = MenuTheme.label(dialog, Rect2(50, 420, 700, 60), "", 20, MenuTheme.RED)
	var cancel: Button = MenuTheme.button(dialog, Rect2(170, 500, 220, 66), tr("REST_CANCEL"))
	cancel.pressed.connect(close)
	_confirm = MenuTheme.button(dialog, Rect2(410, 500, 220, 66), tr("REST_CONFIRM"), 26)
	_confirm.pressed.connect(confirm)
	refresh()

func set_hit_dice(value: int) -> void:
	_hit_dice = clampi(value, 0, RestRules.hit_dice_left(_actor()))
	_update_dialog()

## Arcane Recovery: each toggle adds one slot of that level; toggling off removes it.
func _toggle_slot(slot_level: int) -> void:
	if slot_level in _arcane:
		_arcane.erase(slot_level)
	else:
		_arcane.append(slot_level)
	_update_dialog()

func _update_dialog() -> void:
	var actor: Dictionary = _actor()
	if dialog == null or actor.is_empty():
		return
	var dice: Dictionary = actor["hit_dice"] if actor.get("hit_dice") is Dictionary else {"left": RestRules.hit_dice_left(actor), "max": int(actor.get("level", 1)), "die": ProgressionRules.hit_die(actor)}
	var lines: PackedStringArray = [tr("REST_HP") % [int(actor.get("hp", 0)), int(actor.get("max_hp", 0))]]
	if _long:
		lines.append(tr("REST_LONG_DETAIL"))
	else:
		lines.append(tr("REST_SHORT_DETAIL"))
		_dice_label.text = tr("REST_HIT_DICE") % [_hit_dice, int(dice["left"]), int(dice["die"])]
	_detail.text = "\n".join(lines)
	for index: int in _slot_buttons.size():
		_slot_buttons[index].set_pressed_no_signal((index + 1) in _arcane)
	var reason: String = _command_reason()
	_reason.text = "" if reason.is_empty() else tr(reason)
	_confirm.disabled = not reason.is_empty()

func _command_reason() -> String:
	if _long:
		return RestRules.long_rest_reason(Game.state, actor_id, [])
	return RestRules.short_rest_reason(Game.state, actor_id, _hit_dice, _arcane, [])

func confirm() -> void:
	if not _command_reason().is_empty():
		return
	var command: Command = LongRestCommand.new(actor_id) if _long else ShortRestCommand.new(actor_id, _hit_dice, _arcane)
	close()
	command_requested.emit(command)

func close() -> void:
	if dialog != null:
		dialog.queue_free()
		dialog = null
	_slot_buttons.clear()
	refresh.call_deferred()

func is_open() -> bool:
	return dialog != null

func _on_command(_command: Command, result: Dictionary) -> void:
	for event: Variant in result.get("events", []):
		if event is Dictionary and event.get("type") == "rest" and String(event.get("actor_id", "")) == actor_id:
			_toast.text = tr("REST_DONE_LONG" if event.get("rest") == "long" else "REST_DONE_SHORT") % int(event.get("healed", 0))
			_toast_time = 3.5
		elif event is Dictionary and event.get("type") == "level_up" and String(event.get("actor_id", "")) == actor_id:
			_toast.text = tr("LEVELUP_DONE") % [int(event.get("level", 1)), int(event.get("hp_gained", 0))]
			_toast_time = 3.5
