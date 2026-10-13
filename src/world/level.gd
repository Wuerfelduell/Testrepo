class_name DungeonLevel
extends CombatArena
## A playable level (package 10) on top of the combat arena's orchestration: dormant
## encounters with exploration poses and perception, joiners, the corridor trap, the rest
## point, dialogue hooks and the wall cutaway. State still only changes through commands.

const INTERACT_RANGE_M: float = 2.2
const INTERACT_LAYER: int = 8

var level: Dictionary = {}
var dormant_views: Dictionary = {}
var hook_views: Dictionary = {}
var interaction: LevelInteraction
## Conversations with hooks that have a tree in data/dialogue/ (campaign package 1).
var dialogue: DialoguePanel
## Quest journal on J (campaign package K3).
var journal: JournalPanel
var fader: LevelWallFader
var trap_marker: MeshInstance3D
var _patrol_time: float = 0.0
var _pending_interaction: String = ""
var _capture_room: String = ""
var _level_capture_path: String = ""
var _level_capture_combat: bool = false
var _level_capture_frames: int = -1
var _frame_times: PackedFloat32Array = []
## The AI weighs only tactical points near the active combatant: a fight stays in its
## room (and path queries stay cheap) instead of the whole crypt's cover spots.
const TACTICAL_RADIUS_M: float = 14.0
var _all_tactical_points: Array[Vector3] = []
## Tests switch perception off to place the hero freely.
var perception_enabled: bool = true

func _ready() -> void:
	var path: String = String(Game.state.world.get("data_path", ""))
	if Game.state.actors.is_empty() or path.is_empty():
		# Started directly (F6 or a test): a fresh run with the test Fighter.
		path = EncounterData.CRYPT_PATH
		CommandBus.submit(ResetRunCommand.new())
		if CommandBus.submit(LevelSetupCommand.new({}, path)) != OK:
			push_error("Crypt level data is invalid: " + ", ".join(EncounterData.problems(EncounterData.load_level(path))))
			return
	level = EncounterData.load_level(path)
	interaction = LevelInteraction.new()
	interaction.visible = false
	add_child(interaction)
	dialogue = DialoguePanel.new()
	add_child(dialogue)
	journal = JournalPanel.new()
	add_child(journal)
	await super._ready()
	if not ready_for_input:
		return
	CommandBus.command_applied.connect(_level_command_applied)
	hud.area_key = String(level.get("name_key", ""))
	dialogue.dice_popup = hud.dice_popup
	hud.update_state(Game.state)
	fader = LevelWallFader.new()
	add_child(fader)
	if dungeon is CryptBuilder:
		fader.setup((dungeon as CryptBuilder).occluders)
	_build_dormant_views()
	_build_hooks()
	_build_trap_marker()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--level-capture="):
			_level_capture_path = argument.trim_prefix("--level-capture=")
		elif argument.begins_with("--level-capture-room="):
			_capture_room = argument.trim_prefix("--level-capture-room=")
		elif argument == "--level-capture-combat":
			_level_capture_combat = true
	if not _level_capture_path.is_empty():
		_begin_capture()

## Ids of the dormant encounters still waiting in this level.
func dormant_encounters() -> Array:
	return (Game.state.world.get("dormant", {}) as Dictionary).keys()

func simulation_step(delta: float, fast: bool = false) -> void:
	var state: GameState = Game.state
	if state.mode != &"defeat" and state.actors.has("hero"):
		if state.mode == &"exploration":
			_patrol_time += delta
		_check_trap(state)
		if perception_enabled:
			_check_perception(Game.state)
			_check_joiners(Game.state, fast)
	_focus_tactical_points(Game.state)
	super.simulation_step(delta, fast)

func _focus_tactical_points(state: GameState) -> void:
	if _all_tactical_points.is_empty():
		_all_tactical_points = dungeon.tactical_points.duplicate()
	var active: Dictionary = state.actors.get(state.current_actor_id(), state.actors.get("hero", {}))
	if active.is_empty():
		return
	var center: Vector3 = active["position"]
	# Enemies hold their own room; the hero fights in the room it stands in.
	var room_id: String = String(EncounterData.encounter(level, String(active.get("encounter_id", ""))).get("room", ""))
	if room_id.is_empty():
		room_id = room_at(center)
	var nearby: Array[Vector3] = []
	for point: Vector3 in _all_tactical_points:
		if point.distance_to(center) <= TACTICAL_RADIUS_M and (room_id.is_empty() or EncounterData.in_room(level, room_id, point)):
			nearby.append(point)
	dungeon.tactical_points = nearby

