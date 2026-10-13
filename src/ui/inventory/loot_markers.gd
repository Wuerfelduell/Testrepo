class_name LootMarkers
extends Node3D
## A slowly pulsing gold ring under every body or pile that still holds something.
## The one under the mouse glows brighter (GameMenus.hover_loot).

var _rings: Dictionary = {}
var _material: StandardMaterial3D
var _time: float = 0.0
var _bright: StandardMaterial3D
var highlighted: String = "":
	set(value):
		highlighted = value
		for id: String in _rings:
			(_rings[id] as MeshInstance3D).material_override = _bright if id == value else _material

func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(0.95, 0.78, 0.38, 0.8)
	_bright = StandardMaterial3D.new()
	_bright.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bright.albedo_color = Color(1.0, 0.93, 0.6)
	add_to_group("loot_markers")
	EventBus.state_changed.connect(_sync)
	_sync()

func _sync() -> void:
	var state: GameState = Game.state
	var wanted: Dictionary = LootRules.sources(state)
	for id: String in _rings.keys():
		if not wanted.has(id):
			(_rings[id] as Node).queue_free()
			_rings.erase(id)
	for id: String in wanted:
		if not _rings.has(id):
			var ring: MeshInstance3D = MeshInstance3D.new()
			var torus: TorusMesh = TorusMesh.new()
			torus.inner_radius = 0.62
			torus.outer_radius = 0.7
			ring.mesh = torus
			ring.material_override = _bright if id == highlighted else _material
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(ring)
			_rings[id] = ring
		(_rings[id] as MeshInstance3D).position = (wanted[id] as Vector3) + Vector3.UP * 0.05

func _process(delta: float) -> void:
	if _rings.is_empty():
		return
	_time += delta
	_material.albedo_color.a = 0.45 + sin(_time * 2.5) * 0.3
