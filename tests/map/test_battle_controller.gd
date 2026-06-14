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
	RoundManager.start_round(state)

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

	assert_eq(ctrl._control_state, BattleController.ControlState.ACTION_SELECT,
		"should transition to ACTION_SELECT after activation")
	assert_not_null(state.current_unit, "should have a current unit")


func test_defend_executes_immediately() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()
	ctrl._activate_next()

	var unit := state.current_unit
	var ap_before := unit.ap_remaining

	ctrl._do_defend()

	assert_eq(unit.ap_remaining, ap_before - 1, "defend should cost 1 AP")


func test_wait_ends_activation() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()
	ctrl._activate_next()
	ctrl._do_wait()

	assert_eq(ctrl._control_state, BattleController.ControlState.AWAITING_ACTIVATION,
		"wait should return to AWAITING_ACTIVATION")
	assert_eq(state.current_unit, null, "current_unit should be null after wait")


func test_targeting_cancel_returns_to_action_select() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()
	ctrl._activate_next()
	ctrl._enter_targeting(BattleHUD.ACTION_MOVE)

	assert_eq(ctrl._control_state, BattleController.ControlState.TARGETING)

	ctrl._cancel_targeting()

	assert_eq(ctrl._control_state, BattleController.ControlState.ACTION_SELECT,
		"cancel should return to ACTION_SELECT")


func test_full_round_cycle() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()

	# Activate and wait for both units
	ctrl._activate_next()
	ctrl._do_wait()

	ctrl._activate_next()
	ctrl._do_wait()

	# Should be at round end
	assert_eq(ctrl._control_state, BattleController.ControlState.ROUND_END,
		"after all units wait, should be at ROUND_END")


func test_start_new_round_transitions() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()

	# Complete the round
	ctrl._activate_next()
	ctrl._do_wait()
	ctrl._activate_next()
	ctrl._do_wait()

	assert_eq(ctrl._control_state, BattleController.ControlState.ROUND_END)

	# Start new round
	ctrl._start_new_round()
	assert_eq(ctrl._control_state, BattleController.ControlState.AWAITING_ACTIVATION,
		"new round should return to AWAITING_ACTIVATION")
	assert_eq(state.round_number, 2, "round number should increment")


func test_drag_move_creates_pending_preview() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()
	ctrl._activate_next()

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

	# Simulate tile click at that unit's position
	ctrl.on_tile_selected(pos)

	assert_eq(ctrl._control_state, BattleController.ControlState.ACTION_SELECT,
		"clicking own unit tile should transition to ACTION_SELECT")
	assert_eq(state.current_unit, unit, "clicked unit should be current_unit")


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

	assert_eq(ctrl._control_state, BattleController.ControlState.ACTION_SELECT,
		"N-key shortcut should still activate first available unit")
	assert_not_null(state.current_unit, "should have a current unit")


func test_roster_click_activates_unit() -> void:
	var state := _make_state()
	var ctrl := _make_controller(state)

	ctrl._enter_awaiting_activation()

	var team := RoundManager.current_team(state)
	var available := state.unactivated_units(team)
	assert_false(available.is_empty())
	var unit: BattleUnit = available[0]

	# Simulate roster click via signal handler
	ctrl._on_roster_unit_clicked(unit.character.id)

	assert_eq(ctrl._control_state, BattleController.ControlState.ACTION_SELECT,
		"roster click should transition to ACTION_SELECT")
	assert_eq(state.current_unit, unit, "clicked roster unit should be current_unit")
