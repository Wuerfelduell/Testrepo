class_name TownBuilder
extends CryptBuilder
## Das Torviertel (Overcity, start of act 1): the gate district of Rabenfels. The hero enters
## through the city gate, walks up the Torgasse to the Torplatz; a side alley leads to the
## crypt entrance, the north road is barricaded (later districts). Houses are assembled from
## the Quaternius Medieval Village kit (assets/town/, 2 m grid, 3 m storeys). Only the streets
## have floor colliders, so the baked navigation (tools/bake_level.gd) stays on them.

const TOWN_NAVIGATION_PATH: String = "res://scenes/levels/torviertel/torviertel_navigation.tres"
const KIT: String = "res://assets/town/"
const STOREY: float = 3.0
const SEGMENT: float = 2.0
## Walkable streets as Rect2(x, z, width along x, depth along z) in metres.
const STREETS: Array[Rect2] = [
	Rect2(-4.0, -6.0, 8.0, 24.0),    # Torgasse (gate street), gate at z = 18
	Rect2(-14.0, -24.0, 28.0, 18.0), # Torplatz (square)
	Rect2(-22.0, -16.0, 8.0, 4.0),   # Kellergasse (alley to the crypt entrance)
	Rect2(-3.0, -29.0, 6.0, 5.0),    # north road, barricaded
]
## Houses: front centre on the street, the direction the front faces, width and depth in
## 2 m segments, storeys, ground-floor style ("brick" or "plaster") and whether the front
## has a door. Every roof size exists in the kit (Roof_RoundTiles_<width>x<depth>).
const HOUSES: Array[Dictionary] = [
	# Torgasse, west side (fronts face east)
	{"at": Vector3(-4.4, 0, 15.0), "face": Vector3.RIGHT, "w": 3, "d": 4, "floors": 2, "style": "brick", "door": false},
	{"at": Vector3(-4.4, 0, 8.0), "face": Vector3.RIGHT, "w": 4, "d": 5, "floors": 2, "style": "plaster", "door": true},
	{"at": Vector3(-4.4, 0, 1.0), "face": Vector3.RIGHT, "w": 3, "d": 4, "floors": 3, "style": "brick", "door": true},
	{"at": Vector3(-4.4, 0, -4.0), "face": Vector3.RIGHT, "w": 2, "d": 4, "floors": 2, "style": "plaster", "door": false},
	# Torgasse, east side (fronts face west); the first one is the guard house
	{"at": Vector3(4.4, 0, 16.0), "face": Vector3.LEFT, "w": 2, "d": 3, "floors": 2, "style": "brick", "door": true},
	{"at": Vector3(4.4, 0, 10.0), "face": Vector3.LEFT, "w": 4, "d": 4, "floors": 2, "style": "brick", "door": false},
	{"at": Vector3(4.4, 0, 3.0), "face": Vector3.LEFT, "w": 3, "d": 5, "floors": 2, "style": "plaster", "door": true},
	{"at": Vector3(4.4, 0, -3.0), "face": Vector3.LEFT, "w": 3, "d": 4, "floors": 3, "style": "plaster", "door": false},
	# Torplatz, west side
	{"at": Vector3(-14.4, 0, -9.0), "face": Vector3.RIGHT, "w": 3, "d": 4, "floors": 2, "style": "brick", "door": true},
	{"at": Vector3(-14.4, 0, -20.0), "face": Vector3.RIGHT, "w": 4, "d": 5, "floors": 2, "style": "plaster", "door": true},
	# Torplatz, east side
	{"at": Vector3(14.4, 0, -9.0), "face": Vector3.LEFT, "w": 3, "d": 4, "floors": 2, "style": "plaster", "door": true},
	{"at": Vector3(14.4, 0, -15.0), "face": Vector3.LEFT, "w": 3, "d": 5, "floors": 3, "style": "brick", "door": false},
	{"at": Vector3(14.4, 0, -21.0), "face": Vector3.LEFT, "w": 3, "d": 4, "floors": 2, "style": "plaster", "door": true},
	# Torplatz, north side (fronts face south); the wide one is the inn
	{"at": Vector3(-8.5, 0, -24.4), "face": Vector3.BACK, "w": 4, "d": 6, "floors": 3, "style": "brick", "door": true},
	{"at": Vector3(6.5, 0, -24.4), "face": Vector3.BACK, "w": 3, "d": 4, "floors": 2, "style": "plaster", "door": true},
	{"at": Vector3(11.5, 0, -24.4), "face": Vector3.BACK, "w": 2, "d": 4, "floors": 3, "style": "brick", "door": false},
	# North road, both sides
	{"at": Vector3(-3.4, 0, -30.0), "face": Vector3.RIGHT, "w": 2, "d": 3, "floors": 2, "style": "brick", "door": false},
	{"at": Vector3(3.4, 0, -30.0), "face": Vector3.LEFT, "w": 2, "d": 3, "floors": 2, "style": "plaster", "door": false},
	# Crypt entrance: an old charnel house at the end of the alley
	{"at": Vector3(-22.4, 0, -14.0), "face": Vector3.RIGHT, "w": 2, "d": 2, "floors": 1, "style": "brick", "door": true},
]
const ROOF_SIZES: Dictionary = {2: [4, 6, 8], 3: [4, 6, 8, 10, 12, 14], 4: [8, 10, 12, 14]}
## Paved ground inside the city wall; outside lies open land with the road to the gate.
const GROUND_RECT: Rect2 = Rect2(-38.0, -52.0, 76.0, 70.0)

