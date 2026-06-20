extends GutTest
## Tests for AIPlanner: enumeration legality, scorer sanity, determinism/variance.
## Uses a small hex grid with manually constructed units and real ability data
## (loaded by GameData autoload).

var _default_roller: Callable


func before_each() -> void:
	_default_roller = CombatResolver.dice_roller
	CombatResolver.dice_roller = func() -> int: return 3


func after_each() -> void:
	CombatResolver.dice_roller = _default_roller


# --- Stub terrain provider ---

static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	p.impassable = (id == "rocks")
	if id == "cover_tile":
		p.cover = 2
	if id == "lava":
		p.damage_per_turn = 5
	return p


# --- Helpers ---

func _make_unit(id: String, team: String, pos: Vector2i,
		atk: int = 2, def_val: int = 1, hp: int = 20, rng_val: int = 1,
		spd: int = 3, mag: int = 0, res: int = 0, wp: int = 0,
		classes: Array[String] = [], equipment: Array[String] = [],
		abilities: Array[String] = []) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.race = "human"
	c.classes = classes
	c.equipment = equipment
	c.abilities = abilities
	var sb := StatBlock.new()
	sb.set_base("spd", spd)
	sb.set_base("hp", hp)
	sb.set_base("atk", atk)
	sb.set_base("def", def_val)
	sb.set_base("rng", rng_val)
	sb.set_base("mag", mag)
	sb.set_base("res", res)
	sb.set_base("wp", wp)
	sb.set_base("jump", 2)
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	u.position = pos
	return u


func _flat_graph(radius: int, elev: int = 0, terrain: String = "grass") -> HexGraph:
	var map := MapData.new()
	map.id = "test"
	var tiles: Array[TileRecord] = []
	for coord in Hex.hexes_in_range(Vector2i(0, 0), radius):
		tiles.append(TileRecord.new(coord.x, coord.y, elev, terrain))
	map.tiles = tiles
	var g := HexGraph.new()
	g.build(map, _stub_terrain)
	return g


func _custom_graph(tile_defs: Array) -> HexGraph:
	var map := MapData.new()
	map.id = "test_custom"
	var tiles: Array[TileRecord] = []
	for def_entry in tile_defs:
		tiles.append(TileRecord.new(int(def_entry[0]), int(def_entry[1]), int(def_entry[2]), str(def_entry[3])))
	map.tiles = tiles
	var g := HexGraph.new()
	g.build(map, _stub_terrain)
	return g


func _make_state(graph: HexGraph, units_a: Array, units_b: Array) -> MatchState:
	var state := MatchState.new()
	state.graph = graph
	state.parties = {"playerA": units_a, "playerB": units_b}
	state.initiative = "playerA"
	state.phase = MatchState.Phase.UNIT_TURN

	for u: BattleUnit in units_a:
		state.occupancy[u.position] = u
	for u: BattleUnit in units_b:
		state.occupancy[u.position] = u

	var resolver := AbilityResolver.new(
		GameData.get_ability, GameData.get_job_class, GameData.get_item)
	state.ability_provider = resolver.resolve
	state.item_provider = GameData.get_item

	return state


