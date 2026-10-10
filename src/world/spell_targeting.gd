class_name SpellTargeting
extends Node3D
## Spell targeting in the arena (docs/UI.md section 3): range ring, area template on
## the ground, affected characters highlighted (red enemy, yellow ally), hit chance or
## "DC 12 DEX save" in the HUD before casting. Produces CastSpellCommands only.

signal command_ready(command: Command)

const ENEMY_COLOR: Color = Color(0.93, 0.3, 0.24, 0.9)
const ALLY_COLOR: Color = Color(1.0, 0.82, 0.25, 0.95)
const CONE_COLOR: Color = Color(1.0, 0.45, 0.12, 0.28)
const SPHERE_COLOR: Color = Color(0.62, 0.48, 1.0, 0.28)
const RANGE_COLOR: Color = Color(0.85, 0.75, 0.5, 0.55)

var hud: CombatHUD
var caster_id: String = "hero"
var spell_id: String = ""
var dart_targets: Array[String] = []
var last_preview: Dictionary = {}
var last_point: Vector3 = Vector3.INF
var last_target: String = ""
var _template: MeshInstance3D
var _range_ring: MeshInstance3D
var _rings: Array[MeshInstance3D] = []
var _labels: Array[Label3D] = []

func _ready() -> void:
	_template = _mesh_node()
	_range_ring = _mesh_node()

func is_active() -> bool:
	return not spell_id.is_empty()

func begin(id: String) -> bool:
	var state: GameState = Game.state
	var spell: SpellDefinition = SpellBook.get_spell(id)
	if spell == null or spell.casting_time == "reaction" or not state.actors.has(caster_id):
		return false
	if not SpellResolver.availability_reason(state, caster_id, spell).is_empty():
		return false
	spell_id = id
	dart_targets.clear()
	last_preview = {}
	if hud != null:
		hud.set_spell_mode(id)
	_draw_range(state, spell)
	return true

func cancel() -> void:
	spell_id = ""
	dart_targets.clear()
	last_preview = {}
	last_point = Vector3.INF
	last_target = ""
	_template.mesh = null
	_range_ring.mesh = null
	_clear_highlights()
	if hud != null:
		hud.set_spell_mode("")
		hud.clear_target()

## Cursor over an actor (id may be empty) or the ground point under it.
func hover(actor_id: String, point: Vector3) -> void:
	if not is_active():
		return
	var state: GameState = Game.state
	var spell: SpellDefinition = SpellBook.get_spell(spell_id)
	if spell == null or not state.actors.has(caster_id):
		cancel()
		return
	var caster: Dictionary = state.actors[caster_id]
	var origin: Vector3 = caster["position"]
	var target_ids: Array = []
	var aim: Vector3 = Vector3.INF
	last_target = ""
	match spell.targeting:
		"creature":
			if actor_id.is_empty() or actor_id == caster_id:
				_template.mesh = null
				_clear_highlights()
				if hud != null:
					hud.clear_target()
				return
			target_ids = [actor_id]
			last_target = actor_id
		"darts":
			target_ids = dart_targets.duplicate()
			if not actor_id.is_empty() and actor_id != caster_id:
				last_target = actor_id
		"self", "point":
			aim = point if actor_id.is_empty() or not state.actors.has(actor_id) else state.actors[actor_id]["position"]
			last_point = aim
	var full: Array = target_ids.duplicate()
	if spell.targeting == "darts" and not last_target.is_empty():
		full.append(last_target)
	var count: int = SpellRules.dart_count(spell, SpellResolver.effective_slot(caster, spell, 0))
	if spell.targeting == "darts":
		while full.size() < count and not full.is_empty():
			full.append(full[-1])
	last_preview = SpellResolver.preview(state, caster_id, spell_id, 0, full, aim)
	_draw_template(state, spell, origin, aim, actor_id)
	_highlight(state, last_preview, spell)
	if hud != null:
		hud.show_spell_preview(last_preview, spell, caster, dart_targets.size())