var _scenes: Dictionary = {}

func _init() -> void:
	# 24 m chunks: ~20 % fewer draw calls in the town than 12 m (measured 16-10-2026).
	batch_chunk_m = 24.0

func build() -> void:
	if geometry != null:
		return
	geometry = Node3D.new()
	geometry.name = "TownGeometry"
	add_child(geometry)
	_ground()
	for house: Dictionary in HOUSES:
		_house(house)
	for house: Dictionary in back_rows():
		_house(house)
	_city_wall()
	_square()
	_barricade()
	_town_lights()
	if is_inside_tree():
		_batch_meshes()
	navigation = NavigationRegion3D.new()
	navigation.name = "BakedNavigation"
	add_child(navigation)
	if ResourceLoader.exists(TOWN_NAVIGATION_PATH):
		navigation.navigation_mesh = load(TOWN_NAVIGATION_PATH) as NavigationMesh

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
	assert(mesh.get_polygon_count() > 0, "Town navigation bake must contain polygons")
	assert(ResourceSaver.save(mesh, TOWN_NAVIGATION_PATH) == OK, "Town navigation bake must persist")

func is_floor_cell(cell: Vector2i) -> bool:
	return is_street(Vector3(cell.x * CELL, 0, cell.y * CELL))

func is_street(point: Vector3) -> bool:
	for street: Rect2 in STREETS:
		if street.has_point(Vector2(point.x, point.z)):
			return true
	return false

# Kit pieces ----------------------------------------------------------------------------

## One kit model at its authored size (the kit is metric), turned by `yaw` around Y.
func _kit(asset: String, parent: Node3D, position: Vector3, yaw: float = 0.0) -> Node3D:
	if not _scenes.has(asset):
		_scenes[asset] = load(KIT + asset + ".glb") as PackedScene
	var model: Node3D = (_scenes[asset] as PackedScene).instantiate() as Node3D
	model.position = position
	model.rotation.y = yaw
	parent.add_child(model)
	return model

