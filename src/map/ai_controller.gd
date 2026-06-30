class_name AIController
extends Node
## Scene-level driver that executes AI plans via TurnActions.
## Receives a plan from AIPlanner, plays each step with pacing and
## visual feedback (pawn movement, dice markers, HUD logging),
## then ends the activation. Peer to BattleController for AI teams.

signal turn_complete

var _hud: BattleHUD
var _pawn_manager: PawnManager
var _overlay: OverlayController
var _rng: RandomNumberGenerator
var _difficulty: Dictionary
var _pace_delay: float = 0.4


func setup(
	hud: BattleHUD, pawn_manager: PawnManager, overlay: OverlayController,
	rng_seed: int, difficulty_name: String
) -> void:
	_hud = hud
	_pawn_manager = pawn_manager
	_overlay = overlay
	_rng = RandomNumberGenerator.new()
	_rng.seed = rng_seed
	_difficulty = AIPlanner.difficulty_preset(difficulty_name)
	_pace_delay = float(Constants.get_value("AI_PACE_DELAY", 0.4))


## Execute one full AI activation for state.current_unit.
func take_turn(state: MatchState) -> void:
	var unit: BattleUnit = state.current_unit
	if not unit:
		Log.warn("AIController", "take_turn called with no current unit")
		turn_complete.emit()
		return

	Log.info("AIController", "Planning for %s" % unit.character.display_name)
	var ai_plan: AIPlan = AIPlanner.plan(state, unit, _rng, _difficulty)

	if ai_plan.is_empty():
		Log.info("AIController", "Empty plan — ending activation")
		_end_turn(state)
		return

	for step in ai_plan.steps:
		var kind: String = str(step.get("kind", ""))
		var result: Dictionary

		match kind:
			"move":
				result = await _execute_move(state, unit, step)
			"attack":
				result = await _execute_attack(state, unit, step)
			"ability":
				result = await _execute_ability(state, unit, step)
			"defend":
				result = _execute_defend(state, unit)
			"wait":
				result = _execute_wait(state, unit)
			_:
				result = _execute_wait(state, unit)

		if result.has("error"):
			Log.warn("AIController", "Step '%s' failed: %s — aborting plan" % [kind, str(result["error"])])
			break

		# Pace between steps for readability
		if kind != "wait":
			await get_tree().create_timer(_pace_delay).timeout

	_end_turn(state)


# --- Step executors ---

func _execute_move(state: MatchState, unit: BattleUnit, step: Dictionary) -> Dictionary:
	var destination: Vector2i = step["target_pos"] as Vector2i
	var result := TurnActions.execute_move(state, destination)
	if result.has("error"):
		return result

	_hud.append_log("[AI] %s moves to (%d,%d)" % [
		unit.character.display_name, destination.x, destination.y], "action_move")

	# Log terrain effects
	for outcome in result.get("terrain_effects", []):
		if outcome.get("type") == "terrain_damage":
			_hud.append_log("[AI] %s takes %d terrain damage (%d HP)" % [
				unit.character.display_name, int(outcome["amount"]),
				int(outcome["target_hp_after"])], "terrain_damage")
		elif outcome.get("type") == "terrain_status":
			_hud.append_log("[AI] %s afflicted by %s" % [
				unit.character.display_name, str(outcome["status_id"])], "terrain_status")

	_pawn_manager.update_status_markers(unit)

	# Animate pawn movement and wait for completion
	var tw := _pawn_manager.move_pawn(unit, destination)
	if tw:
		await tw.finished

	return result


