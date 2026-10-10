extends Node
## Real NavigationServer queries: dynamic bodies must never be walked through.

class Fixture extends Command:
	var actor_data: Dictionary
	func _init(data: Dictionary) -> void:
		actor_data = data
	func validate(_state: GameState) -> Error:
		return OK
	func apply(state: GameState) -> Dictionary:
		state.actors = actor_data.duplicate(true)
		return {}

var checks: int = 0
var failures: int = 0
var navigation_map: RID
var region: RID

func _ready() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _fixture(blockers: Array[Dictionary]) -> void:
	var actors: Dictionary = {"hero": {"hp": 12, "position": Vector3(0, 0, 4)}}
	for index: int in blockers.size():
		actors["blocker_" + str(index)] = blockers[index]
	var bus: Node = get_tree().root.get_node("CommandBus")
	check(bus.submit(Fixture.new(actors)) == OK, "Fixture uses authoritative command boundary")

func _map(width: float) -> void:
	var mesh: NavigationMesh = NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-width, 0, -10), Vector3(-width, 0, 10),
		Vector3(width, 0, 10), Vector3(width, 0, -10)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	if not navigation_map.is_valid():
		navigation_map = NavigationServer3D.map_create()
		NavigationServer3D.map_set_active(navigation_map, true)
		region = NavigationServer3D.region_create()
		NavigationServer3D.region_set_map(region, navigation_map)
	NavigationServer3D.region_set_navigation_mesh(region, mesh)
	NavigationServer3D.map_force_update(navigation_map)

func _sync_map(width: float) -> void:
	# Region meshes reach the map asynchronously; wait until its edge sits at the new width.
	var probe: Vector3 = Vector3(width + 5.0, 0, 0)
	for frame: int in 600:
		await get_tree().physics_frame
		if frame >= 4 and absf(NavigationServer3D.map_get_closest_point(navigation_map, probe).x - width) < 0.01:
			return
	check(false, "Navigation map never received the test mesh")

func _check_route(path: PackedVector3Array, bodies: Array[Vector3]) -> void:
	check(path.size() >= 2, "Open space must offer a route around actors")
	if path.size() < 2:
		return
	var valid: bool = true
	var clear: bool = true
	for index: int in range(1, path.size()):
		var steps: int = maxi(1, ceili(path[index - 1].distance_to(path[index]) / 0.025))
		for step: int in range(steps + 1):
			var point: Vector3 = path[index - 1].lerp(path[index], float(step) / steps)
			valid = valid and NavigationServer3D.map_get_closest_point(navigation_map, point).distance_to(point) < 0.01
			for body: Vector3 in bodies:
				if absf(point.y - body.y) < 1.7:
					clear = clear and Vector2(point.x - body.x, point.z - body.z).length() >= 0.699
	check(valid, "Every sampled edge point stays on the navmesh")
	check(clear, "Every sampled edge keeps 0.7 m from overlapping living bodies")

func _run() -> void:
	_map(10.0)
	await _sync_map(10.0)
	var space: ArenaSpace = ArenaSpace.new()
	space.map = navigation_map
	var start: Vector3 = Vector3(0, 0, 4)
	var goal: Vector3 = Vector3(0, 0, -4)
	_fixture([{"hp": 10, "position": Vector3.ZERO}])
	var route: PackedVector3Array = space.query_path(start, goal)
	_check_route(route, [Vector3.ZERO])
	check(CombatRules.path_length(route) > 8.1, "Living body forces a real detour")
	var melee: PackedVector3Array = space.query_path(start, Vector3(0, 0, 1.35))
	_check_route(melee, [Vector3.ZERO])
	check(not melee.is_empty() and melee[-1].distance_to(Vector3.ZERO) <= 1.5, "Legal melee range remains reachable")
	check(space.query_path(start, Vector3.ZERO).is_empty(), "Occupied destination remains forbidden")
	_fixture([{"hp": 0, "position": Vector3.ZERO}])
	route = space.query_path(start, goal)
	check(is_equal_approx(CombatRules.path_length(route), 8.0), "Dead actors do not block navigation")
	_fixture([{"hp": 10, "position": Vector3(0, 2, 0)}])
	route = space.query_path(start, goal)
	check(is_equal_approx(CombatRules.path_length(route), 8.0), "Bodies on a separate floor do not block")
	_fixture([{"hp": 10, "position": Vector3(0, 1.5, 0)}])
	route = space.query_path(start, goal)
	_check_route(route, [Vector3(0, 1.5, 0)])
	check(CombatRules.path_length(route) > 8.1, "Partly overlapping heights still force a detour")
	_fixture([{"hp": 10, "position": Vector3.ZERO}, {"hp": 10, "position": Vector3(0.7, 0, -1.1)}])
	route = space.query_path(start, goal)
	_check_route(route, [Vector3.ZERO, Vector3(0.7, 0, -1.1)])
	_fixture([{"hp": 10, "position": Vector3.ZERO}])
	_map(0.3)
	await _sync_map(0.3)
	check(space.query_path(start, goal).is_empty(), "Body fully blocking a narrow corridor yields no path")
	check(space.query_path(Vector3(3, 0, 4), goal).is_empty(), "Off-mesh source cannot teleport onto navigation")
	NavigationServer3D.free_rid(region)
	NavigationServer3D.free_rid(navigation_map)
	print("ACTOR_NAVIGATION_CHECKS: ", checks, " failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)