func _process(delta: float) -> void:
	super._process(delta)
	if not ready_for_input:
		return
	var state: GameState = Game.state
	for id: String in dormant_views:
		var view: CombatActor = dormant_views[id]
		view.update_dormant(_dormant_position(state, id), delta)
	if not _capture_room.is_empty():
		var room: Dictionary = _room(_capture_room)
		if not room.is_empty():
			camera_rig.follow(EncounterData.vector(room["center"]))
	if fader != null:
		var focus: Array[Vector3] = []
		for member_id: String in PartyRules.living_members(state):
			focus.append(state.actors[member_id]["position"])
		if state.actors.has(_followed_actor) and _followed_actor != "hero":
			focus.append(state.actors[_followed_actor]["position"])
		if not _capture_room.is_empty():
			focus = [EncounterData.vector(_room(_capture_room)["center"])]
		fader.update(camera_rig.camera, focus, delta)
	if not _pending_interaction.is_empty() and state.pending.is_empty():
		var hook_id: String = _pending_interaction
		_pending_interaction = ""
		if _within_reach(state, hook_id):
			interact(hook_id)
	if _level_capture_frames >= 0:
		_frame_times.append(delta)
		_level_capture_frames -= 1
		if _level_capture_frames == 0:
			_capture_level()

func _unhandled_input(event: InputEvent) -> void:
	if (interaction != null and interaction.is_open()) or (dialogue != null and dialogue.is_open()):
		return
	if ready_for_input and event.is_action_pressed("select") and not spell_targeting.is_active() and \
			Game.state.mode == &"exploration" and _can_control():
		var hook_id: String = _hook_under_cursor()
		if not hook_id.is_empty():
			get_viewport().set_input_as_handled()
			if _within_reach(Game.state, hook_id):
				interact(hook_id)
			elif CommandBus.submit(MoveCommand.new(controlled_id(), _interact_point(hook_id))) == OK:
				_pending_interaction = hook_id
			return
	super._unhandled_input(event)

## Opens a hook's conversation (or its placeholder line when it has no tree yet), uses
## the rest point or takes an exit into another area. Returns false if unknown.
func interact(hook_id: String) -> bool:
	if not AreaTravel.exit_by_id(level, hook_id).is_empty():
		var travel: Error = CommandBus.submit(TravelCommand.new(hook_id))
		if travel == ERR_UNAVAILABLE:
			interaction.show_text(tr("TRAVEL_LOCKED"))
		return true
	var rest: Dictionary = level.get("rest", {})
	if hook_id == String(rest.get("id", "")):
		var refused: String = _long_rest()
		if not refused.is_empty():
			interaction.show_text(refused)
		return true
	for hook: Dictionary in level.get("hooks", []):
		if String(hook["id"]) == hook_id:
			var dialogue_id: String = String(hook.get("dialogue", ""))
			if not DialogueData.exists(dialogue_id) or not dialogue.open(dialogue_id):
				interaction.show_text(tr("DIALOGUE_PLACEHOLDER") % hook_id)
			return true
	return false

# Encounters ----------------------------------------------------------------------------

func _check_perception(state: GameState) -> void:
	if not (state.mode == &"exploration" or (state.mode == &"combat" and state.pending.is_empty())):
		return
	if state.mode == &"exploration" and not state.pending.is_empty() and state.pending.get("type") != "move":
		return
	# Every living party member can be noticed (package K4), not only the hero.
	var dormant: Dictionary = state.world.get("dormant", {})
	for encounter_id: String in dormant:
		for id: String in dormant[encounter_id]:
			var record: Dictionary = dormant[encounter_id][id]
			var position: Vector3 = _dormant_position(state, id)
			for member_id: String in PartyRules.living_members(state):
				var member_position: Vector3 = state.actors[member_id]["position"]
				if EncounterData.notices(level, encounter_id, record, position, member_position) and \
						space.visible(position, member_position):
					_trigger(encounter_id)
					return

