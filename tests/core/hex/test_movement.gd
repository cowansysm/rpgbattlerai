extends GutTest
## Tests for Movement: reachable set, two-tier reach, and shortest path.
## All tests use a stub terrain provider — no autoload required.


# --- Stub terrain provider ---

static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	p.impassable = (id == "rocks" or id == "deep_water" or id == "cliff")
	if id == "brush" or id == "trees" or id == "shallow_water":
		p.move_cost = 2
	return p


# --- Helper: build a small flat hex cluster around (0,0) ---

func _flat_graph(radius: int, elev: int = 0, terrain: String = "grass") -> HexGraph:
	var map := MapData.new()
	map.id = "test"
	var tiles: Array[TileRecord] = []
	for c in Hex.hexes_in_range(Vector2i(0, 0), radius):
		tiles.append(TileRecord.new(c.x, c.y, elev, terrain))
	map.tiles = tiles
	var g := HexGraph.new()
	g.build(map, _stub_terrain)
	return g


# --- Helper: build a graph with a high tile ---

func _graph_with_cliff() -> HexGraph:
	var map := MapData.new()
	map.id = "test_cliff"
	var tiles: Array[TileRecord] = []
	# Center at (0,0) elev 0, neighbor at (1,0) elev 3
	tiles.append(TileRecord.new(0, 0, 0, "grass"))
	tiles.append(TileRecord.new(1, 0, 3, "grass"))
	tiles.append(TileRecord.new(0, 1, 0, "grass"))
	tiles.append(TileRecord.new(-1, 1, 0, "grass"))
	tiles.append(TileRecord.new(-1, 0, 0, "grass"))
	tiles.append(TileRecord.new(0, -1, 0, "grass"))
	tiles.append(TileRecord.new(1, -1, 0, "grass"))
	map.tiles = tiles
	var g := HexGraph.new()
	g.build(map, _stub_terrain)
	return g


# --- Helper: build a graph with an impassable tile ---

func _graph_with_rocks() -> HexGraph:
	var map := MapData.new()
	map.id = "test_rocks"
	var tiles: Array[TileRecord] = []
	tiles.append(TileRecord.new(0, 0, 0, "grass"))
	tiles.append(TileRecord.new(1, 0, 0, "rocks"))   # impassable
	tiles.append(TileRecord.new(0, 1, 0, "grass"))
	tiles.append(TileRecord.new(-1, 1, 0, "grass"))
	tiles.append(TileRecord.new(-1, 0, 0, "grass"))
	tiles.append(TileRecord.new(0, -1, 0, "grass"))
	tiles.append(TileRecord.new(1, -1, 0, "grass"))
	map.tiles = tiles
	var g := HexGraph.new()
	g.build(map, _stub_terrain)
	return g


# --- Reachable set tests ---

func test_reachable_flat_open() -> void:
	var g := _flat_graph(2)
	var reach := Movement.reachable(g, Vector2i(0, 0), 2, 99)
	# With move_cost=1, budget=2, radius=2: all 19 tiles should be reachable
	# (center + 6 at distance 1 + 12 at distance 2)
	assert_eq(reach.size(), 19, "all tiles in range 2 should be reachable")


func test_reachable_includes_start() -> void:
	var g := _flat_graph(1)
	var reach := Movement.reachable(g, Vector2i(0, 0), 1, 99)
	assert_true(reach.has(Vector2i(0, 0)), "start tile should be in reachable set")
	assert_eq(reach[Vector2i(0, 0)], 0, "start tile cost should be 0")


func test_reachable_cost_values() -> void:
	var g := _flat_graph(2)
	var reach := Movement.reachable(g, Vector2i(0, 0), 2, 99)
	# Neighbors of origin should have cost 1
	for nb in Hex.neighbors(Vector2i(0, 0)):
		assert_eq(reach[nb], 1, "neighbor %s should cost 1" % str(nb))


func test_jump_blocks_steep_edge() -> void:
	var g := _graph_with_cliff()
	var reach := Movement.reachable(g, Vector2i(0, 0), 10, 1)
	assert_false(reach.has(Vector2i(1, 0)), "tile at elev 3 should be unreachable with jump 1")


func test_jump_allows_within_limit() -> void:
	var g := _graph_with_cliff()
	var reach := Movement.reachable(g, Vector2i(0, 0), 10, 3)
	assert_true(reach.has(Vector2i(1, 0)), "tile at elev 3 should be reachable with jump 3")


func test_impassable_excluded() -> void:
	var g := _graph_with_rocks()
	var reach := Movement.reachable(g, Vector2i(0, 0), 10, 99)
	assert_false(reach.has(Vector2i(1, 0)), "rocks tile should be excluded from reachable set")


func test_rough_terrain_costs_more() -> void:
	var map := MapData.new()
	map.id = "test_brush"
	var tiles: Array[TileRecord] = []
	tiles.append(TileRecord.new(0, 0, 0, "grass"))
	tiles.append(TileRecord.new(1, 0, 0, "brush"))   # move_cost = 2
	tiles.append(TileRecord.new(0, 1, 0, "grass"))
	map.tiles = tiles
	var g := HexGraph.new()
	g.build(map, _stub_terrain)
	var reach := Movement.reachable(g, Vector2i(0, 0), 1, 99)
	assert_false(reach.has(Vector2i(1, 0)), "brush (cost 2) unreachable with budget 1")
	var reach2 := Movement.reachable(g, Vector2i(0, 0), 2, 99)
	assert_true(reach2.has(Vector2i(1, 0)), "brush reachable with budget 2")


# --- Two-tier tests ---

func test_two_tiers_disjoint() -> void:
	var g := _flat_graph(3)
	var tiers := Movement.two_tier(g, Vector2i(0, 0), 2, 99)
	for c in tiers["tier1"].keys():
		assert_false(tiers["tier2"].has(c), "tier1 tile %s should not be in tier2" % str(c))


func test_two_tiers_partition() -> void:
	var g := _flat_graph(3)
	var tiers := Movement.two_tier(g, Vector2i(0, 0), 2, 99)
	var full := Movement.reachable(g, Vector2i(0, 0), 4, 99)
	var combined_count: int = tiers["tier1"].size() + tiers["tier2"].size()
	assert_eq(combined_count, full.size(), "tier1 + tier2 should equal full double-move reach")


func test_tier1_within_move_budget() -> void:
	var g := _flat_graph(3)
	var tiers := Movement.two_tier(g, Vector2i(0, 0), 2, 99)
	for c in tiers["tier1"].keys():
		assert_true(int(tiers["tier1"][c]) <= 2, "tier1 cost should be <= move budget")


# --- Path tests ---

func test_path_returns_correct_sequence() -> void:
	var g := _flat_graph(2)
	var p := Movement.path(g, Vector2i(0, 0), Vector2i(1, 0), 99)
	assert_true(p.size() >= 2, "path should have at least start and goal")
	assert_eq(p[0], Vector2i(0, 0), "path should start at origin")
	assert_eq(p[p.size() - 1], Vector2i(1, 0), "path should end at goal")


func test_path_empty_for_unreachable() -> void:
	var g := _graph_with_cliff()
	var p := Movement.path(g, Vector2i(0, 0), Vector2i(1, 0), 1)
	assert_eq(p.size(), 0, "path to unreachable tile should be empty")
