extends Node
## All game randomness goes through this generator. Pure rules receive Rng.rng.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()

func set_seed(value: int) -> void:
	rng.seed = value

func randi_range(from: int, to: int) -> int:
	return rng.randi_range(from, to)

func randf() -> float:
	return rng.randf()
