extends GutTest
## Tests for BattleController state machine transitions.
## Uses DataPipeline for real data to test integration.
## Spec reference: phase8-spec.md §5

var _pipeline: DataPipeline


func before_all() -> void:
	_pipeline = DataPipeline.new()
	var errors := _pipeline.run("res://data")
	assert_eq(errors.size(), 0, "data should load with zero errors")


# --- Helpers ---

static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	return p


func _make_unit(char_id: String, team: String) -> BattleUnit:
	var c: CharacterData = _pipeline.get_character(char_id)
	var fs: StatBlock = _pipeline.get_final_stats(char_id)
	if not c or not fs:
		return null
	var u := BattleUnit.from_character(c, fs)
	u.team = team
	return u


func _make_state() -> MatchState:
	var map := MapData.new()
	map.id = "test_ctrl"
	var tiles: Array[TileRecord] = []
	for q in range(-4, 5):
		for r in range(-4, 5):
			tiles.append(TileRecord.new(q, r, 0, "grass"))
	map.tiles = tiles
	map.deployment_zones = {
		"playerA": ["0,0", "1,0"],
		"playerB": ["3,0", "4,0"],
	}

	var unit_a := _make_unit("human_fighter", "playerA")
	var unit_b := _make_unit("elf_black_mage", "playerB")
	assert_not_null(unit_a)
	assert_not_null(unit_b)

	var party_a: Array[BattleUnit] = [unit_a]
	var party_b: Array[BattleUnit] = [unit_b]
	var state := MatchSetup.create(party_a, party_b, map, _stub_terrain)

	var resolver := AbilityResolver.new(
		_pipeline.get_ability, _pipeline.get_job_class, _pipeline.get_item)
	state.ability_provider = resolver.resolve
	state.item_provider = _pipeline.get_item

	Deployment.auto_deploy(state, map.deployment_zones)
	# auto_deploy now deploys and starts round 1 via DeploymentController

	return state


func _make_controller(state: MatchState) -> BattleController:
	var ctrl := BattleController.new()
	# Manually set state and subsystems for testing
	ctrl._state = state

	var resolver := AbilityResolver.new(
		_pipeline.get_ability, _pipeline.get_job_class, _pipeline.get_item)
	ctrl._resolver = resolver

	# Create minimal overlay controller (needs builder)
	var overlay := OverlayController.new()
	overlay.graph = state.graph
	# We need a MapBuilder with tiles to avoid null errors in overlay.clear()
	var builder := MapBuilder.new()
	add_child_autofree(builder)
	var all_maps: Array = _pipeline.maps.all()
	if not all_maps.is_empty():
		var map_data: MapData = all_maps.front() as MapData
		if map_data:
			builder.build(map_data)
	overlay.builder = builder
	ctrl._overlay = overlay
	ctrl.add_child(overlay)

	# Create PawnManager
	var pawn_mgr := PawnManager.new()
	pawn_mgr.setup(state, state.graph)
	ctrl._pawn_manager = pawn_mgr
	ctrl.add_child(pawn_mgr)

	# Create HUD — call setup() explicitly so UI nodes are built
	var hud := BattleHUD.new()
	hud.setup()
	ctrl._hud = hud
	ctrl.add_child(hud)

	# Connect signals
	hud.action_selected.connect(ctrl._on_action_selected)
	hud.ability_selected.connect(ctrl._on_ability_selected)
	hud.item_selected.connect(ctrl._on_item_selected)
	hud.finalize_move_pressed.connect(ctrl._on_finalize_move)
	hud.cancel_move_pressed.connect(ctrl._on_cancel_move)
	hud.unit_clicked.connect(ctrl._on_roster_unit_clicked)
	hud.back_to_menu_pressed.connect(ctrl._on_back_to_menu)
	hud.confirm_activation_pressed.connect(ctrl._on_confirm_activation)
	hud.cancel_activation_pressed.connect(ctrl._on_cancel_activation)

	ctrl._builder = builder

	add_child_autofree(ctrl)
	return ctrl


# --- Tests ---

func test_initial_state_is_awaiting_activation() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()
	assert_eq(ctrl._control_state, BattleController.ControlState.AWAITING_ACTIVATION)


