class_name ArenaSpace
extends CombatSpace
## Geometry queries derive from the same world used for visible cover and baked navigation.
var world: Node3D
var map: RID

const BODY_CLEARANCE: float = 0.7
const BODY_HEIGHT: float = 1.7
const DETOUR_RADIUS: float = 0.95
const DETOUR_POINTS: int = 8

func query_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not from.is_finite() or not to.is_finite() or not map.is_valid() or \
			NavigationServer3D.map_get_iteration_id(map) == 0:
		return PackedVector3Array()
	var snapped: Vector3 = NavigationServer3D.map_get_closest_point(map, to)
	if snapped.distance_to(to) > 0.6:
		return PackedVector3Array()
	var start: Vector3 = NavigationServer3D.map_get_closest_point(map, from)
	# Authored spawn positions can sit slightly below the baked surface. Never
	# turn an arbitrary off-mesh source into an unchecked segment through a wall.
	if Vector2(start.x - from.x, start.z - from.z).length() > 0.12 or absf(start.y - from.y) > 0.6:
		return PackedVector3Array()
	var bodies: Array[Vector3] = _living_bodies(from)
	if _segment_occupied(from, start, bodies) or _segment_occupied(snapped, snapped, bodies):
		return PackedVector3Array()
	var direct: PackedVector3Array = _navigation_path(start, snapped)
	if direct.is_empty():
		return direct
	if _path_clear(direct, bodies):
		return _with_origin(direct, from)
	# NavigationServer paths respect the static dungeon, but do not avoid actor
	# bodies. Route a small graph around them; every edge is itself a complete
	# navmesh path, checked against every living body. No free-space shortcuts.
	var points: Array[Vector3] = [start, snapped]
	for body: Vector3 in bodies:
		for index: int in DETOUR_POINTS:
			var angle: float = TAU * index / DETOUR_POINTS
			var desired: Vector3 = body + Vector3(cos(angle), 0, sin(angle)) * DETOUR_RADIUS
			var candidate: Vector3 = NavigationServer3D.map_get_closest_point(map, desired)
			var horizontal_snap: float = Vector2(candidate.x - desired.x, candidate.z - desired.z).length()
			if horizontal_snap <= 0.25 and absf(candidate.y - desired.y) < BODY_HEIGHT and \
					not _segment_occupied(candidate, candidate, bodies):
				points.append(candidate)
	var costs: Array[float] = []
	var routes: Array[PackedVector3Array] = []
	var closed: Array[bool] = []
	for point: Vector3 in points:
		costs.append(INF)
		routes.append(PackedVector3Array())
		closed.append(false)
	costs[0] = 0.0
	routes[0] = PackedVector3Array([start])
	for iteration: int in points.size():
		var current: int = -1
		var best: float = INF
		for index: int in points.size():
			var estimate: float = costs[index] + points[index].distance_to(snapped)
			if not closed[index] and estimate < best:
				best = estimate
				current = index
		if current < 0:
			break
		if current == 1:
			return _with_origin(routes[current], from)
		closed[current] = true
		for next: int in points.size():
			if closed[next] or costs[current] + points[current].distance_to(points[next]) >= costs[next]:
				continue
			var edge: PackedVector3Array = _navigation_path(points[current], points[next])
			if edge.is_empty() or not _path_clear(edge, bodies):
				continue
			var cost: float = costs[current] + CombatRules.path_length(edge)
			if cost >= costs[next]:
				continue
			costs[next] = cost
			var route: PackedVector3Array = routes[current].duplicate()
			for vertex: int in range(1, edge.size()):
				route.append(edge[vertex])
			routes[next] = route
	return PackedVector3Array()

func _living_bodies(from: Vector3) -> Array[Vector3]:
	var state: GameState = Game.state
	var moving_id: String = ""
	var closest: float = 0.2
	for id: String in state.actors:
		var actor: Dictionary = state.actors[id]
		var distance: float = (actor["position"] as Vector3).distance_to(from)
		if int(actor["hp"]) > 0 and distance < closest:
			moving_id = id
			closest = distance
	var bodies: Array[Vector3] = []
	for id: String in state.actors:
		if id != moving_id and int(state.actors[id]["hp"]) > 0:
			bodies.append(state.actors[id]["position"])
	return bodies

func _navigation_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, from, to, true)
	if path.size() < 2 or path[0].distance_to(from) > 0.01 or path[-1].distance_to(to) > 0.01:
		return PackedVector3Array()
	return path

func _with_origin(path: PackedVector3Array, from: Vector3) -> PackedVector3Array:
	var result: PackedVector3Array = path.duplicate()
	if result[0].distance_to(from) > 0.001:
		result.insert(0, from)
	else:
		result[0] = from
	return result

func _path_clear(path: PackedVector3Array, bodies: Array[Vector3]) -> bool:
	for index: int in range(1, path.size()):
		if _segment_occupied(path[index - 1], path[index], bodies):
			return false
	return true

func _segment_occupied(from: Vector3, to: Vector3, bodies: Array[Vector3]) -> bool:
	var horizontal: Vector2 = Vector2(to.x - from.x, to.z - from.z)
	var vertical: float = to.y - from.y
	for body: Vector3 in bodies:
		# Feet positions alone are not spheres: actors on separate floors do
		# not collide, while bodies partly overlapping on stairs still do.
		var low: float = 0.0
		var high: float = 1.0
		if absf(vertical) < 0.00001:
			if absf(from.y - body.y) >= BODY_HEIGHT:
				continue
		else:
			var first: float = (body.y - BODY_HEIGHT - from.y) / vertical
			var second: float = (body.y + BODY_HEIGHT - from.y) / vertical
			low = maxf(0.0, minf(first, second))
			high = minf(1.0, maxf(first, second))
			if low >= high:
				continue
		var offset: Vector2 = Vector2(from.x - body.x, from.z - body.z)
		var fraction: float = low
		if horizontal.length_squared() > 0.000001:
			fraction = clampf(-offset.dot(horizontal) / horizontal.length_squared(), low, high)
		if (offset + horizontal * fraction).length_squared() < BODY_CLEARANCE * BODY_CLEARANCE - 0.000001:
			return true
	return false

func _blocked_samples(from: Vector3, to: Vector3) -> int:
	if world == null or not from.is_finite() or not to.is_finite():
		return 5
	var origin: Vector3 = from + Vector3.UP * 1.5
	var blocked: int = 0
	var side: Vector3 = (to - from).cross(Vector3.UP).normalized() * 0.24
	var offsets: Array[Vector3] = [Vector3(0, 0.3, 0), Vector3(0, 0.75, 0), Vector3(0, 1.6, 0), Vector3(0, 1.2, 0) + side, Vector3(0, 1.2, 0) - side]
	for offset: Vector3 in offsets:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, to + offset, 4)
		if not world.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			blocked += 1
	return blocked

func cover(from: Vector3, to: Vector3) -> int:
	var blocked: int = _blocked_samples(from, to)
	if blocked == 5:
		return 99
	if blocked >= 4:
		return 5
	if blocked >= 2:
		return 2
	return 0

func visible(from: Vector3, to: Vector3) -> bool:
	return _blocked_samples(from, to) < 5
