class_name CryptBuilder
extends ArenaBuilder
## The crypt (package 10): seven connected spaces built from the dungeon kit on a 3 m grid.
## Vestibule -> hall (fight 1) -> trapped corridor -> side chamber (fight 2, optional)
## -> ossuary (fight 3) -> rest alcove -> shrine (boss). Every combat room has height
## (a dais or balcony), cover and a narrow passage. Navigation is baked from the colliders
## (tools/bake_level.gd) into scenes/levels/crypt/crypt_navigation.tres.

const CRYPT_NAVIGATION_PATH: String = "res://scenes/levels/crypt/crypt_navigation.tres"
const CELL: float = 3.0
const WALL_HEIGHT: float = 3.0
## Floor cells as [i_min, i_max, j_min, j_max]; cell (i, j) is centred on (3i, 0, 3j).
const AREAS: Array = [
	[-1, 1, 5, 6],    # vestibule
	[0, 0, 4, 4],     # vestibule door
	[-3, 3, 0, 3],    # hall
	[0, 0, -5, -1],   # corridor
	[1, 1, -3, -3],   # side passage
	[2, 5, -4, -2],   # side chamber
	[6, 6, -3, -3],   # locked cell (behind the gate, not walkable)
	[-3, 3, -10, -6], # ossuary
	[0, 0, -13, -11], # rest corridor
	[-1, -1, -12, -12], # rest alcove
	[-3, 3, -18, -14], # shrine
]
## Cells that only exist visually (no floor collider, so no navigation).
const SEALED_CELLS: Array[Vector2i] = [Vector2i(6, -3)]
## Iron gate between the side chamber and the locked cell.
const GATE_CENTER: Vector3 = Vector3(16.5, 0, -9)

## Tall walls, pillars and shelves the camera fades when they hide an actor:
## {"visual": Node3D, "body": StaticBody3D, "box": AABB}.
var occluders: Array[Dictionary] = []
## All static kit meshes end up in MultiMeshes (StaticBatcher) once the level is built.
var batcher: StaticBatcher
var batch_chunk_m: float = StaticBatcher.CHUNK_M
var _cells: Dictionary = {}

func build() -> void:
	if geometry != null:
		return
	geometry = Node3D.new()
	geometry.name = "DungeonGeometry"
	add_child(geometry)
	for area: Array in AREAS:
		for i: int in range(area[0], area[1] + 1):
			for j: int in range(area[2], area[3] + 1):
				_cells[Vector2i(i, j)] = true
	for cell: Vector2i in _cells:
		var center: Vector3 = Vector3(cell.x * CELL, -0.18, cell.y * CELL)
		if cell in SEALED_CELLS:
			_visual("SM_TileFloor", center, Vector3(CELL, 0.18, CELL))
		else:
			_piece("SM_TileFloor", center, Vector3(CELL, 0.18, CELL), false)
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not _cells.has(cell + direction):
				_wall(Vector3(cell.x * CELL + direction.x * CELL * 0.5, 0, cell.y * CELL + direction.y * CELL * 0.5), direction.x != 0)
	_gate()
	_hall()
	_side_chamber()
	_ossuary()
	_shrine()
	_crypt_lights()
	if is_inside_tree():
		_batch_meshes()
	navigation = NavigationRegion3D.new()
	navigation.name = "BakedNavigation"
	add_child(navigation)
	if ResourceLoader.exists(CRYPT_NAVIGATION_PATH):
		navigation.navigation_mesh = load(CRYPT_NAVIGATION_PATH) as NavigationMesh

func bake() -> void:
	var mesh: NavigationMesh = NavigationMesh.new()
	mesh.agent_radius = 0.45
	mesh.agent_height = 1.7
	mesh.agent_max_climb = 0.3
	mesh.agent_max_slope = 48.0
	mesh.cell_size = 0.15
	mesh.cell_height = 0.05
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, geometry)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	navigation.navigation_mesh = mesh
	assert(mesh.get_polygon_count() > 0, "Crypt navigation bake must contain polygons")
	assert(ResourceSaver.save(mesh, CRYPT_NAVIGATION_PATH) == OK, "Crypt navigation bake must persist")

