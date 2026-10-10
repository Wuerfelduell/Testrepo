class_name CommandCodec
extends RefCounted
## Explicit allowlist: no script paths, RNG, paths, costs or simulation ticks from clients.

static func decode(data: Dictionary) -> Command:
	var command: Command = null
	match data.get("type"):
		"end_turn": command = EndTurnCommand.new()
		"move": command = MoveCommand.new()
		"attack": command = AttackCommand.new()
		"dash": command = DashCommand.new()
		"disengage": command = DisengageCommand.new()
		"setup_inventory": command = SetupInventoryCommand.new()
		"equip_item": command = EquipItemCommand.new()
		"unequip_item": command = UnequipItemCommand.new()
		"use_item": command = UseItemCommand.new()
		_: return null
	if command.from_dict(data) != OK:
		return null
	return command
