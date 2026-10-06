extends SceneTree

func _initialize() -> void:
	call_deferred("_bake")

func _bake() -> void:
	var builder: ArenaBuilder = ArenaBuilder.new()
	root.add_child(builder)
	await process_frame
	builder.bake()
	print("ARENA_BAKED_POLYGONS: ", builder.navigation.navigation_mesh.get_polygon_count())
	builder.queue_free()
	await process_frame
	quit()