func _ground() -> void:
	# Cobbles everywhere (gaps between houses stay paved); colliders only on the streets.
	var x: float = GROUND_RECT.position.x + SEGMENT * 0.5
	while x < GROUND_RECT.end.x:
		var z: float = GROUND_RECT.position.y + SEGMENT * 0.5
		while z < GROUND_RECT.end.y:
			_kit("Floor_UnevenBrick" if is_street(Vector3(x, 0, z)) else "Floor_Brick", geometry, Vector3(x, 0, z))
			z += SEGMENT
		x += SEGMENT
	var x_road: float = -1.0
	while x_road <= 1.0:
		var z_road: float = GROUND_RECT.end.y + SEGMENT * 0.5
		while z_road < 40.0:
			_kit("Floor_UnevenBrick", geometry, Vector3(x_road, 0, z_road))
			z_road += SEGMENT
		x_road += SEGMENT
	var land: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(240.0, 240.0)
	land.mesh = plane
	var earth: StandardMaterial3D = StandardMaterial3D.new()
	earth.albedo_color = Color("3b3a2a")
	earth.roughness = 1.0
	land.material_override = earth
	land.position = Vector3(0.0, -0.03, 0.0)
	geometry.add_child(land)
	for street: Rect2 in STREETS:
		_solid(Vector3(street.get_center().x, -0.2, street.get_center().y), Vector3(street.size.x, 0.2, street.size.y), false)

## A house built in its own frame: the front edge is centred on the origin facing +Z and
## the body extends to -Z. The wrapper is turned so the front faces `face`.
func _house(house: Dictionary) -> void:
	var width: int = int(house["w"])
	var depth: int = int(house["d"])
	var floors: int = int(house["floors"])
	var face: Vector3 = house["face"]
	var root: Node3D = Node3D.new()
	root.name = "House%d" % geometry.get_child_count()
	root.position = house["at"]
	root.rotation.y = atan2(face.x, face.z)
	geometry.add_child(root)
	var half_w: float = width * SEGMENT * 0.5
	var full_d: float = depth * SEGMENT
	var ground: String = "UnevenBrick" if String(house["style"]) == "brick" else "Plaster"
	var door_index: int = width / 2 if bool(house["door"]) else -1
	for storey: int in floors:
		var y: float = storey * STOREY
		var material: String = ground if storey == 0 else "Plaster"
		for i: int in width:
			var x: float = -half_w + SEGMENT * (i + 0.5)
			_kit(_front_piece(material, storey, i, door_index), root, Vector3(x, y, 0.0))
			_kit(_back_piece(material, storey, i), root, Vector3(x, y, -full_d), PI)
		for j: int in depth:
			var z: float = -SEGMENT * (j + 0.5)
			var side: String = "Wall_%s_Straight" % material if (j + storey) % 2 == 0 or depth < 3 else "Wall_%s_Window_Thin_Round" % material
			_kit(side, root, Vector3(-half_w, y, z), -PI / 2.0)
			_kit(side, root, Vector3(half_w, y, z), PI / 2.0)
		for corner: Vector3 in [Vector3(-half_w, y, 0.0), Vector3(half_w, y, 0.0), Vector3(-half_w, y, -full_d), Vector3(half_w, y, -full_d)]:
			_kit("Corner_Exterior_Wood" if material == "Plaster" else "Corner_Exterior_Brick", root, corner)
		if storey == 0:
			for i: int in width:
				var x: float = -half_w + SEGMENT * (i + 0.5)
				if i == door_index:
					_kit("Door_4_Round" if material == "UnevenBrick" else "Door_2_Flat", root, Vector3(x - 0.5, y, 0.0))
				else:
					_kit("WindowShutters_Wide_Round_Closed" if material == "UnevenBrick" else "WindowShutters_Wide_Flat_Open", root, Vector3(x, y, 0.0))
		else:
			for i: int in width:
				if (i + storey) % 2 == 0:
					_kit("Window_Wide_Flat1", root, Vector3(-half_w + SEGMENT * (i + 0.5), y, 0.0))
	var top: float = floors * STOREY
	var roof_w: int = width * 2
	var roof_d: int = _roof_depth(width, depth * 2)
	_kit("Roof_RoundTiles_%dx%d" % [roof_w, roof_d], root, Vector3(0.0, top, -full_d * 0.5))
	if roof_w in [4, 6, 8]:
		_kit("Roof_Front_Brick%d" % roof_w, root, Vector3(0.0, top, 0.0))
		_kit("Roof_Front_Brick%d" % roof_w, root, Vector3(0.0, top, -full_d), PI)
	if depth >= 4:
		_kit("Prop_Chimney", root, Vector3(half_w * 0.5, top + 1.0, -full_d * 0.7))
	# The cutaway box reaches over the ridge so chimneys and gables fade too.
	var size: Vector3 = Vector3(width * SEGMENT + 0.4, top + 5.0, full_d + 0.4)
	var body: StaticBody3D = _solid(Vector3.ZERO, Vector3(size.x, top, size.z), true)
	geometry.remove_child(body)
	root.add_child(body)
	body.position = Vector3(0.0, top * 0.5, -full_d * 0.5)
	occluders.append({"visual": root, "body": body, "box": _footprint(root, size, full_d)})

