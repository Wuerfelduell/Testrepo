class_name PreviewActor
extends Node3D
## Presentation only: asset preview, no gameplay state or combat decisions.

const ANIMATIONS: PackedScene = preload("res://assets/animations/universal.glb")
var player: AnimationPlayer
var skeleton: Skeleton3D
var available: PackedStringArray = []
var weapon_attachment: BoneAttachment3D
var weapon: Node3D
var weapon_scene: String = ""
var offhand_attachment: BoneAttachment3D
var offhand: Node3D
const LOOKS_PATH: String = "res://assets/characters/looks.json"
const WEAPONS_PATH: String = "res://assets/weapons/weapons.json"
static var _manifests: Dictionary = {}

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
	var look: Dictionary = look_for(scene_path)
	if look.has("off_hand"):
		equip_offhand(weapon_scene_for(String(look["off_hand"])))
	play_clip("Idle")

## The look's default main-hand weapon, for scenes without combat equipment.
func equip_look_weapon(scene_path: String) -> void:
	var weapon_id: String = String(look_for(scene_path).get("main_hand", ""))
	if not weapon_id.is_empty():
		equip_weapon(weapon_scene_for(weapon_id))

func equip_weapon(scene_path: String) -> void:
	assert(weapon_attachment == null, "Only one preview weapon per hand")
	# Bows and crossbows sit in the left hand: the existing release clip extends the left arm.
	var bone: String = "hand_l" if String(_grip_for(scene_path).get("hand", "right")) == "left" else "hand_r"
	assert(skeleton.find_bone(bone) >= 0, "Source rig must have the weapon hand " + bone)
	weapon_attachment = BoneAttachment3D.new()
	weapon_attachment.name = "MainHandWeapon" if bone == "hand_l" else "RightHandWeapon"
	weapon_attachment.bone_name = bone
	skeleton.add_child(weapon_attachment)
	weapon = _held_item(scene_path, weapon_attachment)
	weapon.name = "PreviewWeapon"
	weapon_scene = scene_path

## Swaps the main-hand model, e.g. a bandit drawing the scimitar after the crossbow.
func swap_weapon(scene_path: String) -> void:
	if scene_path == weapon_scene or scene_path.is_empty():
		return
	if weapon_attachment != null:
		weapon_attachment.free()
		weapon_attachment = null
		weapon = null
	equip_weapon(scene_path)

func equip_offhand(scene_path: String) -> void:
	assert(offhand_attachment == null, "Only one off-hand item")
	assert(skeleton.find_bone("hand_l") >= 0, "Source rig must have a left hand")
	offhand_attachment = BoneAttachment3D.new()
	offhand_attachment.name = "LeftHandItem"
	offhand_attachment.bone_name = "hand_l"
	skeleton.add_child(offhand_attachment)
	offhand = _held_item(scene_path, offhand_attachment)
	offhand.name = "PreviewOffhand"

## Equipment listed for this character scene in assets/characters/looks.json.
static func look_for(scene_path: String) -> Dictionary:
	var looks: Dictionary = _manifest(LOOKS_PATH)
	return looks.get(scene_path, {})

static func weapon_scene_for(weapon_id: String) -> String:
	var entry: Dictionary = _manifest(WEAPONS_PATH).get(weapon_id, {})
	return String(entry.get("scene", ""))

static func _manifest(path: String) -> Dictionary:
	if not _manifests.has(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert(parsed is Dictionary, "Manifest must be a JSON object: " + path)
		_manifests[path] = parsed
	return _manifests[path]

static func _grip_for(scene_path: String) -> Dictionary:
	for entry: Variant in _manifest(WEAPONS_PATH).values():
		if entry is Dictionary and String(entry.get("scene", "")) == scene_path:
			return entry
	return {"hand": "right", "position": [0.0, 0.065, 0.018], "rotation_degrees": [0, 0, -90]}

func _held_item(scene_path: String, attachment: BoneAttachment3D) -> Node3D:
	var item: Node3D = (load(scene_path) as PackedScene).instantiate() as Node3D
	attachment.add_child(item)
	# Authoring origin is the grip centre. Bone +Y runs along the fingers. The default
	# (01b) puts blade +Y across the palm; weapons.json overrides it per weapon, e.g.
	# shafts along the forearm and the crossbow along the fingers.
	var grip: Dictionary = _grip_for(scene_path)
	var offset: Array = grip["position"]
	var turn: Array = grip["rotation_degrees"]
	item.position = Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
	item.rotation_degrees = Vector3(float(turn[0]), float(turn[1]), float(turn[2]))
	return item

func play_clip(clip_name: String) -> void:
	assert(player.has_animation(clip_name), "Missing requested animation: " + clip_name)
	player.stop()
	skeleton.reset_bone_poses()
	player.play(clip_name, 0.15)