func _check_joiners(state: GameState, fast: bool) -> void:
	if state.mode != &"combat" or not state.pending.is_empty() or (not fast and hud.rolls_busy()):
		return
	if state.round_number < int(level.get("join_round", 2)):
		return
	var dormant: Dictionary = state.world.get("dormant", {})
	for encounter_id: String in _fighting_encounters(state):
		for joiner: Variant in EncounterData.encounter(level, encounter_id).get("joins", []):
			if dormant.has(String(joiner)):
				_trigger(String(joiner))
				return

func _fighting_encounters(state: GameState) -> Array[String]:
	var result: Array[String] = []
	for id: String in state.actors:
		var actor: Dictionary = state.actors[id]
		var encounter_id: String = String(actor.get("encounter_id", ""))
		if not encounter_id.is_empty() and CombatRules.alive(actor) and not encounter_id in result:
			result.append(encounter_id)
	return result

func _trigger(encounter_id: String) -> void:
	var state: GameState = Game.state
	var positions: Dictionary = {}
	for id: String in state.world["dormant"][encounter_id]:
		if String(state.world["dormant"][encounter_id][id].get("pose", "")) == "patrol":
			positions[id] = _dormant_position(state, id)
	var was_exploring: bool = state.mode == &"exploration"
	if CommandBus.submit(EncounterTriggerCommand.new(encounter_id, positions)) != OK:
		return
	if was_exploring:
		CommandBus.submit(StartCombatCommand.new())

func _dormant_position(state: GameState, actor_id: String) -> Vector3:
	var dormant: Dictionary = state.world.get("dormant", {})
	for encounter_id: String in dormant:
		var record: Dictionary = dormant[encounter_id].get(actor_id, {})
		if record.is_empty():
			continue
		if String(record.get("pose", "")) == "patrol":
			return EncounterData.patrol_position(record.get("patrol", []), _patrol_time)
		return record["position"]
	return Vector3.INF

func _build_dormant_views() -> void:
	var dormant: Dictionary = Game.state.world.get("dormant", {})
	for encounter_id: String in dormant:
		for id: String in dormant[encounter_id]:
			var record: Dictionary = dormant[encounter_id][id]
			var view: CombatActor = CombatActor.new()
			add_child(view)
			view.setup_actor(record)
			view.set_pose(String(EncounterData.POSE_CLIPS.get(String(record.get("pose", "")), "")))
			view.aim_at(view.global_position + (record.get("facing", Vector3.BACK) as Vector3))
			view.set_selected(false)
			# Unaware enemies are not targets yet.
			(view.get_node("ActorPick") as Area3D).collision_layer = 0
			dormant_views[id] = view

func _level_command_applied(_command: Command, result: Dictionary) -> void:
	for event: Dictionary in result.get("events", []):
		match String(event.get("type", "")):
			"encounter_triggered":
				for id: Variant in event.get("actor_ids", []):
					var view: CombatActor = dormant_views.get(String(id)) as CombatActor
					if view == null:
						continue
					dormant_views.erase(String(id))
					view.set_pose("")
					(view.get_node("ActorPick") as Area3D).collision_layer = 2
					actors[String(id)] = view
					var hero: Dictionary = Game.state.actors.get("hero", {})
					if not hero.is_empty():
						view.aim_at(hero["position"])
			"trap_sprung":
				if trap_marker != null:
					trap_marker.visible = true
			"dialogue_end", "party_joined":
				_hide_finished_hooks.call_deferred()
			"travel":
				# The old area's views must not read the new area's state until the scene changes.
				ready_for_input = false
				set_process(false)
				RunFlow.enter_area.call_deferred(get_tree())

# Trap, rest and hooks ------------------------------------------------------------------

func _check_trap(state: GameState) -> void:
	var trap: Dictionary = level.get("trap", {})
	if trap.is_empty() or bool(state.world.get("trap_sprung", false)):
		return
	if LevelTrapCommand.inside(trap, state.actors["hero"]["position"]) and CombatRules.alive(state.actors["hero"]):
		CommandBus.submit(LevelTrapCommand.new(String(trap["id"])))

