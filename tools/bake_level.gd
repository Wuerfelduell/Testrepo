extends SceneTree
## Bakes the crypt navigation from its colliders (package 10):
## godot --headless --script res://tools/bake_level.gd

func _initialize() -> void:
	call_deferred("_bake")

func _bake() -> void:
	var builder: CryptBuilder = CryptBuilder.new()
	root.add_child(builder)
	await process_frame
	builder.bake()
	print("CRYPT_BAKED_POLYGONS: ", builder.navigation.navigation_mesh.get_polygon_count())
	builder.queue_free()
	await process_frame
	quit()
