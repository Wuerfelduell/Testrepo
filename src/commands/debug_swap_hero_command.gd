class_name DebugSwapHeroCommand
extends Command
## Arena test switch (F4): swaps the arena hero between Fighter and Wizard outside
## combat. Local debug only, never accepted from CommandCodec. Replaced by
## character creation (prompt 06).

func _init() -> void:
	super("hero")

func validate(state: GameState) -> Error:
	if state.mode != &"exploration" or not state.pending.is_empty() or not state.actors.has("hero"):
		return ERR_UNAVAILABLE
	return OK if CombatRules.alive(state.actors["hero"]) else ERR_UNAVAILABLE

func apply(state: GameState) -> Dictionary:
	var current: Dictionary = state.actors["hero"]
	var next_class: StringName = &"fighter" if String(current.get("class_id", "fighter")) == "wizard" else &"wizard"
	state.actors["hero"] = HeroKit.create(next_class, current["position"])
	return {"events": [{"type": "hero_swapped", "actor_id": "hero", "class_id": String(next_class)}]}

func to_dict() -> Dictionary:
	return {"type": "debug_swap_hero", "actor_id": actor_id}
