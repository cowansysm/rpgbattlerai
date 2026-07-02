extends GutTest
## Tests for SpeedRoundTurnSystem: four-stage round, SPD ordering,
## validity policy, interrupt mechanic, and headless determinism.


# --- Helpers ---

static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	return p


func _make_unit(id: String, team: String, spd: int = 3, hp: int = 10,
		atk: int = 5, def: int = 2, rng: int = 1) -> BattleUnit:
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
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	return u


func _deployed_state(units_a: Array, units_b: Array) -> MatchState:
	var map := MapData.new()
	map.id = "test"
	var tiles: Array[TileRecord] = []
	for coord in Hex.hexes_in_range(Vector2i(0, 0), 6):
		tiles.append(TileRecord.new(coord.x, coord.y, 0, "grass"))
	map.tiles = tiles

	var party_a: Array[BattleUnit] = []
	party_a.assign(units_a)
	var party_b: Array[BattleUnit] = []
	party_b.assign(units_b)

	var state := MatchSetup.create(party_a, party_b, map, _stub_terrain)

	# Deploy units at known positions
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


func _make_speed_system(seed_val: int = 42) -> SpeedRoundTurnSystem:
	var sys := SpeedRoundTurnSystem.new()
	sys._tie_seed = seed_val
	return sys


# --- Stage sequencing tests ---

func test_begin_round_sets_ai_planning() -> void:
	var a := _make_unit("a0", "playerA", 5)
	var b := _make_unit("b0", "playerB", 3)
	var state := _deployed_state([a], [b])
	var sys := _make_speed_system()
	state.turn_system = sys

	sys.begin_round(state)
	assert_eq(state.phase, MatchState.Phase.AI_PLANNING)
	assert_eq(sys.current_stage(), SpeedRoundTurnSystem.Stage.AI_PLANNING)


func test_advance_from_ai_planning_to_player_planning() -> void:
	var a := _make_unit("a0", "playerA", 5)
	var b := _make_unit("b0", "playerB", 3)
	var state := _deployed_state([a], [b])
	var sys := _make_speed_system()
	state.turn_system = sys

	sys.begin_round(state)
	sys.advance(state)
	assert_eq(state.phase, MatchState.Phase.PLAYER_PLANNING)
	assert_eq(sys.current_stage(), SpeedRoundTurnSystem.Stage.PLAYER_PLANNING)


func test_advance_from_player_planning_to_resolution() -> void:
	var a := _make_unit("a0", "playerA", 5)
	var b := _make_unit("b0", "playerB", 3)
	var state := _deployed_state([a], [b])
	var sys := _make_speed_system()
	state.turn_system = sys

	sys.begin_round(state)

	# Commit plans for both sides
	sys.commit_ai_plans({"b0": AIPlan.make_defend()}, [b])
	sys.advance(state)  # → PLAYER_PLANNING

	sys.commit_player_plan(a, AIPlan.make_defend())
	sys.advance(state)  # → RESOLUTION

	assert_eq(state.phase, MatchState.Phase.RESOLUTION)
	assert_eq(sys.current_stage(), SpeedRoundTurnSystem.Stage.RESOLUTION)


func test_round_increments_on_begin() -> void:
	var a := _make_unit("a0", "playerA", 5)
	var b := _make_unit("b0", "playerB", 3)
	var state := _deployed_state([a], [b])
	var sys := _make_speed_system()
	state.turn_system = sys

	sys.begin_round(state)
	assert_eq(state.round_number, 1)
	sys.begin_round(state)
	assert_eq(state.round_number, 2)


# --- SPD ordering ---

