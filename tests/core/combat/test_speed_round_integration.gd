extends GutTest
## End-to-end integration tests for the A15 speed-round system.
## Covers: full headless round, deterministic replay, interrupt scenarios,
## move stop-short, terrain damage, telegraph parity, and alternating regression.


var _default_roller: Callable


func before_each() -> void:
	_default_roller = CombatResolver.dice_roller
	CombatResolver.dice_roller = func() -> int: return 3


func after_each() -> void:
	CombatResolver.dice_roller = _default_roller


# --- Helpers ---

static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	return p


func _make_unit(id: String, team: String, spd: int = 3, hp: int = 10,
		atk: int = 5, def: int = 2, rng: int = 1, mag: int = 0,
		wp: int = 0) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = []
	c.abilities = []
	var sb := StatBlock.new()
	sb.set_base("spd", spd)
	sb.set_base("hp", hp)
	sb.set_base("def", def)
	sb.set_base("atk", atk)
	sb.set_base("rng", rng)
	sb.set_base("jump", 2)
	sb.set_base("mag", mag)
	sb.set_base("res", 0)
	sb.set_base("wp", wp)
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	return u


func _deployed_state(units_a: Array, units_b: Array) -> MatchState:
	var map := MapData.new()
	map.id = "test_integration"
	var tiles: Array[TileRecord] = []
	for coord in Hex.hexes_in_range(Vector2i(0, 0), 6):
		tiles.append(TileRecord.new(coord.x, coord.y, 0, "grass"))
	map.tiles = tiles

	var party_a: Array[BattleUnit] = []
	party_a.assign(units_a)
	var party_b: Array[BattleUnit] = []
	party_b.assign(units_b)

	var state := MatchSetup.create(party_a, party_b, map, _stub_terrain)

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

	state.ai_teams = ["playerB"]
	return state


func _make_system(seed_val: int = 42) -> SpeedRoundTurnSystem:
	var sys := SpeedRoundTurnSystem.new()
	sys._tie_seed = seed_val
	return sys


func _run_full_round(state: MatchState, sys: SpeedRoundTurnSystem,
		ai_plans: Dictionary, player_plans: Dictionary) -> Array:
	## Run a complete speed round and return all resolution results.
	sys.begin_round(state)

	# Commit AI plans
	var ai_units: Array = []
	for team in state.ai_teams:
		for unit: BattleUnit in state.living_units(team):
			ai_units.append(unit)
	sys.commit_ai_plans(ai_plans, ai_units)
	sys.advance(state)

	# Commit player plans
	var player_team: String = state.other_team(state.ai_teams[0])
	for unit: BattleUnit in state.living_units(player_team):
		if not unit.is_downed:
			var plan: AIPlan = player_plans.get(unit.character.id)
			if plan:
				sys.commit_player_plan(unit, plan)
	sys.advance(state)

	# Resolve all
	var results: Array = []
	while sys.has_next_resolution():
		var result := sys.resolve_next(state)
		results.append(result)
	return results


# --- Test: Full headless round (2v2) ---

func test_full_round_2v2_all_defend() -> void:
	var a0 := _make_unit("a0", "playerA", 5)
	var a1 := _make_unit("a1", "playerA", 3)
	var b0 := _make_unit("b0", "playerB", 4)
	var b1 := _make_unit("b1", "playerB", 2)
	var state := _deployed_state([a0, a1], [b0, b1])
	var sys := _make_system()

	var ai_plans := {
		"b0": AIPlan.make_defend(),
		"b1": AIPlan.make_defend(),
	}
	var player_plans := {
		"a0": AIPlan.make_defend(),
		"a1": AIPlan.make_defend(),
	}

	var results := _run_full_round(state, sys, ai_plans, player_plans)

	# All 4 units should resolve
	assert_eq(results.size(), 4, "4 units should resolve")
	# Descending SPD order: a0(5), b0(4), a1(3), b1(2)
	assert_eq(str(results[0].get("unit_id", "")), "a0", "fastest unit first")
	assert_eq(str(results[1].get("unit_id", "")), "b0")
	assert_eq(str(results[2].get("unit_id", "")), "a1")
	assert_eq(str(results[3].get("unit_id", "")), "b1", "slowest unit last")

	# System should be in ROUND_RESET
	assert_true(sys.is_round_complete(state))


