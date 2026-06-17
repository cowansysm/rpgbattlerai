extends GutTest
## Integration tests: full round cycle with deployment, activation, and actions.


# --- Stub terrain provider ---

static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	return p


# --- Helpers ---

func _make_unit(id: String, spd: int = 3, hp: int = 10) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = []
	c.abilities = []
	var sb := StatBlock.new()
	sb.set_base("spd", spd)
	sb.set_base("hp", hp)
	sb.set_base("def", 1)
	sb.set_base("atk", 2)
	sb.set_base("rng", 1)
	return BattleUnit.from_character(c, sb)


func _setup_match() -> MatchState:
	var map := MapData.new()
	map.id = "test_integration"
	var tiles: Array[TileRecord] = []
	for c in Hex.hexes_in_range(Vector2i(0, 0), 5):
		tiles.append(TileRecord.new(c.x, c.y, 0, "grass"))
	map.tiles = tiles
	map.deployment_zones = {
		"playerA": ["-3,0", "-3,1"],
		"playerB": ["3,0", "3,-1"],
	}

	var party_a: Array[BattleUnit] = [
		_make_unit("a0", 4),	# SPD 4 (higher)
		_make_unit("a1", 3),
	]
	var party_b: Array[BattleUnit] = [
		_make_unit("b0", 3),
		_make_unit("b1", 2),
	]

	var state := MatchSetup.create(party_a, party_b, map, _stub_terrain)
	Deployment.auto_deploy(state, map.deployment_zones)
	return state


# --- Tests ---

func test_full_round_deploy_activate_act() -> void:
	var state := _setup_match()

	# After deployment, state should be ROUND_START
	assert_eq(state.phase, MatchState.Phase.ROUND_START)
	assert_eq(state.initiative, "playerA",
		"playerA has SPD 4, should have initiative")

	# Start round 1
	RoundManager.start_round(state)
	assert_eq(state.round_number, 1)
	assert_eq(state.phase, MatchState.Phase.AWAITING_ACTIVATION)

	# All 4 units should be in the queue
	assert_eq(state.activation_queue.size(), 4)

	# Activate each unit in turn and have them wait
	for i in range(4):
		var team := RoundManager.current_team(state)
		assert_false(team.is_empty(), "should have a team for activation %d" % i)

		var available := state.unactivated_units(team)
		assert_true(available.size() > 0,
			"team %s should have available units at step %d" % [team, i])

		var unit: BattleUnit = available[0]
		var err := RoundManager.activate_unit(state, unit)
		assert_eq(err, "", "activation should succeed at step %d" % i)
		assert_eq(state.phase, MatchState.Phase.UNIT_TURN)

		# Wait to end turn
		TurnActions.execute_wait(state)
		assert_eq(unit.ap_remaining, 0)

		RoundManager.end_activation(state)

	# After all activations, round should end
	assert_eq(state.phase, MatchState.Phase.ROUND_START)
	# Initiative should flip to playerB
	assert_eq(state.initiative, "playerB")


func test_move_then_wait_round() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# First unit: move then wait
	var team := RoundManager.current_team(state)
	var unit: BattleUnit = state.unactivated_units(team)[0]
	RoundManager.activate_unit(state, unit)

	# Move to an adjacent tile
	var neighbors := Hex.neighbors(unit.position)
	var dest: Vector2i = Vector2i.ZERO
	for nb in neighbors:
		if state.graph.has_tile(nb) and not state.is_occupied(nb):
			dest = nb
			break
	var move_result := TurnActions.execute_move(state, dest)
	assert_false(move_result.has("error"), "move should succeed")
	assert_eq(unit.position, dest)
	assert_eq(unit.ap_remaining, 1)

	# Wait with remaining AP
	TurnActions.execute_wait(state)
	assert_eq(unit.ap_remaining, 0)
	RoundManager.end_activation(state)

	# Match log should have 2 records (move + wait)
	assert_eq(state.match_log.size(), 2)


func test_defend_persists_until_next_round() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Activate first unit and defend
	var team := RoundManager.current_team(state)
	var unit: BattleUnit = state.unactivated_units(team)[0]
	RoundManager.activate_unit(state, unit)

	var base_def: int = unit.stats.base("def")
	TurnActions.execute_defend(state)
	assert_eq(unit.stats.effective("def"), base_def + 3,
		"DEF should be increased after defend")

	TurnActions.execute_wait(state)
	RoundManager.end_activation(state)

	# DEF still boosted during the rest of this round
	assert_eq(unit.stats.effective("def"), base_def + 3)

	# Complete the round (wait for remaining 3 units)
	for i in range(3):
		var t := RoundManager.current_team(state)
		var u: BattleUnit = state.unactivated_units(t)[0]
		RoundManager.activate_unit(state, u)
		TurnActions.execute_wait(state)
		RoundManager.end_activation(state)

	# Start round 2 — defend persists through round start (cleared on activation)
	RoundManager.start_round(state)
	assert_eq(unit.stats.effective("def"), base_def + 3,
		"DEF should persist through round start")
	# Defend cleared when unit is activated again
	var t2 := RoundManager.current_team(state)
	if t2 != unit.team:
		# Skip other team's activation to reach our unit's turn
		var skip_u: BattleUnit = state.unactivated_units(t2)[0]
		RoundManager.activate_unit(state, skip_u)
		TurnActions.execute_wait(state)
		RoundManager.end_activation(state)
	RoundManager.activate_unit(state, unit)
	assert_eq(unit.stats.effective("def"), base_def,
		"DEF should be reset on next activation")


func test_two_rounds_initiative_alternates() -> void:
	var state := _setup_match()

	# Round 1
	RoundManager.start_round(state)
	var r1_initiative := state.initiative
	for i in range(4):
		var t := RoundManager.current_team(state)
		var u: BattleUnit = state.unactivated_units(t)[0]
		RoundManager.activate_unit(state, u)
		TurnActions.execute_wait(state)
		RoundManager.end_activation(state)

	# Round 2
	RoundManager.start_round(state)
	assert_eq(state.initiative, state.other_team(r1_initiative),
		"initiative should flip for round 2")

	# Complete round 2
	for i in range(4):
		var t := RoundManager.current_team(state)
		var u: BattleUnit = state.unactivated_units(t)[0]
		RoundManager.activate_unit(state, u)
		TurnActions.execute_wait(state)
		RoundManager.end_activation(state)

	# Round 3 should flip back
	assert_eq(state.initiative, r1_initiative,
		"initiative should flip back for round 3")


func test_occupancy_blocks_movement() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Activate first unit
	var team := RoundManager.current_team(state)
	var unit: BattleUnit = state.unactivated_units(team)[0]
	RoundManager.activate_unit(state, unit)

	# Try to move to a tile occupied by a teammate
	var ally_pos: Vector2i = Vector2i.ZERO
	for t in state.parties[team]:
		var u: BattleUnit = t
		if u != unit:
			ally_pos = u.position
			break

	if ally_pos != Vector2i.ZERO:
		var result := TurnActions.execute_move(state, ally_pos)
		assert_true(result.has("error"), "should not move to occupied tile")