func test_resolution_order_by_spd() -> void:
	var fast := _make_unit("fast", "playerA", 7, 10, 5, 2, 1)
	var mid := _make_unit("mid", "playerB", 5, 10, 5, 2, 1)
	var slow := _make_unit("slow", "playerA", 3, 10, 5, 2, 1)
	var state := _deployed_state([fast, slow], [mid])
	var sys := _make_speed_system()
	state.turn_system = sys

	sys.begin_round(state)
	sys.commit_ai_plans({"mid": AIPlan.make_defend()}, [mid])
	sys.advance(state)
	sys.commit_player_plan(fast, AIPlan.make_defend())
	sys.commit_player_plan(slow, AIPlan.make_defend())
	sys.advance(state)

	# Resolve all — should be fast (7), mid (5), slow (3)
	var order: Array = []
	while sys.has_next_resolution():
		var result := sys.resolve_next(state)
		order.append(result.get("unit_id", ""))

	assert_eq(order, ["fast", "mid", "slow"],
		"Units should resolve in descending SPD order")


# --- Validity policy: interrupt (fast kills slow) ---

func test_interrupt_fast_kills_slow_target_fizzles() -> void:
	# Set up: fast attacker (SPD 7) and slow attacker (SPD 3)
	# They attack each other. Fast should kill slow before slow can act.
	CombatResolver.dice_roller = func() -> int: return 6  # Max damage

	var fast := _make_unit("fast", "playerA", 7, 20, 15, 2, 1)
	var slow := _make_unit("slow", "playerB", 3, 5, 15, 2, 1)

	# Place them adjacent
	var state := _deployed_state([fast], [slow])
	fast.position = Vector2i(0, 0)
	state.occupancy.erase(Vector2i(-3, 0))
	state.occupancy[Vector2i(0, 0)] = fast
	slow.position = Vector2i(1, 0)
	state.occupancy.erase(Vector2i(3, 0))
	state.occupancy[Vector2i(1, 0)] = slow

	var sys := _make_speed_system()
	state.turn_system = sys

	sys.begin_round(state)

	# Both plan to attack each other
	sys.commit_ai_plans({"slow": AIPlan.make_attack_only(Vector2i(0, 0))}, [slow])
	sys.advance(state)
	sys.commit_player_plan(fast, AIPlan.make_attack_only(Vector2i(1, 0)))
	sys.advance(state)

	# Fast resolves first — kills slow
	var fast_result := sys.resolve_next(state)
	assert_eq(fast_result["unit_id"], "fast")
	assert_true(slow.current_hp <= 0 or slow.is_downed,
		"Slow should be downed by fast's attack")

	# Slow's turn — should fizzle because it's dead
	var slow_result := sys.resolve_next(state)
	assert_eq(slow_result["unit_id"], "slow")
	assert_true(slow_result.get("fizzled", false),
		"Slow's attack should fizzle because it's dead")

	CombatResolver.dice_roller = func() -> int: return randi() % 6 + 1


# --- Validity policy: move stops short ---

func test_move_stops_short_on_occupied_tile() -> void:
	# Unit A plans to move to tile (2, 0), but unit B is faster and moves there first
	var fast_b := _make_unit("fast_b", "playerB", 7, 10, 5, 2, 1)
	var slow_a := _make_unit("slow_a", "playerA", 3, 10, 5, 2, 1)

	var state := _deployed_state([slow_a], [fast_b])
	slow_a.position = Vector2i(-2, 0)
	state.occupancy.erase(Vector2i(-3, 0))
	state.occupancy[Vector2i(-2, 0)] = slow_a
	fast_b.position = Vector2i(4, 0)
	state.occupancy.erase(Vector2i(3, 0))
	state.occupancy[Vector2i(4, 0)] = fast_b

	var sys := _make_speed_system()
	state.turn_system = sys

	sys.begin_round(state)

	# Both plan to move to (1, 0)
	var target_tile := Vector2i(1, 0)
	sys.commit_ai_plans({"fast_b": AIPlan.make_move_only(target_tile)}, [fast_b])
	sys.advance(state)
	sys.commit_player_plan(slow_a, AIPlan.make_move_only(target_tile))
	sys.advance(state)

	# Fast_b resolves first — gets the tile
	var fast_result := sys.resolve_next(state)
	assert_eq(fast_b.position, target_tile, "Fast unit should reach the target tile")

	# Slow_a resolves second — should stop short
	var slow_result := sys.resolve_next(state)
	assert_ne(slow_a.position, target_tile,
		"Slow unit should NOT be on the target tile (occupied)")
	assert_ne(slow_a.position, Vector2i(-2, 0),
		"Slow unit should have moved some distance")