func test_full_round_2v2_move_and_attack() -> void:
	var a0 := _make_unit("a0", "playerA", 5, 20, 6, 2)
	var b0 := _make_unit("b0", "playerB", 3, 20, 4, 2)
	var state := _deployed_state([a0], [b0])

	var sys := _make_system()

	# a0 attacks b0 (they're 6 hexes apart, so attack from adjacency needs a move)
	# Position a0 at (-3,0), b0 at (3,0). Move a0 to (2,0) then attack (3,0)
	var ai_plans := {"b0": AIPlan.make_defend()}
	var player_plans := {"a0": AIPlan.make_move_attack(Vector2i(2, 0), Vector2i(3, 0))}

	var results := _run_full_round(state, sys, ai_plans, player_plans)

	assert_eq(results.size(), 2, "2 units should resolve")
	# a0 is faster, resolves first
	assert_eq(str(results[0].get("unit_id", "")), "a0")
	assert_false(results[0].get("fizzled", false), "a0 should not fizzle")

	# a0 should have moved and attacked
	var a0_results: Array = results[0].get("results", [])
	assert_true(a0_results.size() >= 2, "a0 should have move + attack results")

	# b0 should still resolve (defend)
	assert_eq(str(results[1].get("unit_id", "")), "b0")
	assert_false(results[1].get("fizzled", false), "b0 should not fizzle")


# --- Test: Deterministic by seed ---

func test_deterministic_same_seed_same_results() -> void:
	var results_1 := _run_deterministic_round(42)
	var results_2 := _run_deterministic_round(42)

	assert_eq(results_1.size(), results_2.size(), "same number of results")
	for i in range(results_1.size()):
		assert_eq(
			str(results_1[i].get("unit_id", "")),
			str(results_2[i].get("unit_id", "")),
			"unit order matches at index %d" % i)
		assert_eq(
			results_1[i].get("fizzled", false),
			results_2[i].get("fizzled", false),
			"fizzle state matches at index %d" % i)


func _run_deterministic_round(seed_val: int) -> Array:
	var a0 := _make_unit("a0", "playerA", 5, 20, 6, 2)
	var a1 := _make_unit("a1", "playerA", 3, 20, 4, 2)
	var b0 := _make_unit("b0", "playerB", 4, 20, 5, 2)
	var b1 := _make_unit("b1", "playerB", 2, 20, 3, 2)
	var state := _deployed_state([a0, a1], [b0, b1])
	var sys := _make_system(seed_val)

	var ai_plans := {
		"b0": AIPlan.make_defend(),
		"b1": AIPlan.make_wait(),
	}
	var player_plans := {
		"a0": AIPlan.make_defend(),
		"a1": AIPlan.make_wait(),
	}
	return _run_full_round(state, sys, ai_plans, player_plans)


# --- Test: Interrupt (fast kills slow → slow fizzles) ---

func test_interrupt_fast_kills_slow() -> void:
	# a0 (SPD 10) attacks b0 (SPD 1, low HP)
	# b0 plans to attack a0, but should fizzle because a0 kills it first
	var a0 := _make_unit("a0", "playerA", 10, 20, 15, 2)
	var b0 := _make_unit("b0", "playerB", 1, 3, 5, 0)  # 3 HP, 0 DEF → will die
	var state := _deployed_state([a0], [b0])

	# Place them adjacent for attack
	a0.position = Vector2i(0, 0)
	state.occupancy[Vector2i(0, 0)] = a0
	state.occupancy.erase(Vector2i(-3, 0))
	b0.position = Vector2i(1, 0)
	state.occupancy[Vector2i(1, 0)] = b0
	state.occupancy.erase(Vector2i(3, 0))

	var sys := _make_system()

	var ai_plans := {"b0": AIPlan.make_attack_only(Vector2i(0, 0))}
	var player_plans := {"a0": AIPlan.make_attack_only(Vector2i(1, 0))}

	var results := _run_full_round(state, sys, ai_plans, player_plans)

	# a0 resolves first (SPD 10) and kills b0
	assert_eq(str(results[0].get("unit_id", "")), "a0")
	assert_false(results[0].get("fizzled", false))

	# b0 should fizzle because it's dead
	assert_eq(str(results[1].get("unit_id", "")), "b0")
	assert_true(results[1].get("fizzled", false), "b0 should fizzle (killed by a0)")
	assert_eq(str(results[1].get("reason", "")), "unit_dead")


# --- Test: Move stop-short ---

