extends GutTest
## Tests for the TurnSystem seam and AlternatingTurnSystem wrapper.


# --- Helpers (mirror test_round_manager.gd) ---

static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	return p


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


# --- TurnSystem base class tests ---

func test_base_turn_system_wants_telegraph_false() -> void:
	var ts := TurnSystem.new()
	assert_false(ts.wants_telegraph())


func test_base_turn_system_is_round_complete_returns_true() -> void:
	var ts := TurnSystem.new()
	var state := _deployed_state(1, 1)
	assert_true(ts.is_round_complete(state))


# --- MatchState Phase extensions ---

func test_new_phases_exist() -> void:
	assert_eq(MatchState.Phase.AI_PLANNING, 6)
	assert_eq(MatchState.Phase.PLAYER_PLANNING, 7)
	assert_eq(MatchState.Phase.RESOLUTION, 8)


func test_turn_system_defaults_null() -> void:
	var state := MatchState.new()
	assert_null(state.turn_system)


# --- AlternatingTurnSystem tests ---

func test_alternating_wants_telegraph_false() -> void:
	var ats := AlternatingTurnSystem.new()
	assert_false(ats.wants_telegraph())


func test_alternating_begin_round_increments_counter() -> void:
	var state := _deployed_state(2, 2)
	var ats := AlternatingTurnSystem.new()
	ats.begin_round(state)
	assert_eq(state.round_number, 1)
	ats.begin_round(state)
	assert_eq(state.round_number, 2)


func test_alternating_begin_round_sets_phase() -> void:
	var state := _deployed_state(2, 2)
	var ats := AlternatingTurnSystem.new()
	ats.begin_round(state)
	assert_eq(state.phase, MatchState.Phase.AWAITING_ACTIVATION)


func test_alternating_begin_round_builds_queue() -> void:
	var state := _deployed_state(2, 2)
	var ats := AlternatingTurnSystem.new()
	ats.begin_round(state)
	assert_eq(state.activation_queue.size(), 4)


func test_alternating_begin_round_resets_units() -> void:
	var state := _deployed_state(2, 2)
	state.parties["playerA"][0].is_activated = true
	state.parties["playerA"][0].ap_remaining = 0
	var ats := AlternatingTurnSystem.new()
	ats.begin_round(state)
	assert_false(state.parties["playerA"][0].is_activated)
	assert_eq(state.parties["playerA"][0].ap_remaining, 2)


func test_alternating_is_round_complete() -> void:
	var state := _deployed_state(1, 1)
	var ats := AlternatingTurnSystem.new()
	ats.begin_round(state)
	assert_false(ats.is_round_complete(state))

	# Activate and end all units
	for i in range(2):
		var team := RoundManager.current_team(state)
		var unit: BattleUnit = state.unactivated_units(team)[0]
		RoundManager.activate_unit(state, unit)
		RoundManager.end_activation(state)

	assert_true(ats.is_round_complete(state))


# --- RoundManager delegation tests ---

func test_start_round_delegates_when_turn_system_set() -> void:
	var state := _deployed_state(2, 2)
	var ats := AlternatingTurnSystem.new()
	state.turn_system = ats
	RoundManager.start_round(state)
	# Should have delegated to AlternatingTurnSystem.begin_round
	assert_eq(state.round_number, 1)
	assert_eq(state.phase, MatchState.Phase.AWAITING_ACTIVATION)
	assert_eq(state.activation_queue.size(), 4)


func test_start_round_legacy_when_turn_system_null() -> void:
	var state := _deployed_state(2, 2)
	state.turn_system = null
	RoundManager.start_round(state)
	# Should use legacy path
	assert_eq(state.round_number, 1)
	assert_eq(state.phase, MatchState.Phase.AWAITING_ACTIVATION)
	assert_eq(state.activation_queue.size(), 4)


func test_do_round_start_bookkeeping_increments_round() -> void:
	var state := _deployed_state(1, 1)
	RoundManager.do_round_start_bookkeeping(state)
	assert_eq(state.round_number, 1)
	RoundManager.do_round_start_bookkeeping(state)
	assert_eq(state.round_number, 2)


func test_do_round_start_bookkeeping_expires_buffs() -> void:
	var state := _deployed_state(1, 1)
	var unit: BattleUnit = state.parties["playerA"][0]
	unit.stats.push_modifier(StatModifier.new("atk", 3, "buff:test"))
	state.buff_durations.append({
		"source_tag": "buff:test",
		"unit": unit,
		"remaining": 1,
	})
	RoundManager.do_round_start_bookkeeping(state)
	assert_eq(state.buff_durations.size(), 0, "Expired buff should be removed")
	assert_false(unit.stats.has_modifier_from_source("buff:test"))


func test_do_round_start_bookkeeping_ticks_statuses() -> void:
	var state := _deployed_state(1, 1)
	var unit: BattleUnit = state.parties["playerA"][0]
	unit.status_effects.append({"id": "poison", "duration": 2, "source": "test"})
	RoundManager.do_round_start_bookkeeping(state)
	assert_eq(unit.status_effects[0]["duration"], 1)
	RoundManager.do_round_start_bookkeeping(state)
	assert_eq(unit.status_effects.size(), 0, "Status should expire after duration reaches 0")


func test_do_round_start_bookkeeping_resets_units() -> void:
	var state := _deployed_state(1, 1)
	var unit: BattleUnit = state.parties["playerA"][0]
	unit.is_activated = true
	unit.has_moved = true
	unit.ap_remaining = 0
	RoundManager.do_round_start_bookkeeping(state)
	assert_false(unit.is_activated)
	assert_false(unit.has_moved)
	assert_eq(unit.ap_remaining, 2)
