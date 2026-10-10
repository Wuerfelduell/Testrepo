extends Node
## Run after the normal project import:
## godot --headless --path . tests/integration/check_inventory_ui.tscn
## Real arena: the inventory window drives commands, and the hero's hand model follows.
var checks: int = 0
var failed: bool = false

func _ready() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error(message)

func _click(slot: ItemSlot) -> void:
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	slot._gui_input(press)

func _bag_slot(menus: GameMenus, item_id: String) -> ItemSlot:
	for slot: ItemSlot in menus.inventory.bag_slots:
		if slot.item_id == item_id:
			return slot
	return null

func _run() -> void:
	var game: Node = get_tree().root.get_node("Game")
	var arena: CombatArena = (load("res://scenes/arena/arena.tscn") as PackedScene).instantiate() as CombatArena
	get_tree().root.add_child(arena)
	var frames: int = 0
	while not arena.ready_for_input and frames < 120:
		await get_tree().physics_frame
		frames += 1
	check(arena.ready_for_input, "Arena must initialize fully")
	var hero: Dictionary = game.state.actors["hero"]
	check(EquipmentRules.has_inventory(hero), "The arena hero receives the Fighter starting kit")
	check(int(hero["ac"]) == 18 and String(hero["weapon"]["id"]) == "longsword", "Kit keeps the arena hero's numbers")
	var menus: GameMenus = arena.menus
	check(not menus.is_open(), "Windows start closed")
	menus.toggle_inventory()
	check(menus.inventory.visible and not menus.character.visible, "I opens only the inventory")
	check((menus.inventory.equipment_slots["main_hand"] as ItemSlot).item_id == "longsword", "Main hand slot shows the sword")
	var axe_state: GameState = game.state
	EquipmentRules.add_item(axe_state.actors["hero"], "battleaxe")
	# Test-only state injection, the same way the unit tests set up fixtures.
	game._commit_state(axe_state)
	EventBus.state_changed.emit()
	var axe: ItemSlot = _bag_slot(menus, "battleaxe")
	check(axe != null, "New loot appears in the bag grid")
	if axe != null:
		menus.inventory._on_hovered(axe)
		check(menus.tooltip.visible, "Hovering an item shows its tooltip")
		_click(axe)
	check(String(game.state.actors["hero"]["weapon"]["id"]) == "battleaxe", "Clicking a weapon equips it")
	var hand: CombatActor = arena.actors["hero"]
	check(hand.weapon != null and hand.weapon_attachment != null, "The battleaxe model is in the hero's hand")
	var dagger: ItemSlot = _bag_slot(menus, "dagger")
	if dagger != null:
		_click(dagger)
	await get_tree().process_frame
	check(String(game.state.actors["hero"]["weapon"]["id"]) == "dagger", "Swapping again works")
	check(hand.weapon_attachment == null or String(game.state.actors["hero"]["weapon"]["model"]) != "",
		"A weapon without a model does not leave the old model in the hand")
	var potion: ItemSlot = _bag_slot(menus, "potion_of_healing")
	check(potion != null and potion.blocked, "A potion at full health is shown as not usable")
	menus.toggle_character()
	check(menus.character.visible and not menus.inventory.visible, "C switches to the character sheet")
	check(menus.character._skills.text.contains("Athletics"), "The sheet lists skills")
	menus.close_all()
	check(not menus.is_open(), "Esc / close hides every window")
	print("Inventory UI checks: %d, failed: %s" % [checks, failed])
	get_tree().quit(1 if failed else 0)