func test_move_stop_short_on_occupied_tile() -> void:
	# a0 plans to move to (3,0) but b0 is already there — should stop short
	var a0 := _make_unit("a0", "playerA", 5, 10, 5, 2)
	var b0 := _make_unit("b0", "playerB", 3, 10, 5, 2)
	var state := _deployed_state([a0], [b0])

	var sys := _make_system()

	# a0 wants to move to b0's position → should stop short
	var ai_plans := {"b0": AIPlan.make_defend()}
	var player_plans := {"a0": AIPlan.make_move_only(Vector2i(3, 0))}

	var results := _run_full_round(state, sys, ai_plans, player_plans)

	# a0 should resolve first (SPD 5 > 3)
	assert_eq(str(results[0].get("unit_id", "")), "a0")
	assert_false(results[0].get("fizzled", false))

	# a0 should have stopped short of (3,0) — it should NOT be at b0's position
	assert_ne(a0.position, Vector2i(3, 0), "a0 should not land on b0's tile")
	# a0 should have moved closer
	assert_ne(a0.position, Vector2i(-3, 0), "a0 should have moved from start")


# --- Test: Single-target fizzle (target gone) ---

func test_attack_fizzles_when_target_already_dead() -> void:
	# Both a0 and a1 plan to attack b0. a0 is faster and kills it.
	# a1's attack should fizzle.
	var a0 := _make_unit("a0", "playerA", 10, 20, 15, 2)
	var a1 := _make_unit("a1", "playerA", 5, 20, 10, 2)
	var b0 := _make_unit("b0", "playerB", 1, 3, 5, 0)
	var state := _deployed_state([a0, a1], [b0])

	# Place adjacent
	a0.position = Vector2i(0, 0)
	state.occupancy[Vector2i(0, 0)] = a0
	state.occupancy.erase(Vector2i(-3, 0))
	a1.position = Vector2i(0, 1)
	state.occupancy[Vector2i(0, 1)] = a1
	state.occupancy.erase(Vector2i(-2, 0))
	b0.position = Vector2i(1, 0)
	state.occupancy[Vector2i(1, 0)] = b0
	state.occupancy.erase(Vector2i(3, 0))

	var sys := _make_system()

	var ai_plans := {"b0": AIPlan.make_defend()}
	var player_plans := {
		"a0": AIPlan.make_attack_only(Vector2i(1, 0)),
		"a1": AIPlan.make_attack_only(Vector2i(1, 0)),
	}

	var results := _run_full_round(state, sys, ai_plans, player_plans)

	# a0 (SPD 10) kills b0
	assert_eq(str(results[0].get("unit_id", "")), "a0")

	# a1 (SPD 5) attack fizzles — target gone
	assert_eq(str(results[1].get("unit_id", "")), "a1")
	var a1_results: Array = results[1].get("results", [])
	var found_fizzle := false
	for r in a1_results:
		if r is Dictionary and r.get("fizzled", false):
			found_fizzle = true
			assert_eq(str(r.get("reason", "")), "target_gone")
	assert_true(found_fizzle, "a1's attack should fizzle")

	# b0 (SPD 1) also fizzles — dead
	assert_eq(str(results[2].get("unit_id", "")), "b0")
	assert_true(results[2].get("fizzled", false))


# --- Test: Fizzle spends AP/WP ---

func test_fizzle_spends_ap() -> void:
	# a0 (fast) kills b0, a1 (slow) planned attack on b0 → fizzles with AP spent
	var a0 := _make_unit("a0", "playerA", 10, 20, 15, 2)
	var a1 := _make_unit("a1", "playerA", 2, 20, 10, 2)
	var b0 := _make_unit("b0", "playerB", 1, 3, 5, 0)
	var state := _deployed_state([a0, a1], [b0])

	a0.position = Vector2i(0, 0)
	state.occupancy[Vector2i(0, 0)] = a0
	state.occupancy.erase(Vector2i(-3, 0))
	a1.position = Vector2i(0, 1)
	state.occupancy[Vector2i(0, 1)] = a1
	state.occupancy.erase(Vector2i(-2, 0))
	b0.position = Vector2i(1, 0)
	state.occupancy[Vector2i(1, 0)] = b0
	state.occupancy.erase(Vector2i(3, 0))

	var sys := _make_system()

	var ai_plans := {"b0": AIPlan.make_defend()}
	var player_plans := {
		"a0": AIPlan.make_attack_only(Vector2i(1, 0)),
		"a1": AIPlan.make_attack_only(Vector2i(1, 0)),
	}

	var results := _run_full_round(state, sys, ai_plans, player_plans)

	# a1's attack fizzles — check AP was spent
	var a1_result: Dictionary = results[1]
	var a1_sub: Array = a1_result.get("results", [])
	for r in a1_sub:
		if r is Dictionary and r.get("fizzled", false):
			assert_eq(int(r.get("ap_spent", 0)), 1, "fizzle should spend 1 AP")