func _build_trap_marker() -> void:
	var trap: Dictionary = level.get("trap", {})
	if trap.is_empty():
		return
	var low: Vector3 = EncounterData.vector(trap["min"])
	var high: Vector3 = EncounterData.vector(trap["max"])
	trap_marker = MeshInstance3D.new()
	trap_marker.name = "TrapPlate"
	var plate: BoxMesh = BoxMesh.new()
	plate.size = Vector3(high.x - low.x, 0.03, high.z - low.z)
	trap_marker.mesh = plate
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("8c2f25")
	material.emission_enabled = true
	material.emission = Color("ff5236")
	material.emission_energy_multiplier = 0.35
	trap_marker.material_override = material
	trap_marker.position = Vector3((low.x + high.x) * 0.5, 0.02, (low.z + high.z) * 0.5)
	add_child(trap_marker)
	# A hero with passive Perception at the notice DC sees the plate before stepping on it.
	var hero: Dictionary = Game.state.actors.get("hero", {})
	trap_marker.visible = bool(Game.state.world.get("trap_sprung", false)) or \
		int(hero.get("passive_perception", 10)) >= int(trap.get("notice_dc", 99))

func _build_hooks() -> void:
	var entries: Array[Dictionary] = []
	for hook: Dictionary in level.get("hooks", []):
		entries.append(hook)
	var rest: Dictionary = level.get("rest", {})
	if not rest.is_empty():
		entries.append({"id": String(rest["id"]), "position": rest["position"], "model": "", "rest": true})
	for exit: Dictionary in level.get("exits", []):
		entries.append({"id": String(exit["id"]), "position": exit["position"], "model": "", "exit": true})
	for hook: Dictionary in entries:
		var id: String = String(hook["id"])
		if _hook_hidden(hook):
			continue
		var position: Vector3 = EncounterData.vector(hook["position"])
		var anchor: Node3D = Node3D.new()
		anchor.name = "Hook_" + id
		anchor.position = position
		add_child(anchor)
		var model: String = String(hook.get("model", ""))
		if not model.is_empty() and ResourceLoader.exists(model):
			var figure: PreviewActor = PreviewActor.new()
			anchor.add_child(figure)
			figure.setup(model, "")
			for label: Node in figure.find_children("*", "Label3D", true, false):
				(label as Label3D).visible = false
			var pose: String = String(hook.get("pose", ""))
			if figure.player.has_animation(pose):
				figure.player.get_animation(pose).loop_mode = Animation.LOOP_LINEAR
				figure.play_clip(pose)
			var facing: Vector3 = EncounterData.vector(hook.get("facing", [0.0, 0.0, 1.0]))
			# The imported figures look along -Z: aim that side at the facing direction.
			figure.look_at(figure.global_position + facing, Vector3.UP, false)
		elif bool(hook.get("rest", false)):
			_rest_marker(anchor)
		# Floating rune above the hook; the click area covers rune and figure.
		var rune: MeshInstance3D = MeshInstance3D.new()
		var shape_mesh: PrismMesh = PrismMesh.new()
		shape_mesh.size = Vector3(0.28, 0.36, 0.06)
		rune.mesh = shape_mesh
		rune.rotation_degrees.z = 180.0
		var glow: StandardMaterial3D = StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = Color("7fe0c4") if bool(hook.get("rest", false)) else \
			(Color("8fb8ff") if bool(hook.get("exit", false)) else Color("e9c46a"))
		glow.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		rune.material_override = glow
		rune.position = Vector3(0, 2.3, 0)
		anchor.add_child(rune)
		var area: Area3D = Area3D.new()
		area.collision_layer = INTERACT_LAYER
		area.collision_mask = 0
		area.set_meta("interact_id", id)
		var shape: CollisionShape3D = CollisionShape3D.new()
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = 0.6
		capsule.height = 2.8
		shape.shape = capsule
		shape.position.y = 1.3
		area.add_child(shape)
		anchor.add_child(area)
		hook_views[id] = anchor

## A hook with "hide_if" conditions (DialogueData format) disappears once they hold,
## e.g. a figure that was killed in its conversation.
func _hook_hidden(hook: Dictionary) -> bool:
	return hook.has("hide_if") and DialogueData.conditions_met(hook["hide_if"], Game.state)

func _hide_finished_hooks() -> void:
	for hook: Dictionary in level.get("hooks", []):
		var id: String = String(hook["id"])
		if hook_views.has(id) and _hook_hidden(hook):
			(hook_views[id] as Node3D).queue_free()
			hook_views.erase(id)

