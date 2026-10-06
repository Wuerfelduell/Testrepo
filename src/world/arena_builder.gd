class_name ArenaBuilder
extends Node3D
## Visible kit pieces plus deliberately authored collision geometry.
## Navigation is baked from these colliders, never from a separate hand-drawn path grid.

const NAVIGATION_PATH: String = "res://scenes/arena/arena_navigation.tres"
var navigation: NavigationRegion3D
var geometry: Node3D
var tactical_points: Array[Vector3] = []

func _ready() -> void:
	build()

func build() -> void:
	if geometry != null:
		return
	geometry = Node3D.new()
	geometry.name = "DungeonGeometry"
	add_child(geometry)
	for x: int in range(-3, 4):
		for z: int in range(-4, 4):
			_piece("SM_TileFloor", Vector3(x * 3.0, -0.18, z * 3.0 + 1.5), Vector3(3, 0.18, 3), false)
	for x: int in range(-3, 4):
		_piece("SM_Wall", Vector3(x * 3.0, 0, -12), Vector3(3, 3, 0.4), true)
	for z: int in range(-3, 4):
		_piece("SM_Wall", Vector3(-10.5, 0, z * 3.0), Vector3(0.4, 3, 3), true)
		_piece("SM_Wall", Vector3(10.5, 0, z * 3.0), Vector3(0.4, 3, 3), true)
	# A 2 m balcony; stair treads rise by 0.25 m, matching the visible kit staircase.
	for x: float in [4.5, 7.5]:
		for z: float in [-9.0, -6.0]:
			_piece("SM_TileFloor", Vector3(x, 1.82, z), Vector3(3, 0.18, 3), false)
	_box(Vector3(6, 0, -7.5), Vector3(6, 2, 6), true)
	var stairs: Node3D = _visual("SM_Stairs", Vector3(6, 0, -2.5), Vector3(3, 2, 4))
	# The source kit rises toward local +Z; the balcony is north (-Z).
	stairs.rotation.y = PI
	for step: int in 8:
		_box(Vector3(6, 0, -0.75 - step * 0.5), Vector3(3, (step + 1) * 0.25, 0.5), false)
	# Two split walls make a narrow passage; columns deny straight approaches.
	for x: float in [-7.2, -4.2]:
		_piece("SM_Wall", Vector3(x, 0, 0), Vector3(3, 2.6, 0.45), true)
	for point: Vector3 in [Vector3(-1.5, 0, 0), Vector3(2.0, 0, 3.0), Vector3(-6.0, 0, -7.0)]:
		_piece("SM_WallEnders", point, Vector3(1.1, 3, 1.1), true)
	for point: Vector3 in [Vector3(-3.0, 0, -3), Vector3(-3.85, 0, -3), Vector3(1.3, 0, -6.0), Vector3(7.5, 2, -7.0)]:
		_piece("SM_WoodenBarrel", point, Vector3(0.9, 1.2, 0.9), true)
		for direction: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			tactical_points.append(point + direction * 1.25)
	_piece("SM_FullBookShelf", Vector3(-9.6, 0, -10.4), Vector3(1.0, 2.4, 2.3), true)
	for point: Vector3 in [Vector3(4, 2, -5), Vector3(8.1, 2, -5), Vector3(4, 2, -9), Vector3(-6, 0, -4.5), Vector3(0, 0, 5), Vector3(7, 0, 4), Vector3(-7, 0, 6)]:
		tactical_points.append(point)
	_lights()
	navigation = NavigationRegion3D.new()
	navigation.name = "BakedNavigation"
	add_child(navigation)
	if ResourceLoader.exists(NAVIGATION_PATH):
		navigation.navigation_mesh = load(NAVIGATION_PATH) as NavigationMesh

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
	assert(mesh.get_polygon_count() > 0, "Arena navigation bake must contain polygons")
	assert(ResourceSaver.save(mesh, NAVIGATION_PATH) == OK, "Navigation bake must persist")

func _bounds(model: Node3D) -> AABB:
	var found: bool = false
	var result: AABB = AABB()
	for child: Node in model.find_children("*", "MeshInstance3D", true, false):
		var item: MeshInstance3D = child as MeshInstance3D
		var transform_to_root: Transform3D = Transform3D.IDENTITY
		var current: Node3D = item
		while current != model:
			transform_to_root = current.transform * transform_to_root
			current = current.get_parent() as Node3D
		var item_bounds: AABB = transform_to_root * item.get_aabb()
		result = result.merge(item_bounds) if found else item_bounds
		found = true
	return result

func _visual(asset: String, base: Vector3, size: Vector3) -> Node3D:
	var scene: PackedScene = load("res://assets/dungeon/" + asset + ".glb") as PackedScene
	var model: Node3D = scene.instantiate() as Node3D
	var bounds: AABB = _bounds(model)
	var wrapper: Node3D = Node3D.new()
	wrapper.position = base
	geometry.add_child(wrapper)
	wrapper.add_child(model)
	wrapper.scale = size / bounds.size
	model.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z)
	return wrapper

func _piece(asset: String, base: Vector3, size: Vector3, cover_object: bool) -> void:
	_visual(asset, base, size)
	_box(base, size, cover_object)

func _box(base: Vector3, size: Vector3, cover_object: bool) -> void:
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

func _lights() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("090e17")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a6bcde")
	environment.ambient_light_energy = 0.5
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_intensity = 1.5
	environment.glow_enabled = true
	environment.fog_enabled = true
	environment.fog_light_color = Color("26313f")
	environment.fog_density = 0.007
	environment.volumetric_fog_enabled = RenderingServer.get_current_rendering_method() == "forward_plus"
	environment.volumetric_fog_density = 0.006
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-60, -20, 0)
	key.light_color = Color("b6ccec")
	key.light_energy = 0.85
	key.shadow_enabled = true
	add_child(key)
	for point: Vector3 in [Vector3(-9.8, 1.6, -7), Vector3(9.8, 1.6, -7), Vector3(-9.8, 1.6, 5), Vector3(9.8, 1.6, 5), Vector3(0, 1.6, -11.7)]:
		_visual("SM_WallTorch", point, Vector3(0.35, 0.7, 0.3))
		var light: OmniLight3D = OmniLight3D.new()
		light.position = point + Vector3(0, 0.5, 0.6)
		light.light_color = Color("ffb76f")
		light.light_energy = 3.2
		light.omni_range = 10.0
		light.shadow_enabled = true
		add_child(light)
