class_name CombatArena
extends Node3D
## Scene-side orchestration only. All state changes, including animation impacts,
## pass through CommandBus; geometry and presentation never decide the dice.

@onready var dungeon: ArenaBuilder = $Dungeon
var space: ArenaSpace
var camera_rig: CombatCamera
var hud: CombatHUD
var director: AIDirector
var actors: Dictionary = {}
var path_display: MeshInstance3D
var hovered_actor: String = ""
var hovered_ground: Vector3 = Vector3.INF
var ready_for_input: bool = false
var _ai_delay: float = 0.0
var _preview_time: float = 0.0
var _followed_actor: String = ""
var _capture_frames: int = -1
var _capture_path: String = ""
var _capture_combat: bool = false
var auto_play: bool = false
var _critical_focus: float = 0.0
var _attack_mode: bool = false

func _ready() -> void:
	camera_rig = CombatCamera.new()
	add_child(camera_rig)
	hud = CombatHUD.new()
	add_child(hud)
	hud.action_requested.connect(_action_requested)
	director = AIDirector.new()
	path_display = MeshInstance3D.new()
	add_child(path_display)
	space = ArenaSpace.new()
	space.world = self
	space.map = get_world_3d().navigation_map
	CombatSpace.active = space
	if dungeon.navigation.navigation_mesh == null:
		push_error("Arena navigation is missing; run tests/integration/bake_arena.gd")
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(space.map)
	CommandBus.command_applied.connect(_command_applied)
	CommandBus.command_rejected.connect(_command_rejected)
	if Game.state.actors.is_empty():
		if CommandBus.submit(SetupArenaCommand.new()) != OK:
			return
	for id: String in Game.state.actors:
		var actor: CombatActor = CombatActor.new()
		add_child(actor)
		actor.setup_actor(Game.state.actors[id])
		actors[id] = actor
	camera_rig.follow(Game.state.actors["hero"]["position"])
	hud.update_state(Game.state)
	ready_for_input = true
	# Parse before acting: capture behavior must not depend on argument ordering.
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--arena-capture="):
			_capture_path = argument.trim_prefix("--arena-capture=")
		elif argument == "--arena-capture-combat":
			_capture_combat = true
	if not _capture_path.is_empty():
		if _capture_combat:
			# Wait for an actual command-produced roll, independent of rendering speed.
			hud.dice_popup.roll_started.connect(_hold_capture_roll, CONNECT_ONE_SHOT)
			Rng.set_seed(6142)
			if CommandBus.submit(MoveCommand.new("hero", Vector3(0, 0, 2))) != OK:
				push_error("Combat capture could not begin the exploration move")
				get_tree().quit(1)
		else:
			# First follow already snaps the camera. Allow assets and both viewports
			# to render without waiting a minute on software-rendered CI hosts.
			_capture_frames = 8

func _exit_tree() -> void:
	if CombatSpace.active == space:
		CombatSpace.active = null

func _physics_process(delta: float) -> void:
	if ready_for_input:
		_critical_focus = maxf(0.0, _critical_focus - delta)
		simulation_step(delta * (0.25 if _critical_focus > 0.0 else 1.0))

