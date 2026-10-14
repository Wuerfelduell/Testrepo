extends Node
## Campaign package K4 on the real scenes: a companion on the Torplatz joins through the
## dialogue window, appears next to the hero, takes commands out of combat (portrait or Tab),
## the party walks together and travels into the crypt, and in combat the game waits for the
## player on the companion's turn instead of letting the AI play it.
var checks: int = 0
var failed: bool = false
var level: DungeonLevel
var events: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error(message)

func _run() -> void:
	var game: Node = get_tree().root.get_node("Game")
	var bus: Node = get_tree().root.get_node("CommandBus")
	get_tree().root.get_node("Rng").set_seed(6142)
	var hero: Dictionary = HeroKit.create(&"fighter")
	hero["hp"] = 160
	hero["max_hp"] = 160
	bus.submit(ResetRunCommand.new())
	check(bus.submit(LevelSetupCommand.new(hero, TownLevel.TORVIERTEL_PATH)) == OK, "Torviertel setup accepted")
	level = (load("res://scenes/levels/torviertel/torviertel.tscn") as PackedScene).instantiate() as DungeonLevel
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	level = await _wait_for_level(null, true)
	check(level != null, "Torviertel initializes fully")
	level.set_physics_process(false)
	bus.command_applied.connect(func(_command: Command, result: Dictionary) -> void:
		for event: Dictionary in result.get("events", []):
			events.append(event))
	for id: String in PartyRules.definitions():
		check(level.hook_views.has(id), id + " waits on the Torplatz")
	# Kael's duel: a non-lethal fight against his own fighter sheet. A weak hero loses it.
	check(bus.submit(MoveCommand.new("hero", Vector3(-9.0, 0, -11.5))) == OK, "Walk up to Kael")
	await _settle()
	game.state.actors["hero"]["hp"] = 3
	check(level.interact("companion_kael"), "Kael answers")
	for slot: int in [2, 0, 0]:
		level.dialogue.choice_buttons[slot].pressed.emit()
		await get_tree().process_frame
	await get_tree().process_frame
	check(game.state.mode == &"combat" and game.state.actors.has("kael_duelist"), "The duel starts")
	var duel_steps: int = 0
	while duel_steps < 3000 and game.state.mode == &"combat":
		if game.state.pending.is_empty() and game.state.current_actor_id() == "hero":
			while level.hud.dice_popup.is_busy():
				level.hud.dice_popup.skip()
				await get_tree().process_frame
			level._action_requested("end_turn")
		level.simulation_step(0.1, true)
		duel_steps += 1
		if duel_steps % 10 == 0:
			await get_tree().process_frame
	check(game.state.mode == &"exploration" and String(game.state.world["flags"].get("kael_duel_fight", "")) == "lost", "Kael wins the duel")
	check(int(game.state.actors["hero"]["hp"]) >= 1 and not game.state.actors.has("kael_duelist"), "Nobody died; Kael is back at his spot")
	await get_tree().process_frame
	await get_tree().process_frame
	check(level.interact("companion_kael") and game.state.world["conversation"]["node"] == "duel_lost", "Kael talks about the duel")
	check(bus.submit(DialogueEndCommand.new()) == OK, "Walk away from Kael")
	await get_tree().process_frame
	game.state.actors["hero"]["hp"] = 160
	while level.hud.dice_popup.is_busy():
		level.hud.dice_popup.skip()
		await get_tree().process_frame
	# Recruit through the real dialogue window.
	check(level.interact("companion_lyra"), "Lyra answers")
	check(level.dialogue.is_open() and level.dialogue.speaker_label.text == "Lyra Vossen", "Her conversation opens")
	# "I'm looking for someone who knows magic" -> "You can come along" -> accept her condition.
	for slot: int in [5, 0, 0]:
		level.dialogue.choice_buttons[slot].pressed.emit()
		await get_tree().process_frame
	check(PartyRules.members(game.state) == (["hero", "companion_lyra"] as Array[String]), "Lyra joins the party")
	check(level.actors.has("companion_lyra"), "The companion appears in the world")
	check(level.dialogue.is_open() and level.dialogue.choice_buttons.size() == 1, "The joined line ends the conversation")
	level.dialogue.choice_buttons[0].pressed.emit()
	await get_tree().process_frame
	check(not level.dialogue.is_open() and not game.state.world.has("conversation"), "The conversation ends")
	await get_tree().process_frame
	await get_tree().process_frame
	check(not level.hook_views.has("companion_lyra"), "The hook figure is gone once they joined")
	var spot: Vector3 = game.state.actors["companion_lyra"]["position"]
	check(not level.space.query_path(spot, Vector3(0, 0, 8)).is_empty(), "The companion stands on walkable ground")
	# Right-click on her portrait: the camp talk; "Show me your gear" opens her inventory.
	var right: InputEventMouseButton = InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	level.hud._party_clicked(right, "companion_lyra")
	check(level.dialogue.is_open() and String(game.state.world["conversation"]["id"]) == "camp_lyra", "Right-click opens Lyra's camp talk")
	level.dialogue.choice_buttons[3].pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not level.dialogue.is_open() and level.menus.inventory.visible and level.menus.actor_id == "companion_lyra", "Her gear opens")
	level.menus.close_all()
	level.select_member("hero")
	# Portrait click / Tab hand the commands to the companion.
	level.hud.actor_selected.emit("companion_lyra")
	check(level.controlled_id() == "companion_lyra", "A portrait click takes command of the companion")
	check(level.menus.actor_id == "companion_lyra" and level.spell_targeting.caster_id == "companion_lyra", "Windows and spells follow the commanded member")
	var tab: InputEventAction = InputEventAction.new()
	tab.action = "party_next"
	tab.pressed = true
	level._unhandled_input(tab)
	check(level.controlled_id() == "hero", "Tab cycles back to the hero")
	level.select_member("companion_lyra")
	# The companion leads, the hero follows.
	var lead_to: Vector3 = Vector3(1.0, 0, 6.0)
	check(bus.submit(MoveCommand.new(level.controlled_id(), lead_to)) == OK, "The companion walks where the player clicks")
	await _settle()
	var state: GameState = game.state
	check((state.actors["companion_lyra"]["position"] as Vector3).distance_to(lead_to) < 0.2, "The companion arrives")
	var gap: float = (state.actors["hero"]["position"] as Vector3).distance_to(lead_to)
	check(gap > 0.8 and gap < 4.0, "The hero follows the companion (%.2f m behind)" % gap)
	# The companion leads the party to the crypt entrance; the whole party travels.
	check(bus.submit(MoveCommand.new("companion_lyra", Vector3(-19.0, 0, -14.0))) == OK, "Walk to the crypt entrance")
	await _settle()
	check(level.interact("torviertel_crypt_entrance"), "The crypt entrance answers")
	var crypt: DungeonLevel = await _wait_for_level(level)
	check(crypt != null and String(game.state.world["level"]) == "crypt", "The party entered the crypt")
	level = crypt
	level.set_physics_process(false)
	check(level.actors.has("companion_lyra") and PartyRules.members(game.state).size() == 2, "The companion came along")
	check(PartyRegroupCommand.stranded(game.state).is_empty(), "Everyone stands on walkable ground in the crypt")
	# Walk into the hall until the patrol notices the party.
	level.select_member("hero")
	check(bus.submit(MoveCommand.new("hero", Vector3(0, 0, 6.0))) == OK, "Hero walks into the hall")
	var steps: int = 0
	while steps < 2000 and game.state.mode != &"combat":
		level.simulation_step(0.1, true)
		steps += 1
	state = game.state
	check(state.mode == &"combat" and "companion_lyra" in state.turn_order, "The companion rolls initiative")
	# Enemies act by AI; the hero passes. On the companion's turn the game waits for the player.
	var waited: bool = false
	steps = 0
	while steps < 3000 and game.state.mode == &"combat" and not waited:
		state = game.state
		var active: String = state.current_actor_id()
		if state.pending.is_empty() and PartyRules.is_member(state, active):
			while level.hud.dice_popup.is_busy():
				level.hud.dice_popup.skip()
				await get_tree().process_frame
			if active == "hero":
				level._action_requested("end_turn")
			else:
				var before: String = JSON.stringify(JSON.from_native(state.to_dict()))
				for index: int in 5:
					level.simulation_step(0.1, true)
				waited = JSON.stringify(JSON.from_native(game.state.to_dict())) == before
				check(level.controlled_id() == "companion_lyra" and level._can_control(), "The player commands the companion on its turn")
				check(level.hud.controlled_id == "companion_lyra", "The HUD shows the companion's bars and actions")
				level._action_requested("end_turn")
				check(game.state.current_actor_id() != "companion_lyra", "End turn passes the companion's turn")
		level.simulation_step(0.1, true)
		steps += 1
		if steps % 10 == 0:
			await get_tree().process_frame
	check(waited, "No AI plays the companion's turn")
	print("PARTY_CHECKS: %d, failed: %s, steps %d" % [checks, failed, steps])
	level.queue_free()
	await get_tree().process_frame
	bus.submit(ResetRunCommand.new())
	get_tree().quit(1 if failed else 0)

## Runs the timeline until the current move (leader and followers) is over.
func _settle() -> void:
	var game: Node = get_tree().root.get_node("Game")
	var steps: int = 0
	while not game.state.pending.is_empty() and steps < 600:
		level.simulation_step(0.1, true)
		steps += 1
		if steps % 20 == 0:
			await get_tree().process_frame

## Waits until the current scene is a ready level; with `old` given, a different one.
func _wait_for_level(old: DungeonLevel, first: bool = false) -> DungeonLevel:
	for frame: int in range(600):
		await get_tree().physics_frame
		var current: Node = get_tree().current_scene
		if current is DungeonLevel and (current as DungeonLevel).ready_for_input and (first or current != old):
			return current as DungeonLevel
	return null