func test_activate_next_transitions_to_action_select() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()
	ctrl._activate_next()

	# activate_next now sets pending — not yet in ACTION_SELECT
	assert_eq(ctrl._control_state, BattleController.ControlState.AWAITING_ACTIVATION,
		"should still be AWAITING_ACTIVATION until confirmed")
	assert_not_null(ctrl._pending_activation_unit, "should have a pending unit")

	ctrl._on_confirm_activation()

	assert_eq(ctrl._control_state, BattleController.ControlState.ACTION_SELECT,
		"should transition to ACTION_SELECT after confirmation")
	assert_not_null(state.current_unit, "should have a current unit")


func test_defend_executes_immediately() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()
	ctrl._activate_next()
	ctrl._on_confirm_activation()

	var unit := state.current_unit
	var ap_before := unit.ap_remaining

	ctrl._do_defend()

	assert_eq(unit.ap_remaining, ap_before - 1, "defend should cost 1 AP")


func test_wait_ends_activation() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()
	ctrl._activate_next()
	ctrl._on_confirm_activation()
	ctrl._do_wait()

	assert_eq(ctrl._control_state, BattleController.ControlState.AWAITING_ACTIVATION,
		"wait should return to AWAITING_ACTIVATION")
	assert_eq(state.current_unit, null, "current_unit should be null after wait")


func test_targeting_cancel_returns_to_action_select() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()
	ctrl._activate_next()
	ctrl._on_confirm_activation()
	ctrl._enter_targeting(BattleHUD.ACTION_MOVE)

	assert_eq(ctrl._control_state, BattleController.ControlState.TARGETING)

	ctrl._cancel_targeting()

	assert_eq(ctrl._control_state, BattleController.ControlState.ACTION_SELECT,
		"cancel should return to ACTION_SELECT")


func test_full_round_cycle() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()

	# Activate and wait for both units (select + confirm + wait)
	ctrl._activate_next()
	ctrl._on_confirm_activation()
	ctrl._do_wait()

	ctrl._activate_next()
	ctrl._on_confirm_activation()
	ctrl._do_wait()

	# Rounds auto-advance — should be in AWAITING_ACTIVATION for round 2
	assert_eq(ctrl._control_state, BattleController.ControlState.AWAITING_ACTIVATION,
		"after all units wait, round should auto-advance to AWAITING_ACTIVATION")
	assert_eq(state.round_number, 2, "round should have advanced to 2")


func test_start_new_round_transitions() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()
	assert_eq(state.round_number, 1, "should start at round 1")

	# Complete the round (select + confirm + wait for each) — auto-advances
	ctrl._activate_next()
	ctrl._on_confirm_activation()
	ctrl._do_wait()
	ctrl._activate_next()
	ctrl._on_confirm_activation()
	ctrl._do_wait()

	# Round auto-advanced
	assert_eq(ctrl._control_state, BattleController.ControlState.AWAITING_ACTIVATION,
		"new round should auto-advance to AWAITING_ACTIVATION")
	assert_eq(state.round_number, 2, "round number should increment")

	# Complete round 2 — should auto-advance again
	ctrl._activate_next()
	ctrl._on_confirm_activation()
	ctrl._do_wait()
	ctrl._activate_next()
	ctrl._on_confirm_activation()
	ctrl._do_wait()

	assert_eq(state.round_number, 3, "round number should increment again")


func test_drag_move_creates_pending_preview() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()
	ctrl._activate_next()
	ctrl._on_confirm_activation()

	var unit := state.current_unit
	assert_not_null(unit)
	var start_pos := unit.position
	var ap_before := unit.ap_remaining

	# Pick a reachable destination (one tile away)
	var dest := Vector2i(start_pos.x + 1, start_pos.y)

	# Simulate drag-move — should create preview, NOT commit
	ctrl._on_drag_move(dest)

	assert_true(ctrl._has_pending_move, "should have a pending move")
	assert_eq(ctrl._pending_move_coord, dest, "pending coord should match")
	assert_eq(unit.position, start_pos, "unit position should NOT change yet")
	assert_eq(unit.ap_remaining, ap_before, "AP should NOT be spent yet")