func simulation_step(delta: float, fast: bool = false) -> void:
	var state: GameState = Game.state
	if state.mode == &"defeat":
		return
	if not state.pending.is_empty():
		CommandBus.submit(AdvanceCombatCommand.new(minf(delta, 0.1)))
		state = Game.state
	if state.mode == &"exploration":
		for id: String in state.actors:
			var enemy: Dictionary = state.actors[id]
			if enemy["team"] != "enemy" or int(enemy["hp"]) <= 0:
				continue
			var hero: Dictionary = state.actors["hero"]
			if (enemy["position"] as Vector3).distance_to(hero["position"]) <= 12.0 and space.visible(enemy["position"], hero["position"]):
				CommandBus.submit(StartCombatCommand.new())
				state = Game.state
				break
	if not state.pending.is_empty() or state.mode != &"combat":
		return
	if not fast and hud.rolls_busy():
		return
	var active: String = state.current_actor_id()
	if active.is_empty():
		return
	if state.actors[active]["team"] == "hero" and not auto_play:
		return
	_ai_delay -= delta
	if not fast and _ai_delay > 0.0:
		return
	var command: Command
	if state.actors[active]["team"] == "hero":
		command = UtilityAI.choose(state, active, dungeon.tactical_points)
	else:
		command = director.decide(state, dungeon.tactical_points)
		hud.set_ai_options(director.last_candidates)
	if command != null:
		var result: Error = CommandBus.submit(command)
		if result != OK:
			# A stale geometry candidate cannot bypass validation or stall the turn.
			CommandBus.submit(EndTurnCommand.new(active))
	_ai_delay = 0.45

func _process(delta: float) -> void:
	if not ready_for_input:
		return
	var state: GameState = Game.state
	for id: String in actors:
		var actor: CombatActor = actors[id]
		actor.update_actor(state.actors[id], state.pending, delta)
		actor.set_selected(id == state.current_actor_id() if state.mode == &"combat" else id == "hero")
	var followed: String = state.current_actor_id() if state.mode == &"combat" else "hero"
	if not state.pending.is_empty() and state.pending.get("type") == "move":
		followed = str(state.pending.get("actor_id", followed))
	if state.actors.has(followed):
		camera_rig.follow(state.actors[followed]["position"])
	_followed_actor = followed
	_preview_time += delta
	if _preview_time >= 0.06:
		_preview_time = 0.0
		_update_hover()
	if _capture_frames > 0:
		_capture_frames -= 1
		if _capture_frames == 0:
			_capture()

func _can_control() -> bool:
	var state: GameState = Game.state
	return ready_for_input and state.pending.is_empty() and not hud.rolls_busy() and state.mode != &"defeat" and (state.mode == &"exploration" or state.current_actor_id() == "hero")

func _unhandled_input(event: InputEvent) -> void:
	if not ready_for_input:
		return
	if event.is_action_pressed("combat_debug"):
		hud.toggle_debug()
	elif event.is_action_pressed("cancel") or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed):
		_set_attack_mode(false)
		_clear_hover()
	elif event.is_action_pressed("combat_attack"):
		_action_requested("attack")
	elif event.is_action_pressed("end_turn"):
		_action_requested("end_turn")
	elif event.is_action_pressed("combat_dash"):
		_action_requested("dash")
	elif event.is_action_pressed("combat_disengage"):
		_action_requested("disengage")
	elif event.is_action_pressed("select") and _can_control():
		_update_hover()
		if not hovered_actor.is_empty() and hovered_actor != "hero":
			CommandBus.submit(AttackCommand.new("hero", hovered_actor))
			_set_attack_mode(false)
		elif hovered_ground.is_finite() and not _attack_mode:
			CommandBus.submit(MoveCommand.new("hero", hovered_ground))
		_clear_hover()

func _action_requested(kind: String) -> void:
	if kind == "main_menu":
		get_tree().change_scene_to_file("res://scenes/showcase/asset_showcase.tscn")
		return
	if not _can_control():
		return
	match kind:
		"dash": CommandBus.submit(DashCommand.new("hero"))
		"disengage": CommandBus.submit(DisengageCommand.new("hero"))
		"end_turn": CommandBus.submit(EndTurnCommand.new("hero"))
		"attack": _set_attack_mode(true)

