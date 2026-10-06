class_name PreviewActor
extends Node3D
## Presentation only: asset preview, no gameplay state or combat decisions.

const ANIMATIONS: PackedScene = preload("res://assets/animations/universal.glb")
var player: AnimationPlayer
var skeleton: Skeleton3D
var available: PackedStringArray = []
var weapon_attachment: BoneAttachment3D
var weapon: Node3D

func setup(scene_path: String, title_key: String) -> void:
	var model: Node3D = (load(scene_path) as PackedScene).instantiate()
	add_child(model)
	var skeletons: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	assert(skeletons.size() == 1, "Expected one humanoid skeleton")
	skeleton = skeletons[0] as Skeleton3D
	player = AnimationPlayer.new()
	model.add_child(player)
	player.root_node = NodePath("..")
	var source: Node3D = ANIMATIONS.instantiate()
	var source_player: AnimationPlayer = source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var source_skeleton: Skeleton3D = source.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var library: AnimationLibrary = AnimationLibrary.new()
	for clip_name: String in source_player.get_animation_list():
		if clip_name == "RESET" or clip_name == "A_TPose":
			continue
		var clip: Animation = source_player.get_animation(clip_name).duplicate(true) as Animation
		for track: int in range(clip.get_track_count() - 1, -1, -1):
			var old_path: NodePath = clip.track_get_path(track)
			if old_path.get_subname_count() == 0:
				clip.remove_track(track)
				continue
			var bone_name: String = old_path.get_subname(0)
			if skeleton.find_bone(bone_name) < 0:
				clip.remove_track(track)
				continue
			clip.track_set_path(track, NodePath(str(model.get_path_to(skeleton)) + ":" + bone_name))
			var source_rest: Transform3D = source_skeleton.get_bone_rest(source_skeleton.find_bone(bone_name))
			var target_rest: Transform3D = skeleton.get_bone_rest(skeleton.find_bone(bone_name))
			if clip.track_get_type(track) == Animation.TYPE_SCALE_3D:
				clip.remove_track(track)
				continue
			for frame: int in clip.track_get_key_count(track):
				if clip.track_get_type(track) == Animation.TYPE_POSITION_3D:
					var source_position: Vector3 = clip.track_get_key_value(track, frame)
					clip.track_set_key_value(track, frame, target_rest.origin + source_position - source_rest.origin)
				elif clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
					var source_rotation: Quaternion = clip.track_get_key_value(track, frame)
					clip.track_set_key_value(track, frame, target_rest.basis.get_rotation_quaternion() * source_rest.basis.get_rotation_quaternion().inverse() * source_rotation)
		if clip_name.ends_with("Loop") or clip_name.ends_with("_Loop"):
			clip.loop_mode = Animation.LOOP_LINEAR
		library.add_animation(clip_name, clip)
	player.add_animation_library("", library)
	available = player.get_animation_list()
	source.free()
	var title: Label3D = Label3D.new()
	title.text = tr(title_key)
	title.position = Vector3(0, 2.05, 0)
	title.font_size = 46
	title.pixel_size = 0.0042
	title.modulate = Color("ead4a0")
	title.outline_modulate = Color("0d1421")
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.no_depth_test = true
	add_child(title)
	play_clip("Idle")

func equip_weapon(scene_path: String) -> void:
	assert(weapon_attachment == null, "Only one preview weapon per hand")
	assert(skeleton.find_bone("hand_r") >= 0, "Source rig must have a right hand")
	weapon_attachment = BoneAttachment3D.new()
	weapon_attachment.name = "RightHandWeapon"
	weapon_attachment.bone_name = "hand_r"
	skeleton.add_child(weapon_attachment)
	weapon = (load(scene_path) as PackedScene).instantiate() as Node3D
	weapon.name = "PreviewWeapon"
	weapon_attachment.add_child(weapon)
	# Authoring origin is the grip centre. Bone +Y runs along the fingers;
	# blade +Y is rotated across the palm, not along the fingers/forearm.
	weapon.position = Vector3(0.0, 0.065, 0.018)
	weapon.rotation_degrees = Vector3(0, 0, -90)

func play_clip(clip_name: String) -> void:
	assert(player.has_animation(clip_name), "Missing requested animation: " + clip_name)
	player.stop()
	skeleton.reset_bone_poses()
	player.play(clip_name, 0.15)
