class_name PortraitStudio
extends Node
## HUD and initiative portraits rendered from the actual 3D models (package 10): each
## character scene is posed in its own SubViewport world, the camera frames the head bone,
## one frame is rendered and kept as a texture. One render per model (and per-piece hero
## colours, HeroColors) per session.
## Without a renderer (headless tests) no texture exists and the HUD draws a plain disc.

signal portrait_ready(model_path: String)

const SIZE: Vector2i = Vector2i(160, 160)
const NODE_NAME: String = "PortraitStudio"

static var cache: Dictionary = {}
var _queue: Array[String] = []
var _colors: Dictionary = {}
var _busy: bool = false

## The studio living under the scene tree root (created on first use).
static func shared(tree: SceneTree) -> PortraitStudio:
	var existing: Node = tree.root.get_node_or_null(NODE_NAME)
	if existing != null:
		return existing as PortraitStudio
	var studio: PortraitStudio = PortraitStudio.new()
	studio.name = NODE_NAME
	tree.root.add_child.call_deferred(studio)
	return studio

static func can_render() -> bool:
	return DisplayServer.get_name() != "headless"

## Cache key: the model path, plus the colour choice when the hero has one.
static func key_for(model_path: String, colors: Variant = {}) -> String:
	var signature: String = HeroColors.signature(colors)
	return model_path if signature.is_empty() else "%s|%s" % [model_path, signature]

static func texture_for(model_path: String, colors: Variant = {}) -> Texture2D:
	return cache.get(key_for(model_path, colors)) as Texture2D

## Queues a render; portrait_ready fires once the texture is in the cache.
func request(model_path: String, colors: Variant = {}) -> void:
	var key: String = key_for(model_path, colors)
	if not can_render() or cache.has(key) or key in _queue or not ResourceLoader.exists(model_path):
		return
	_colors[key] = HeroColors.clean(colors)
	_queue.append(key)
	if not _busy:
		_work.call_deferred()

func pending() -> int:
	return _queue.size() + (1 if _busy else 0)

func _work() -> void:
	if _busy:
		return
	_busy = true
	while not _queue.is_empty():
		var key: String = _queue.pop_front()
		var texture: Texture2D = await render(key.get_slice("|", 0), _colors.get(key, {}))
		_colors.erase(key)
		if texture != null:
			cache[key] = texture
			portrait_ready.emit(key)
	_busy = false

## Renders one head shot. Returns null when nothing could be rendered.
func render(model_path: String, colors: Variant = {}) -> Texture2D:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var world: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8d9bb4")
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	viewport.add_child(world)
	var figure: PreviewActor = PreviewActor.new()
	viewport.add_child(figure)
	figure.setup(model_path, "")
	HeroColors.apply(figure, colors)
	for label: Node in figure.find_children("*", "Label3D", true, false):
		label.queue_free()
	# A calm idle frame instead of the bind pose.
	figure.player.play("Idle")
	figure.player.seek(0.6, true)
	var head: Vector3 = _head_position(figure)
	var camera: Camera3D = Camera3D.new()
	camera.fov = 24.0
	camera.near = 0.05
	viewport.add_child(camera)
	# Characters face +Z; look slightly from the right and above, like a bust portrait.
	camera.position = head + Vector3(0.2, 0.06, 1.12) * _model_scale(figure)
	camera.look_at(head + Vector3(0, -0.02, 0), Vector3.UP)
	camera.current = true
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.light_color = Color("ffd9a8")
	key.light_energy = 1.6
	key.rotation_degrees = Vector3(-25, 35, 0)
	viewport.add_child(key)
	var rim: OmniLight3D = OmniLight3D.new()
	rim.light_color = Color("7fa6ff")
	rim.light_energy = 1.4
	rim.omni_range = 3.0
	rim.position = head + Vector3(-0.6, 0.4, -0.5)
	viewport.add_child(rim)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

static func _head_position(figure: PreviewActor) -> Vector3:
	var skeleton: Skeleton3D = figure.skeleton
	for bone_name: String in ["head", "Head", "neck_01", "neck"]:
		var bone: int = skeleton.find_bone(bone_name)
		if bone >= 0:
			skeleton.force_update_all_bone_transforms()
			var pose: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone)
			return pose.origin + Vector3.UP * 0.08 * _model_scale(figure)
	return figure.global_position + Vector3.UP * 1.62

## Bosses are built larger (the Cult Priest is 1.22x): frame them with the same tightness.
static func _model_scale(figure: PreviewActor) -> float:
	var skeleton: Skeleton3D = figure.skeleton
	return maxf(0.5, skeleton.global_transform.basis.get_scale().y) if skeleton != null else 1.0