## Scenery houses closing the district off behind the street houses (west, north, east);
## the north row leaves the road open. Never walkable, no NPCs.
static func back_rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var widths: Array[int] = [3, 4, 2, 3, 4, 3, 2, 4]
	var index: int = 0
	var z: float = 4.0
	while z > -40.0:
		var w: int = widths[index % widths.size()]
		result.append({"at": Vector3(-27.5, 0, z - w), "face": Vector3.RIGHT, "w": w, "d": 4,
			"floors": 2 + index % 2, "style": "brick" if index % 3 == 0 else "plaster", "door": index % 2 == 0})
		result.append({"at": Vector3(27.5, 0, z - w - 1.0), "face": Vector3.LEFT, "w": w, "d": 4,
			"floors": 2 + (index + 1) % 2, "style": "plaster" if index % 3 == 0 else "brick", "door": false})
		z -= w * 2.0
		index += 1
	var x: float = -26.0
	while x < 26.0:
		var w: int = widths[index % widths.size()]
		if x + w * 2.0 > -4.0 and x < 4.0:
			x = 4.0
			continue
		result.append({"at": Vector3(x + w, 0, -38.5), "face": Vector3.BACK, "w": w, "d": 4,
			"floors": 2 + index % 2, "style": "brick" if index % 2 == 0 else "plaster", "door": index % 3 == 0})
		x += w * 2.0
		index += 1
	return result

func _roof_depth(width: int, depth_m: int) -> int:
	var options: Array = ROOF_SIZES[width]
	var best: int = options[0]
	for option: int in options:
		if absi(option - depth_m) < absi(best - depth_m):
			best = option
	return best

func _front_piece(material: String, storey: int, index: int, door_index: int) -> String:
	if storey == 0:
		if index == door_index:
			return "Wall_%s_Door_Round" % material
		return "Wall_%s_Window_Wide_Round" % material if material == "UnevenBrick" else "Wall_Plaster_Window_Wide_Flat"
	return "Wall_Plaster_Window_Wide_Flat" if (index + storey) % 2 == 0 else "Wall_Plaster_WoodGrid"

func _back_piece(material: String, storey: int, index: int) -> String:
	if (index + storey) % 3 == 1:
		return "Wall_%s_Window_Thin_Round" % material
	return "Wall_%s_Straight" % material

## World-space box of a house for the cutaway (front edge at the wrapper origin).
func _footprint(root: Node3D, size: Vector3, full_d: float) -> AABB:
	var centre: Vector3 = root.position + root.basis * Vector3(0.0, 0.0, -full_d * 0.5)
	var extent: Vector3 = (root.basis * Vector3(size.x, 0.0, size.z)).abs()
	return AABB(Vector3(centre.x - extent.x * 0.5, 0.0, centre.z - extent.z * 0.5), Vector3(extent.x, size.y, extent.z))

# Gate, square and barricade ------------------------------------------------------------

