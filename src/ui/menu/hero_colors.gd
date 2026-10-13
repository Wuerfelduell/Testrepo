class_name HeroColors
extends RefCounted
## Per-piece hero colours chosen in character creation (assets/characters/hero_colors.json).
## A record's "colors" maps slot id -> palette id; a missing slot keeps the built look's
## colour. apply() swaps the matching outfit materials of a loaded model for recoloured
## copies, so creation preview, combat actors and portraits all show the same hero.

const PATH: String = "res://assets/characters/hero_colors.json"
const SHADER: Shader = preload("res://assets/characters/shaders/hero_recolor.gdshader")

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_data = parsed if parsed is Dictionary else {"palettes": {}, "slots": {}, "order": [], "materials": {}}
	return _data

## Palette entries ({id, name_key, rgb}) offered for a slot.
static func palette(slot: String) -> Array:
	var info: Dictionary = data()["slots"].get(slot, {})
	return data()["palettes"].get(String(info.get("palette", "")), [])

static func default_id(slot: String) -> String:
	return String(data()["slots"].get(slot, {}).get("default", ""))

static func slot_name_key(slot: String) -> String:
	return String(data()["slots"].get(slot, {}).get("name_key", slot))

static func entry(slot: String, color_id: String) -> Dictionary:
	for candidate: Dictionary in palette(slot):
		if String(candidate["id"]) == color_id:
			return candidate
	return {}

static func rgb(slot: String, color_id: String) -> Color:
	var values: Array = entry(slot, color_id).get("rgb", [0.5, 0.5, 0.5])
	return Color(float(values[0]), float(values[1]), float(values[2]))

## Roughly how the colour reads on the model, for menu swatches.
static func swatch(slot: String, color_id: String) -> Color:
	var palette_id: String = String(data()["slots"].get(slot, {}).get("palette", ""))
	var scale: float = float(data().get("swatch_scale", {}).get(palette_id, 1.0))
	var color: Color = rgb(slot, color_id)
	return Color(color.r * scale, color.g * scale, color.b * scale)

## Slots the model's materials offer, in display order.
static func slots_for(model: Node) -> Array[String]:
	var found: Dictionary = {}
	for material_name: String in _material_names(model):
		var spec: Dictionary = data()["materials"].get(material_name, {})
		for key: String in ["cloth", "leather", "tint"]:
			if spec.has(key):
				found[String(spec[key])] = true
	var result: Array[String] = []
	for slot: Variant in data()["order"]:
		if found.has(String(slot)):
			result.append(String(slot))
	return result

## Only known slots with known, non-default colours; the rest is dropped.
static func clean(colors: Variant, slots: Array[String] = []) -> Dictionary:
	var result: Dictionary = {}
	if not colors is Dictionary:
		return result
	for slot: Variant in colors:
		var key: String = String(slot)
		var value: String = String(colors[slot])
		if not data()["slots"].has(key) or (not slots.is_empty() and not key in slots):
			continue
		if not entry(key, value).is_empty() and value != default_id(key):
			result[key] = value
	return result

## Recolours every matching surface below root. Calling it again with other colours
## replaces the earlier overrides; an empty dictionary restores the built look.
static func apply(root: Node, colors: Variant) -> void:
	var chosen: Dictionary = clean(colors)
	var made: Dictionary = {}
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for surface: int in mesh.mesh.get_surface_count():
			var original: Material = mesh.mesh.surface_get_material(surface)
			if original == null or not data()["materials"].has(original.resource_name):
				continue
			if not made.has(original.resource_name):
				made[original.resource_name] = _recoloured(original, data()["materials"][original.resource_name], chosen)
			mesh.set_surface_override_material(surface, made[original.resource_name])

static func _recoloured(original: Material, spec: Dictionary, chosen: Dictionary) -> Material:
	var base: StandardMaterial3D = original as StandardMaterial3D
	if base == null:
		return null
	if spec.has("tint"):
		var slot: String = String(spec["tint"])
		if not chosen.has(slot):
			return null
		var tinted: StandardMaterial3D = base.duplicate() as StandardMaterial3D
		tinted.albedo_color = rgb(slot, chosen[slot])
		return tinted
	var cloth: String = String(spec.get("cloth", ""))
	var leather: String = String(spec.get("leather", ""))
	if not chosen.has(cloth) and not chosen.has(leather):
		return null
	var material: ShaderMaterial = ShaderMaterial.new()
	material.resource_name = original.resource_name
	material.shader = SHADER
	material.set_shader_parameter("albedo_tex", base.albedo_texture)
	material.set_shader_parameter("albedo_color", base.albedo_color)
	material.set_shader_parameter("mask_tex", load(String(spec["mask"])))
	material.set_shader_parameter("use_normal", base.normal_enabled and base.normal_texture != null)
	material.set_shader_parameter("normal_tex", base.normal_texture)
	material.set_shader_parameter("normal_scale", base.normal_scale)
	material.set_shader_parameter("use_orm", base.roughness_texture != null)
	material.set_shader_parameter("orm_tex", base.roughness_texture)
	material.set_shader_parameter("metallic", base.metallic)
	material.set_shader_parameter("roughness", base.roughness)
	for pair: Array in [["cloth", cloth], ["leather", leather]]:
		var slot: String = pair[1]
		var on: bool = chosen.has(slot)
		material.set_shader_parameter(pair[0] + "_amount", 1.0 if on else 0.0)
		if on:
			var color: Color = rgb(slot, chosen[slot])
			material.set_shader_parameter(pair[0] + "_color", Vector3(color.r, color.g, color.b))
	return material

static func _material_names(model: Node) -> Dictionary:
	var names: Dictionary = {}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh != null:
			for surface: int in mesh.mesh.get_surface_count():
				var material: Material = mesh.mesh.surface_get_material(surface)
				if material != null:
					names[material.resource_name] = true
	return names

## Stable text for caches keyed by look and colours (portraits).
static func signature(colors: Variant) -> String:
	var chosen: Dictionary = clean(colors)
	var keys: Array = chosen.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for key: Variant in keys:
		parts.append("%s=%s" % [key, chosen[key]])
	return ",".join(parts)
