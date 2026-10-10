class_name CombatCamera
extends Node3D
## Isometric camera rig. Following, panning and attack focus never change game state.

const MIN_ZOOM: float = 9.0
const MAX_ZOOM: float = 34.0
const PAN_SPEED: float = 12.0
const ROTATION_SPEED: float = 1.3
## Options scale this (camera rotation speed); ROTATION_SPEED stays the default.
var rotation_speed: float = ROTATION_SPEED

var camera: Camera3D
var _follow_position: Vector3 = Vector3.ZERO
var _pan_offset: Vector3 = Vector3.ZERO
var _focus_position: Vector3 = Vector3.ZERO
var _focus_remaining: float = 0.0
var _zoom_target: float = 22.0
var _dragging: bool = false
var _first_follow: bool = true


func _ready() -> void:
	rotation.y = deg_to_rad(45.0)
	camera = Camera3D.new()
	camera.name = "IsometricCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = _zoom_target
	camera.near = 0.1
	camera.far = 160.0
	camera.position = Vector3(0.0, 20.0, 28.284271)
	camera.rotation.x = -atan(1.0 / sqrt(2.0))
	camera.current = true
	add_child(camera)


func follow(position_to_follow: Vector3) -> void:
	_follow_position = position_to_follow
	if _first_follow:
		global_position = position_to_follow
		_first_follow = false


func focus_target(target: Vector3, seconds: float = 0.65) -> void:
	_focus_position = target
	_focus_remaining = maxf(0.0, seconds)


func reset_pan() -> void:
	_pan_offset = Vector3.ZERO


func _process(delta: float) -> void:
	if camera == null:
		return
	var rotate_axis: float = Input.get_axis("camera_rotate_left", "camera_rotate_right")
	rotation.y += rotate_axis * rotation_speed * delta
	var pan: Vector2 = Input.get_vector("camera_pan_left", "camera_pan_right", "camera_pan_forward", "camera_pan_back")
	_pan_offset += (global_basis.x * pan.x + global_basis.z * pan.y) * PAN_SPEED * delta * camera.size / 22.0
	var target: Vector3 = _follow_position + _pan_offset
	if _focus_remaining > 0.0:
		target = _focus_position
		_focus_remaining = maxf(0.0, _focus_remaining - delta)
	global_position = global_position.lerp(target, 1.0 - exp(-7.0 * delta))
	camera.size = lerpf(camera.size, _zoom_target, 1.0 - exp(-12.0 * delta))


func _unhandled_input(event: InputEvent) -> void:
	# Right click belongs to cancel/targeting (docs/UI.md); never rotate with it.
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mouse_button.pressed
			get_viewport().set_input_as_handled()
		elif mouse_button.pressed and event.is_action("camera_zoom_in"):
			_zoom_target = clampf(_zoom_target / 1.1, MIN_ZOOM, MAX_ZOOM)
			get_viewport().set_input_as_handled()
		elif mouse_button.pressed and event.is_action("camera_zoom_out"):
			_zoom_target = clampf(_zoom_target * 1.1, MIN_ZOOM, MAX_ZOOM)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var viewport_height: float = maxf(1.0, get_viewport().get_visible_rect().size.y)
		var scale_per_pixel: float = camera.size / viewport_height
		# Compensate for the tilted view so vertical drags cover the same screen distance.
		_pan_offset -= global_basis.x * motion.relative.x * scale_per_pixel
		_pan_offset -= global_basis.z * motion.relative.y * scale_per_pixel / sin(-camera.rotation.x)
		_focus_remaining = 0.0
		get_viewport().set_input_as_handled()