func _city_wall() -> void:
	# Two storeys of rough brick along z = 18.4 across the whole district; the gate is a 4 m gap in the lower storey.
	var wall: Node3D = Node3D.new()
	wall.name = "CityWall"
	geometry.add_child(wall)
	var x: float = -37.0
	while x < 38.0:
		if absf(x) > 2.0:
			_kit("Wall_UnevenBrick_Straight", wall, Vector3(x, 0.0, 18.4))
		_kit("Wall_UnevenBrick_Straight", wall, Vector3(x, STOREY, 18.4))
		x += SEGMENT
	for side: float in [-2.0, 2.0]:
		_kit("Corner_Exterior_Brick", wall, Vector3(side, 0.0, 18.4))
	# The gate stays shut: the world outside is not part of this slice.
	for offset: float in [-2.0, 0.0]:
		_kit("Door_8_Flat", wall, Vector3(offset, 0.0, 18.3))
	_solid(Vector3(0.0, 0.0, 18.4), Vector3(76.0, STOREY * 2.0, 0.5), true)
	occluders.append({"visual": wall, "body": null, "box": AABB(Vector3(-38.0, 0.0, 18.0), Vector3(76.0, STOREY * 2.0, 0.8))})

func _square() -> void:
	# Well in the middle of the Torplatz, the merchant's cart west of it, crates by the houses.
	_well(Vector3(0.0, 0.0, -14.0))
	_kit("Prop_Wagon", geometry, Vector3(-9.5, 0.0, -15.5))
	_solid(Vector3(-9.5, 0.0, -17.0), Vector3(2.0, 1.5, 3.6), true)
	for point: Vector3 in [Vector3(-11.8, 0, -21.2), Vector3(-12.9, 0, -21.4), Vector3(-12.3, 1.06, -21.3), Vector3(9.5, 0, -18.0), Vector3(12.5, 0, -7.0)]:
		_kit("Prop_Crate", geometry, point, 0.3 * point.x)
		if point.y < 0.5:
			_solid(point, Vector3(1.1, 1.06, 1.1), true)
			for direction: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
				var spot: Vector3 = point + direction * 1.4
				if is_street(spot):
					tactical_points.append(spot)
	_notice_board(Vector3(-3.9, 0.0, -23.2))

## Wooden board on two posts for notices (placeholder art from the kit's wood texture).
func _notice_board(at: Vector3) -> void:
	var wood: StandardMaterial3D = StandardMaterial3D.new()
	wood.albedo_texture = load(KIT + "textures/T_WoodTrim_BaseColor.png") as Texture2D
	wood.uv1_triplanar = true
	var paper: StandardMaterial3D = StandardMaterial3D.new()
	paper.albedo_color = Color("d9ccaa")
	for part: Array in [[Vector3(-0.8, 1.0, 0), Vector3(0.12, 2.0, 0.12), wood], [Vector3(0.8, 1.0, 0), Vector3(0.12, 2.0, 0.12), wood],
			[Vector3(0, 1.45, 0), Vector3(1.9, 0.95, 0.08), wood], [Vector3(-0.35, 1.5, 0.05), Vector3(0.45, 0.55, 0.01), paper],
			[Vector3(0.3, 1.4, 0.05), Vector3(0.4, 0.5, 0.01), paper]]:
		var mesh: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = part[1]
		mesh.mesh = box
		mesh.material_override = part[2]
		mesh.position = at + (part[0] as Vector3)
		geometry.add_child(mesh)
	_solid(at, Vector3(1.9, 2.0, 0.3), true)