## Hundreds of kit pieces become a few dozen MultiMeshes; the fading walls keep their
## wrapper nodes and the fader re-places their instances (see LevelWallFader).
func _batch_meshes() -> void:
	batcher = StaticBatcher.new()
	batcher.name = "StaticBatches"
	batcher.chunk_m = batch_chunk_m
	add_child(batcher)
	var wrappers: Array[Node3D] = []
	for entry: Dictionary in occluders:
		wrappers.append(entry["visual"] as Node3D)
		entry["batcher"] = batcher
	batcher.batch(geometry, wrappers)

func is_floor_cell(cell: Vector2i) -> bool:
	return _cells.has(cell) and not cell in SEALED_CELLS

# Rooms ---------------------------------------------------------------------------------

func _hall() -> void:
	# West gallery 1 m up (sleeping cultist), stairs rising from the hall floor.
	_dais(Rect2(-10.5, 1.5, 3.0, 9.0), 1.0)
	_stairs(Vector3(-5.5, 0, 3.0), Vector3.LEFT, 1.0)
	# Two low walls leave a 1.5 m gap in the middle of the hall.
	_low_wall(Vector3(-2.25, 0, 4.5), 3.0, false)
	_low_wall(Vector3(2.25, 0, 4.5), 3.0, false)
	for point: Vector3 in [Vector3(-4.5, 0, 8.0), Vector3(4.5, 0, 8.0)]:
		_pillar(point)
	for point: Vector3 in [Vector3(6.5, 0, 8.5), Vector3(7.4, 0, 8.5), Vector3(-8.6, 0, -0.6)]:
		_barrel(point)

func _side_chamber() -> void:
	# South-east platform for the bandit, stairs from the north.
	_dais(Rect2(10.5, -13.5, 6.0, 3.0), 1.0)
	_stairs(Vector3(12.0, 0, -8.5), Vector3.FORWARD, 1.0)
	_low_wall(Vector3(7.5, 0, -6.5), 3.0, false)
	_pillar(Vector3(6.5, 0, -12.4))
	for point: Vector3 in [Vector3(8.6, 0, -12.6), Vector3(9.5, 0, -12.6)]:
		_barrel(point)
	_prop("SM_WoodenTable", Vector3(13.6, 0, -5.8), Vector3(2.0, 0.9, 1.1), true)

func _ossuary() -> void:
	# East balcony 2 m up (bandit), long stairs from the south.
	_dais(Rect2(7.5, -31.5, 3.0, 9.0), 2.0)
	_stairs(Vector3(9.0, 0, -18.5), Vector3.FORWARD, 2.0)
	# Bone shelves along the west wall around the praying cultist.
	for point: Vector3 in [Vector3(-9.9, 0, -19.6), Vector3(-9.9, 0, -28.4)]:
		var shelf: Node3D = _prop("SM_FullBookShelf", point, Vector3(1.0, 2.4, 2.3), true)
		occluders.append({"visual": shelf, "body": shelf.get_meta("body"), "box": _box_of(point, Vector3(1.0, 2.4, 2.3))})
	_low_wall(Vector3(-1.5, 0, -23.0), 3.0, false)
	_low_wall(Vector3(3.0, 0, -23.0), 3.0, false)
	for point: Vector3 in [Vector3(-6.5, 0, -19.5), Vector3(-6.5, 0, -28.5), Vector3(4.5, 0, -27.0)]:
		_pillar(point)
	for point: Vector3 in [Vector3(5.6, 0, -30.4), Vector3(6.5, 0, -30.4)]:
		_barrel(point)

func _shrine() -> void:
	# Altar dais for the Cult Priest, stairs from the south.
	_dais(Rect2(-4.5, -55.5, 9.0, 3.0), 1.0)
	_stairs(Vector3(0.0, 0, -50.5), Vector3.FORWARD, 1.0)
	_low_wall(Vector3(-2.25, 0, -42.5), 3.0, false)
	_low_wall(Vector3(2.25, 0, -42.5), 3.0, false)
	for point: Vector3 in [Vector3(-4.5, 0, -47.5), Vector3(4.5, 0, -47.5), Vector3(-8.0, 0, -51.5), Vector3(8.0, 0, -51.5)]:
		_pillar(point)
	_prop("SM_WoodenTable", Vector3(0.0, 1.0, -54.9), Vector3(2.4, 0.9, 1.0), true)

