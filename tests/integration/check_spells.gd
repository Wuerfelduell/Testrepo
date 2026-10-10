extends Node
## Real arena, navigation and AI: an auto-played Wizard fights the whole encounter
## with spells (prompt 05). Headless: godot --headless tests/integration/check_spells.tscn

var checks: int = 0
var failed: bool = false

func _ready() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error(message)

func _run() -> void:
	Rng.set_seed(9021)
	var arena: CombatArena = (load("res://scenes/arena/arena.tscn") as PackedScene).instantiate() as CombatArena
	get_tree().root.add_child(arena)
	for frame: int in 240:
		await get_tree().physics_frame
		if arena.ready_for_input:
			break
	check(arena.ready_for_input, "Arena must initialize fully")
	check(CommandBus.submit(DebugSwapHeroCommand.new()) == OK, "F4 swaps to the Wizard")
	await get_tree().process_frame
	var hero: Dictionary = Game.state.actors["hero"]
	check(hero["class_id"] == "wizard" and hero["spell_slots"] == [2], "Wizard with two level 1 slots")
	check(arena.hud.hotbar_entries().size() == 6, "Six spell buttons in the hotbar")
	check(CommandBus.submit(DebugSwapHeroCommand.new()) == OK and Game.state.actors["hero"]["class_id"] == "fighter", "F4 swaps back")
	check(arena.hud.hotbar_entries() == ["feature:second_wind"], "Fighter shows Second Wind")
	CommandBus.submit(DebugSwapHeroCommand.new())
	await get_tree().process_frame
	# Saving throws read like attacks in the dice popup: the target's roll vs the DC.
	arena.hud.consume_events([{"type": "roll", "kind": "save", "actor_id": "guard", "target_id": "guard",
		"caster_id": "hero", "ability": "dex", "dc": 12, "success": false, "roll": {
			"groups": [{"sides": 20, "values": [7], "kept_indices": [0]}],
			"modifiers": [{"amount": 1, "source": "dex"}], "total": 8}}])
	arena.hud.dice_popup.skip()
	check(arena.hud.dice_popup._outcome.text == tr("COMBAT_ROLL_VS_DC") % [8, 12, tr("COMBAT_SAVE_FAIL")],
		"Save shows roll vs DC: " + arena.hud.dice_popup._outcome.text)
	check(arena.hud.dice_popup._title.text.contains(tr("COMBAT_ROLL_SAVE") % tr("ABILITY_DEX")), "Save title names the ability")
	arena.hud.dice_popup.skip()
	arena.set_physics_process(false)
	arena.auto_play = true
	var events: Array[Dictionary] = []
	var listener: Callable = func(_command: Command, result: Dictionary) -> void:
		for event: Dictionary in result.get("events", []):
			events.append(event)
	CommandBus.command_applied.connect(listener)
	check(CommandBus.submit(MoveCommand.new("hero", Vector3(0, 0, 2))) == OK, "Exploration move accepted")
	var combat_seen: bool = false
	var steps: int = 0
	while steps < 5000:
		arena.simulation_step(0.1, true)
		var state: GameState = Game.state
		combat_seen = combat_seen or state.mode == &"combat"
		if combat_seen and state.mode != &"combat" and state.pending.is_empty():
			break
		steps += 1
		if steps % 10 == 0:
			await get_tree().process_frame
	CommandBus.command_applied.disconnect(listener)
	check(combat_seen, "Combat starts")
	check(steps < 5000, "The Wizard's encounter finishes without stalling")
	var casts: Dictionary = {}
	for event: Dictionary in events:
		if event.get("type") == "start_spell":
			casts[String(event["spell_id"])] = int(casts.get(String(event["spell_id"]), 0)) + 1
	check(not casts.is_empty(), "The auto-played Wizard casts spells")
	check(Game.state.mode == &"exploration" or Game.state.mode == &"defeat", "Encounter terminal mode")
	print("SPELL_ARENA: mode=%s steps=%d casts=%s" % [Game.state.mode, steps, str(casts)])
	if failed:
		get_tree().quit(1)
		return
	print("SPELL_ARENA_CHECKS_PASSED: %d" % checks)
	get_tree().quit(0)
