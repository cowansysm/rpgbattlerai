extends GutTest
## Tests for RoundManager: activation queue, round lifecycle, initiative.


# --- Stub terrain provider ---

static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	return p


# --- Helpers ---

func _make_unit(id: String, team: String, spd: int = 3) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = []
	c.abilities = []
	var sb := StatBlock.new()
	sb.set_base("spd", spd)
	sb.set_base("hp", 10)
	sb.set_base("def", 1)
	sb.set_base("atk", 2)
	sb.set_base("rng", 1)
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	return u


func _deployed_state(count_a: int, count_b: int) -> MatchState:
	var map := MapData.new()
	map.id = "test"
	var tiles: Array[TileRecord] = []
	for c in Hex.hexes_in_range(Vector2i(0, 0), 5):
		tiles.append(TileRecord.new(c.x, c.y, 0, "grass"))
	map.tiles = tiles

	var party_a: Array[BattleUnit] = []
	var party_b: Array[BattleUnit] = []
	for i in range(count_a):
		party_a.append(_make_unit("a%d" % i, "playerA", 4))
	for i in range(count_b):
		party_b.append(_make_unit("b%d" % i, "playerB", 3))

	var state := MatchSetup.create(party_a, party_b, map, _stub_terrain)

	# Manual deployment to known positions
	var idx := 0
	for u: BattleUnit in party_a:
		var pos := Vector2i(-4 + idx, 0)
		u.position = pos
		state.occupancy[pos] = u
		idx += 1
	idx = 0
	for u: BattleUnit in party_b:
		var pos := Vector2i(4 - idx, 0)
		u.position = pos
		state.occupancy[pos] = u
		idx += 1

	state.phase = MatchState.Phase.ROUND_START
	return state


# --- Tests ---

func test_start_round_increments_counter() -> void:
	var state := _deployed_state(2, 2)
	RoundManager.start_round(state)
	assert_eq(state.round_number, 1)
	RoundManager.start_round(state)
	assert_eq(state.round_number, 2)


func test_start_round_resets_units() -> void:
	var state := _deployed_state(2, 2)
	# Pre-activate a unit
	state.parties["playerA"][0].is_activated = true
	state.parties["playerA"][0].ap_remaining = 0
	state.parties["playerA"][0].has_moved = true
	RoundManager.start_round(state)
	assert_false(state.parties["playerA"][0].is_activated)
	assert_eq(state.parties["playerA"][0].ap_remaining, 2)
	assert_false(state.parties["playerA"][0].has_moved, "has_moved should reset")


func test_start_round_uses_base_ap() -> void:
	var state := _deployed_state(1, 1)
	state.parties["playerA"][0].base_ap = 3
	RoundManager.start_round(state)
	assert_eq(state.parties["playerA"][0].ap_remaining, 3,
		"ap_remaining should use base_ap")


func test_defend_persists_through_round_start() -> void:
	var state := _deployed_state(1, 1)
	state.parties["playerA"][0].stats.push_modifier(
		StatModifier.new("def", 2, "defend"))
	var base_def: int = state.parties["playerA"][0].stats.base("def")
	assert_eq(state.parties["playerA"][0].stats.effective("def"), base_def + 2)
	# Defend modifier should survive round start (lasts until unit's next turn)
	RoundManager.start_round(state)
	assert_eq(state.parties["playerA"][0].stats.effective("def"), base_def + 2,
		"defend should persist through round start")


func test_defend_removed_on_activation() -> void:
	var state := _deployed_state(1, 1)
	var unit: BattleUnit = state.parties["playerA"][0]
	unit.stats.push_modifier(StatModifier.new("def", 2, "defend"))
	var base_def: int = unit.stats.base("def")
	assert_eq(unit.stats.effective("def"), base_def + 2)
	RoundManager.start_round(state)
	# Activate the unit — defend should be cleared
	var team := RoundManager.current_team(state)
	RoundManager.activate_unit(state, unit)
	assert_eq(unit.stats.effective("def"), base_def,
		"defend should be removed when unit is activated")


func test_activation_queue_alternates_equal_parties() -> void:
	var state := _deployed_state(2, 2)
	RoundManager.start_round(state)
	assert_eq(state.activation_queue.size(), 4)
	# Initiative team goes first
	assert_eq(state.activation_queue[0], state.initiative)
	# Teams alternate
	assert_ne(state.activation_queue[0], state.activation_queue[1])
	assert_eq(state.activation_queue[0], state.activation_queue[2])
	assert_eq(state.activation_queue[1], state.activation_queue[3])