# Pieces --------------------------------------------------------------------------------

func _wall(center: Vector3, along_z: bool) -> void:
	# Rotate instead of squashing: the kit wall keeps its texture proportions.
	var visual: Node3D = _visual("SM_Wall", center, Vector3(CELL, WALL_HEIGHT, 0.4))
	if along_z:
		visual.rotation.y = PI / 2.0
	var size: Vector3 = Vector3(0.4, WALL_HEIGHT, CELL) if along_z else Vector3(CELL, WALL_HEIGHT, 0.4)
	var body: StaticBody3D = _solid(center, size, true)
	occluders.append({"visual": visual, "body": body, "box": _box_of(center, size)})

func _gate() -> void:
	var arch: Node3D = _visual("SM_DoorWay", GATE_CENTER, Vector3(CELL, WALL_HEIGHT, 0.6))
	arch.rotation.y = PI / 2.0
	var bar: CylinderMesh = CylinderMesh.new()
	bar.top_radius = 0.03
	bar.bottom_radius = 0.03
	bar.height = 2.3
	var metal: StandardMaterial3D = StandardMaterial3D.new()
	metal.albedo_color = Color("2b2622")
	metal.metallic = 0.8
	metal.roughness = 0.45
	bar.material = metal
	for index: int in 9:
		var rod: MeshInstance3D = MeshInstance3D.new()
		rod.mesh = bar
		rod.position = GATE_CENTER + Vector3(0, 1.15, -1.0 + index * 0.25)
		geometry.add_child(rod)
	_solid(GATE_CENTER, Vector3(0.3, WALL_HEIGHT, CELL), false)

func _dais(area: Rect2, height: float) -> void:
	var center: Vector3 = Vector3(area.position.x + area.size.x * 0.5, 0, area.position.y + area.size.y * 0.5)
	_solid(center, Vector3(area.size.x, height, area.size.y), true)
	var x: float = area.position.x + CELL * 0.5
	while x < area.end.x:
		var z: float = area.position.y + CELL * 0.5
		while z < area.end.y:
			_visual("SM_TileFloor", Vector3(x, height - 0.18, z), Vector3(CELL, 0.18, CELL))
			z += CELL
		x += CELL

## Stairs of 0.25 m treads (0.5 m deep) starting at `start` and rising along `direction`.
func _stairs(start: Vector3, direction: Vector3, height: float) -> void:
	var steps: int = roundi(height / 0.25)
	var run: float = steps * 0.5
	var visual: Node3D = _visual("SM_Stairs", start + direction * run * 0.5, Vector3(CELL, height, run))
	# The source kit rises toward local +Z.
	visual.rotation.y = atan2(direction.x, direction.z)
	for step: int in steps:
		var size: Vector3 = Vector3(CELL, (step + 1) * 0.25, 0.5) if absf(direction.z) > 0.5 else Vector3(0.5, (step + 1) * 0.25, CELL)
		_solid(start + direction * (0.25 + step * 0.5), size, false)

func _low_wall(center: Vector3, width: float, along_z: bool) -> void:
	var visual: Node3D = _visual("SM_Wall", center, Vector3(width, 1.25, 0.45))
	if along_z:
		visual.rotation.y = PI / 2.0
	_solid(center, Vector3(0.45, 1.25, width) if along_z else Vector3(width, 1.25, 0.45), true)
	for side: Vector3 in ([Vector3.LEFT, Vector3.RIGHT] if along_z else [Vector3.FORWARD, Vector3.BACK]):
		tactical_points.append(center + side * 0.9)

func _pillar(point: Vector3) -> void:
	var size: Vector3 = Vector3(1.1, WALL_HEIGHT, 1.1)
	var visual: Node3D = _prop("SM_WallEnders", point, size, true)
	occluders.append({"visual": visual, "body": visual.get_meta("body"), "box": _box_of(point, size)})

