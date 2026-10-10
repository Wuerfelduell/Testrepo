extends Node
## Renders the Wizard targeting and casting Burning Hands in the real arena, and
## checks the visible contracts on the way (template, highlights, HUD preview,
## damage only when the fire arrives). Needs a display (Xvfb), see capture_spells.sh.

class Fixture extends Command:
	var actor_data: Dictionary
	func _init(data: Dictionary) -> void:
		actor_data = data
	func validate(_state: GameState) -> Error:
		return OK
	func apply(state: GameState) -> Dictionary:
		state.actors = actor_data.duplicate(true)
		state.mode = &"combat"
		state.pending = {}
		state.turn_order.assign(["hero", "guard", "bandit", "cultist"])
		state.turn_index = 0
		state.round_number = 1
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
	Rng.set_seed(505)
	arena = (load("res://scenes/arena/arena.tscn") as PackedScene).instantiate() as CombatArena
	add_child(arena)
	for frame: int in 600:
		await get_tree().physics_frame
		if arena.ready_for_input:
			break
	check(arena.ready_for_input, "Arena starts")
	check(CommandBus.submit(DebugSwapHeroCommand.new()) == OK, "F4 switch turns the Fighter into the Wizard")
	await _frames(4)
	var actors: Dictionary = Game.state.actors.duplicate(true)
	check(actors["hero"]["class_id"] == "wizard", "Hero is a Wizard")
	actors["hero"]["position"] = Vector3(0, 0, 1)
	actors["guard"]["position"] = Vector3(-0.7, 0, -1.9)
	actors["bandit"]["position"] = Vector3(0.9, 0, -2.7)
	actors["cultist"]["position"] = Vector3(0.5, 0, -7.5)
	CommandBus.submit(Fixture.new(actors))
	arena.hud.update_state(Game.state)
	await _frames(20)
	var aim: Vector3 = Vector3(0, 0, -3)
	check(arena.spell_targeting.begin("burning_hands"), "Burning Hands can be targeted")
	arena.get_viewport().warp_mouse(arena.camera_rig.camera.unproject_position(aim))
	for frame: int in 30:
		await get_tree().process_frame
		arena.spell_targeting.hover("", aim)
	var preview: Dictionary = arena.spell_targeting.last_preview
	check(bool(preview.get("legal", false)), "Cone preview is legal")
	var ids: Array = preview.get("targets", []).map(func(target: Dictionary) -> String: return String(target["id"]))
	ids.sort()
	check(ids == ["bandit", "guard"], "Guard and bandit are inside the cone, the cultist is not: %s" % str(ids))
	check(arena.spell_targeting._rings.size() == 2, "Both targets are highlighted")
	check(arena.hud._target_panel.visible and arena.hud._target_detail.text.contains("DC 12"), "HUD shows the DC: " + arena.hud._target_detail.text)
	await _capture("arena-spell-target.png")
	var hp_before: int = int(Game.state.actors["guard"]["hp"])
	var command: Command = arena.spell_targeting.click()
	check(command is CastSpellCommand, "Click casts the spell")
	var impact: float = float(Game.state.pending.get("impact_time", 0.0))
	check(impact > 0.0, "The cast is on the timeline")
	# Step the authoritative timeline by hand so slow software rendering cannot skip
	# past the moment the flames are in the air.
	arena.set_physics_process(false)
	while float(Game.state.pending.get("elapsed", 0.0)) < impact - 0.1:
		arena.simulation_step(1.0 / 60.0)
		await get_tree().process_frame
	check(int(Game.state.actors["guard"]["hp"]) == hp_before, "No damage before the fire arrives")
	await _frames(3)
	await _capture("arena-spell-cast.png")
	arena.set_physics_process(true)
	for frame: int in 120:
		await get_tree().physics_frame
		if Game.state.pending.is_empty():
			break
	check(int(Game.state.actors["guard"]["hp"]) < hp_before, "Fire damages the guard at impact (3d6, at least 1 on a save)")
	check(Game.state.actors["hero"]["spell_slots"] == [1], "One level 1 slot spent")
	print("SPELL_CAPTURE: failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().process_frame

func _capture(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	check(image.save_png(out_dir.path_join(file_name)) == OK, "Saved " + file_name)
