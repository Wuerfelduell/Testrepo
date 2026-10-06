extends Node
## Run after the normal project import:
## godot --headless --path . tests/integration/check_combat_ui.tscn
## Checks presentation contracts without sampling or mutating gameplay RNG.

var _hud: CombatHUD
var _finished: Array[String] = []
var _failures: PackedStringArray = []
var _saw_dropped: bool = false
var _checks: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	_hud = CombatHUD.new()
	add_child(_hud)
	await get_tree().process_frame
	var state: GameState = GameState.new()
	state.actors = {
		"hero": {"id": "hero", "team": "hero", "name_key": "ACTOR_FIGHTER", "hp": 12,
			"max_hp": 12, "ac": 16, "level": 1, "xp": 0, "action_available": true,
			"bonus_available": true, "reaction_available": true, "speed_m": 9.0, "move_left": 9.0,
			"weapon": {"name_key": "WEAPON_LONGSWORD", "damage_dice": "1d8",
				"damage_type": "slashing", "damage_modifiers": [{"amount": 3, "source": "str"}]}},
		"enemy": {"id": "enemy", "team": "enemy", "name_key": "ACTOR_GUARD", "hp": 11,
			"max_hp": 11, "ac": 16, "weapon": {"ranged": false}},
	}
	state.mode = &"combat"
	state.turn_order = ["hero", "enemy"]
	_hud.update_state(state)
	await get_tree().process_frame
	_check(_hud._move_bar.get_rect().end.y <= _hud._conditions.position.y,
		"Movement bar must not cover condition text")
	_check(_hud._hp_bar.get_rect().end.y <= _hud._resource_label.position.y,
		"Health bar must not overlap resource text")
	_check((_hud._initiative.get_parent() as Control).visible, "Initiative appears during combat")
	state.mode = &"exploration"
	_hud.update_state(state)
	_check(not (_hud._initiative.get_parent() as Control).visible,
		"Exploration must not display an empty combat round panel")
	_check(_hud._move_label.text == tr("COMBAT_FREE_MOVEMENT"),
		"Exploration resources must not imply a turn movement limit")
	_hud.show_path(5.0, INF, false)
	_check(_hud._path_label.text == tr("COMBAT_PATH_FREE") % 5.0,
		"Unlimited exploration movement has no false zero or infinity remainder")
	state.mode = &"combat"
	_hud.update_state(state)
	var portrait_before: int = _hud._initiative.get_child(0).get_instance_id()
	state.actors["hero"]["move_left"] = 7.5
	_hud.update_state(state)
	_check(_hud._initiative.get_child(0).get_instance_id() == portrait_before,
		"Movement ticks must retain portrait nodes")
	_hud.show_target({"chance": 0.65, "legal": true, "armor_class": 16}, state.actors["enemy"])
	_hud.show_path(5.0, 2.5, true)
	_check(_hud._path_label.text.begins_with(tr("COMBAT_PATH") % [5.0, 2.5]),
		"Combat paths still show the actual finite movement remainder")
	_check(_hud._target_panel.visible and _hud._path_label.visible, "Target/path previews are visible")
	_hud.clear_target()
	_check(not _hud._target_panel.visible and not _hud._path_label.visible, "Cancel clears both previews")
	_hud.toggle_debug()
	_hud.set_ai_options([{"score": 3.4, "reason_key": "AI_ATTACK_TARGET", "breakdown": {"hit_chance": 0.65}}])
	_check(_hud._debug.visible, "Debug panel toggles")
	_hud.dice_popup.speed = 20.0
	_hud.dice_popup.roll_finished.connect(_on_roll_finished)
	_hud.dice_popup.roll_started.connect(_on_roll_started)
	var events: Array[Dictionary] = [
		{"type": "roll", "kind": "initiative", "actor_id": "hero", "roll": {
			"groups": [{"sides": 20, "values": [14], "kept_indices": [0]}],
			"modifiers": [{"amount": 2, "source": "dex"}], "total": 16}},
		{"type": "roll", "kind": "attack", "actor_id": "hero", "target_id": "enemy",
			"armor_class": 16, "hit": true, "roll": {
				"groups": [{"sides": 20, "values": [3, 20], "kept_indices": [1]}],
				"modifiers": [{"amount": 3, "source": "str"}, {"amount": 2, "source": "proficiency"}],
				"total": 25, "natural_20": true, "mode": "advantage"}},
		{"type": "roll", "kind": "damage", "actor_id": "hero", "target_id": "enemy", "roll": {
			"groups": [{"sides": 8, "values": [6, 7], "kept_indices": [0, 1]}],
			"modifiers": [{"amount": 3, "source": "str"}], "total": 16}},
	]
	_hud.consume_events(events)
	_check(_hud.rolls_busy(), "A queued roll blocks the next action")
	_hud.dice_popup.skip()
	_check(_finished.is_empty(), "First skip lands the current roll without losing it")
	state.actors["hero"]["hp"] = 0
	state.mode = &"defeat"
	_hud.update_state(state)
	_check(not _hud._death.visible, "Defeat must not obscure queued final rolls")
	for _frame: int in range(900):
		await get_tree().process_frame
		if not _hud.rolls_busy():
			break
	await get_tree().process_frame
	_check(_finished == ["initiative", "attack", "damage"], "All queued rolls finish in their original order")
	_check(_saw_dropped, "Advantage shows both physical d20s and greys the dropped one")
	_check(not _hud.rolls_busy(), "The roll queue drains")
	_check(_hud._death.visible, "Defeat appears after the final roll")
	var die: DiceMesh = DiceMesh.new()
	add_child(die)
	for value: int in range(1, 21):
		die.configure(value)
		var transformed: Vector3 = die.basis * die._face_bases[value - 1].z
		_check(transformed.is_equal_approx(Vector3.BACK), "Landed d20 face %d faces the camera" % value)
		_check((die.basis * die._face_bases[value - 1].y).is_equal_approx(Vector3.UP),
			"Landed d20 face %d is upright" % value)
	_hud.queue_free()
	die.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("COMBAT_UI_OK: %d checks; FIFO rolls, previews, defeat, portrait reuse, 20 numbered landings" % _checks)
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error(failure)
		get_tree().quit(1)

func _on_roll_finished(event: Dictionary) -> void:
	_finished.append(String(event.get("kind", "")))

func _on_roll_started(event: Dictionary) -> void:
	if event.get("kind") == "attack":
		var dice: Array[DiceMesh] = _hud.dice_popup._dice
		_saw_dropped = dice.size() == 2 and dice[0].dropped and not dice[1].dropped

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
