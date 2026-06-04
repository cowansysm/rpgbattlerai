class_name Phase4Demo
extends Node
## Phase 4 demo controller. Deploys two small parties and runs
## the alternating activation round loop with keyboard controls.
## N=next unit, M=move to selected tile, F=attack selected tile,
## G=defend, X=wait, R=start new round.
## Spec reference: phase4-spec.md, phase4-implementation-plan.md Group F

var _state: MatchState
var _builder: MapBuilder
var _overlay: OverlayController
var _selected_tile: Vector2i = Vector2i(-999, -999)


func setup(builder: MapBuilder, map_data: MapData) -> void:
	_builder = builder

	# Create two parties (2v2 for demo)
	var party_a: Array[BattleUnit] = []
	var party_b: Array[BattleUnit] = []
	party_a.append(_make_unit("human_fighter"))
	party_a.append(_make_unit("human_rogue"))
	party_b.append(_make_unit("elf_black_mage"))
	party_b.append(_make_unit("halfling_white_mage"))

	_state = MatchSetup.create(party_a, party_b, map_data, GameData.get_terrain)

	# Wire ability provider via AbilityResolver
	var resolver := AbilityResolver.new(
		GameData.get_ability, GameData.get_job_class, GameData.get_item)
	_state.ability_provider = resolver.resolve

	# Deploy
	var errors := Deployment.auto_deploy(_state, map_data.deployment_zones)
	if not errors.is_empty():
		for e in errors:
			Log.error("Phase4Demo", e)
		return

	# Overlay controller for movement preview
	_overlay = OverlayController.new()
	_overlay.graph = _state.graph
	_overlay.builder = builder
	add_child(_overlay)

	# Start first round
	RoundManager.start_round(_state)
	_log_state()


func _make_unit(char_id: String) -> BattleUnit:
	var c := GameData.get_character(char_id)
	var fs := GameData.get_final_stats(char_id)
	if not c or not fs:
		Log.error("Phase4Demo", "Character '%s' not found" % char_id)
		return null
	return BattleUnit.from_character(c, fs)


func _unhandled_input(event: InputEvent) -> void:
	if not _state:
		return

	if event.is_action_pressed("p4_next"):
		_activate_next()
	elif event.is_action_pressed("p4_move"):
		_do_move()
	elif event.is_action_pressed("p4_attack"):
		_do_attack()
	elif event.is_action_pressed("p4_defend"):
		_do_defend()
	elif event.is_action_pressed("p4_wait"):
		_do_wait()
	elif event.is_action_pressed("p4_round"):
		_start_new_round()
	elif event.is_action_pressed("demo_clear"):
		if _overlay:
			_overlay.clear()


func set_selected_tile(tile: Vector2i) -> void:
	_selected_tile = tile


func _activate_next() -> void:
	if _state.phase != MatchState.Phase.AWAITING_ACTIVATION:
		Log.info("Phase4Demo", "Not awaiting activation (phase=%d)" % _state.phase)
		return

	var team := RoundManager.current_team(_state)
	var available := _state.unactivated_units(team)
	if available.is_empty():
		Log.info("Phase4Demo", "No unactivated units for %s" % team)
		return

	var unit: BattleUnit = available[0]
	var err := RoundManager.activate_unit(_state, unit)
	if not err.is_empty():
		Log.error("Phase4Demo", err)
		return

	Log.info("Phase4Demo", "Activated %s (%s) at (%d,%d) — AP=%d" % [
		unit.character.id, unit.team,
		unit.position.x, unit.position.y, unit.ap_remaining])

	# Show movement overlay for the activated unit
	if _overlay:
		_overlay.show_movement(
			unit.position,
			unit.stats.effective_move(),
			unit.stats.effective_jump_climb())