func _update_hover() -> void:
	if not _can_control() or get_viewport().gui_get_hovered_control() != null:
		_clear_hover()
		return
	var cursor: Vector2 = get_viewport().get_mouse_position()
	var origin: Vector3 = camera_rig.camera.project_ray_origin(cursor)
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + camera_rig.camera.project_ray_normal(cursor) * 200.0, 3)
	ray.collide_with_areas = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		_clear_hover()
		return
	var collider: Object = hit["collider"]
	var id: String = str(collider.get_meta("actor_id", ""))
	var state: GameState = Game.state
	if not id.is_empty() and id != "hero" and int(state.actors[id]["hp"]) > 0:
		hovered_actor = id
		hovered_ground = Vector3.INF
		path_display.mesh = null
		hud.show_target(CombatRules.attack_preview(state, "hero", id), state.actors[id])
		return
	hovered_actor = ""
	hovered_ground = hit["position"]
	var path: PackedVector3Array = space.query_path(state.actors["hero"]["position"], hovered_ground)
	if path.size() < 2:
		_clear_hover()
		return
	var budget: float = float(state.actors["hero"]["move_left"]) if state.mode == &"combat" else INF
	var danger: bool = _path_danger(state, path)
	_draw_path(path, budget)
	hud.show_path(CombatRules.path_length(path), budget - CombatRules.path_length(path) if is_finite(budget) else 0.0, danger)

func _set_attack_mode(active: bool) -> void:
	_attack_mode = active
	hud.set_attack_mode(active)

func _path_danger(state: GameState, path: PackedVector3Array) -> bool:
	return state.mode == &"combat" and not CombatRules.opportunity_crossings(state, "hero", path).is_empty()

func _draw_path(path: PackedVector3Array, budget: float) -> void:
	var mesh: ImmediateMesh = ImmediateMesh.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var distance: float = 0.0
	for index: int in range(1, path.size()):
		var start: Vector3 = path[index - 1] + Vector3.UP * 0.06
		var end: Vector3 = path[index] + Vector3.UP * 0.06
		var length: float = start.distance_to(end)
		if distance < budget and distance + length > budget:
			var boundary: Vector3 = start.lerp(end, (budget - distance) / length)
			mesh.surface_set_color(Color("72e8a4"))
			mesh.surface_add_vertex(start)
			mesh.surface_add_vertex(boundary)
			mesh.surface_set_color(Color("ff6d68"))
			mesh.surface_add_vertex(boundary)
			mesh.surface_add_vertex(end)
		else:
			mesh.surface_set_color(Color("72e8a4") if distance < budget else Color("ff6d68"))
			mesh.surface_add_vertex(start)
			mesh.surface_add_vertex(end)
		distance += length
	mesh.surface_end()
	path_display.mesh = mesh

func _clear_hover() -> void:
	hovered_actor = ""
	hovered_ground = Vector3.INF
	if path_display != null:
		path_display.mesh = null
	if hud != null:
		hud.clear_target()

func _command_applied(_command: Command, result: Dictionary) -> void:
	var events: Array[Dictionary] = []
	for value: Dictionary in result.get("events", []):
		events.append(value)
	for event: Dictionary in events:
		if event.get("type") == "roll" and event.get("kind") == "attack" and bool(event.get("critical", false)):
			_critical_focus = 0.6
		if event.get("type") == "start_attack":
			var source: String = str(event["actor_id"])
			var target: String = str(event["target_id"])
			if actors.has(source) and actors.has(target):
				actors[source].aim_at(actors[target].global_position)
				camera_rig.focus_target(actors[target].global_position, 0.65)
		for actor: CombatActor in actors.values():
			actor.react_to_event(event, actors)
	hud.consume_events(events)
	hud.update_state(Game.state)

func _command_rejected(_command: Command, _reason: Error) -> void:
	_clear_hover()

func _hold_capture_roll(_event: Dictionary) -> void:
	# The first real initiative event creates its numbered mesh before this signal.
	# Land and hold only the presentation; gameplay state and RNG are untouched.
	hud.dice_popup.skip()
	hud.dice_popup.set_process(false)
	_capture_frames = 2

func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("An actual rendering display is required for arena screenshots")
		get_tree().quit(1)
		return
	await RenderingServer.frame_post_draw
	var captured: Image = get_viewport().get_texture().get_image()
	var result: Error = captured.save_png(_capture_path)
	get_tree().quit(0 if result == OK else 1)