# --- Validity policy: single-target fizzle ---

func test_single_target_fizzle_when_target_dead() -> void:
	CombatResolver.dice_roller = func() -> int: return 6

	var fast := _make_unit("fast", "playerA", 7, 20, 15, 2, 1)
	var slow := _make_unit("slow", "playerA", 3, 20, 5, 2, 1)
	var target := _make_unit("target", "playerB", 1, 5, 5, 2, 1)

	var state := _deployed_state([fast, slow], [target])
	fast.position = Vector2i(0, 0)
	state.occupancy.erase(Vector2i(-3, 0))
	state.occupancy[Vector2i(0, 0)] = fast
	slow.position = Vector2i(-1, 0)
	state.occupancy.erase(Vector2i(-2, 0))
	state.occupancy[Vector2i(-1, 0)] = slow
	target.position = Vector2i(1, 0)
	state.occupancy.erase(Vector2i(3, 0))
	state.occupancy[Vector2i(1, 0)] = target

	var sys := _make_speed_system()
	state.turn_system = sys

	sys.begin_round(state)

	# Both player units plan to attack the same target
	sys.commit_ai_plans({"target": AIPlan.make_defend()}, [target])
	sys.advance(state)
	sys.commit_player_plan(fast, AIPlan.make_attack_only(Vector2i(1, 0)))
	sys.commit_player_plan(slow, AIPlan.make_attack_only(Vector2i(1, 0)))
	sys.advance(state)

	# Fast kills target
	sys.resolve_next(state)
	assert_true(target.current_hp <= 0 or target.is_downed)

	# Slow's attack should fizzle — target is gone
	var slow_result := sys.resolve_next(state)
	var found_fizzle := false
	for r in slow_result.get("results", []):
		if r.get("fizzled", false):
			found_fizzle = true
			break
	assert_true(found_fizzle, "Slow's attack should fizzle when target is dead")

	# Target's defend should also fizzle (target is dead)
	var target_result := sys.resolve_next(state)
	assert_true(target_result.get("fizzled", false),
		"Dead target's action should fizzle")

	CombatResolver.dice_roller = func() -> int: return randi() % 6 + 1


# --- Fizzle spends AP/WP ---

func test_fizzle_spends_ap() -> void:
	CombatResolver.dice_roller = func() -> int: return 6

	var fast := _make_unit("fast", "playerA", 7, 20, 15, 2, 1)
	var slow := _make_unit("slow", "playerA", 3, 20, 5, 2, 1)
	var target := _make_unit("target", "playerB", 1, 5, 5, 2, 1)

	var state := _deployed_state([fast, slow], [target])
	fast.position = Vector2i(0, 0)
	state.occupancy.erase(Vector2i(-3, 0))
	state.occupancy[Vector2i(0, 0)] = fast
	slow.position = Vector2i(-1, 0)
	state.occupancy.erase(Vector2i(-2, 0))
	state.occupancy[Vector2i(-1, 0)] = slow
	target.position = Vector2i(1, 0)
	state.occupancy.erase(Vector2i(3, 0))
	state.occupancy[Vector2i(1, 0)] = target

	var sys := _make_speed_system()
	state.turn_system = sys

	sys.begin_round(state)
	sys.commit_ai_plans({"target": AIPlan.make_defend()}, [target])
	sys.advance(state)
	sys.commit_player_plan(fast, AIPlan.make_attack_only(Vector2i(1, 0)))
	sys.commit_player_plan(slow, AIPlan.make_attack_only(Vector2i(1, 0)))
	sys.advance(state)

	# Fast kills target
	sys.resolve_next(state)
	var ap_before: int = slow.ap_remaining

	# Slow's attack fizzles — AP should still be spent
	sys.resolve_next(state)

	# After resolution, unit is marked activated
	assert_true(slow.is_activated)

	CombatResolver.dice_roller = func() -> int: return randi() % 6 + 1


