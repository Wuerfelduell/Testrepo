class_name TownLevel
extends DungeonLevel
## A district of the Overcity (act 1). Same level flow as DungeonLevel; started directly
## (F6 or a test) it opens the Torviertel instead of the crypt.

const TORVIERTEL_PATH: String = "res://data/encounters/torviertel.json"

func _ready() -> void:
	if Game.state.actors.is_empty() or String(Game.state.world.get("data_path", "")).is_empty():
		CommandBus.submit(ResetRunCommand.new())
		CommandBus.submit(LevelSetupCommand.new({}, TORVIERTEL_PATH))
	await super._ready()
