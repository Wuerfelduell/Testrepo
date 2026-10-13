extends GutTest
## StaticBatcher: kit meshes collapse into MultiMeshes per mesh and chunk, and tracked
## wrappers (fading walls) still move their instances.

func _piece(parent: Node3D, mesh: Mesh, position: Vector3) -> Node3D:
	var wrapper: Node3D = Node3D.new()
	wrapper.position = position
	parent.add_child(wrapper)
	var item: MeshInstance3D = MeshInstance3D.new()
	item.mesh = mesh
	item.position = Vector3(0, 0.5, 0)
	wrapper.add_child(item)
	return wrapper

func test_same_mesh_in_one_chunk_becomes_one_multimesh() -> void:
	var root: Node3D = Node3D.new()
	add_child_autofree(root)
	var box: BoxMesh = BoxMesh.new()
	var sphere: SphereMesh = SphereMesh.new()
	var wall: Node3D = _piece(root, box, Vector3(1, 0, 1))
	_piece(root, box, Vector3(4, 0, 1))
	_piece(root, sphere, Vector3(2, 0, 2))
	_piece(root, box, Vector3(40, 0, 1))
	var batcher: StaticBatcher = StaticBatcher.new()
	root.add_child(batcher)
	batcher.batch(root, [wall])
	assert_eq(batcher.batch_count(), 3, "box near, sphere, box in a far chunk")
	assert_eq(batcher.instance_total(), 4)
	await get_tree().process_frame
	assert_eq(root.find_children("*", "MeshInstance3D", true, false).size(), 0, "originals are gone")
	# Headless tests use the dummy renderer, which keeps no instance data: check the bookkeeping.
	var tracked: Array = batcher._instances[wall]
	assert_eq(tracked.size(), 1)
	assert_eq((tracked[0]["local"] as Transform3D).origin, Vector3(0, 0.5, 0), "mesh offset inside the wall wrapper")
	wall.scale.y = 0.12
	batcher.sync(wall)
	assert_almost_eq((wall.global_transform * (tracked[0]["local"] as Transform3D)).origin.y, 0.06, 0.001)