func test_finalize_move_commits() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()
	ctrl._activate_next()
	ctrl._on_confirm_activation()

	var unit := state.current_unit
	assert_not_null(unit)
	var start_pos := unit.position
	var ap_before := unit.ap_remaining

	var dest := Vector2i(start_pos.x + 1, start_pos.y)
	ctrl._on_drag_move(dest)
	ctrl._on_finalize_move()

	assert_eq(unit.position, dest, "unit should be at finalized destination")
	assert_eq(unit.ap_remaining, ap_before - 1, "finalize should cost 1 AP")
	assert_true(unit.has_moved, "unit should be marked as has_moved")
	assert_false(ctrl._has_pending_move, "pending move should be cleared")


func test_cancel_move_reverts() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()
	ctrl._activate_next()
	ctrl._on_confirm_activation()

	var unit := state.current_unit
	assert_not_null(unit)
	var start_pos := unit.position
	var ap_before := unit.ap_remaining

	var dest := Vector2i(start_pos.x + 1, start_pos.y)
	ctrl._on_drag_move(dest)
	ctrl._on_cancel_move()

	assert_eq(unit.position, start_pos, "unit should be back at original position")
	assert_eq(unit.ap_remaining, ap_before, "AP should not change on cancel")
	assert_false(unit.has_moved, "unit should not be marked as moved")
	assert_false(ctrl._has_pending_move, "pending move should be cleared")
	assert_eq(ctrl._control_state, BattleController.ControlState.ACTION_SELECT,
		"should return to ACTION_SELECT after cancel")


func test_must_reserve_move_blocks_at_1ap() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()
	ctrl._activate_next()
	ctrl._on_confirm_activation()

	var unit := state.current_unit
	assert_not_null(unit)
	unit.ap_remaining = 1
	unit.has_moved = false
	unit.base_ap = 2

	assert_true(ctrl._must_reserve_move(),
		"should reserve move when 1 AP, hasn't moved, base_ap >= 2")


func test_after_move_no_reserve() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()
	ctrl._activate_next()
	ctrl._on_confirm_activation()

	var unit := state.current_unit
	assert_not_null(unit)
	unit.ap_remaining = 1
	unit.has_moved = true
	unit.base_ap = 2

	assert_false(ctrl._must_reserve_move(),
		"should not reserve move after unit has moved")


func test_tile_click_activates_unit() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()
	assert_eq(ctrl._control_state, BattleController.ControlState.AWAITING_ACTIVATION)

	# Find the current team's first unactivated unit and its position
	var team := RoundManager.current_team(state)
	var available := state.unactivated_units(team)
	assert_false(available.is_empty(), "should have available units")

	var unit: BattleUnit = available[0]
	var pos := unit.position

	# Simulate tile click — sets pending, not yet activated
	ctrl.on_tile_selected(pos)

	assert_eq(ctrl._control_state, BattleController.ControlState.AWAITING_ACTIVATION,
		"tile click should set pending, not activate yet")
	assert_eq(ctrl._pending_activation_unit, unit, "clicked unit should be pending")

	# Confirm activation
	ctrl._on_confirm_activation()

	assert_eq(ctrl._control_state, BattleController.ControlState.ACTION_SELECT,
		"confirm should transition to ACTION_SELECT")
	assert_eq(state.current_unit, unit, "confirmed unit should be current_unit")


func test_tile_click_wrong_team_ignored() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()

	# Find the other team's unit position
	var team := RoundManager.current_team(state)
	var other := state.other_team(team)
	var enemy_units := state.unactivated_units(other)
	assert_false(enemy_units.is_empty(), "should have enemy units")

	var enemy_pos: Vector2i = enemy_units[0].position

	# Click on enemy tile — should do nothing
	ctrl.on_tile_selected(enemy_pos)

	assert_eq(ctrl._control_state, BattleController.ControlState.AWAITING_ACTIVATION,
		"clicking enemy unit should not change state")
	assert_eq(state.current_unit, null, "no unit should be activated")


func test_tile_click_empty_tile_ignored() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()

	# Click an empty tile
	ctrl.on_tile_selected(Vector2i(-3, -3))

	assert_eq(ctrl._control_state, BattleController.ControlState.AWAITING_ACTIVATION,
		"clicking empty tile should not change state")
	assert_eq(state.current_unit, null, "no unit should be activated")


func test_activate_next_still_works() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()
	ctrl._activate_next()

	assert_not_null(ctrl._pending_activation_unit,
		"N-key should set pending activation unit")
	assert_eq(ctrl._control_state, BattleController.ControlState.AWAITING_ACTIVATION,
		"should still be AWAITING until confirmed")

	ctrl._on_confirm_activation()

	assert_eq(ctrl._control_state, BattleController.ControlState.ACTION_SELECT,
		"after confirm, should be in ACTION_SELECT")
	assert_not_null(state.current_unit, "should have a current unit")