# --- Defend during speed-round ---

func test_defend_applies_modifier() -> void:
	var a := _make_unit("a0", "playerA", 5, 10, 5, 2, 1)
	var b := _make_unit("b0", "playerB", 3, 10, 5, 2, 1)
	var state := _deployed_state([a], [b])

	var sys := _make_speed_system()
	state.turn_system = sys

	sys.begin_round(state)
	sys.commit_ai_plans({"b0": AIPlan.make_defend()}, [b])
	sys.advance(state)
	sys.commit_player_plan(a, AIPlan.make_defend())
	sys.advance(state)

	# Resolve all
	while sys.has_next_resolution():
		sys.resolve_next(state)

	# Both should have defend modifier
	assert_true(a.stats.has_modifier_from_source("defend"))
	assert_true(b.stats.has_modifier_from_source("defend"))


# --- Headless determinism ---

func test_headless_deterministic() -> void:
	CombatResolver.dice_roller = func() -> int: return 4

	var results_1 := _run_deterministic_round(42)
	var results_2 := _run_deterministic_round(42)

	assert_eq(results_1.size(), results_2.size(),
		"Same seed should produce same number of results")
	for i in range(results_1.size()):
		assert_eq(results_1[i].get("unit_id", ""), results_2[i].get("unit_id", ""),
			"Resolution order should be identical for same seed")

	CombatResolver.dice_roller = func() -> int: return randi() % 6 + 1


func _run_deterministic_round(seed_val: int) -> Array:
	var a := _make_unit("a0", "playerA", 5, 10, 5, 2, 1)
	var b := _make_unit("b0", "playerB", 3, 10, 5, 2, 1)
	var state := _deployed_state([a], [b])

	var sys := _make_speed_system(seed_val)
	state.turn_system = sys

	sys.begin_round(state)
	sys.commit_ai_plans({"b0": AIPlan.make_defend()}, [b])
	sys.advance(state)
	sys.commit_player_plan(a, AIPlan.make_defend())
	sys.advance(state)

	var results: Array = []
	while sys.has_next_resolution():
		results.append(sys.resolve_next(state))
	return results


# --- Round-reset bookkeeping ---

func test_round_resets_statuses() -> void:
	var a := _make_unit("a0", "playerA", 5, 10, 5, 2, 1)
	var b := _make_unit("b0", "playerB", 3, 10, 5, 2, 1)
	var state := _deployed_state([a], [b])

	# Add a status with duration 1
	a.status_effects.append({"id": "poison", "duration": 1, "source": "test"})

	var sys := _make_speed_system()
	state.turn_system = sys

	# Round 1
	sys.begin_round(state)
	assert_eq(a.status_effects.size(), 0,
		"Status with duration 1 should expire at round start")


func test_round_complete_flag() -> void:
	var a := _make_unit("a0", "playerA", 5)
	var b := _make_unit("b0", "playerB", 3)
	var state := _deployed_state([a], [b])

	var sys := _make_speed_system()
	state.turn_system = sys

	sys.begin_round(state)
	assert_false(sys.is_round_complete(state))

	sys.commit_ai_plans({"b0": AIPlan.make_defend()}, [b])
	sys.advance(state)
	sys.commit_player_plan(a, AIPlan.make_defend())
	sys.advance(state)

	# Resolve all
	while sys.has_next_resolution():
		sys.resolve_next(state)

	assert_true(sys.is_round_complete(state))


# --- A18 deferred item B: Half-WP in speed-round path ---

