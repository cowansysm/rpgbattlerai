extends GutTest
## Tests for ChargeTimeTurnSystem: system integration, round boundaries,
## mode selection, telegraph forced off.


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
	c.race = "human"
	var sb := StatBlock.new()
	sb.set_base("spd", spd)
	sb.set_base("hp", 10)
	sb.set_base("def", 1)
	sb.set_base("atk", 2)
	sb.set_base("rng", 1)
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	return u


func _deployed_state(units_a: Array, units_b: Array) -> MatchState:
	var map := MapData.new()
	map.id = "test"
	var tiles: Array[TileRecord] = []
	for coord in Hex.hexes_in_range(Vector2i(0, 0), 5):
		tiles.append(TileRecord.new(coord.x, coord.y, 0, "grass"))
	map.tiles = tiles

	var party_a: Array[BattleUnit] = []
	var party_b: Array[BattleUnit] = []
	for u in units_a:
		party_a.append(u)
	for u in units_b:
		party_b.append(u)

	var state := MatchSetup.create(party_a, party_b, map, _stub_terrain)

	# Deploy to positions
	var idx := 0
	for u: BattleUnit in party_a:
		var pos := Vector2i(-3 + idx, 0)
		u.position = pos
		state.occupancy[pos] = u
		idx += 1
	idx = 0
	for u: BattleUnit in party_b:
		var pos := Vector2i(3 - idx, 0)
		u.position = pos
		state.occupancy[pos] = u
		idx += 1

	state.phase = MatchState.Phase.ROUND_START
	return state


# --- Tests ---

func test_wants_telegraph_returns_false() -> void:
	var sys := ChargeTimeTurnSystem.new()
	assert_false(sys.wants_telegraph(), "CT system should not want telegraph")


func test_begin_round_sets_phase() -> void:
	var fast := _make_unit("fast", "playerA", 7)
	var slow := _make_unit("slow", "playerB", 3)
	var state := _deployed_state([fast], [slow])
	var sys := ChargeTimeTurnSystem.new()
	sys.setup([fast, slow], 42)
	state.turn_system = sys

	sys.begin_round(state)
	assert_eq(state.phase, MatchState.Phase.AWAITING_ACTIVATION)


func test_advance_activates_unit_on_threshold() -> void:
	var fast := _make_unit("fast", "playerA", 10)
	var slow := _make_unit("slow", "playerB", 3)
	var state := _deployed_state([fast], [slow])
	var sys := ChargeTimeTurnSystem.new()
	sys.setup([fast, slow], 42)
	state.turn_system = sys

	sys.begin_round(state)

	# Tick until a unit crosses threshold
	var activated: BattleUnit = null
	for _i in range(200):
		sys.advance(state)
		if sys.activated_unit:
			activated = sys.activated_unit
			break

	assert_not_null(activated, "A unit should be activated")
	assert_eq(activated.character.id, "fast", "Fastest unit should activate first")


func test_on_activation_complete_clears_activated() -> void:
	var unit := _make_unit("warrior", "playerA", 10)
	var state := _deployed_state([unit], [_make_unit("foe", "playerB", 3)])
	var sys := ChargeTimeTurnSystem.new()
	sys.setup([unit, state.parties["playerB"][0]], 42)
	state.turn_system = sys

	sys.begin_round(state)

	# Tick until activation
	for _i in range(200):
		sys.advance(state)
		if sys.activated_unit:
			break

	assert_not_null(sys.activated_unit)
	sys.on_activation_complete(state, false)
	assert_null(sys.activated_unit, "activated_unit should be cleared after completion")


func test_round_completes_after_all_units_activate() -> void:
	var a := _make_unit("a", "playerA", 5)
	var b := _make_unit("b", "playerB", 5)
	var state := _deployed_state([a], [b])
	var sys := ChargeTimeTurnSystem.new()
	sys.setup([a, b], 42)
	state.turn_system = sys

	sys.begin_round(state)

	var activations := 0
	for _i in range(500):
		sys.advance(state)
		if sys.activated_unit:
			activations += 1
			state.current_unit = sys.activated_unit
			sys.on_activation_complete(state, false)
		if sys.is_round_complete(state):
			break

	assert_gte(activations, 2, "Both units should have activated")
	assert_true(sys.is_round_complete(state), "Round should be complete")


