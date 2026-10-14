extends Node
## Prompt 08 in the real arena: the "Level up" button appears outside combat once the
## XP is there, the level-up screen takes every choice, Short rest spends Hit Point
## Dice through the dice popup. A Fighter and a Wizard go from level 1 to 5 through
## the screen. With a display (capture_levelup.sh) it also saves screenshots.

class Fixture extends Command:
	var actor_data: Dictionary
	func _init(data: Dictionary) -> void:
		actor_data = data
	func validate(_state: GameState) -> Error:
		return OK
	func apply(state: GameState) -> Dictionary:
		state.actors = actor_data.duplicate(true)
		state.mode = &"exploration"
		state.pending = {}
		state.turn_order.clear()
		state.turn_index = 0
		return {}

var out_dir: String = "build"
var failures: int = 0
var arena: CombatArena

func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out_dir = argument.trim_prefix("--out=")
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	Rng.set_seed(808)
	arena = (load("res://scenes/arena/arena.tscn") as PackedScene).instantiate() as CombatArena
	add_child(arena)
	for frame: int in 600:
		await get_tree().physics_frame
		if arena.ready_for_input:
			break
	check(arena.ready_for_input, "Arena starts")
	check(not arena.level_up_prompt.button.visible, "No level-up button without the XP")
	await _fighter()
	check(CommandBus.submit(DebugSwapHeroCommand.new()) == OK, "F4 switch turns the Fighter into the Wizard")
	await _frames(4)
	await _wizard()
	print("LEVELUP_CHECK: failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)

## Enemies far away (no combat, no rest block) and the hero with the given XP.
func _prepare(xp: int, hp_missing: int = 0) -> void:
	var actors: Dictionary = Game.state.actors.duplicate(true)
	var offset: float = 0.0
	for id: String in actors:
		if actors[id]["team"] == "enemy":
			actors[id]["position"] = Vector3(-40.0 - offset, 0, -40.0)
			offset += 3.0
	actors["hero"]["xp"] = xp
	actors["hero"]["position"] = Vector3(0, 0, 4)
	actors["hero"]["hp"] = int(actors["hero"]["max_hp"]) - hp_missing
	CommandBus.submit(Fixture.new(actors))
	arena.hud.update_state(Game.state)
	await _frames(6)

func _open_screen() -> LevelUpScreen:
	check(arena.level_up_prompt.button.visible, "Level-up button is shown at level %d" % int(Game.state.actors["hero"]["level"]))
	arena.level_up_prompt.open()
	await _frames(3)
	check(arena.level_up_prompt.is_open(), "Level-up screen opens")
	return arena.level_up_prompt.screen

func _confirm(screen: LevelUpScreen, expected_level: int) -> void:
	check(screen.is_confirmable(), "Level %d choices are complete: %s" % [expected_level, screen._reason.text])
	screen.confirm()
	await _frames(2)
	check(int(Game.state.actors["hero"]["level"]) == expected_level, "Hero reached level %d" % expected_level)
	await _wait_rolls()

func _wait_rolls() -> void:
	for frame: int in 30:
		await get_tree().process_frame
		if arena.hud.rolls_busy():
			arena.hud.dice_popup.skip()
			arena.hud.dice_popup.skip()
	check(not arena.hud.rolls_busy(), "Dice popup finished")

func _fighter() -> void:
	await _prepare(6500, 6)
	await _capture("levelup-button.png")
	var screen: LevelUpScreen = await _open_screen()
	await _capture("levelup-fighter-2.png")
	screen.choose_hp("roll")
	var popups: Array = []
	arena.hud.dice_popup.roll_started.connect(func(event: Dictionary) -> void: popups.append(event), CONNECT_ONE_SHOT)
	await _confirm(screen, 2)
	check(popups.size() == 1 and popups[0]["kind"] == "hit_points", "Rolled hit points play in the dice popup")
	check(Game.state.actors["hero"]["features"].has("action_surge"), "Level 2: Action Surge")
	screen = await _open_screen()
	await _confirm(screen, 3)
	screen = await _open_screen()
	check(not screen.is_confirmable(), "Level 4 waits for the ability points")
	screen.raise("str")
	screen.raise("str")
	await _frames(2)
	await _capture("levelup-fighter-4.png")
	await _confirm(screen, 4)
	check(ProgressionRules.score(Game.state.actors["hero"], "str") == 18, "STR 16 + 2")
	screen = await _open_screen()
	await _confirm(screen, 5)
	var fighter: Dictionary = Game.state.actors["hero"]
	check(fighter["features"].has("extra_attack") and int(fighter["proficiency_bonus"]) == 3, "Level 5: Extra Attack, proficiency +3")
	check(not arena.level_up_prompt.button.visible, "No button once the XP is used up")
	var hp_before: int = int(fighter["hp"])
	fighter = Game.state.actors["hero"]
	await _prepare(6500, 20)
	hp_before = int(Game.state.actors["hero"]["hp"])
	check(arena.rest_panel.button.visible and not arena.rest_panel.button.disabled, "Short rest is offered outside combat")
	arena.rest_panel.open_short_rest()
	await _frames(2)
	arena.rest_panel.set_hit_dice(2)
	await _frames(2)
	await _capture("rest-short.png")
	arena.rest_panel.confirm()
	await _frames(2)
	check(int(Game.state.actors["hero"]["hp"]) > hp_before, "Hit Point Dice healed the Fighter")
	check(int(Game.state.actors["hero"]["hit_dice"]["left"]) == 3, "Two of five Hit Point Dice spent")
	await _wait_rolls()
	# An enemy close by blocks the rest button.
	var actors: Dictionary = Game.state.actors.duplicate(true)
	for id: String in actors:
		if actors[id]["team"] == "enemy":
			actors[id]["position"] = Vector3(0, 0, -12)
			break
	CommandBus.submit(Fixture.new(actors))
	await _frames(3)
	check(arena.rest_panel.button.disabled, "Enemies nearby block the short rest")
	await _prepare(6500)

func _wizard() -> void:
	await _prepare(6500)
	var screen: LevelUpScreen = await _open_screen()
	check(not screen.is_confirmable(), "Scholar asks for a skill")
	screen.pick("expertise", "arcana")
	screen.pick("spellbook", "mage_armor")
	screen.pick("spellbook", "grease")
	await _confirm(screen, 2)
	screen = await _open_screen()
	screen.pick("spellbook", "shatter")
	screen.pick("spellbook", "misty_step")
	await _frames(2)
	await _capture("levelup-wizard-3.png")
	await _confirm(screen, 3)
	check("shatter" in Game.state.actors["hero"]["spells"], "Shatter is prepared")
	screen = await _open_screen()
	screen.choose_feat("skilled")
	for skill: String in ["stealth", "insight", "medicine"]:
		screen.pick("skills", skill)
	screen.pick("cantrips", "acid_splash")
	screen.pick("spellbook", "web")
	screen.pick("spellbook", "blur")
	await _confirm(screen, 4)
	screen = await _open_screen()
	screen.pick("spellbook", "fireball")
	screen.pick("spellbook", "haste")
	await _confirm(screen, 5)
	var wizard: Dictionary = Game.state.actors["hero"]
	check(wizard["spell_slots_max"] == [4, 3, 2], "Level 5 slots")
	check("fireball" in wizard["spells"] and "acid_splash" in wizard["spells"], "Fireball and Acid Splash on the hotbar")
	await _frames(4)
	check(arena.hud.hotbar_entries().has("spell:fireball"), "Hotbar shows Fireball")

func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().process_frame

func _capture(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _frames(2)
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	check(image.save_png(out_dir.path_join(file_name)) == OK, "Saved " + file_name)