func _well(center: Vector3) -> void:
	var stone: StandardMaterial3D = StandardMaterial3D.new()
	stone.albedo_texture = load(KIT + "textures/T_RockTrim_BaseColor.png") as Texture2D
	stone.uv1_triplanar = true
	stone.uv1_scale = Vector3(0.6, 0.6, 0.6)
	var ring: MeshInstance3D = MeshInstance3D.new()
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = 1.2
	cylinder.bottom_radius = 1.3
	cylinder.height = 0.9
	ring.mesh = cylinder
	ring.material_override = stone
	ring.position = center + Vector3(0, 0.45, 0)
	geometry.add_child(ring)
	var water: MeshInstance3D = MeshInstance3D.new()
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	water.mesh = disc
	var dark: StandardMaterial3D = StandardMaterial3D.new()
	dark.albedo_color = Color("0d1418")
	dark.roughness = 0.1
	water.material_override = dark
	water.position = center + Vector3(0, 0.88, 0)
	geometry.add_child(water)
	# Winch: two posts and a crossbar.
	var wood: StandardMaterial3D = StandardMaterial3D.new()
	wood.albedo_texture = load(KIT + "textures/T_WoodTrim_BaseColor.png") as Texture2D
	wood.uv1_triplanar = true
	for part: Array in [[Vector3(-1.15, 1.1, 0), Vector3(0.16, 2.2, 0.16)], [Vector3(1.15, 1.1, 0), Vector3(0.16, 2.2, 0.16)],
			[Vector3(0, 1.95, 0), Vector3(2.5, 0.14, 0.14)]]:
		var beam: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = part[1]
		beam.mesh = box
		beam.material_override = wood
		beam.position = center + (part[0] as Vector3)
		geometry.add_child(beam)
	_solid(center, Vector3(2.6, 0.9, 2.6), true)
	for direction: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		tactical_points.append(center + direction * 2.2)

func _barricade() -> void:
	# The north road is closed for now (later districts): a cart across the road and crates.
	_kit("Prop_Wagon", geometry, Vector3(1.6, 0.0, -27.0), PI / 2.0)
	for point: Vector3 in [Vector3(-2.0, 0, -27.2), Vector3(-1.9, 1.06, -27.2)]:
		_kit("Prop_Crate", geometry, point, 0.4)
	_solid(Vector3(0.0, 0.0, -27.2), Vector3(6.0, 1.6, 1.4), true)

func _town_lights() -> void:
	# Overcast late afternoon above Rabenfels; lanterns are already lit.
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("2a3445")
	sky_material.sky_horizon_color = Color("8c8478")
	sky_material.ground_bottom_color = Color("1c1a18")
	sky_material.ground_horizon_color = Color("6b645a")
	sky_material.sun_angle_max = 20.0
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_intensity = 1.2
	environment.glow_enabled = true
	environment.fog_enabled = true
	environment.fog_light_color = Color("6f6a63")
	environment.fog_density = 0.004
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.light_color = Color("f2c99a")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	# Wall lanterns (dungeon kit torches) along the street and around the square.
	var lanterns: Array = [
		[Vector3(-4.2, 2.2, 12.0), Vector3.RIGHT, true], [Vector3(4.2, 2.2, 6.0), Vector3.LEFT, false],
		[Vector3(-4.2, 2.2, -2.0), Vector3.RIGHT, false], [Vector3(14.2, 2.2, -12.0), Vector3.LEFT, true],
		[Vector3(-14.2, 2.2, -16.5), Vector3.RIGHT, false], [Vector3(5.0, 2.2, -24.2), Vector3.BACK, true],
		[Vector3(-8.0, 2.2, -24.2), Vector3.BACK, false], [Vector3(-21.0, 2.2, -12.2), Vector3.FORWARD, false],
	]
	for entry: Array in lanterns:
		var point: Vector3 = entry[0]
		var facing: Vector3 = entry[1]
		var torch: Node3D = _visual("SM_WallTorch", point, Vector3(0.35, 0.7, 0.3))
		torch.rotation.y = atan2(facing.x, facing.z)
		var light: OmniLight3D = OmniLight3D.new()
		light.position = point + Vector3(0, 0.5, 0) + facing * 0.6
		light.light_color = Color("ffb06a")
		light.light_energy = 2.4
		light.omni_range = 8.0
		light.shadow_enabled = bool(entry[2])
		light.distance_fade_enabled = true
		light.distance_fade_begin = 45.0
		light.distance_fade_length = 10.0
		add_child(light)