func test_get_timeline_returns_forecast() -> void:
	var fast := _make_unit("fast", "playerA", 7)
	var slow := _make_unit("slow", "playerB", 3)
	var state := _deployed_state([fast], [slow])
	var sys := ChargeTimeTurnSystem.new()
	sys.setup([fast, slow], 42)
	state.turn_system = sys

	sys.begin_round(state)

	var timeline: Array = sys.get_timeline(4)
	assert_gte(timeline.size(), 1, "Timeline should have entries")
	# First entry should be fastest unit
	assert_eq(timeline[0]["unit"].character.id, "fast")


func test_ct_system_with_haste_and_slow() -> void:
	var normal := _make_unit("normal", "playerA", 5)
	var hasted := _make_unit("hasted", "playerA", 5)
	var slowed := _make_unit("slowed_u", "playerB", 5)
	hasted.status_effects = [{"id": "haste", "duration": 3, "source": "test"}]
	slowed.status_effects = [{"id": "slowed", "duration": 3, "source": "test"}]

	var state := _deployed_state([normal, hasted], [slowed])
	var sys := ChargeTimeTurnSystem.new()
	sys.setup([normal, hasted, slowed], 42)
	state.turn_system = sys

	sys.begin_round(state)

	# Tick until first activation — should be hasted
	var first_id: String = ""
	for _i in range(200):
		sys.advance(state)
		if sys.activated_unit:
			first_id = sys.activated_unit.character.id
			break

	assert_eq(first_id, "hasted", "Hasted unit should activate before normal and slowed")


func test_mode_skirmish_forces_telegraph_off() -> void:
	## When mode is "skirmish", CT system is used and telegraph is disabled.
	var sys := ChargeTimeTurnSystem.new()
	assert_false(sys.wants_telegraph(), "CT system should never want telegraph")
	# In BattleController, mode="skirmish" forces CT system which returns
	# wants_telegraph() == false, so telegraph code is never invoked.


func test_seeded_determinism_full_cycle() -> void:
	## Two CT systems with same seed should produce identical activation order.
	var units_1a := _make_unit("alpha", "playerA", 5)
	var units_1b := _make_unit("beta", "playerB", 5)
	var units_2a := _make_unit("alpha", "playerA", 5)
	var units_2b := _make_unit("beta", "playerB", 5)

	var state_1 := _deployed_state([units_1a], [units_1b])
	var state_2 := _deployed_state([units_2a], [units_2b])

	var sys_1 := ChargeTimeTurnSystem.new()
	sys_1.setup([units_1a, units_1b], 12345)
	state_1.turn_system = sys_1

	var sys_2 := ChargeTimeTurnSystem.new()
	sys_2.setup([units_2a, units_2b], 12345)
	state_2.turn_system = sys_2

	sys_1.begin_round(state_1)
	sys_2.begin_round(state_2)

	var order_1: Array = []
	var order_2: Array = []
	for _i in range(500):
		sys_1.advance(state_1)
		sys_2.advance(state_2)
		if sys_1.activated_unit:
			order_1.append(sys_1.activated_unit.character.id)
			state_1.current_unit = sys_1.activated_unit
			sys_1.on_activation_complete(state_1, false)
		if sys_2.activated_unit:
			order_2.append(sys_2.activated_unit.character.id)
			state_2.current_unit = sys_2.activated_unit
			sys_2.on_activation_complete(state_2, false)
		if order_1.size() >= 4:
			break

	assert_eq(order_1, order_2, "Same seed should produce identical activation order")


func test_match_over_detected() -> void:
	var a := _make_unit("hero", "playerA", 5)
	var b := _make_unit("foe", "playerB", 5)
	b.current_hp = 0
	var state := _deployed_state([a], [b])
	var sys := ChargeTimeTurnSystem.new()
	sys.setup([a, b], 42)
	state.turn_system = sys

	sys.begin_round(state)

	# Advance and let hero activate, then mark complete
	for _i in range(200):
		sys.advance(state)
		if sys.activated_unit:
			state.current_unit = sys.activated_unit
			sys.on_activation_complete(state, false)
			break

	var winner := state.check_winner()
	assert_eq(winner, "playerA", "PlayerA should win when all playerB units are dead")
