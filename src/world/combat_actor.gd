class_name CombatActor
extends PreviewActor
## A view of a combatant. Only commands change HP, position, or combat resources.
## Reuses the showcase's imported, retargeted clips and hand attachment.

# Authored 30 FPS Sword_Attack: frame 13 is the forward/downward blade sweep.
# The command owns impact_time; piecewise playback aligns this authored pose to it.
const SWORD_CONTACT_SECONDS: float = 13.0 / 30.0
const RANGED_RELEASE_SECONDS: float = 4.0 / 30.0
# Measured median backward foot velocity during ground contact in universal.glb.
# Scaling the animation clock by distance/speed keeps planted feet from sliding.
const WALK_METRES_PER_SECOND: float = 0.93
const JOG_METRES_PER_SECOND: float = 5.22
const SPRINT_METRES_PER_SECOND: float = 7.87
const STATE_CLIPS: Dictionary = {
	"idle": "Idle", "walk": "Walk", "sprint": "Sprint",
	"attack": "Sword_Attack", "hit": "Hit_Chest", "death": "Death01",
}

var actor_id: String = ""
var animation_state: String = "idle"
var _record: Dictionary = {}
var _last_hp: int = -1
var _hit_remaining: float = 0.0
var _selection: MeshInstance3D
var _selection_material: StandardMaterial3D
var _dead: bool = false
var _active_clip: String = ""


func setup_actor(record: Dictionary) -> void:
	actor_id = String(record["id"])
	_record = record.duplicate(true)
	set_meta("actor_id", actor_id)
	setup(String(record["model"]), String(record["name_key"]))
	# Playback shares the command clock, never an independent AnimationPlayer clock.
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var weapon_data: Dictionary = record.get("weapon", {})
	var weapon_model: String = String(weapon_data.get("model", ""))
	if not weapon_model.is_empty():
		equip_weapon(weapon_model)
	global_position = _as_position(record.get("position", Vector3.ZERO))
	_last_hp = int(record.get("hp", 1))
	_create_selection_ring()
	_create_pick_area()
	_set_animation("idle")
	player.advance(0.0)
	if _last_hp <= 0:
		_die()


func update_actor(record: Dictionary, pending: Dictionary, delta: float) -> void:
	if player == null:
		return
	_record = record.duplicate(true)
	var next_position: Vector3 = _as_position(record.get("position", global_position))
	var displacement: Vector3 = next_position - global_position
	global_position = next_position
	var hp: int = int(record.get("hp", _last_hp))
	if hp < _last_hp:
		if hp > 0:
			_hit_remaining = player.get_animation("Hit_Chest").length
	_last_hp = hp
	if hp <= 0:
		if not _dead:
			_die()
		_advance_once(delta)
		return
	if _hit_remaining > 0.0:
		_set_animation("hit")
		_hit_remaining = maxf(0.0, _hit_remaining - delta)
		_advance_once(delta)
		return
	if String(pending.get("type", "")) == "attack" and String(pending.get("actor_id", "")) == actor_id:
		_sync_attack(pending)
		return
	var speed: float = displacement.length() / maxf(delta, 0.000001)
	if speed > 0.025:
		var horizontal: Vector3 = Vector3(displacement.x, 0.0, displacement.z)
		if horizontal.length_squared() > 0.000001:
			aim_at(global_position + horizontal)
		var sprinting: bool = speed > 4.2
		var jogging: bool = speed > 1.5 and not sprinting
		_set_animation("sprint" if sprinting else "walk", "Jog_Fwd" if jogging else "")
		# Gait phase follows metres actually travelled, including stairs and slow moves.
		var authored_speed: float = SPRINT_METRES_PER_SECOND if sprinting else (
			JOG_METRES_PER_SECOND if jogging else WALK_METRES_PER_SECOND)
		player.advance(delta * speed / authored_speed)
	else:
		_set_animation("idle")
		player.advance(delta)


func aim_at(target: Vector3) -> void:
	var flat_target: Vector3 = Vector3(target.x, global_position.y, target.z)
	if global_position.distance_squared_to(flat_target) > 0.000001:
		# Imported characters face local +Z, rather than Godot camera forward (-Z).
		look_at(flat_target, Vector3.UP, true)


func set_selected(selected: bool) -> void:
	if _selection == null:
		return
	_selection.visible = not _dead
	_selection.scale = Vector3(1.0, 0.25, 1.0) * (1.13 if selected else 1.0)
	_selection_material.albedo_color = Color("e9bf62") if selected else (
		Color("a44035") if String(_record.get("team", "")) == "enemy" else Color("667f9c"))
	_selection_material.emission = _selection_material.albedo_color
	_selection_material.emission_energy_multiplier = 0.8 if selected else 0.2