func _barrel(point: Vector3) -> void:
	_prop("SM_WoodenBarrel", point, Vector3(0.9, 1.2, 0.9), true)

func _prop(asset: String, point: Vector3, size: Vector3, cover_object: bool) -> Node3D:
	var visual: Node3D = _visual(asset, point, size)
	visual.set_meta("body", _solid(point, size, cover_object))
	if cover_object and point.y < 0.5:
		for direction: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			var spot: Vector3 = point + direction * (maxf(size.x, size.z) * 0.5 + 0.8)
			if is_floor_cell(Vector2i(roundi(spot.x / CELL), roundi(spot.z / CELL))):
				tactical_points.append(Vector3(spot.x, 0, spot.z))
	return visual

func _solid(base: Vector3, size: Vector3, cover_object: bool) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.position = base + Vector3(0, size.y / 2.0, 0)
	body.collision_layer = 5 if cover_object else 1
	body.collision_mask = 0
	geometry.add_child(body)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	return body

static func _box_of(base: Vector3, size: Vector3) -> AABB:
	return AABB(base - Vector3(size.x * 0.5, 0, size.z * 0.5), size)

func _crypt_lights() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("06090f")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("94a9c9")
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_intensity = 1.5
	environment.glow_enabled = true
	environment.fog_enabled = true
	environment.fog_light_color = Color("1d2532")
	environment.fog_density = 0.008
	environment.volumetric_fog_enabled = RenderingServer.get_current_rendering_method() == "forward_plus"
	environment.volumetric_fog_density = 0.006
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-60, -20, 0)
	key.light_color = Color("b6ccec")
	key.light_energy = 0.7
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 60.0
	add_child(key)
	# One shadowed torch per room keeps the light count cheap on mid hardware.
	var torches: Array = [
		[Vector3(-4.1, 1.6, 15.0), true], [Vector3(4.1, 1.6, 18.0), false],
		[Vector3(10.1, 1.6, 2.0), true], [Vector3(10.1, 1.6, 8.5), false], [Vector3(-6.0, 1.6, -1.1), false],
		[Vector3(-10.1, 2.6, 8.0), false],
		[Vector3(1.1, 1.6, -5.0), false], [Vector3(-1.1, 1.6, -14.0), true],
		[Vector3(16.1, 1.6, -5.5), true], [Vector3(5.0, 1.6, -13.1), false],
		[Vector3(-10.1, 1.6, -24.0), true], [Vector3(-6.0, 1.6, -16.9), false], [Vector3(10.1, 3.6, -28.0), false],
		[Vector3(6.0, 1.6, -16.9), false],
		[Vector3(-4.1, 1.6, -36.0), true],
		[Vector3(-10.1, 1.6, -44.0), false], [Vector3(10.1, 1.6, -44.0), false],
		[Vector3(-10.1, 1.6, -51.0), false], [Vector3(10.1, 1.6, -51.0), false], [Vector3(0.0, 2.6, -55.1), true],
	]
	for entry: Array in torches:
		var point: Vector3 = entry[0]
		_visual("SM_WallTorch", point, Vector3(0.35, 0.7, 0.3))
		var light: OmniLight3D = OmniLight3D.new()
		light.position = point + Vector3(0, 0.5, 0) + _inward(point) * 0.6
		light.light_color = Color("ffb06a")
		light.light_energy = 3.0
		light.omni_range = 9.0
		light.shadow_enabled = bool(entry[1])
		light.distance_fade_enabled = true
		light.distance_fade_begin = 40.0
		light.distance_fade_length = 10.0
		add_child(light)

## Direction from a wall-mounted point toward the open floor next to it.
func _inward(point: Vector3) -> Vector3:
	var cell: Vector2i = Vector2i(roundi(point.x / CELL), roundi(point.z / CELL))
	var offset: Vector3 = point - Vector3(cell.x * CELL, point.y, cell.y * CELL)
	if absf(offset.x) > absf(offset.z):
		return Vector3(-signf(offset.x), 0, 0)
	return Vector3(0, 0, -signf(offset.z))