## Left click while targeting. Returns the command when the cast is complete.
func click() -> Command:
	if not is_active() or last_preview.is_empty():
		return null
	var spell: SpellDefinition = SpellBook.get_spell(spell_id)
	var command: Command = null
	match spell.targeting:
		"creature":
			if bool(last_preview["legal"]) and not last_target.is_empty():
				command = CastSpellCommand.new(caster_id, spell_id, [last_target])
		"darts":
			if last_target.is_empty():
				return null
			var probe: Array = dart_targets.duplicate()
			probe.append(last_target)
			var caster: Dictionary = Game.state.actors[caster_id]
			var count: int = SpellRules.dart_count(spell, SpellResolver.effective_slot(caster, spell, 0))
			var filled: Array = probe.duplicate()
			while filled.size() < count:
				filled.append(filled[-1])
			if not bool(SpellResolver.preview(Game.state, caster_id, spell_id, 0, filled)["legal"]):
				return null
			dart_targets.append(last_target)
			if dart_targets.size() >= count:
				command = CastSpellCommand.new(caster_id, spell_id, dart_targets)
			else:
				hover(last_target, Vector3.INF)
		"self", "point":
			if bool(last_preview["legal"]) and last_point.is_finite():
				command = CastSpellCommand.new(caster_id, spell_id, [], last_point)
	if command != null:
		cancel()
		command_ready.emit(command)
	return command

func _draw_range(state: GameState, spell: SpellDefinition) -> void:
	if spell.range_m <= 0.0:
		_range_ring.mesh = null
		return
	var center: Vector3 = state.actors[caster_id]["position"]
	var mesh: ImmediateMesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material(RANGE_COLOR, true))
	var segments: int = 96
	for index: int in segments:
		var a: float = TAU * index / segments
		var b: float = TAU * (index + 1) / segments
		mesh.surface_add_vertex(center + Vector3(cos(a), 0.07, sin(a)) * Vector3(spell.range_m, 1.0, spell.range_m))
		mesh.surface_add_vertex(center + Vector3(cos(b), 0.07, sin(b)) * Vector3(spell.range_m, 1.0, spell.range_m))
	mesh.surface_end()
	_range_ring.mesh = mesh

func _draw_template(state: GameState, spell: SpellDefinition, origin: Vector3, aim: Vector3, actor_id: String) -> void:
	var mesh: ImmediateMesh = ImmediateMesh.new()
	match spell.area:
		"cone":
			var direction: Vector3 = Vector3(aim.x - origin.x, 0.0, aim.z - origin.z)
			if direction.length_squared() < 0.01:
				_template.mesh = null
				return
			direction = direction.normalized()
			var half_angle: float = atan(0.5)
			var base: Vector3 = origin + Vector3.UP * 0.06
			mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(CONE_COLOR, false))
			var steps: int = 24
			for index: int in steps:
				var a: float = -half_angle + 2.0 * half_angle * index / steps
				var b: float = -half_angle + 2.0 * half_angle * (index + 1) / steps
				var length_a: float = spell.area_size_m / cos(a)
				var length_b: float = spell.area_size_m / cos(b)
				mesh.surface_add_vertex(base)
				mesh.surface_add_vertex(base + direction.rotated(Vector3.UP, a) * length_a)
				mesh.surface_add_vertex(base + direction.rotated(Vector3.UP, b) * length_b)
			mesh.surface_end()
			_outline_cone(mesh, base, direction, half_angle, spell.area_size_m)
		"sphere":
			var center: Vector3 = aim + Vector3.UP * 0.08
			var legal: bool = bool(last_preview.get("legal", false))
			mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(SPHERE_COLOR if legal else Color(0.9, 0.2, 0.2, 0.25), false))
			var segments: int = 48
			for index: int in segments:
				var a: float = TAU * index / segments
				var b: float = TAU * (index + 1) / segments
				mesh.surface_add_vertex(center)
				mesh.surface_add_vertex(center + Vector3(cos(a), 0, sin(a)) * spell.area_size_m)
				mesh.surface_add_vertex(center + Vector3(cos(b), 0, sin(b)) * spell.area_size_m)
			mesh.surface_end()
		_:
			# Single-target spells: a line from the caster's hands to the target.
			var target_id: String = actor_id if not actor_id.is_empty() else last_target
			if target_id.is_empty() or not state.actors.has(target_id):
				_template.mesh = null
				return
			var color: Color = Color(0.55, 0.9, 1.0, 0.8) if bool(last_preview.get("legal", false)) else Color(1, 0.35, 0.3, 0.8)
			mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material(color, true))
			mesh.surface_add_vertex(origin + Vector3.UP * 1.3)
			mesh.surface_add_vertex((state.actors[target_id]["position"] as Vector3) + Vector3.UP * 1.0)
			mesh.surface_end()
	_template.mesh = mesh

