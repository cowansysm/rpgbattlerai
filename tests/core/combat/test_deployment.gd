extends GutTest
## Tests for Deployment: auto-deploy into zones with validation.


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


func _setup_state(count_a: int, count_b: int) -> MatchState:
	var map := MapData.new()
	map.id = "test"
	var tiles: Array[TileRecord] = []
	for c in Hex.hexes_in_range(Vector2i(0, 0), 4):
		tiles.append(TileRecord.new(c.x, c.y, 0, "grass"))
	map.tiles = tiles

	var party_a: Array[BattleUnit] = []
	var party_b: Array[BattleUnit] = []
	for i in range(count_a):
		party_a.append(_make_unit("a%d" % i, "playerA"))
	for i in range(count_b):
		party_b.append(_make_unit("b%d" % i, "playerB"))

	return MatchSetup.create(party_a, party_b, map, _stub_terrain)


# --- Tests ---

func test_deploy_places_units() -> void:
	var state := _setup_state(2, 2)
	var zones := {
		"playerA": ["0,-3", "1,-3"],
		"playerB": ["0,3", "-1,3"],
	}
	var errors := Deployment.auto_deploy(state, zones)
	assert_eq(errors.size(), 0, "deployment should succeed with no errors")
	assert_eq(state.parties["playerA"][0].position, Vector2i(0, -3))
	assert_eq(state.parties["playerA"][1].position, Vector2i(1, -3))
	assert_eq(state.parties["playerB"][0].position, Vector2i(0, 3))
	assert_eq(state.parties["playerB"][1].position, Vector2i(-1, 3))


func test_deploy_populates_occupancy() -> void:
	var state := _setup_state(2, 2)
	var zones := {
		"playerA": ["0,-3", "1,-3"],
		"playerB": ["0,3", "-1,3"],
	}
	Deployment.auto_deploy(state, zones)
	assert_true(state.is_occupied(Vector2i(0, -3)))
	assert_true(state.is_occupied(Vector2i(1, -3)))
	assert_true(state.is_occupied(Vector2i(0, 3)))
	assert_true(state.is_occupied(Vector2i(-1, 3)))
	assert_false(state.is_occupied(Vector2i(0, 0)))


func test_deploy_transitions_to_round_start() -> void:
	var state := _setup_state(1, 1)
	var zones := {
		"playerA": ["0,-3"],
		"playerB": ["0,3"],
	}
	Deployment.auto_deploy(state, zones)
	assert_eq(state.phase, MatchState.Phase.AWAITING_ACTIVATION)


func test_deploy_too_many_units_returns_error() -> void:
	var state := _setup_state(3, 1)
	var zones := {
		"playerA": ["0,-3", "1,-3"],	# Only 2 tiles for 3 units
		"playerB": ["0,3"],
	}
	var errors := Deployment.auto_deploy(state, zones)
	assert_true(errors.size() > 0, "should error when more units than zone tiles")


func test_deploy_off_map_tile_returns_error() -> void:
	var state := _setup_state(1, 1)
	var zones := {
		"playerA": ["99,99"],	# Not on map
		"playerB": ["0,3"],
	}
	var errors := Deployment.auto_deploy(state, zones)
	assert_true(errors.size() > 0, "should error for off-map zone tile")


func test_deploy_no_double_occupancy() -> void:
	# Deploy two units from different teams to the same tile
	var state := _setup_state(1, 1)
	var zones := {
		"playerA": ["0,-3"],
		"playerB": ["0,-3"],	# Same tile as playerA
	}
	var errors := Deployment.auto_deploy(state, zones)
	assert_true(errors.size() > 0, "should error for double occupancy")