func react_to_event(event: Dictionary, actors: Dictionary = {}) -> void:
	# Damage events retain overkill and separate damage types; clamped HP cannot.
	if String(event.get("actor_id", "")) == actor_id:
		var target_id: String = String(event.get("target_id", ""))
		var target: CombatActor = actors.get(target_id) as CombatActor
		if target != null:
			aim_at(target.global_position)
	if String(event.get("type", "")) == "damage" and String(event.get("target_id", "")) == actor_id:
		_show_damage(int(event.get("amount", 0)), String(event.get("damage_type", "")))


func _sync_attack(pending: Dictionary) -> void:
	var weapon_data: Dictionary = pending.get("weapon", {})
	if weapon_data.is_empty():
		weapon_data = _record.get("weapon", {})
	var ranged: bool = bool(weapon_data.get("ranged", false))
	# The supplied set has no bow/throw clip or bow model. This existing release
	# gesture is visibly provisional ranged art, not a spell or invented equipment.
	var clip_name: String = String(weapon_data.get("attack_clip", "Spell_Simple_Shoot" if ranged else "Sword_Attack"))
	_set_animation("attack", clip_name)
	var duration: float = maxf(0.001, float(pending.get("duration", 0.8)))
	var impact: float = clampf(float(pending.get("impact_time", duration * 0.5)), 0.001, duration - 0.001)
	var elapsed: float = clampf(float(pending.get("elapsed", 0.0)), 0.0, duration)
	var clip_length: float = player.get_animation(clip_name).length
	var contact: float = minf(RANGED_RELEASE_SECONDS if ranged else SWORD_CONTACT_SECONDS, clip_length)
	var clip_time: float = contact * elapsed / impact if elapsed <= impact else (
		contact + (clip_length - contact) * (elapsed - impact) / (duration - impact))
	player.seek(clip_time, true)


func _set_animation(state: String, requested_clip: String = "") -> void:
	var clip_name: String = String(STATE_CLIPS[state]) if requested_clip.is_empty() else requested_clip
	if animation_state == state and _active_clip == clip_name:
		return
	assert(player.has_animation(clip_name), "Combat clip missing: " + clip_name)
	animation_state = state
	_active_clip = clip_name
	# Seeking attacks must not leave an unadvanced cross-fade over the impact pose.
	player.play(clip_name, 0.0 if state == "attack" else 0.08)


func _advance_once(delta: float) -> void:
	var length: float = player.get_animation(_active_clip).length
	var time: float = player.current_animation_position if player.is_playing() else length
	if time + delta >= length:
		player.seek(length, true)
		player.pause()
	else:
		player.advance(delta)


func _die() -> void:
	_dead = true
	_hit_remaining = 0.0
	_set_animation("death")
	_selection.hide()
	var pick_area: Area3D = get_node("ActorPick") as Area3D
	pick_area.collision_layer = 0


func _create_selection_ring() -> void:
	_selection = MeshInstance3D.new()
	_selection.name = "SelectionRing"
	var mesh: TorusMesh = TorusMesh.new()
	mesh.inner_radius = 0.34
	mesh.outer_radius = 0.39
	mesh.rings = 32
	mesh.ring_segments = 8
	_selection.mesh = mesh
	_selection.position.y = 0.035
	_selection.scale.y = 0.25
	_selection.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selection_material = StandardMaterial3D.new()
	_selection_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection_material.emission_enabled = true
	_selection.material_override = _selection_material
	add_child(_selection)
	set_selected(false)


func _create_pick_area() -> void:
	var area: Area3D = Area3D.new()
	area.name = "ActorPick"
	area.set_meta("actor_id", actor_id)
	area.collision_layer = 2
	area.collision_mask = 0
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.75
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.9
	area.add_child(collision)
	add_child(area)


func _show_damage(amount: int, damage_type: String) -> void:
	var stack_index: int = 0
	for child: Node in get_children():
		if child is Label3D and child.has_meta("damage_amount"):
			stack_index += 1
	var label: Label3D = Label3D.new()
	label.set_meta("damage_amount", amount)
	label.set_meta("damage_type", damage_type)
	label.text = tr("COMBAT_DAMAGE_NUMBER") % amount
	label.font_size = 84
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 14
	label.outline_modulate = Color("160c11")
	var colors: Dictionary = {"fire": Color("ff9b43"), "cold": Color("8ddbff"),
		"poison": Color("a9d64e"), "necrotic": Color("b482e9"), "radiant": Color("fff3a8")}
	label.modulate = colors.get(damage_type, Color("ffddd3"))
	add_child(label)
	label.position = Vector3(0.0, 2.0 + float(stack_index) * 0.42, 0.0)
	var tween: Tween = label.create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 0.85, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.45).set_delay(0.55)
	tween.chain().tween_callback(label.queue_free)


static func _as_position(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Dictionary:
		return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))
	return Vector3.ZERO
