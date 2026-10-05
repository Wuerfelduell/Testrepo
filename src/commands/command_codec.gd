class_name CommandCodec
extends RefCounted
## Explicit allowlist: never load script paths supplied by network data.

static func decode(data: Dictionary) -> Command:
	if data.get("type") != "end_turn":
		return null
	var command: EndTurnCommand = EndTurnCommand.new()
	if command.from_dict(data) != OK:
		return null
	return command