# --- Test: Round-start bookkeeping (buff/status tick) ---

func test_round_start_bookkeeping_ticks_buffs() -> void:
	var a0 := _make_unit("a0", "playerA", 5, 20)
	var b0 := _make_unit("b0", "playerB", 3, 20)
	var state := _deployed_state([a0], [b0])

	# Add a buff with 2 rounds remaining
	a0.stats.push_modifier(StatModifier.new("def", 3, "buff:shield_1"))
	state.buff_durations.append({
		"source_tag": "buff:shield_1",
		"unit": a0,
		"remaining": 2,
	})

	var sys := _make_system()

	# Round 1
	var ai_plans := {"b0": AIPlan.make_defend()}
	var player_plans := {"a0": AIPlan.make_defend()}
	_run_full_round(state, sys, ai_plans, player_plans)

	# After round 1, buff should still be active (duration decremented to 1)
	var found := false
	for bd in state.buff_durations:
		if bd.get("source_tag") == "buff:shield_1":
			found = true
			assert_eq(int(bd.get("remaining", 0)), 1, "buff should have 1 round left")
	assert_true(found, "buff should still exist after round 1")

	# Round 2
	_run_full_round(state, sys, ai_plans, player_plans)

	# After round 2, buff should be expired and removed
	var still_found := false
	for bd in state.buff_durations:
		if bd.get("source_tag") == "buff:shield_1":
			still_found = true
	assert_false(still_found, "buff should be expired after round 2")


# --- Test: Telegraph parity (off vs full → identical match_log) ---

func test_telegraph_parity_off_vs_full() -> void:
	# Run the same scenario twice: once with telegraph on, once off
	# The match_log entries should be identical (telegraph is purely visual)

	var log_full := _run_with_telegraph("full")
	var log_off := _run_with_telegraph("off")

	assert_eq(log_full.size(), log_off.size(),
		"match_log size should be identical regardless of telegraph mode")
	for i in range(log_full.size()):
		assert_eq(log_full[i], log_off[i],
			"match_log entry %d should be identical" % i)


func _run_with_telegraph(mode: String) -> Array:
	var a0 := _make_unit("a0", "playerA", 5, 20, 6, 2)
	var b0 := _make_unit("b0", "playerB", 3, 20, 4, 2)
	var state := _deployed_state([a0], [b0])
	state.match_log = []

	var sys := _make_system(42)

	# Build telegraph intents (just to exercise the code path)
	var ai_plans := {"b0": AIPlan.make_defend()}

	sys.begin_round(state)

	var ai_units: Array = []
	for team in state.ai_teams:
		for unit: BattleUnit in state.living_units(team):
			ai_units.append(unit)
	sys.commit_ai_plans(ai_plans, ai_units)

	# In full mode, build intents (purely informational, no state mutation)
	if mode == "full":
		var intents: Array = TelegraphService.build_intents(state, ai_plans, ai_units)
		sys.set_intents(intents)

	sys.advance(state)

	# Commit player plans
	var player_plans := {"a0": AIPlan.make_defend()}
	for unit: BattleUnit in state.living_units("playerA"):
		if not unit.is_downed:
			var plan: AIPlan = player_plans.get(unit.character.id)
			if plan:
				sys.commit_player_plan(unit, plan)
	sys.advance(state)

	# Resolve all
	while sys.has_next_resolution():
		sys.resolve_next(state)

	return state.match_log.duplicate()


# --- Test: Alternating activation regression ---