func test_activation_queue_uneven_parties() -> void:
	var state := _deployed_state(3, 1)
	RoundManager.start_round(state)
	assert_eq(state.activation_queue.size(), 4)
	# After the smaller team runs out, larger team gets consecutive turns
	# Initiative is playerA (SPD 4 > SPD 3), so: A, B, A, A
	assert_eq(state.activation_queue[0], "playerA")
	assert_eq(state.activation_queue[1], "playerB")
	assert_eq(state.activation_queue[2], "playerA")
	assert_eq(state.activation_queue[3], "playerA")


func test_activate_unit_sets_current() -> void:
	var state := _deployed_state(2, 2)
	RoundManager.start_round(state)
	var team := RoundManager.current_team(state)
	var unit: BattleUnit = state.unactivated_units(team)[0]
	var err := RoundManager.activate_unit(state, unit)
	assert_eq(err, "")
	assert_eq(state.current_unit, unit)
	assert_eq(state.phase, MatchState.Phase.UNIT_TURN)


func test_activate_unit_resets_has_moved() -> void:
	var state := _deployed_state(2, 2)
	RoundManager.start_round(state)
	var team := RoundManager.current_team(state)
	var unit: BattleUnit = state.unactivated_units(team)[0]
	unit.has_moved = true  # simulate leftover from previous activation
	RoundManager.activate_unit(state, unit)
	assert_false(unit.has_moved, "activate_unit should reset has_moved")


func test_activate_wrong_team_fails() -> void:
	var state := _deployed_state(2, 2)
	RoundManager.start_round(state)
	var wrong_team := state.other_team(RoundManager.current_team(state))
	var unit: BattleUnit = state.unactivated_units(wrong_team)[0]
	var err := RoundManager.activate_unit(state, unit)
	assert_true(err.length() > 0, "activating wrong team should fail")


func test_activate_already_activated_fails() -> void:
	var state := _deployed_state(2, 2)
	RoundManager.start_round(state)
	var team := RoundManager.current_team(state)
	var unit: BattleUnit = state.unactivated_units(team)[0]
	unit.is_activated = true
	var err := RoundManager.activate_unit(state, unit)
	assert_true(err.length() > 0, "activating already-activated unit should fail")


func test_end_activation_marks_spent() -> void:
	var state := _deployed_state(2, 2)
	RoundManager.start_round(state)
	var team := RoundManager.current_team(state)
	var unit: BattleUnit = state.unactivated_units(team)[0]
	RoundManager.activate_unit(state, unit)
	RoundManager.end_activation(state)
	assert_true(unit.is_activated)
	assert_eq(unit.ap_remaining, 0)


func test_end_activation_advances_queue() -> void:
	var state := _deployed_state(2, 2)
	RoundManager.start_round(state)
	assert_eq(state.current_index, 0)
	var unit: BattleUnit = state.unactivated_units(
		RoundManager.current_team(state))[0]
	RoundManager.activate_unit(state, unit)
	RoundManager.end_activation(state)
	assert_eq(state.current_index, 1)


func test_round_ends_when_all_activated() -> void:
	var state := _deployed_state(1, 1)
	RoundManager.start_round(state)

	# Activate and end both units
	for i in range(2):
		var team := RoundManager.current_team(state)
		var unit: BattleUnit = state.unactivated_units(team)[0]
		RoundManager.activate_unit(state, unit)
		RoundManager.end_activation(state)

	# Round should have ended, phase back to ROUND_START
	assert_eq(state.phase, MatchState.Phase.ROUND_START)


func test_initiative_flips_after_round() -> void:
	var state := _deployed_state(1, 1)
	var first_initiative: String = state.initiative
	RoundManager.start_round(state)

	# Complete the round
	for i in range(2):
		var team := RoundManager.current_team(state)
		var unit: BattleUnit = state.unactivated_units(team)[0]
		RoundManager.activate_unit(state, unit)
		RoundManager.end_activation(state)

	# Initiative should have flipped
	assert_eq(state.initiative, state.other_team(first_initiative))


func test_full_round_cycle() -> void:
	var state := _deployed_state(2, 2)
	RoundManager.start_round(state)
	assert_eq(state.round_number, 1)

	# Activate all 4 units
	for i in range(4):
		var team := RoundManager.current_team(state)
		assert_false(team.is_empty(), "should have activations remaining")
		var unit: BattleUnit = state.unactivated_units(team)[0]
		RoundManager.activate_unit(state, unit)
		RoundManager.end_activation(state)

	# Should be ready for next round
	assert_eq(state.phase, MatchState.Phase.ROUND_START)

	# Start round 2
	RoundManager.start_round(state)
	assert_eq(state.round_number, 2)
	assert_eq(state.activation_queue.size(), 4)
