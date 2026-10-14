class_name Money
extends RefCounted
## Coins of an actor, kept as one number of copper pieces in actor["money"] (owner's
## economy, 14-10-2026: fees and prices in copper, silver and gold; SRD 5.2 rates
## 10 cp = 1 sp, 10 sp = 1 gp). Older saves kept whole gold pieces in actor["gold"];
## they are read as copper here and replaced on the next change.

const CP_PER_SP: int = 10
const CP_PER_GP: int = 100

static func copper(actor: Dictionary) -> int:
	if actor.has("money"):
		return int(actor["money"])
	return int(actor.get("gold", 0)) * CP_PER_GP

static func set_copper(actor: Dictionary, amount: int) -> void:
	actor.erase("gold")
	actor["money"] = maxi(0, amount)

## Adds (or with a negative amount takes) copper. False and no change when it cannot be paid.
static func change(actor: Dictionary, amount: int) -> bool:
	var total: int = copper(actor) + amount
	if total < 0:
		return false
	set_copper(actor, total)
	return true

## "4 gp 3 sp 5 cp"; leaves out empty coins, "0 cp" when there is nothing.
static func format(amount: int) -> String:
	var parts: PackedStringArray = []
	var coins: Array = [[amount / CP_PER_GP, "MONEY_GP"], [amount % CP_PER_GP / CP_PER_SP, "MONEY_SP"],
		[amount % CP_PER_SP, "MONEY_CP"]]
	for coin: Array in coins:
		if int(coin[0]) > 0:
			parts.append(TranslationServer.translate(String(coin[1])) % int(coin[0]))
	if parts.is_empty():
		return TranslationServer.translate("MONEY_CP") % 0
	return " ".join(parts)
