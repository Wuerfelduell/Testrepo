class_name DiceMesh
extends Node3D
## Presentation only: the rules provide the value. Geometry never determines a roll.
## Every triangular face carries its actual number, including the landed face.

var value: int = 1
var dropped: bool = false
var landing_basis: Basis = Basis.IDENTITY
var _faces: Array[PackedVector3Array] = []
var _face_bases: Array[Basis] = []

func configure(result: int, is_dropped: bool = false) -> void:
	value = clampi(result, 1, 20)
	dropped = is_dropped
	_build_icosahedron()
	landing_basis = _face_bases[value - 1].transposed()
	basis = landing_basis

func tumble(elapsed: float, offset: float) -> void:
	rotation = Vector3(elapsed * 8.3 + offset, elapsed * 11.7, elapsed * 5.2 + offset)
	position.y = absf(sin(elapsed * 8.0 + offset)) * 0.2

func land() -> void:
	basis = landing_basis
	position.y = 0.0

func _build_icosahedron() -> void:
	for child: Node in get_children():
		child.queue_free()
	_faces.clear()
	_face_bases.clear()
	var phi: float = (1.0 + sqrt(5.0)) / 2.0
	var vertices: Array[Vector3] = [
		Vector3(-1, phi, 0), Vector3(1, phi, 0), Vector3(-1, -phi, 0), Vector3(1, -phi, 0),
		Vector3(0, -1, phi), Vector3(0, 1, phi), Vector3(0, -1, -phi), Vector3(0, 1, -phi),
		Vector3(phi, 0, -1), Vector3(phi, 0, 1), Vector3(-phi, 0, -1), Vector3(-phi, 0, 1),
	]
	var indices: Array[Vector3i] = [
		Vector3i(0,11,5), Vector3i(0,5,1), Vector3i(0,1,7), Vector3i(0,7,10), Vector3i(0,10,11),
		Vector3i(1,5,9), Vector3i(5,11,4), Vector3i(11,10,2), Vector3i(10,7,6), Vector3i(7,1,8),
		Vector3i(3,9,4), Vector3i(3,4,2), Vector3i(3,2,6), Vector3i(3,6,8), Vector3i(3,8,9),
		Vector3i(4,9,5), Vector3i(2,4,11), Vector3i(6,2,10), Vector3i(8,6,7), Vector3i(9,8,1),
	]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("454956") if dropped else Color("a17b39")
	material.metallic = 0.4
	material.roughness = 0.32
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	for face_index: int in range(indices.size()):
		var triangle: Vector3i = indices[face_index]
		var a: Vector3 = vertices[triangle.x].normalized()
		var b: Vector3 = vertices[triangle.y].normalized()
		var c: Vector3 = vertices[triangle.z].normalized()
		var center: Vector3 = (a + b + c) / 3.0
		var normal: Vector3 = center.normalized()
		var up: Vector3 = (a - center).normalized()
		var right: Vector3 = up.cross(normal).normalized()
		var face_basis: Basis = Basis(right, normal.cross(right).normalized(), normal)
		_face_bases.append(face_basis)
		_faces.append(PackedVector3Array([a, b, c]))
		for vertex: Vector3 in [a, b, c]:
			surface.set_normal(normal)
			surface.add_vertex(vertex)
		var number: Label3D = Label3D.new()
		number.text = str(face_index + 1)
		number.font_size = 64
		number.pixel_size = 0.0045
		number.outline_size = 5
		number.modulate = Color("a2a6b0") if dropped else Color("fff4cd")
		number.outline_modulate = Color("24202b")
		number.no_depth_test = false
		number.shaded = false
		number.position = center + normal * 0.008
		number.basis = face_basis
		add_child(number)
	var shape: MeshInstance3D = MeshInstance3D.new()
	shape.mesh = surface.commit()
	add_child(shape)