func _outline_cone(mesh: ImmediateMesh, base: Vector3, direction: Vector3, half_angle: float, length: float) -> void:
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _material(Color(1.0, 0.6, 0.25, 0.9), true))
	mesh.surface_add_vertex(base)
	var steps: int = 16
	for index: int in steps + 1:
		var a: float = -half_angle + 2.0 * half_angle * index / steps
		mesh.surface_add_vertex(base + direction.rotated(Vector3.UP, a) * (length / cos(a)))
	mesh.surface_add_vertex(base)
	mesh.surface_end()

func _highlight(state: GameState, preview: Dictionary, spell: SpellDefinition) -> void:
	_clear_highlights()
	var counts: Dictionary = {}
	for value: Variant in dart_targets:
		counts[String(value)] = int(counts.get(String(value), 0)) + 1
	for target: Dictionary in preview.get("targets", []):
		var id: String = String(target["id"])
		if not state.actors.has(id):
			continue
		var position: Vector3 = state.actors[id]["position"]
		_add_ring(position, ALLY_COLOR if bool(target.get("ally", false)) else ENEMY_COLOR)
		var text: String = ""
		match spell.resolution:
			"attack":
				text = "%d%%" % roundi(float(target.get("chance", 0.0)) * 100.0)
			"save":
				text = tr("ABILITY_" + String(spell.save_ability).to_upper()) + " %d%%" % roundi(float(target.get("save_chance", 0.0)) * 100.0)
			"auto":
				text = "×%d" % int(counts.get(id, 0)) if counts.has(id) else ""
		if not text.is_empty():
			_add_label(position + Vector3.UP * 2.45, text, ALLY_COLOR if bool(target.get("ally", false)) else Color(1, 0.86, 0.75))
	if spell.targeting == "darts":
		for id: String in counts:
			if state.actors.has(id) and not preview.get("targets", []).any(func(t: Dictionary) -> bool: return String(t["id"]) == id):
				_add_ring(state.actors[id]["position"], ENEMY_COLOR)
				_add_label((state.actors[id]["position"] as Vector3) + Vector3.UP * 2.45, "×%d" % int(counts[id]), Color(1, 0.86, 0.75))

func _add_ring(position: Vector3, color: Color) -> void:
	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.46
	torus.outer_radius = 0.56
	torus.rings = 32
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = _material(color, true)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = position + Vector3.UP * 0.05
	ring.scale = Vector3(1.0, 0.2, 1.0)
	_rings.append(ring)

func _add_label(position: Vector3, text: String, color: Color) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 12
	label.modulate = color
	add_child(label)
	label.global_position = position
	_labels.append(label)

func _clear_highlights() -> void:
	for node: Node3D in _rings:
		node.queue_free()
	for node: Node3D in _labels:
		node.queue_free()
	_rings.clear()
	_labels.clear()

func _mesh_node() -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

static func _material(color: Color, on_top: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = on_top
	return material
