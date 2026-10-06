class_name CombatSpace
extends RefCounted
## Encounter geometry adapter. Runtime overrides this with navigation/physics queries.
## No submitted command may supply its own path, visibility or cover result.

static var active: CombatSpace = null

func query_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	return PackedVector3Array([from, to])

func cover(_from: Vector3, _to: Vector3) -> int:
	return 0

func visible(from: Vector3, to: Vector3) -> bool:
	return cover(from, to) < 99

static func current() -> CombatSpace:
	return active if active != null else CombatSpace.new()
