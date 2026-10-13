extends Node
## Package 10: every hero look and every enemy type gets a portrait rendered from its 3D
## model (needs a real display: run through tests/integration/check_level_capture.sh).
## Writes a contact sheet of all portraits to the path given with --portraits-sheet=.
var checks: int = 0
var failed: bool = false

func _ready() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error(message)

static func models() -> Array[String]:
	var result: Array[String] = []
	for body: String in ["male", "female"]:
		for class_id: String in ["fighter", "wizard"]:
			for look: Dictionary in HeroLooks.for_class(class_id, body):
				if not String(look["scene"]) in result:
					result.append(String(look["scene"]))
	for file: String in DirAccess.get_files_at("res://data/monsters"):
		if file.ends_with(".tres"):
			var monster: MonsterDefinition = load("res://data/monsters/" + file) as MonsterDefinition
			if monster != null and monster.is_valid() and not monster.model in result:
				result.append(monster.model)
	return result

func _run() -> void:
	check(PortraitStudio.can_render(), "Portraits need a rendering display")
	var studio: PortraitStudio = PortraitStudio.shared(get_tree())
	await get_tree().process_frame
	var list: Array[String] = models()
	check(list.size() >= 10, "Six hero looks and four enemy types")
	var sheet: Image = Image.create_empty(PortraitStudio.SIZE.x * 5, PortraitStudio.SIZE.y * ceili(list.size() / 5.0), false, Image.FORMAT_RGBA8)
	sheet.fill(Color("101624"))
	var hashes: Dictionary = {}
	for index: int in list.size():
		var model: String = list[index]
		var texture: Texture2D = await studio.render(model)
		check(texture != null, "Portrait rendered: " + model)
		if texture == null:
			continue
		var image: Image = texture.get_image()
		image.convert(Image.FORMAT_RGBA8)
		var covered: int = 0
		var bright: float = 0.0
		for y: int in range(0, image.get_height(), 4):
			for x: int in range(0, image.get_width(), 4):
				var pixel: Color = image.get_pixel(x, y)
				if pixel.a > 0.5:
					covered += 1
					bright += pixel.get_luminance()
		var samples: int = (image.get_width() / 4) * (image.get_height() / 4)
		var coverage: float = float(covered) / samples
		check(coverage > 0.25 and coverage < 0.995, "Portrait frames the head of %s (coverage %.2f)" % [model, coverage])
		check(covered > 0 and bright / covered > 0.06, "Portrait of %s is lit" % model)
		var digest: int = hash(image.get_data())
		check(not hashes.has(digest), "Portrait of %s differs from %s" % [model, hashes.get(digest, "")])
		hashes[digest] = model
		sheet.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(index % 5, index / 5) * PortraitStudio.SIZE)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--portraits-sheet="):
			sheet.save_png(argument.trim_prefix("--portraits-sheet="))
	print("PORTRAIT_CHECKS: %d models, %d checks, failed: %s" % [list.size(), checks, failed])
	get_tree().quit(1 if failed else 0)