func _fixed_rng(seed_val: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return rng


func _hard() -> Dictionary:
	return AIPlanner.difficulty_preset("hard")


func _normal() -> Dictionary:
	return AIPlanner.difficulty_preset("normal")


# --- Enumeration tests ---

func test_enumeration_always_has_fallback() -> void:
	var graph := _flat_graph(3)
	var unit_a := _make_unit("a", "playerA", Vector2i(0, 0))
	var unit_b := _make_unit("b", "playerB", Vector2i(3, 0))
	var state := _make_state(graph, [unit_a], [unit_b])
	state.current_unit = unit_a
	unit_a.ap_remaining = 2

	var plans := AIPlanner.enumerate(state, unit_a, 12)
	assert_true(plans.size() >= 2, "Should have at least defend + wait")

	var has_defend := false
	var has_wait := false
	for plan in plans:
		if plan is AIPlan:
			if plan.steps.size() == 1:
				if plan.steps[0]["kind"] == "defend":
					has_defend = true
				if plan.steps[0]["kind"] == "wait":
					has_wait = true
	assert_true(has_defend, "Should always have a defend fallback")
	assert_true(has_wait, "Should always have a wait fallback")


func test_enumeration_includes_attack_plans() -> void:
	var graph := _flat_graph(2)
	var unit_a := _make_unit("a", "playerA", Vector2i(0, 0), 2, 1, 20, 1)
	var unit_b := _make_unit("b", "playerB", Vector2i(1, 0), 2, 1, 20, 1)
	var state := _make_state(graph, [unit_a], [unit_b])
	state.current_unit = unit_a
	unit_a.ap_remaining = 2

	var plans := AIPlanner.enumerate(state, unit_a, 12)
	var has_attack := false
	for plan in plans:
		if plan is AIPlan:
			for step in plan.steps:
				if step["kind"] == "attack":
					has_attack = true
					break
	assert_true(has_attack, "Should enumerate attack plans when enemy is adjacent")


func test_enumeration_includes_ability_plans() -> void:
	## A soldier with power_strike should have ability plans.
	var graph := _flat_graph(2)
	var unit_a := _make_unit("a", "playerA", Vector2i(0, 0), 2, 1, 20, 1, 3, 0, 0, 5,
		["soldier"] as Array[String])
	var unit_b := _make_unit("b", "playerB", Vector2i(1, 0), 2, 1, 20, 1)
	var state := _make_state(graph, [unit_a], [unit_b])
	state.current_unit = unit_a
	unit_a.ap_remaining = 2

	var plans := AIPlanner.enumerate(state, unit_a, 12)
	var has_ability := false
	for plan in plans:
		if plan is AIPlan:
			for step in plan.steps:
				if step["kind"] == "ability":
					has_ability = true
					break
	assert_true(has_ability, "Soldier should have ability plans (power_strike)")


func test_enumeration_respects_min_range() -> void:
	## Ranged units (rng > 1) cannot attack adjacent targets from current position.
	var graph := _flat_graph(3)
	var archer := _make_unit("archer", "playerA", Vector2i(0, 0), 2, 1, 20, 3)
	var enemy := _make_unit("enemy", "playerB", Vector2i(1, 0))
	var state := _make_state(graph, [archer], [enemy])
	state.current_unit = archer
	archer.ap_remaining = 2

	var plans := AIPlanner.enumerate(state, archer, 12)
	var violations := 0
	for plan in plans:
		if plan is AIPlan:
			# Check "stay and attack" plans (single attack step, no move)
			if plan.steps.size() == 1 and plan.steps[0]["kind"] == "attack":
				if plan.steps[0]["target_pos"] == Vector2i(1, 0):
					violations += 1
	assert_eq(violations, 0, "Ranged unit should not attack adjacent hex from current position")


# --- Scorer sanity tests ---

func test_prefers_kill_over_weak_hit() -> void:
	var graph := _flat_graph(2)
	var unit_a := _make_unit("a", "playerA", Vector2i(0, 0), 5, 1, 20, 1)
	var enemy_low := _make_unit("low_hp", "playerB", Vector2i(1, 0), 2, 1, 1, 1)
	var enemy_full := _make_unit("full_hp", "playerB", Vector2i(0, 1), 2, 1, 20, 1)
	var state := _make_state(graph, [unit_a], [enemy_low, enemy_full])
	state.current_unit = unit_a
	unit_a.ap_remaining = 2

	var plan := AIPlanner.plan(state, unit_a, _fixed_rng(1), _hard())
	var targets_low := false
	for step in plan.steps:
		if step["kind"] == "attack" and step["target_pos"] == Vector2i(1, 0):
			targets_low = true
	assert_true(targets_low, "AI should prefer to finish off low-HP enemy")


func test_avoids_hazard_tile() -> void:
	## AI should prefer a non-lava path to reach the enemy.
	## Layout: unit at (-1,0), lava at (0,0), grass at (0,1), enemy at (1,0).
	## The AI can go via (0,1) then attack (1,0), avoiding lava.
	var graph := _custom_graph([
		[-1, 0, 0, "grass"],   # unit start
		[0, 0, 0, "lava"],     # hazard shortcut
		[0, 1, 0, "grass"],    # safe detour
		[1, 0, 0, "grass"],    # enemy position
		[1, 1, 0, "grass"],    # extra tile
		[-1, 1, 0, "grass"],   # extra tile
	])
	var unit_a := _make_unit("a", "playerA", Vector2i(-1, 0), 5, 1, 20, 1, 3)
	var enemy := _make_unit("enemy", "playerB", Vector2i(1, 0), 2, 1, 10, 1)
	var state := _make_state(graph, [unit_a], [enemy])
	state.current_unit = unit_a
	unit_a.ap_remaining = 2

	# Score two plans: move through lava vs move through safe tile
	var plan_lava := AIPlan.make_move_attack(Vector2i(0, 0), Vector2i(1, 0))
	var plan_safe := AIPlan.make_move_attack(Vector2i(0, 1), Vector2i(1, 0))
	var w: Dictionary = AIPlanner.difficulty_preset("hard")["weights"] as Dictionary
	var score_lava: float = AIScorer.score(state, unit_a, plan_lava, w)
	var score_safe: float = AIScorer.score(state, unit_a, plan_safe, w)
	assert_true(score_safe > score_lava,
		"Plan avoiding lava should score higher (safe=%f > lava=%f)" % [score_safe, score_lava])


func test_prefers_cover_position() -> void:
	var graph := _custom_graph([
		[0, 0, 0, "grass"],
		[1, 0, 0, "cover_tile"],
		[-1, 0, 0, "grass"],
		[2, 0, 0, "grass"],
		[-2, 0, 0, "grass"],
		[0, 1, 0, "grass"],
		[0, -1, 0, "grass"],
	])
	var archer := _make_unit("archer", "playerA", Vector2i(0, 0), 2, 1, 20, 3, 3)
	var enemy := _make_unit("enemy", "playerB", Vector2i(2, 0), 2, 1, 10, 1)
	var state := _make_state(graph, [archer], [enemy])
	state.current_unit = archer
	archer.ap_remaining = 2

	var plan_cover := AIPlan.make_move_attack(Vector2i(1, 0), Vector2i(2, 0))
	var plan_open := AIPlan.make_attack_only(Vector2i(2, 0))
	var w: Dictionary = AIPlanner.difficulty_preset("hard")["weights"] as Dictionary
	var score_cover: float = AIScorer.score(state, archer, plan_cover, w)
	var score_open: float = AIScorer.score(state, archer, plan_open, w)
	assert_true(score_cover > score_open,
		"Plan ending on cover tile should score higher than open ground")


func test_heals_hurt_ally() -> void:
	## A healer with cure_1 should heal a badly hurt ally when no enemies are
	## in attack range. Enemy placed far away so the healer's only impactful
	## option is to heal.
	var graph := _flat_graph(4)
	# Give the healer cure_1 directly via abilities array; spd=1 limits movement
	var healer := _make_unit("healer", "playerA", Vector2i(0, 0), 1, 1, 20, 1, 1, 3, 0, 10,
		[] as Array[String], [] as Array[String], ["cure_1"] as Array[String])
	var hurt_ally := _make_unit("ally", "playerA", Vector2i(1, 0), 2, 1, 20, 1)
	hurt_ally.current_hp = 3  # badly hurt
	var enemy := _make_unit("enemy", "playerB", Vector2i(4, 0), 2, 1, 20, 1)
	var state := _make_state(graph, [healer, hurt_ally], [enemy])
	state.current_unit = healer
	healer.ap_remaining = 2

	var plan := AIPlanner.plan(state, healer, _fixed_rng(1), _hard())
	var has_heal := false
	for step in plan.steps:
		if step["kind"] == "ability":
			var ability_id: String = str(step.get("ability_id", ""))
			if "cure" in ability_id:
				has_heal = true
	assert_true(has_heal, "Healer should heal a badly hurt ally")


# --- Determinism / variance tests ---

func test_deterministic_with_fixed_seed() -> void:
	var graph := _flat_graph(2)

	var plan1: AIPlan
	var plan2: AIPlan
	for i in range(2):
		# Create fresh units each iteration (BattleUnit has no duplicate())
		var unit_a := _make_unit("a", "playerA", Vector2i(0, 0), 3, 1, 20, 1)
		var enemy := _make_unit("b", "playerB", Vector2i(1, 0), 2, 1, 10, 1)
		var state := _make_state(graph, [unit_a], [enemy])
		state.current_unit = unit_a
		unit_a.ap_remaining = 2

		var p := AIPlanner.plan(state, unit_a, _fixed_rng(42), _normal())
		if i == 0:
			plan1 = p
		else:
			plan2 = p

	assert_eq(plan1.steps.size(), plan2.steps.size(), "Same seed should produce same plan length")
	for j in range(plan1.steps.size()):
		assert_eq(str(plan1.steps[j]), str(plan2.steps[j]),
			"Same seed should produce identical steps")


func test_variance_with_different_seeds() -> void:
	var graph := _flat_graph(2)
	var plans: Array = []

	for seed_val in range(1, 20):
		var unit_a := _make_unit("a", "playerA", Vector2i(0, 0), 3, 1, 20, 1, 3, 0, 0, 0)
		var enemy1 := _make_unit("e1", "playerB", Vector2i(1, 0), 2, 1, 10, 1)
		var enemy2 := _make_unit("e2", "playerB", Vector2i(0, 1), 2, 1, 10, 1)
		var state := _make_state(graph, [unit_a], [enemy1, enemy2])
		state.current_unit = unit_a
		unit_a.ap_remaining = 2

		var plan := AIPlanner.plan(state, unit_a, _fixed_rng(seed_val),
			AIPlanner.difficulty_preset("easy"))
		plans.append(str(plan.steps))

	var all_same := true
	for i in range(1, plans.size()):
		if plans[i] != plans[0]:
			all_same = false
			break
	assert_false(all_same, "Different seeds should sometimes produce different plans")


func test_difficulty_presets_exist() -> void:
	for preset_name in ["easy", "normal", "hard"]:
		var preset := AIPlanner.difficulty_preset(preset_name)
		assert_true(preset.has("top_n"), "%s preset should have top_n" % preset_name)
		assert_true(preset.has("temperature"), "%s preset should have temperature" % preset_name)
		assert_true(preset.has("max_tiles"), "%s preset should have max_tiles" % preset_name)
		assert_true(preset.has("weights"), "%s preset should have weights" % preset_name)