func _rest_marker(anchor: Node3D) -> void:
	var roll: MeshInstance3D = MeshInstance3D.new()
	var mat: BoxMesh = BoxMesh.new()
	mat.size = Vector3(0.8, 0.12, 1.9)
	roll.mesh = mat
	var cloth: StandardMaterial3D = StandardMaterial3D.new()
	cloth.albedo_color = Color("5a4630")
	roll.material_override = cloth
	roll.position.y = 0.06
	anchor.add_child(roll)
	var embers: OmniLight3D = OmniLight3D.new()
	embers.light_color = Color("ff9a52")
	embers.light_energy = 1.4
	embers.omni_range = 4.0
	embers.position = Vector3(0.9, 0.4, 0.0)
	anchor.add_child(embers)

func _hook_under_cursor() -> String:
	var cursor: Vector2 = get_viewport().get_mouse_position()
	var origin: Vector3 = camera_rig.camera.project_ray_origin(cursor)
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + camera_rig.camera.project_ray_normal(cursor) * 200.0, INTERACT_LAYER)
	ray.collide_with_areas = true
	ray.collide_with_bodies = false
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	return String((hit["collider"] as Object).get_meta("interact_id", "")) if not hit.is_empty() else ""

func _interact_point(hook_id: String) -> Vector3:
	var exit: Dictionary = AreaTravel.exit_by_id(level, hook_id)
	if not exit.is_empty():
		return EncounterData.vector(exit["position"])
	for hook: Dictionary in level.get("hooks", []):
		if String(hook["id"]) == hook_id:
			return EncounterData.vector(hook.get("interact_at", hook["position"]))
	return EncounterData.vector(level.get("rest", {}).get("position", Vector3.INF))

func _within_reach(state: GameState, hook_id: String) -> bool:
	var target: Vector3 = _interact_point(hook_id)
	var hero: Vector3 = state.actors[controlled_id()]["position"]
	return target.is_finite() and Vector2(target.x - hero.x, target.z - hero.z).length() <= INTERACT_RANGE_M + 0.5

## Package 08 owns resting: the rest point opens its long-rest dialog (LongRestCommand).
## Returns the line to show when resting is refused, or "" when the dialog opened.
func _long_rest() -> String:
	var reason: String = RestRules.long_rest_reason(Game.state, "hero", [] as Array[String])
	if not reason.is_empty():
		return tr(reason)
	if rest_panel == null:
		return tr("REST_REASON_UNKNOWN")
	rest_panel.open_long_rest()
	return ""

## Id of the room containing a point, or "" between rooms.
func room_at(point: Vector3) -> String:
	for room: Dictionary in level.get("rooms", []):
		if EncounterData.in_room(level, String(room["id"]), point):
			return String(room["id"])
	return ""

func _room(room_id: String) -> Dictionary:
	for room: Dictionary in level.get("rooms", []):
		if String(room["id"]) == room_id:
			return room
	return {}

# Screenshots for docs/ -----------------------------------------------------------------

func _begin_capture() -> void:
	perception_enabled = false
	if _level_capture_combat:
		Rng.set_seed(6142)
		# Walk into the hall until the patrol notices: real initiative, HUD and portraits.
		perception_enabled = true
		CommandBus.submit(MoveCommand.new("hero", Vector3(0, 0, 7.5)))
		_level_capture_frames = 160
	else:
		_level_capture_frames = 40

func _capture_level() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("An actual rendering display is required for level screenshots")
		get_tree().quit(1)
		return
	if _level_capture_combat:
		hud.dice_popup.skip()
	# The Xvfb cursor sits mid-screen: no hover path in documentation shots.
	set_process(false)
	_clear_hover()
	var total: float = 0.0
	for value: float in _frame_times:
		total += value
	print("LEVEL_FRAME_MS: %.2f over %d frames (%s), %d draw calls, %d objects, %d primitives" % [
		total / maxf(1.0, _frame_times.size()) * 1000.0, _frame_times.size(), RenderingServer.get_video_adapter_name(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	await RenderingServer.frame_post_draw
	var captured: Image = get_viewport().get_texture().get_image()
	# Documentation size: 1280 px wide keeps docs/ small.
	captured.resize(1280, roundi(1280.0 * captured.get_height() / captured.get_width()), Image.INTERPOLATE_LANCZOS)
	var result: Error = captured.save_png(_level_capture_path)
	get_tree().quit(0 if result == OK else 1)
