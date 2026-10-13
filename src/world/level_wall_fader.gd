class_name LevelWallFader
extends Node
## BG3-style cutaway (package 10): walls, pillars and shelves between the camera and the
## hero or the active combatant are cut down to a low stub (and fade where the renderer
## supports transparency), and stop catching mouse clicks while cut.
## Cover and line of sight (collision layer 4) never change: this is presentation only.

const FADED: float = 1.0
## Height left of a cut wall, as a fraction (a stub keeps the room outline readable).
const STUB: float = 0.12
const FADE_SPEED: float = 5.0
const CAST_LENGTH: float = 45.0
## Body layer bits: 1 = floor/walls for picking and navigation parsing, 4 = cover rays.
const PICK_LAYER: int = 1

var occluders: Array[Dictionary] = []
var _amount: Array[float] = []

var _base_scale: Array[float] = []

func setup(p_occluders: Array[Dictionary]) -> void:
	occluders = p_occluders
	_amount.resize(occluders.size())
	_amount.fill(0.0)
	_base_scale.clear()
	for entry: Dictionary in occluders:
		_base_scale.append((entry["visual"] as Node3D).scale.y)

## Indices of occluders that hide any focus point from the camera.
func blocking(camera: Camera3D, focus_points: Array[Vector3]) -> Dictionary:
	var result: Dictionary = {}
	if camera == null:
		return result
	var back: Vector3 = camera.global_basis.z.normalized()
	var side: Vector3 = camera.global_basis.x.normalized()
	for point: Vector3 in focus_points:
		if not point.is_finite():
			continue
		for offset: Vector3 in [Vector3.UP * 0.3, Vector3.UP * 1.7, Vector3.UP * 1.0 + side * 0.7, Vector3.UP * 1.0 - side * 0.7]:
			var from: Vector3 = point + offset
			var to: Vector3 = from + back * CAST_LENGTH
			for index: int in occluders.size():
				if not result.has(index) and (occluders[index]["box"] as AABB).grow(0.05).intersects_segment(from, to):
					result[index] = true
	return result

func update(camera: Camera3D, focus_points: Array[Vector3], delta: float) -> void:
	var hidden: Dictionary = blocking(camera, focus_points)
	for index: int in occluders.size():
		var target: float = FADED if hidden.has(index) else 0.0
		var previous: float = _amount[index]
		var next: float = move_toward(previous, target, delta * FADE_SPEED)
		if is_equal_approx(next, previous):
			continue
		_amount[index] = next
		var entry: Dictionary = occluders[index]
		var visual: Node3D = entry["visual"] as Node3D
		visual.scale.y = _base_scale[index] * lerpf(1.0, STUB, next)
		if entry.get("batcher") is StaticBatcher:
			# The wall's meshes live in a MultiMesh: move its instances with the wrapper.
			(entry["batcher"] as StaticBatcher).sync(visual)
		for child: Node in visual.find_children("*", "GeometryInstance3D", true, false):
			(child as GeometryInstance3D).transparency = next * 0.4
		var body: StaticBody3D = entry["body"] as StaticBody3D
		if body != null:
			if next > 0.3:
				body.collision_layer &= ~PICK_LAYER
			else:
				body.collision_layer |= PICK_LAYER

func faded_count() -> int:
	var count: int = 0
	for value: float in _amount:
		if value > 0.3:
			count += 1
	return count