func _execute_attack(state: MatchState, unit: BattleUnit, step: Dictionary) -> Dictionary:
	var target_pos: Vector2i = step["target_pos"] as Vector2i
	var target_unit: BattleUnit = state.unit_at(target_pos)

	var result := TurnActions.execute_attack(state, target_pos)
	if result.has("error"):
		return result

	# Log the attack
	_log_attack_result(result)

	# Show symbol pawn beside target (awaitable landing beat)
	if target_unit:
		await _pawn_manager.show_ability_pawns([target_unit], "action_attack")

	# Show dice roll animations
	if result.has("atk_roll"):
		_pawn_manager.show_dice_roll(unit, int(result["atk_roll"]), true)
	var def_roll: int = int(result.get("def_roll", 0))
	if target_unit and def_roll > 0:
		_pawn_manager.show_dice_roll(target_unit, def_roll, false)

	if result.get("is_downed", false) and target_unit:
		_delay_down_pawn(target_unit)

	# Update status markers
	if target_unit:
		_pawn_manager.update_status_markers(target_unit)
	_pawn_manager.update_status_markers(unit)

	# Wait for dice animation
	await get_tree().create_timer(DiceMarker.TOTAL_DURATION).timeout

	return result


func _execute_ability(state: MatchState, unit: BattleUnit, step: Dictionary) -> Dictionary:
	var ability_id: String = str(step.get("ability_id", ""))
	var target_pos: Vector2i = step["target_pos"] as Vector2i

	# Snapshot affected units before execution
	var units_before := _snapshot_affected_units(state, target_pos)

	var result := TurnActions.execute_ability(state, ability_id, target_pos)
	if result.has("error"):
		return result

	# Log ability result
	_log_ability_result(result, ability_id)

	# Show symbol pawn beside each affected target (awaitable landing beat)
	var outcomes: Array = result.get("outcomes", [])
	var affected: Array = []
	for outcome in outcomes:
		var target_unit: BattleUnit = units_before.get(str(outcome.get("target", "")))
		if target_unit and target_unit not in affected:
			affected.append(target_unit)
	if not affected.is_empty():
		var ability: AbilityData = state.ability_provider.call(unit, ability_id)
		var icon: String = SymbolAtlas.symbol_for_ability(ability)
		await _pawn_manager.show_ability_pawns(affected, icon)

	# Show dice roll animations for damage outcomes
	for outcome in outcomes:
		if outcome.has("atk_roll"):
			_pawn_manager.show_dice_roll(unit, int(outcome["atk_roll"]), true)
			var def_val: int = int(outcome.get("def_roll", 0))
			if def_val > 0:
				var target_unit_dr: BattleUnit = units_before.get(str(outcome.get("target", "")))
				if target_unit_dr:
					_pawn_manager.show_dice_roll(target_unit_dr, def_val, false)

	# Handle downing and revive
	for outcome in outcomes:
		if outcome.get("is_downed", false):
			var downed_unit: BattleUnit = units_before.get(str(outcome["target"]))
			if downed_unit:
				_delay_down_pawn(downed_unit)
		elif outcome.get("revived", false):
			var revived_unit: BattleUnit = units_before.get(str(outcome["target"]))
			if revived_unit:
				_pawn_manager.revive_pawn(revived_unit)

	# Update status markers
	_pawn_manager.update_status_markers(unit)
	for key in units_before:
		var u: BattleUnit = units_before[key]
		_pawn_manager.update_status_markers(u)

	# Wait for dice animation if there were damage outcomes
	var has_dice := false
	for outcome in outcomes:
		if outcome.has("atk_roll"):
			has_dice = true
			break
	if has_dice:
		await get_tree().create_timer(DiceMarker.TOTAL_DURATION).timeout

	return result


func _execute_defend(state: MatchState, unit: BattleUnit) -> Dictionary:
	var result := TurnActions.execute_defend(state)
	if result.has("error"):
		return result

	_hud.append_log("[AI] %s defends (+3 DEF)" % unit.character.display_name, "action_defend")
	_pawn_manager.update_status_markers(unit)
	return result


func _execute_wait(state: MatchState, unit: BattleUnit) -> Dictionary:
	var result := TurnActions.execute_wait(state)
	_hud.append_log("[AI] %s waits" % unit.character.display_name, "action_wait")
	return result


