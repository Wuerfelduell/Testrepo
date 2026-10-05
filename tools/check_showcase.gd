extends SceneTree
## Import/runtime acceptance checks. These do not replace the owner's visual art approval.

var checks: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(false, message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/showcase/asset_showcase.tscn")
	check(packed != null, "Showcase scene must load")
	var gallery: Node3D = packed.instantiate()
	root.add_child(gallery)
	await process_frame
	check(gallery.actors.size() == 6, "Both human bases and four outfit samples must be present")
	check(gallery.animation_names.size() == 42, "42 authored motion clips must be available (T-pose excluded)")
	for actor: PreviewActor in gallery.actors:
		check(actor.skeleton.get_bone_count() > 40, "Imported characters must retain the humanoid rig")
		for name: String in gallery.animation_names:
			check(actor.player.has_animation(name), "Every sample must support " + name)
			var animation: Animation = actor.player.get_animation(name)
			check(animation.get_track_count() > 0, "Motion tracks must survive retargeting: " + name)
			actor.play_clip(name)
			actor.player.advance(minf(0.25, animation.length / 2.0))
			check(actor.player.current_animation == name, "Requested clip must actually start: " + name)
			for track: int in animation.get_track_count():
				var path: NodePath = animation.track_get_path(track)
				check(actor.skeleton.find_bone(path.get_subname(0)) >= 0, "No animation may target a missing bone")
	gallery._select_animation(0)
	var old: int = gallery.selector.selected
	var next: InputEventAction = InputEventAction.new()
	next.action = "gallery_next"
	next.pressed = true
	gallery._unhandled_input(next)
	check(gallery.selector.selected != old, "Keyboard next action must change the selected animation")
	gallery._reset_view()
	check(is_equal_approx(gallery.distance, 18.0), "Reset must restore the gallery framing")
	check(tr("GALLERY_TITLE") == "THE RPG", "English translation must be installed")
	for filename: String in DirAccess.get_files_at("res://assets/dungeon"):
		if not filename.ends_with(".glb"):
			continue
		var scene: PackedScene = load("res://assets/dungeon/" + filename)
		check(scene != null, "Every selected dungeon asset must import")
		var model: Node3D = scene.instantiate()
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for surface: int in mesh.mesh.get_surface_count():
				var material: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				check(material != null, "Dungeon surfaces must use PBR materials")
				check(material.albedo_texture != null, "Dungeon albedo map must resolve")
				check(material.normal_texture != null, "Dungeon normal map must resolve")
				check(material.roughness_texture != null, "Dungeon roughness map must resolve")
		model.free()
	gallery.queue_free()
	await process_frame
	print("SHOWCASE_CHECKS_PASSED: ", checks)
	quit()
