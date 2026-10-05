extends GutTest

func test_reseeding_replays_both_wrapper_and_injected_generator() -> void:
	Rng.set_seed(81732)
	var first: Array[float] = []
	for index: int in range(32):
		first.append(float(Rng.randi_range(1, 20)))
		first.append(Rng.rng.randf())
	Rng.set_seed(81732)
	var second: Array[float] = []
	for index: int in range(32):
		second.append(float(Rng.rng.randi_range(1, 20)))
		second.append(Rng.randf())
	assert_eq(first, second)

func test_seeded_stream_matches_independent_godot_generator() -> void:
	var reference: RandomNumberGenerator = RandomNumberGenerator.new()
	reference.seed = 72
	Rng.set_seed(72)
	for index: int in range(100):
		assert_eq(Rng.randi_range(1, 6), reference.randi_range(1, 6))

func test_rng_state_can_resume_exactly() -> void:
	Rng.set_seed(44)
	Rng.randi_range(1, 20)
	var saved_state: int = Rng.rng.state
	var expected: int = Rng.randi_range(1, 20)
	Rng.rng.state = saved_state
	assert_eq(Rng.randi_range(1, 20), expected)