func test_roster_click_activates_unit() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()

	var team := RoundManager.current_team(state)
	var available := state.unactivated_units(team)
	assert_false(available.is_empty())
	var unit: BattleUnit = available[0]

	# Simulate roster click — sets pending
	ctrl._on_roster_unit_clicked(unit.character.id)

	assert_eq(ctrl._pending_activation_unit, unit, "roster click should set pending")
	assert_eq(ctrl._control_state, BattleController.ControlState.AWAITING_ACTIVATION,
		"should still be AWAITING until confirmed")

	# Confirm activation
	ctrl._on_confirm_activation()

	assert_eq(ctrl._control_state, BattleController.ControlState.ACTION_SELECT,
		"confirm should transition to ACTION_SELECT")
	assert_eq(state.current_unit, unit, "confirmed roster unit should be current_unit")


func test_cancel_activation_clears_pending() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()
	ctrl._activate_next()

	assert_not_null(ctrl._pending_activation_unit, "should have pending unit")

	ctrl._on_cancel_activation()

	assert_eq(ctrl._pending_activation_unit, null, "cancel should clear pending unit")
	assert_eq(ctrl._control_state, BattleController.ControlState.AWAITING_ACTIVATION,
		"should remain in AWAITING_ACTIVATION after cancel")
	assert_eq(state.current_unit, null, "no unit should be activated")


func test_zero_ap_stays_in_action_select() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()
	ctrl._activate_next()
	ctrl._on_confirm_activation()

	var unit := state.current_unit
	assert_not_null(unit)
	unit.ap_remaining = 0

	ctrl._check_end_activation_or_continue()

	assert_eq(ctrl._control_state, BattleController.ControlState.ACTION_SELECT,
		"0 AP should stay in ACTION_SELECT for explicit End Turn")
	assert_not_null(state.current_unit, "unit should still be current")


func test_match_over_when_team_eliminated() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	# Eliminate all playerB units
	for unit: BattleUnit in state.parties["playerB"]:
		unit.current_hp = 0
		unit.is_downed = false

	assert_eq(state.check_winner(), "playerA", "playerA should win when playerB has no viable units")


func test_winner_when_all_units_downed() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	# Down all playerB units — A17: all downed means team loses
	for unit: BattleUnit in state.parties["playerB"]:
		unit.current_hp = 0
		unit.is_downed = true

	assert_eq(state.check_winner(), "playerA", "team with all units downed should lose")


func test_check_winner_empty_when_both_alive() -> void:
	var state := _make_state()
	assert_eq(state.check_winner(), "", "no winner when both teams have living units")


func test_downed_unit_excluded_from_activation() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()

	# Down the current team's unit
	var team := RoundManager.current_team(state)
	var all_units := state.parties[team].duplicate()
	var unit: BattleUnit = all_units[0]
	unit.current_hp = 0
	unit.is_downed = true

	# A17: downed unit should be excluded from activatable_units
	var activatable := state.activatable_units(team)
	assert_false(activatable.has(unit),
		"downed unit should not appear in activatable_units")


func test_downed_unit_stays_on_board() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	RoundManager.start_round(state)

	# Down a unit
	var team := RoundManager.current_team(state)
	var unit: BattleUnit = state.parties[team][0]
	unit.current_hp = 0
	unit.is_downed = true

	# A17: downed unit stays on board (is_living) but is not activatable
	assert_true(unit.is_living(), "downed unit should still be living (on board)")
	assert_false(unit.is_active(), "downed unit should not be active")
	assert_true(state.is_occupied(unit.position), "downed unit's hex should remain occupied")


func test_activate_next_prefers_living_over_downed() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()

	var team := RoundManager.current_team(state)
	var units := state.activatable_units(team)
	# If there's a living unit, activate_next should prefer it
	var has_living := false
	for u: BattleUnit in units:
		if not u.is_downed:
			has_living = true
			break

	if has_living:
		ctrl._activate_next()
		assert_not_null(ctrl._pending_activation_unit)
		assert_false(ctrl._pending_activation_unit.is_downed,
			"activate_next should prefer living units")