# --- End turn ---

func _end_turn(state: MatchState) -> void:
	var removed := RoundManager.end_activation(state)
	if removed:
		_pawn_manager.remove_pawn(removed)
		_hud.append_log("[AI] %s has been permanently removed" % removed.character.display_name)
	_overlay.clear()
	turn_complete.emit()


# --- Helpers (mirror BattleController patterns) ---

func _delay_down_pawn(unit: BattleUnit) -> void:
	get_tree().create_timer(DiceMarker.TOTAL_DURATION).timeout.connect(
		func() -> void:
			if is_instance_valid(_pawn_manager) and _pawn_manager.has_pawn(unit):
				_pawn_manager.down_pawn(unit))


func _snapshot_affected_units(state: MatchState, target_pos: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	for team in state.parties.keys():
		for unit: BattleUnit in state.parties[team]:
			if unit.current_hp > 0 or unit.is_downed:
				result[unit.character.id] = unit
	return result


func _log_attack_result(result: Dictionary) -> void:
	var actor: String = str(result.get("actor", ""))
	var target: String = str(result.get("target", ""))

	if result.get("missed", false):
		_hud.append_log("[AI] %s attacks %s -- MISSED (%s)" % [
			actor, target, str(result.get("reason", ""))], "action_attack")
	else:
		var dmg: int = int(result.get("damage", 0))
		var hp_after: int = int(result.get("target_hp_after", 0))
		var downed: String = " DOWNED!" if result.get("is_downed", false) else ""
		_hud.append_log("[AI] %s attacks %s for %d damage (%d HP)%s" % [
			actor, target, dmg, hp_after, downed], "action_attack")


func _log_ability_result(result: Dictionary, ability_id: String = "") -> void:
	var actor: String = str(result.get("actor", ""))
	var ability_name: String = str(result.get("ability", ""))

	for outcome in result.get("outcomes", []):
		var target_name: String = str(outcome.get("target", ""))
		if outcome.has("damage"):
			var dmg: int = int(outcome.get("damage", 0))
			var hp_after: int = int(outcome.get("target_hp_after", 0))
			var downed: String = " DOWNED!" if outcome.get("is_downed", false) else ""
			var element: String = str(outcome.get("element", ""))
			var elem_str := " %s" % element if not element.is_empty() else ""
			_hud.append_log("[AI] %s casts %s on %s -- %d%s damage (%d HP)%s" % [
				actor, ability_name, target_name, dmg, elem_str, hp_after, downed], ability_id)
		elif outcome.has("healing"):
			var heal: int = int(outcome.get("healing", 0))
			var hp_after: int = int(outcome.get("target_hp_after", 0))
			_hud.append_log("[AI] %s casts %s on %s -- heals %d HP (%d HP)" % [
				actor, ability_name, target_name, heal, hp_after], ability_id)
		elif outcome.has("buff_stat"):
			var stat: String = str(outcome.get("buff_stat", ""))
			var val: int = int(outcome.get("buff_value", 0))
			var dur: int = int(outcome.get("buff_duration", 1))
			_hud.append_log("[AI] %s casts %s on %s -- +%d %s for %d rounds" % [
				actor, ability_name, target_name, val, stat.to_upper(), dur], ability_id)
		elif outcome.get("revived", false):
			var hp_after: int = int(outcome.get("target_hp_after", 0))
			_hud.append_log("[AI] %s casts %s on %s -- REVIVED! (%d HP)" % [
				actor, ability_name, target_name, hp_after], ability_id)
		elif outcome.has("status_id"):
			var status_id: String = str(outcome.get("status_id", ""))
			var dur: int = int(outcome.get("status_duration", 1))
			_hud.append_log("[AI] %s casts %s on %s -- %s for %d rounds" % [
				actor, ability_name, target_name, status_id, dur], ability_id)
