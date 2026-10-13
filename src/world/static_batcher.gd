class_name StaticBatcher
extends Node3D
## Draw-call reduction for built levels: every static kit mesh (floors, walls, stairs,
## props) is moved into one MultiMesh per mesh, material and 12 m chunk, so a room costs
## a few dozen draw calls instead of one per piece and surface. Chunks keep frustum and
## light culling local. The original wrapper nodes stay in the tree without meshes:
## gameplay code may still move or scale them (the wall cutaway does) and calls sync().
## Colliders, navigation and picking never depend on these meshes.

const CHUNK_M: float = 12.0

## Wrapper node -> [{"multimesh": MultiMesh, "index": int, "local": Transform3D}].
var _instances: Dictionary = {}
var _batches: Array[MultiMeshInstance3D] = []

## Batches every MeshInstance3D below `source`. `wrappers` are the nodes whose transform
## may change later (fading walls); their instances are tracked for sync().
func batch(source: Node3D, wrappers: Array[Node3D] = []) -> void:
	var tracked: Dictionary = {}
	for wrapper: Node3D in wrappers:
		tracked[wrapper] = true
	var groups: Dictionary = {}
	var order: Array = []
	for node: Node in source.find_children("*", "MeshInstance3D", true, false):
		var item: MeshInstance3D = node as MeshInstance3D
		if item.mesh == null or not item.is_visible_in_tree() or _has_surface_overrides(item):
			continue
		var world: Transform3D = item.global_transform
		var chunk: Vector2i = Vector2i(floori(world.origin.x / CHUNK_M), floori(world.origin.z / CHUNK_M))
		var key: Array = [item.mesh, item.material_override, item.cast_shadow, chunk]
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		var owner_wrapper: Node3D = _tracked_ancestor(item, tracked)
		groups[key].append({"item": item, "world": world, "wrapper": owner_wrapper})
	for key: Array in order:
		var entries: Array = groups[key]
		var multimesh: MultiMesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = key[0]
		multimesh.instance_count = entries.size()
		var holder: MultiMeshInstance3D = MultiMeshInstance3D.new()
		holder.name = "Batch%d" % _batches.size()
		holder.multimesh = multimesh
		holder.material_override = key[1]
		holder.cast_shadow = key[2]
		add_child(holder)
		holder.global_transform = Transform3D.IDENTITY
		for index: int in entries.size():
			var entry: Dictionary = entries[index]
			multimesh.set_instance_transform(index, entry["world"])
			var wrapper: Node3D = entry["wrapper"]
			if wrapper != null:
				if not _instances.has(wrapper):
					_instances[wrapper] = []
				_instances[wrapper].append({"multimesh": multimesh, "index": index,
					"local": wrapper.global_transform.affine_inverse() * entry["world"]})
		_batches.append(holder)
		for entry: Dictionary in entries:
			(entry["item"] as MeshInstance3D).queue_free()

## Re-places the instances of a tracked wrapper after its transform changed.
func sync(wrapper: Node3D) -> void:
	for entry: Dictionary in _instances.get(wrapper, []):
		(entry["multimesh"] as MultiMesh).set_instance_transform(int(entry["index"]), wrapper.global_transform * (entry["local"] as Transform3D))

func batch_count() -> int:
	return _batches.size()

func instance_total() -> int:
	var total: int = 0
	for holder: MultiMeshInstance3D in _batches:
		total += holder.multimesh.instance_count
	return total

static func _has_surface_overrides(item: MeshInstance3D) -> bool:
	for surface: int in item.get_surface_override_material_count():
		if item.get_surface_override_material(surface) != null:
			return true
	return false

static func _tracked_ancestor(item: Node, tracked: Dictionary) -> Node3D:
	var current: Node = item
	while current != null:
		if tracked.has(current):
			return current as Node3D
		current = current.get_parent()
	return null