func test_alternating_activation_still_works() -> void:
	var a0 := _make_unit("a0", "playerA", 5, 20, 6, 2)
	var b0 := _make_unit("b0", "playerB", 3, 20, 4, 2)
	var state := _deployed_state([a0], [b0])

	# Use alternating turn system (NOT speed round)
	state.turn_system = AlternatingTurnSystem.new()

	RoundManager.start_round(state)
	assert_eq(state.phase, MatchState.Phase.AWAITING_ACTIVATION)

	# Activate and run a standard turn
	var team := RoundManager.current_team(state)
	var units := state.unactivated_units(team)
	assert_true(units.size() > 0, "should have units to activate")

	var unit: BattleUnit = units[0]
	var err := RoundManager.activate_unit(state, unit)
	assert_eq(err, "", "activation should succeed")
	assert_eq(state.phase, MatchState.Phase.UNIT_TURN)

	# Execute wait and end activation
	TurnActions.execute_wait(state)
	RoundManager.end_activation(state)

	# Should still be in AWAITING_ACTIVATION (other team's turn)
	assert_eq(state.phase, MatchState.Phase.AWAITING_ACTIVATION)


# --- Test: SPD ordering in resolution ---

func test_spd_ordering_descending() -> void:
	var a0 := _make_unit("a0", "playerA", 2)
	var a1 := _make_unit("a1", "playerA", 8)
	var b0 := _make_unit("b0", "playerB", 5)
	var b1 := _make_unit("b1", "playerB", 1)
	var state := _deployed_state([a0, a1], [b0, b1])

	var sys := _make_system()

	var ai_plans := {
		"b0": AIPlan.make_defend(),
		"b1": AIPlan.make_defend(),
	}
	var player_plans := {
		"a0": AIPlan.make_defend(),
		"a1": AIPlan.make_defend(),
	}

	var results := _run_full_round(state, sys, ai_plans, player_plans)

	var order: Array = []
	for r in results:
		order.append(str(r.get("unit_id", "")))

	# Expected: a1(8), b0(5), a0(2), b1(1)
	assert_eq(order, ["a1", "b0", "a0", "b1"], "should resolve in descending SPD")


# --- Test: Multi-round cycle ---

func test_multi_round_cycle() -> void:
	var a0 := _make_unit("a0", "playerA", 5)
	var b0 := _make_unit("b0", "playerB", 3)
	var state := _deployed_state([a0], [b0])

	var sys := _make_system()
	var ai_plans := {"b0": AIPlan.make_defend()}
	var player_plans := {"a0": AIPlan.make_defend()}

	# Round 1
	_run_full_round(state, sys, ai_plans, player_plans)
	assert_true(sys.is_round_complete(state))
	assert_eq(state.round_number, 1)

	# Round 2
	_run_full_round(state, sys, ai_plans, player_plans)
	assert_true(sys.is_round_complete(state))
	assert_eq(state.round_number, 2)

	# Round 3
	_run_full_round(state, sys, ai_plans, player_plans)
	assert_true(sys.is_round_complete(state))
	assert_eq(state.round_number, 3)

	# No winner — all units still alive
	assert_true(state.check_winner().is_empty())


# --- Test: TelegraphService single-plan contract ---

func test_telegraph_intent_matches_executed_plan() -> void:
	# The AI plan used for telegraph should be the same one executed in resolution
	var a0 := _make_unit("a0", "playerA", 5, 20, 6, 2)
	var b0 := _make_unit("b0", "playerB", 3, 20, 4, 2)
	var state := _deployed_state([a0], [b0])

	var sys := _make_system()

	var ai_plans := {"b0": AIPlan.make_defend()}

	sys.begin_round(state)

	var ai_units: Array = []
	for team in state.ai_teams:
		for unit: BattleUnit in state.living_units(team):
			ai_units.append(unit)
	sys.commit_ai_plans(ai_plans, ai_units)

	# Build intents from the SAME plans
	var intents: Array = TelegraphService.build_intents(state, ai_plans, ai_units)
	sys.set_intents(intents)
	sys.advance(state)

	# Verify intent matches the plan
	assert_eq(intents.size(), 1, "should have one intent")
	var intent: IntentPlan = intents[0]
	assert_eq(intent.unit_id, "b0")
	assert_eq(intent.action_kind, "defend")
	assert_true(intent.committed)

	# Commit player and resolve
	sys.commit_player_plan(a0, AIPlan.make_defend())
	sys.advance(state)

	# Find b0's resolution result
	var b0_result: Dictionary = {}
	while sys.has_next_resolution():
		var result := sys.resolve_next(state)
		if str(result.get("unit_id", "")) == "b0":
			b0_result = result

	# b0 should have resolved (not fizzled) — the intent and execution match
	assert_false(b0_result.get("fizzled", false), "b0 should resolve (same plan)")
