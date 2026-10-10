class_name SpellVFX
extends Node3D
## Presentation of spells. Every effect follows the authoritative spell timeline
## (Game.state.pending elapsed), so a projectile arrives exactly when the rules
## apply damage. Persistent markers show Shield and Sleep while they last.

const FIRE: Color = Color(1.0, 0.52, 0.16)
const FROST: Color = Color(0.62, 0.9, 1.0)
const ARCANE: Color = Color(0.68, 0.55, 1.0)
const SLEEP: Color = Color(0.78, 0.66, 1.0)
const SHIELD: Color = Color(0.45, 0.75, 1.0)
const FADE: float = 0.5

var actors: Dictionary = {}
var _active: Array[Dictionary] = []
var _bubbles: Dictionary = {}
var _sleep_marks: Dictionary = {}

## The caster plays the cast clip, released at release_time (CombatActor treats it
## like a ranged attack with an animation override).
static func animation_pending(pending: Dictionary) -> Dictionary:
	match String(pending.get("type", "")):
		"spell":
			return {"type": "attack", "actor_id": pending["actor_id"], "duration": pending["duration"],
				"impact_time": pending["release_time"], "elapsed": minf(float(pending["elapsed"]), float(pending["duration"])),
				"weapon": {"ranged": true, "attack_clip": SpellResolver.CAST_CLIP}}
		"reaction":
			return animation_pending(pending.get("resume", {}))
	return pending

func on_event(event: Dictionary) -> void:
	match String(event.get("type", "")):
		"start_spell":
			_start(event)
		"cast_reaction":
			var actor: Node3D = actors.get(String(event.get("actor_id", ""))) as Node3D
			if actor != null:
				_burst(actor.global_position + Vector3.UP * 1.0, SHIELD, 50, 0.45, 2.5)

func _start(event: Dictionary) -> void:
	var caster: Node3D = actors.get(String(event["actor_id"])) as Node3D
	if caster == null:
		return
	var effect: Dictionary = {"spell_id": String(event["spell_id"]), "actor_id": String(event["actor_id"]),
		"release": float(event["release_time"]), "impact": float(event["impact_time"]),
		"duration": float(event["duration"]), "time": 0.0, "impacted": false, "nodes": [],
		"target_ids": event.get("target_ids", []).duplicate(), "point": event.get("point", Vector3.ZERO)}
	match effect["spell_id"]:
		"fire_bolt":
			effect["nodes"] = [_bolt(FIRE, 0.16, true)]
		"ray_of_frost":
			effect["nodes"] = [_beam(FROST)]
		"magic_missile":
			var darts: Array = []
			for index: int in effect["target_ids"].size():
				darts.append(_bolt(ARCANE, 0.1, true))
			effect["nodes"] = darts
		"burning_hands":
			effect["nodes"] = [_cone_fire(caster)]
		"sleep":
			effect["nodes"] = [_bolt(SLEEP, 0.12, true)]
	for node: Node3D in effect["nodes"]:
		node.visible = false
	_active.append(effect)

## Called every frame by the arena with the current authoritative state.
func sync(state: GameState, delta: float) -> void:
	var pending: Dictionary = state.pending
	var running: Dictionary = pending
	if pending.get("type") == "reaction":
		running = pending.get("resume", {})
	for effect: Dictionary in _active.duplicate():
		var follows: bool = running.get("type") == "spell" and String(running.get("spell_id", "")) == effect["spell_id"] \
			and String(running.get("actor_id", "")) == effect["actor_id"]
		if follows:
			effect["time"] = float(running["elapsed"])
		elif pending.get("type") != "reaction":
			effect["time"] = float(effect["time"]) + delta
		_update(effect, state)
		if float(effect["time"]) > float(effect["duration"]) + FADE:
			for node: Node3D in effect["nodes"]:
				if is_instance_valid(node):
					node.queue_free()
			_active.erase(effect)
	_update_markers(state, delta)

