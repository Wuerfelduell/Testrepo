class_name HitEffects
extends RefCounted
## Presentation only: blood, sparks and dust for combat events. Never touches GameState.
## CPUParticles3D because the shipped renderer is gl_compatibility (no GPU particles there
## on every driver). Every effect frees itself; blood stains on the floor stay a while.

const BLOOD: StringName = &"blood"
const BLOOD_CRITICAL: StringName = &"blood_critical"
const SPARKS: StringName = &"sparks"
const DUST: StringName = &"dust"
const NONE: StringName = &""
# Melee contact is decided from geometry: the events carry no weapon, and an attack is
# melee when the two combatants stand within reach (1.5 m) plus body radii.
const MELEE_DISTANCE: float = 2.4
const PHYSICAL: PackedStringArray = ["slashing", "piercing", "bludgeoning"]
const MAX_STAINS: int = 24
const STAIN_SECONDS: float = 45.0
const DEATH_DUST_DELAY: float = 0.75

static var _stains: Array[Node3D] = []


## Which effect an event shows on the actor it targets. Pure, so it is unit-tested.
## `critical` is the last attack roll against this target (damage follows its roll).
static func effect_for(event: Dictionary, attacker_distance: float, critical: bool) -> StringName:
	match String(event.get("type", "")):
		"roll":
			if String(event.get("kind", "")) == "attack" and not bool(event.get("hit", true)) \
					and attacker_distance <= MELEE_DISTANCE:
				return SPARKS
		"damage":
			if int(event.get("amount", 0)) > 0 and PHYSICAL.has(String(event.get("damage_type", ""))):
				return BLOOD_CRITICAL if critical else BLOOD
		"death":
			return DUST
	return NONE


static func spawn(parent: Node, effect: StringName, at: Vector3, from_direction: Vector3) -> Node3D:
	match effect:
		BLOOD:
			return _blood(parent, at, from_direction, false)
		BLOOD_CRITICAL:
			return _blood(parent, at, from_direction, true)
		SPARKS:
			return _sparks(parent, at, from_direction)
		DUST:
			return _dust(parent, at)
	return null


static func _blood(parent: Node, at: Vector3, from_direction: Vector3, heavy: bool) -> Node3D:
	var root: Node3D = _root(parent, "BloodSpray", at)
	var away: Vector3 = _flat(from_direction)
	# The spray leaves the wound away from the attacker and falls to the floor.
	var spray: CPUParticles3D = _particles(root, 80 if heavy else 40, 1.1, 0.95)
	spray.direction = away + Vector3.UP * 0.45
	spray.spread = 38.0 if heavy else 28.0
	spray.initial_velocity_min = 2.2 if heavy else 1.6
	spray.initial_velocity_max = 5.2 if heavy else 3.6
	spray.gravity = Vector3(0, -9.0, 0)
	spray.scale_amount_min = 0.03
	spray.scale_amount_max = 0.09 if heavy else 0.065
	spray.color_ramp = _ramp([Color(0.55, 0.02, 0.02, 1.0), Color(0.32, 0.0, 0.0, 1.0), Color(0.18, 0.0, 0.0, 0.0)])
	spray.mesh = _sphere_mesh(_material(Color(0.5, 0.02, 0.02), false))
	if heavy:
		var flash: OmniLight3D = OmniLight3D.new()
		flash.light_color = Color(1.0, 0.25, 0.15)
		flash.light_energy = 2.5
		flash.omni_range = 2.5
		root.add_child(flash)
		root.create_tween().tween_property(flash, "light_energy", 0.0, 0.25)
	# The floor keeps a stain where the blood lands.
	_stain(parent, Vector3(at.x, 0.0, at.z) + away * (0.55 if heavy else 0.35), 0.55 if heavy else 0.32)
	_expire(root, 1.4)
	return root


static func _sparks(parent: Node, at: Vector3, from_direction: Vector3) -> Node3D:
	var root: Node3D = _root(parent, "WeaponSparks", at)
	var sparks: CPUParticles3D = _particles(root, 40, 0.45, 1.0)
	# Sparks fly back toward the attacker and up off the parried edge.
	sparks.direction = -_flat(from_direction) + Vector3.UP * 0.6
	sparks.spread = 55.0
	sparks.initial_velocity_min = 2.5
	sparks.initial_velocity_max = 6.0
	sparks.gravity = Vector3(0, -12.0, 0)
	sparks.scale_amount_min = 0.02
	sparks.scale_amount_max = 0.045
	sparks.color_ramp = _ramp([Color(1.0, 0.95, 0.7, 1.0), Color(1.0, 0.6, 0.15, 1.0), Color(0.8, 0.2, 0.0, 0.0)])
	sparks.mesh = _sphere_mesh(_material(Color(1.0, 0.8, 0.4), true, true))
	var flash: OmniLight3D = OmniLight3D.new()
	flash.light_color = Color(1.0, 0.75, 0.4)
	flash.light_energy = 1.6
	flash.omni_range = 2.0
	root.add_child(flash)
	root.create_tween().tween_property(flash, "light_energy", 0.0, 0.18)
	_expire(root, 0.8)
	return root


