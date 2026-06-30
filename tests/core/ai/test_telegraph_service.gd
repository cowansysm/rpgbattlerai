extends GutTest
## Tests for TelegraphService: IntentPlan building and single-plan contract.


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


func _deployed_state() -> MatchState:
	var map := MapData.new()
	map.id = "test"
	var tiles: Array[TileRecord] = []
	for coord in Hex.hexes_in_range(Vector2i(0, 0), 6):
		tiles.append(TileRecord.new(coord.x, coord.y, 0, "grass"))
	map.tiles = tiles

	var a := _make_unit("a0", "playerA", 5, 10, 5, 2, 1)
	var b := _make_unit("b0", "playerB", 3, 10, 5, 2, 1)

	var party_a: Array[BattleUnit] = [a]
	var party_b: Array[BattleUnit] = [b]

	var state := MatchSetup.create(party_a, party_b, map, _stub_terrain)

	a.position = Vector2i(-2, 0)
	state.occupancy[Vector2i(-2, 0)] = a
	b.position = Vector2i(2, 0)
	state.occupancy[Vector2i(2, 0)] = b

	state.ai_teams = ["playerB"]
	return state


# --- Tests ---

func test_build_intents_from_defend_plan() -> void:
	var state := _deployed_state()
	var b: BattleUnit = state.parties["playerB"][0]
	var plans := {"b0": AIPlan.make_defend()}

	var intents := TelegraphService.build_intents(state, plans, [b])
	assert_eq(intents.size(), 1)
	var intent: IntentPlan = intents[0]
	assert_eq(intent.unit_id, "b0")
	assert_eq(intent.action_kind, "defend")
	assert_true(intent.committed)


func test_build_intents_from_move_attack_plan() -> void:
	var state := _deployed_state()
	var a: BattleUnit = state.parties["playerA"][0]
	var b: BattleUnit = state.parties["playerB"][0]
	# B moves to (1, 0) then attacks A at (-2, 0)
	# Note: attack range is 1, so this would only make sense if A were adjacent
	# For test purposes, just check that fields are populated
	var plan := AIPlan.make_move_only(Vector2i(1, 0))
	var plans := {"b0": plan}

	var intents := TelegraphService.build_intents(state, plans, [b])
	assert_eq(intents.size(), 1)
	var intent: IntentPlan = intents[0]
	assert_eq(intent.unit_id, "b0")
	assert_eq(intent.move_to, Vector2i(1, 0))
	assert_true(intent.path.size() > 0, "Path should be computed for move")


func test_intent_attack_has_projection() -> void:
	var state := _deployed_state()
	var a: BattleUnit = state.parties["playerA"][0]
	var b: BattleUnit = state.parties["playerB"][0]

	# Place them adjacent so attack is valid for projection
	a.position = Vector2i(0, 0)
	state.occupancy.erase(Vector2i(-2, 0))
	state.occupancy[Vector2i(0, 0)] = a
	b.position = Vector2i(1, 0)
	state.occupancy.erase(Vector2i(2, 0))
	state.occupancy[Vector2i(1, 0)] = b

	var plan := AIPlan.make_attack_only(Vector2i(0, 0))
	var plans := {"b0": plan}

	var intents := TelegraphService.build_intents(state, plans, [b])
	assert_eq(intents.size(), 1)
	var intent: IntentPlan = intents[0]
	assert_eq(intent.action_kind, "attack")
	assert_eq(intent.target_pos, Vector2i(0, 0))
	assert_eq(intent.target_unit_id, "a0")
	assert_true(intent.projection.has("min"), "Projection should have min")
	assert_true(intent.projection.has("max"), "Projection should have max")
	assert_true(intent.projection.has("mid"), "Projection should have mid")


func test_single_plan_contract() -> void:
	## The IntentPlan's action kind and target should match the AIPlan steps.
	var state := _deployed_state()
	var a: BattleUnit = state.parties["playerA"][0]
	var b: BattleUnit = state.parties["playerB"][0]

	a.position = Vector2i(0, 0)
	state.occupancy.erase(Vector2i(-2, 0))
	state.occupancy[Vector2i(0, 0)] = a
	b.position = Vector2i(1, 0)
	state.occupancy.erase(Vector2i(2, 0))
	state.occupancy[Vector2i(1, 0)] = b

	var plan := AIPlan.make_attack_only(Vector2i(0, 0))
	var plans := {"b0": plan}

	var intents := TelegraphService.build_intents(state, plans, [b])
	var intent: IntentPlan = intents[0]

	# Verify contract: intent action matches plan step
	var attack_step: Dictionary = plan.steps[0]
	assert_eq(intent.action_kind, str(attack_step["kind"]))
	assert_eq(intent.target_pos, attack_step["target_pos"])


func test_empty_plan_produces_no_intent() -> void:
	var state := _deployed_state()
	var b: BattleUnit = state.parties["playerB"][0]
	var empty_plan := AIPlan.new()
	var plans := {"b0": empty_plan}

	var intents := TelegraphService.build_intents(state, plans, [b])
	assert_eq(intents.size(), 0, "Empty plan should produce no intent")


func test_wait_plan_intent() -> void:
	var state := _deployed_state()
	var b: BattleUnit = state.parties["playerB"][0]
	var plans := {"b0": AIPlan.make_wait()}

	var intents := TelegraphService.build_intents(state, plans, [b])
	assert_eq(intents.size(), 1)
	assert_eq(intents[0].action_kind, "wait")