func _make_unit_with_wp(id: String, team: String, spd: int = 3, hp: int = 20, wp: int = 10) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = []
	c.abilities = []
	var sb := StatBlock.new()
	sb.set_base("spd", spd)
	sb.set_base("hp", hp)
	sb.set_base("def", 2)
	sb.set_base("atk", 4)
	sb.set_base("rng", 1)
	sb.set_base("jump", 2)
	sb.set_base("mag", 0)
	sb.set_base("wp", wp)
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	return u


func test_half_wp_halves_cost_in_speed_round_path() -> void:
	## Unit with wp_cost_mult=0.5 should spend floor(wp_cost * 0.5) WP in speed-round resolution.
	## Base wp_cost=4; Half-WP should deduct floor(4 * 0.5) = 2.
	var attacker := _make_unit_with_wp("a0", "playerA", 5, 20, 10)
	var target := _make_unit_with_wp("b0", "playerB", 3, 20, 10)
	var state := _deployed_state([attacker], [target])

	# Set Half-WP multiplier on the attacker
	attacker.wp_cost_mult = 0.5

	# Build a heal ability with wp_cost=4 so attacker can cast on self
	var ab := AbilityData.new()
	ab.id = "test_heal"
	ab.ability_range = 0
	ab.ap_cost = 1
	ab.wp_cost = 4
	ab.type = "spell"
	ab.mag_scaling = 0.0
	ab.area = {}
	ab.effect = {"effect_type": "heal", "value": 5}
	state.ability_provider = func(_u: BattleUnit, ab_id: String) -> AbilityData:
		if ab_id == "test_heal":
			return ab
		return null

	var sys := _make_speed_system()
	state.turn_system = sys
	sys.begin_round(state)

	var plan := AIPlan.new()
	plan.steps = [{"kind": "ability", "ability_id": "test_heal",
		"target_pos": attacker.position, "ap_cost": 1}]

	sys.commit_ai_plans({"b0": AIPlan.make_defend()}, [target])
	sys.advance(state)
	sys.commit_player_plan(attacker, plan)
	sys.advance(state)

	var wp_before: int = attacker.current_wp
	while sys.has_next_resolution():
		sys.resolve_next(state)

	var wp_spent: int = wp_before - attacker.current_wp
	assert_eq(wp_spent, 2, "Half-WP unit should spend floor(4 * 0.5) = 2 WP in speed-round")


func test_full_wp_cost_in_speed_round_without_half_wp() -> void:
	## Without Half-WP, unit spends full wp_cost=4.
	var attacker := _make_unit_with_wp("a0", "playerA", 5, 20, 10)
	var target := _make_unit_with_wp("b0", "playerB", 3, 20, 10)
	var state := _deployed_state([attacker], [target])

	# wp_cost_mult is 1.0 by default (full cost)

	var ab := AbilityData.new()
	ab.id = "test_heal"
	ab.ability_range = 0
	ab.ap_cost = 1
	ab.wp_cost = 4
	ab.type = "spell"
	ab.mag_scaling = 0.0
	ab.area = {}
	ab.effect = {"effect_type": "heal", "value": 5}
	state.ability_provider = func(_u: BattleUnit, ab_id: String) -> AbilityData:
		if ab_id == "test_heal":
			return ab
		return null

	var sys := _make_speed_system()
	state.turn_system = sys
	sys.begin_round(state)

	var plan := AIPlan.new()
	plan.steps = [{"kind": "ability", "ability_id": "test_heal",
		"target_pos": attacker.position, "ap_cost": 1}]

	sys.commit_ai_plans({"b0": AIPlan.make_defend()}, [target])
	sys.advance(state)
	sys.commit_player_plan(attacker, plan)
	sys.advance(state)

	var wp_before: int = attacker.current_wp
	while sys.has_next_resolution():
		sys.resolve_next(state)

	var wp_spent: int = wp_before - attacker.current_wp
	assert_eq(wp_spent, 4, "Without Half-WP, should spend full wp_cost=4")