static func _dust(parent: Node, at: Vector3) -> Node3D:
	var root: Node3D = _root(parent, "DeathDust", Vector3(at.x, 0.05, at.z))
	var dust: CPUParticles3D = _particles(root, 28, 1.6, 1.0)
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	dust.emission_ring_axis = Vector3.UP
	dust.emission_ring_radius = 0.45
	dust.emission_ring_inner_radius = 0.2
	dust.emission_ring_height = 0.02
	dust.direction = Vector3.UP
	dust.spread = 80.0
	dust.initial_velocity_min = 0.3
	dust.initial_velocity_max = 0.9
	dust.gravity = Vector3(0, 0.15, 0)
	dust.damping_min = 0.6
	dust.damping_max = 1.2
	dust.scale_amount_min = 0.12
	dust.scale_amount_max = 0.3
	dust.color_ramp = _ramp([Color(0.55, 0.5, 0.44, 0.0), Color(0.5, 0.46, 0.4, 0.5), Color(0.45, 0.42, 0.38, 0.0)])
	dust.mesh = _sphere_mesh(_material(Color(0.55, 0.5, 0.44), true))
	# The body hits the floor part-way into Death01; the dust waits for it (hidden until
	# then: an idle emitter would still draw its instances at the origin). Connections to
	# a freed node are dropped by the engine, so no stale callbacks remain.
	dust.visible = false
	var landed: Signal = root.get_tree().create_timer(DEATH_DUST_DELAY).timeout
	landed.connect(dust.show)
	landed.connect(dust.restart)
	_expire(root, DEATH_DUST_DELAY + 2.0)
	return root


static func _stain(parent: Node, at: Vector3, radius: float) -> void:
	var stain: MeshInstance3D = MeshInstance3D.new()
	stain.name = "BloodStain"
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = Vector2(radius, radius * 0.75) * 2.0
	stain.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.0, 0.0, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.25
	material.albedo_texture = _splat_texture()
	material.render_priority = -1
	stain.material_override = material
	stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(stain, true)
	stain.global_position = at + Vector3(0, 0.012 + 0.0005 * _stains.size(), 0)
	stain.rotation.y = randf() * TAU
	_stains.assign(_stains.filter(func(node: Variant) -> bool: return is_instance_valid(node)))
	_stains.append(stain)
	while _stains.size() > MAX_STAINS:
		_stains.pop_front().queue_free()
	var fade: Tween = stain.create_tween()
	fade.tween_interval(STAIN_SECONDS)
	fade.tween_property(material, "albedo_color:a", 0.0, 4.0)
	fade.tween_callback(stain.queue_free)


static var _splat: ImageTexture

static func _splat_texture() -> ImageTexture:
	# Deterministic irregular splat: a soft blob with droplets, built once.
	if _splat != null:
		return _splat
	var size: int = 64
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 707
	var blobs: Array[Vector3] = [Vector3(0.5, 0.5, 0.3)]
	for i: int in 9:
		var angle: float = rng.randf() * TAU
		var distance: float = rng.randf_range(0.18, 0.42)
		blobs.append(Vector3(0.5 + cos(angle) * distance, 0.5 + sin(angle) * distance, rng.randf_range(0.03, 0.09)))
	for y: int in size:
		for x: int in size:
			var p: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5) / float(size)
			var alpha: float = 0.0
			for blob: Vector3 in blobs:
				var d: float = p.distance_to(Vector2(blob.x, blob.y)) / blob.z
				alpha = maxf(alpha, clampf(1.4 - d * 1.4, 0.0, 1.0))
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	_splat = ImageTexture.create_from_image(image)
	return _splat


static func _root(parent: Node, node_name: String, at: Vector3) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = node_name
	parent.add_child(root, true)
	root.global_position = at
	# A fresh emitter draws all instances at its origin until its first update: show the
	# effect from the next frame on, never as one big blob.
	root.visible = false
	root.get_tree().process_frame.connect(root.show, CONNECT_ONE_SHOT)
	return root


static func _particles(root: Node3D, amount: int, lifetime: float, explosiveness: float) -> CPUParticles3D:
	var particles: CPUParticles3D = CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = explosiveness
	particles.randomness = 0.6
	particles.local_coords = false
	particles.emitting = true
	root.add_child(particles)
	return particles


static func _material(color: Color, transparent: bool, glow: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if glow else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if transparent:
		# No BILLBOARD_PARTICLES: the compatibility renderer drops the particle scale with it.
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 3.0
	return material


static func _sphere_mesh(material: Material) -> SphereMesh:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = material
	return mesh


static func _ramp(colors: Array[Color]) -> Gradient:
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray(colors)
	var offsets: PackedFloat32Array = []
	for i: int in colors.size():
		offsets.append(float(i) / float(colors.size() - 1))
	gradient.offsets = offsets
	return gradient


static func _flat(direction: Vector3) -> Vector3:
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD


static func _expire(root: Node3D, seconds: float) -> void:
	root.get_tree().create_timer(seconds).timeout.connect(root.queue_free)
