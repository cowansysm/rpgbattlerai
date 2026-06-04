extends GutTest
## Tests for MatchSetup: match initialization and initiative determination.


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


func _small_map() -> MapData:
	var map := MapData.new()
	map.id = "test"
	var tiles: Array[TileRecord] = []
	for c in Hex.hexes_in_range(Vector2i(0, 0), 3):
		tiles.append(TileRecord.new(c.x, c.y, 0, "grass"))
	map.tiles = tiles
	map.deployment_zones = {
		"playerA": ["0,-3", "1,-3"],
		"playerB": ["0,3", "-1,3"],
	}
	return map


# --- Tests ---

func test_create_returns_setup_phase() -> void:
	var a: Array[BattleUnit] = [_make_unit("a1")]
	var b: Array[BattleUnit] = [_make_unit("b1")]
	var state := MatchSetup.create(a, b, _small_map(), _stub_terrain)
	assert_eq(state.phase, MatchState.Phase.SETUP)


func test_create_assigns_teams() -> void:
	var a: Array[BattleUnit] = [_make_unit("a1")]
	var b: Array[BattleUnit] = [_make_unit("b1")]
	var state := MatchSetup.create(a, b, _small_map(), _stub_terrain)
	assert_eq(state.parties["playerA"][0].team, "playerA")
	assert_eq(state.parties["playerB"][0].team, "playerB")


func test_create_builds_graph() -> void:
	var a: Array[BattleUnit] = [_make_unit("a1")]
	var b: Array[BattleUnit] = [_make_unit("b1")]
	var state := MatchSetup.create(a, b, _small_map(), _stub_terrain)
	assert_not_null(state.graph)
	assert_true(state.graph.has_tile(Vector2i(0, 0)))


func test_higher_spd_gets_initiative() -> void:
	var a: Array[BattleUnit] = [_make_unit("a1", 5)]
	var b: Array[BattleUnit] = [_make_unit("b1", 3)]
	var state := MatchSetup.create(a, b, _small_map(), _stub_terrain)
	assert_eq(state.initiative, "playerA",
		"party A with SPD 5 should get initiative over party B with SPD 3")


func test_lower_spd_loses_initiative() -> void:
	var a: Array[BattleUnit] = [_make_unit("a1", 2)]
	var b: Array[BattleUnit] = [_make_unit("b1", 4)]
	var state := MatchSetup.create(a, b, _small_map(), _stub_terrain)
	assert_eq(state.initiative, "playerB",
		"party B with SPD 4 should get initiative over party A with SPD 2")


func test_tied_spd_assigns_initiative() -> void:
	# Both parties have SPD 3 — initiative should be one of the two teams
	var a: Array[BattleUnit] = [_make_unit("a1", 3)]
	var b: Array[BattleUnit] = [_make_unit("b1", 3)]
	var state := MatchSetup.create(a, b, _small_map(), _stub_terrain)
	assert_true(state.initiative in ["playerA", "playerB"],
		"tied SPD should still assign initiative to one team")
