class_name GraphicsQuality
extends RefCounted
## Graphics presets (owner report 16-10-2026: ~5 FPS on his PC). Levels build their
## environments and lights at full quality; the Settings autoload calls these helpers for
## every WorldEnvironment and Light3D that enters the tree and again on every change, so
## builders never need to know about the preset. Presentation only, never game state.
## "high" restores what the builder authored (kept in node metadata).

const LEVELS: Array[String] = ["low", "medium", "high"]
const DEFAULT: String = "low"

## Root viewport and RenderingServer settings for a preset.
static func apply_viewport(viewport: Viewport, level: String) -> void:
	if viewport == null:
		return
	var low: bool = level == "low"
	var high: bool = level == "high"
	# FSR 1 upscales a smaller 3D image; the UI keeps full resolution.
	# The compatibility renderer (captures, old GPUs) has no FSR: plain bilinear there.
	var compatibility: bool = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var fsr: bool = low and not compatibility
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if fsr else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = 0.77 if low else 1.0
	viewport.msaa_3d = Viewport.MSAA_2X if high else Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if high or compatibility else Viewport.SCREEN_SPACE_AA_FXAA
	viewport.mesh_lod_threshold = 1.0 if high else (4.0 if low else 2.0)
	# Size 0 switches positional (lantern, torch) shadows off entirely.
	viewport.positional_shadow_atlas_size = 0 if low else (2048 if level == "medium" else 4096)
	RenderingServer.directional_shadow_atlas_set_size(2048 if low else 4096, not high)
	var filter: RenderingServer.ShadowQuality = RenderingServer.SHADOW_QUALITY_HARD if low else \
		(RenderingServer.SHADOW_QUALITY_SOFT_LOW if level == "medium" else RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	RenderingServer.directional_soft_shadow_filter_set_quality(filter)
	RenderingServer.positional_soft_shadow_filter_set_quality(filter)
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW if not high else RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
		not high, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_volumetric_fog_volume_size(64 if high else 32, 64 if high else 32)

## Screen-space effects of one environment. SSAO, SSIL, SSR, SDFGI and volumetric fog are
## the expensive ones; plain distance fog stays on everywhere because the levels rely on it.
static func apply_environment(environment: Environment, level: String) -> void:
	if environment == null:
		return
	if not environment.has_meta("authored_quality"):
		environment.set_meta("authored_quality", {
			"ssao": environment.ssao_enabled, "ssil": environment.ssil_enabled,
			"ssr": environment.ssr_enabled, "sdfgi": environment.sdfgi_enabled,
			"glow": environment.glow_enabled, "volumetric": environment.volumetric_fog_enabled,
		})
	var authored: Dictionary = environment.get_meta("authored_quality")
	var low: bool = level == "low"
	var high: bool = level == "high"
	environment.ssao_enabled = bool(authored["ssao"]) and not low
	environment.ssil_enabled = bool(authored["ssil"]) and high
	environment.ssr_enabled = bool(authored["ssr"]) and high
	environment.sdfgi_enabled = bool(authored["sdfgi"]) and high
	environment.glow_enabled = bool(authored["glow"]) and not low
	environment.volumetric_fog_enabled = bool(authored["volumetric"]) and high

## Shadows of one light: the sun keeps a cheaper shadow on low, lanterns lose theirs.
static func apply_light(light: Light3D, level: String) -> void:
	if light == null:
		return
	if not light.has_meta("authored_shadow"):
		light.set_meta("authored_shadow", light.shadow_enabled)
	var authored: bool = bool(light.get_meta("authored_shadow"))
	if light is DirectionalLight3D:
		var sun: DirectionalLight3D = light as DirectionalLight3D
		sun.shadow_enabled = authored
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if level == "low" \
			else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	else:
		light.shadow_enabled = authored and level != "low"
