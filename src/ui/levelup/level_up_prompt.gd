class_name LevelUpPrompt
extends CanvasLayer
## The "Level up" button: shown outside combat once the hero has the XP for the next
## level (never forced, never mid-combat). Opens the LevelUpScreen.

signal command_requested(command: Command)

const BUTTON_RECT: Rect2 = Rect2(1418, 806, 470, 64)

var hud: CombatHUD
var actor_id: String = "hero"
var button: Button
var screen: LevelUpScreen
var _pulse: float = 0.0

func _ready() -> void:
	layer = 6
	var root: Control = MenuTheme.design_root(self)
	button = MenuTheme.button(root, BUTTON_RECT, tr("LEVELUP_BUTTON"), 26)
	button.add_theme_color_override("font_color", MenuTheme.GOLD)
	button.pressed.connect(open)
	button.visible = false
	EventBus.state_changed.connect(refresh)
	refresh()

func available() -> bool:
	var state: GameState = Game.state
	var actor: Dictionary = state.actors.get(actor_id, {})
	return state.mode == &"exploration" and state.pending.is_empty() and ProgressionRules.can_level_up(actor)

func refresh() -> void:
	if button == null:
		return
	var actor: Dictionary = Game.state.actors.get(actor_id, {})
	button.visible = available() and screen == null
	if button.visible:
		button.text = tr("LEVELUP_BUTTON") % (int(actor.get("level", 1)) + 1)

func _process(delta: float) -> void:
	if button == null or not button.visible:
		return
	_pulse += delta
	button.modulate = Color(1, 1, 1).lerp(Color(1.25, 1.12, 0.85), 0.5 + 0.5 * sin(_pulse * 3.0))
	button.disabled = hud != null and hud.rolls_busy()

func open() -> void:
	if not available() or screen != null:
		return
	screen = LevelUpScreen.new()
	add_child(screen)
	screen.setup(Game.state.actors[actor_id], actor_id)
	screen.command_requested.connect(func(command: Command) -> void: command_requested.emit(command))
	screen.closed.connect(func() -> void:
		screen = null
		refresh.call_deferred())
	refresh()

func is_open() -> bool:
	return screen != null