func _update(effect: Dictionary, state: GameState) -> void:
	var caster: Node3D = actors.get(effect["actor_id"]) as Node3D
	if caster == null:
		return
	var time: float = float(effect["time"])
	var release: float = float(effect["release"])
	var impact: float = float(effect["impact"])
	var progress: float = clampf((time - release) / maxf(0.001, impact - release), 0.0, 1.0)
	var hand: Vector3 = caster.global_position + Vector3.UP * 1.35 + caster.global_transform.basis.z.normalized() * 0.35
	var flying: bool = time >= release and time < impact
	match effect["spell_id"]:
		"fire_bolt", "sleep":
			var node: Node3D = effect["nodes"][0]
			var destination: Vector3 = _target_point(effect, state, 0)
			node.visible = flying
			node.global_position = hand.lerp(destination, progress) + Vector3.UP * sin(progress * PI) * 0.4
		"ray_of_frost":
			var beam: MeshInstance3D = effect["nodes"][0]
			var destination: Vector3 = _target_point(effect, state, 0)
			var tip: Vector3 = hand.lerp(destination, progress)
			beam.visible = time >= release and time < impact + 0.25
			_place_beam(beam, hand, tip)
		"magic_missile":
			for index: int in effect["nodes"].size():
				var dart: Node3D = effect["nodes"][index]
				var destination: Vector3 = _target_point(effect, state, index)
				var side: Vector3 = (destination - hand).cross(Vector3.UP).normalized() * (float(index) - 1.0) * 1.4
				var control: Vector3 = hand.lerp(destination, 0.45) + side + Vector3.UP * (0.8 + 0.3 * index)
				var t: float = progress
				dart.visible = flying
				dart.global_position = hand.lerp(control, t).lerp(control.lerp(destination, t), t)
		"burning_hands":
			var fire: CPUParticles3D = effect["nodes"][0]
			fire.global_position = hand
			fire.emitting = time >= release and time < impact + 0.15
			fire.visible = true
	if not bool(effect["impacted"]) and time >= impact:
		effect["impacted"] = true
		_impact(effect, state)

func _impact(effect: Dictionary, state: GameState) -> void:
	match effect["spell_id"]:
		"fire_bolt":
			_burst(_target_point(effect, state, 0), FIRE, 70, 0.55, 4.0)
		"ray_of_frost":
			_burst(_target_point(effect, state, 0), FROST, 60, 0.6, 3.0)
		"magic_missile":
			for index: int in effect["target_ids"].size():
				_burst(_target_point(effect, state, index), ARCANE, 30, 0.4, 2.5)
		"sleep":
			_sleep_mist(effect["point"] as Vector3)

func _target_point(effect: Dictionary, state: GameState, index: int) -> Vector3:
	var ids: Array = effect["target_ids"]
	if index < ids.size():
		var node: Node3D = actors.get(String(ids[index])) as Node3D
		if node != null:
			return node.global_position + Vector3.UP * 1.0
	return (effect["point"] as Vector3) + Vector3.UP * 0.5

func _update_markers(state: GameState, delta: float) -> void:
	for id: String in actors:
		var record: Dictionary = state.actors.get(id, {})
		var node: Node3D = actors[id] as Node3D
		var shielded: bool = CombatRules.alive(record) and ActiveEffects.has_kind(record, "shield")
		if shielded and not _bubbles.has(id):
			_bubbles[id] = _shield_bubble()
		if _bubbles.has(id):
			var bubble: MeshInstance3D = _bubbles[id]
			if not shielded:
				bubble.queue_free()
				_bubbles.erase(id)
			else:
				bubble.global_position = node.global_position + Vector3.UP * 1.0
				var material: StandardMaterial3D = bubble.material_override
				material.albedo_color.a = 0.13 + 0.05 * sin(Time.get_ticks_msec() / 220.0)
		var asleep: bool = CombatRules.alive(record) and ActiveEffects.has_kind(record, "sleep")
		if asleep and not _sleep_marks.has(id):
			_sleep_marks[id] = _sleep_label()
		if _sleep_marks.has(id):
			var mark: Label3D = _sleep_marks[id]
			if not asleep:
				mark.queue_free()
				_sleep_marks.erase(id)
			else:
				var deep: bool = "unconscious" in record.get("conditions", [])
				mark.text = "Z z z" if deep else "z z"
				mark.global_position = node.global_position + Vector3.UP * (2.3 + 0.08 * sin(Time.get_ticks_msec() / 400.0))

