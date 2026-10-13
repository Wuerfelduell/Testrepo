extends SceneTree
## Bakes the level navigation from their colliders (package 10 crypt, Torviertel):
## godot --headless --script res://tools/bake_level.gd

func _initialize() -> void:
	call_deferred("_bake")

func _bake() -> void:
	for builder: CryptBuilder in [CryptBuilder.new(), TownBuilder.new()]:
		root.add_child(builder)
		await process_frame
		builder.bake()
		print("%s_BAKED_POLYGONS: %d" % ["TOWN" if builder is TownBuilder else "CRYPT", builder.navigation.navigation_mesh.get_polygon_count()])
		builder.queue_free()
		await process_frame
	quit()
