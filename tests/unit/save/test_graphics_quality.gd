extends GutTest
## GraphicsQuality: presets switch expensive effects and lantern shadows off and "high"
## restores what the level builder authored.

func test_low_drops_expensive_effects_and_high_restores_them() -> void:
	var environment: Environment = Environment.new()
	environment.ssao_enabled = true
	environment.glow_enabled = true
	environment.volumetric_fog_enabled = true
	environment.fog_enabled = true
	GraphicsQuality.apply_environment(environment, "low")
	assert_false(environment.ssao_enabled)
	assert_false(environment.glow_enabled)
	assert_false(environment.volumetric_fog_enabled)
	assert_true(environment.fog_enabled, "plain fog stays on")
	GraphicsQuality.apply_environment(environment, "medium")
	assert_true(environment.ssao_enabled)
	assert_false(environment.volumetric_fog_enabled)
	GraphicsQuality.apply_environment(environment, "high")
	assert_true(environment.volumetric_fog_enabled)

func test_lantern_shadows_only_above_low_and_never_added() -> void:
	var lantern: OmniLight3D = autofree(OmniLight3D.new())
	lantern.shadow_enabled = true
	var plain: OmniLight3D = autofree(OmniLight3D.new())
	var sun: DirectionalLight3D = autofree(DirectionalLight3D.new())
	sun.shadow_enabled = true
	for light: Light3D in [lantern, plain, sun]:
		GraphicsQuality.apply_light(light, "low")
	assert_false(lantern.shadow_enabled)
	assert_true(sun.shadow_enabled, "the sun keeps a cheaper shadow")
	assert_eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	for light: Light3D in [lantern, plain, sun]:
		GraphicsQuality.apply_light(light, "high")
	assert_true(lantern.shadow_enabled)
	assert_false(plain.shadow_enabled)

func test_default_is_low() -> void:
	assert_eq(GraphicsQuality.DEFAULT, "low")
	assert_true(GraphicsQuality.DEFAULT in GraphicsQuality.LEVELS)