func _do_move() -> void:
	if _state.phase != MatchState.Phase.UNIT_TURN or not _state.current_unit:
		Log.info("Phase4Demo", "No unit is currently activated")
		return

	if _selected_tile == Vector2i(-999, -999):
		Log.info("Phase4Demo", "No tile selected — click a tile first")
		return

	var result := TurnActions.execute_move(_state, _selected_tile)
	if result.has("error"):
		Log.error("Phase4Demo", "Move failed: %s" % str(result["error"]))
		return

	Log.info("Phase4Demo", "Moved %s to (%d,%d) — AP=%d" % [
		_state.current_unit.character.id,
		_selected_tile.x, _selected_tile.y,
		_state.current_unit.ap_remaining])

	# Refresh overlay from new position
	if _overlay:
		if _state.current_unit.ap_remaining > 0:
			_overlay.show_movement(
				_state.current_unit.position,
				_state.current_unit.stats.effective_move(),
				_state.current_unit.stats.effective_jump_climb())
		else:
			_overlay.clear()

	_check_end_activation()


func _do_attack() -> void:
	if _state.phase != MatchState.Phase.UNIT_TURN or not _state.current_unit:
		Log.info("Phase4Demo", "No unit is currently activated")
		return

	if _selected_tile == Vector2i(-999, -999):
		Log.info("Phase4Demo", "No tile selected — click a tile first")
		return

	var result := TurnActions.execute_attack(_state, _selected_tile)
	if result.has("error"):
		Log.error("Phase4Demo", "Attack failed: %s" % str(result["error"]))
		return

	Log.info("Phase4Demo", "Attack: %s -> %s (would hit) — AP=%d" % [
		str(result["actor"]), str(result["target"]),
		_state.current_unit.ap_remaining])

	_check_end_activation()


func _do_defend() -> void:
	if _state.phase != MatchState.Phase.UNIT_TURN or not _state.current_unit:
		Log.info("Phase4Demo", "No unit is currently activated")
		return

	var result := TurnActions.execute_defend(_state)
	if result.has("error"):
		Log.error("Phase4Demo", "Defend failed: %s" % str(result["error"]))
		return

	Log.info("Phase4Demo", "%s defends (+2 DEF) — AP=%d" % [
		_state.current_unit.character.id,
		_state.current_unit.ap_remaining])

	_check_end_activation()


func _do_wait() -> void:
	if _state.phase != MatchState.Phase.UNIT_TURN or not _state.current_unit:
		Log.info("Phase4Demo", "No unit is currently activated")
		return

	var result := TurnActions.execute_wait(_state)
	Log.info("Phase4Demo", "%s waits (forfeited %s AP)" % [
		str(result["actor"]), str(result["ap_forfeited"])])

	if _overlay:
		_overlay.clear()
	RoundManager.end_activation(_state)
	_log_state()


func _check_end_activation() -> void:
	if _state.current_unit and _state.current_unit.ap_remaining <= 0:
		Log.info("Phase4Demo", "%s finished (0 AP)" % _state.current_unit.character.id)
		if _overlay:
			_overlay.clear()
		RoundManager.end_activation(_state)
		_log_state()


func _start_new_round() -> void:
	if _state.phase != MatchState.Phase.ROUND_START:
		Log.info("Phase4Demo", "Cannot start round (phase=%d)" % _state.phase)
		return
	RoundManager.start_round(_state)
	_log_state()


func _log_state() -> void:
	Log.info("Phase4Demo", "--- Round %d | Initiative: %s | Phase: %d ---" % [
		_state.round_number, _state.initiative, _state.phase])

	if _state.phase == MatchState.Phase.AWAITING_ACTIVATION:
		var team := RoundManager.current_team(_state)
		var available := _state.unactivated_units(team)
		Log.info("Phase4Demo", "Waiting for %s to activate (%d available)" % [
			team, available.size()])

	# Log all unit positions
	for team in _state.parties.keys():
		for u: BattleUnit in _state.parties[team]:
			Log.info("Phase4Demo", "  %s [%s] at (%d,%d) HP=%d activated=%s" % [
				u.character.id, u.team,
				u.position.x, u.position.y,
				u.current_hp, str(u.is_activated)])