func _bolt(color: Color, radius: float, trail: bool) -> Node3D:
	var root: Node3D = Node3D.new()
	add_child(root)
	var core: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	core.mesh = sphere
	core.material_override = _glow(color, 1.0, 6.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var light: OmniLight3D = OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.5
	light.omni_range = 4.0
	root.add_child(light)
	if trail:
		var particles: CPUParticles3D = _particles(color, 60, 0.35, radius * 0.9)
		particles.local_coords = false
		particles.initial_velocity_min = 0.1
		particles.initial_velocity_max = 0.5
		particles.spread = 180.0
		root.add_child(particles)
	return root

func _beam(color: Color) -> MeshInstance3D:
	var beam: MeshInstance3D = MeshInstance3D.new()
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = 0.05
	cylinder.bottom_radius = 0.09
	cylinder.height = 1.0
	beam.mesh = cylinder
	beam.material_override = _glow(color, 0.85, 4.0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	return beam

static func _place_beam(beam: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var length: float = maxf(0.01, from.distance_to(to))
	beam.global_position = from.lerp(to, 0.5)
	var axis: Vector3 = (to - from).normalized()
	if axis.length_squared() < 0.5:
		return
	var reference: Vector3 = Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x: Vector3 = axis.cross(reference).normalized()
	var z: Vector3 = x.cross(axis).normalized()
	beam.global_basis = Basis(x, axis * length, z)

func _cone_fire(caster: Node3D) -> CPUParticles3D:
	var particles: CPUParticles3D = _particles(FIRE, 260, 0.42, 0.42)
	particles.local_coords = false
	particles.emitting = false
	particles.direction = Vector3(0, 0, 1)
	particles.spread = rad_to_deg(atan(0.5))
	particles.initial_velocity_min = 8.5
	particles.initial_velocity_max = 11.0
	particles.damping_min = 2.0
	particles.damping_max = 4.0
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(1.0, 0.9, 0.45, 1.0))
	ramp.set_color(1, Color(0.8, 0.1, 0.02, 0.0))
	ramp.add_point(0.45, Color(1.0, 0.42, 0.08, 0.9))
	particles.color_ramp = ramp
	add_child(particles)
	# Emit along the caster's facing (imported characters face local +Z).
	particles.global_basis = caster.global_basis.orthonormalized()
	return particles

func _sleep_mist(center: Vector3) -> void:
	var mist: CPUParticles3D = _particles(SLEEP, 90, 1.8, 0.35)
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	mist.emission_sphere_radius = 1.5
	mist.direction = Vector3.UP
	mist.spread = 40.0
	mist.initial_velocity_min = 0.1
	mist.initial_velocity_max = 0.4
	mist.one_shot = true
	mist.explosiveness = 0.6
	add_child(mist)
	mist.global_position = center + Vector3.UP * 0.6
	mist.emitting = true
	get_tree().create_timer(2.5).timeout.connect(mist.queue_free)

func _burst(position: Vector3, color: Color, amount: int, lifetime: float, speed: float) -> void:
	var burst: CPUParticles3D = _particles(color, amount, lifetime, 0.12)
	burst.one_shot = true
	burst.explosiveness = 0.95
	burst.spread = 180.0
	burst.initial_velocity_min = speed * 0.4
	burst.initial_velocity_max = speed
	add_child(burst)
	burst.global_position = position
	burst.emitting = true
	var light: OmniLight3D = OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = 5.0
	add_child(light)
	light.global_position = position
	var tween: Tween = light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, lifetime)
	tween.tween_callback(light.queue_free)
	get_tree().create_timer(lifetime + 0.6).timeout.connect(burst.queue_free)

func _particles(color: Color, amount: int, lifetime: float, size: float) -> CPUParticles3D:
	var particles: CPUParticles3D = CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.gravity = Vector3.ZERO
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(size, size)
	var material: StandardMaterial3D = _glow(color, 0.9, 3.0)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	# Soft round sprites with additive light instead of hard squares.
	material.albedo_texture = _soft_dot()
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.emission_enabled = false
	quad.material = material
	particles.mesh = quad
	particles.color = color
	var shrink: Curve = Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.15))
	particles.scale_amount_curve = shrink
	return particles

static var _dot: GradientTexture2D

static func _soft_dot() -> GradientTexture2D:
	if _dot == null:
		var gradient: Gradient = Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.35, Color(1, 1, 1, 0.75))
		_dot = GradientTexture2D.new()
		_dot.gradient = gradient
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		_dot.width = 64
		_dot.height = 64
	return _dot

func _shield_bubble() -> MeshInstance3D:
	var bubble: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.85
	sphere.height = 2.1
	bubble.mesh = sphere
	bubble.material_override = _glow(SHIELD, 0.15, 1.5)
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bubble)
	return bubble

func _sleep_label() -> Label3D:
	var label: Label3D = Label3D.new()
	label.font_size = 72
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 10
	label.modulate = SLEEP
	add_child(label)
	return label

static func _glow(color: Color, alpha: float, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
