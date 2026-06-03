extends GutTest
## Tests for LineOfSight: hex-line sampling with elevation rules.
## All tests use a stub terrain provider — no autoload required.


# --- Stub terrain provider ---

static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	if id == "trees":
		p.blocks_los = true
		p.los_height = 2
	elif id == "rocks":
		p.blocks_los = true
		p.los_height = 3
	elif id == "cliff":
		p.blocks_los = true
		p.los_height = 3
	return p


# --- Helper: build a linear graph along q axis ---

func _linear_graph(tiles_data: Array) -> HexGraph:
	var map := MapData.new()
	map.id = "test_linear"
	var tiles: Array[TileRecord] = []
	for t in tiles_data:
		tiles.append(TileRecord.new(int(t[0]), int(t[1]), int(t[2]), str(t[3])))
	map.tiles = tiles
	var g := HexGraph.new()
	g.build(map, _stub_terrain)
	return g


# --- LoS tests ---

func test_adjacent_always_has_los() -> void:
	var g := _linear_graph([
		[0, 0, 0, "grass"],
		[1, 0, 0, "grass"],
	])
	assert_true(LineOfSight.has_los(g, Vector2i(0, 0), Vector2i(1, 0)),
		"adjacent tiles should always have LoS")


func test_same_tile_has_los() -> void:
	var g := _linear_graph([
		[0, 0, 0, "grass"],
	])
	assert_true(LineOfSight.has_los(g, Vector2i(0, 0), Vector2i(0, 0)),
		"same tile should have LoS")


func test_clear_ground_has_los() -> void:
	var g := _linear_graph([
		[0, 0, 0, "grass"],
		[1, 0, 0, "grass"],
		[2, 0, 0, "grass"],
		[3, 0, 0, "grass"],
	])
	assert_true(LineOfSight.has_los(g, Vector2i(0, 0), Vector2i(3, 0)),
		"clear grass should have LoS")


func test_tall_terrain_blocks() -> void:
	# A(0,0) elev 0 — trees(1,0) elev 0 — B(2,0) elev 0
	# Trees have los_height=2, sightline at midpoint = 1.0 (UNIT_EYE=1.0 at both ends)
	# Block height = 0 + 2 = 2.0 > 1.0 → blocked
	var g := _linear_graph([
		[0, 0, 0, "grass"],
		[1, 0, 0, "trees"],
		[2, 0, 0, "grass"],
	])
	assert_false(LineOfSight.has_los(g, Vector2i(0, 0), Vector2i(2, 0)),
		"trees between equal-height tiles should block LoS")


func test_higher_attacker_sees_over() -> void:
	# A(0,0) elev 4 — trees(1,0) elev 0 — B(2,0) elev 0
	# ha = 4 + 1.0 = 5.0, hb = 0 + 1.0 = 1.0
	# Sightline at midpoint (i=1, n=2): lerp(5.0, 1.0, 0.5) = 3.0
	# Block height = 0 + 2 = 2.0 < 3.0 → clear
	var g := _linear_graph([
		[0, 0, 4, "grass"],
		[1, 0, 0, "trees"],
		[2, 0, 0, "grass"],
	])
	assert_true(LineOfSight.has_los(g, Vector2i(0, 0), Vector2i(2, 0)),
		"attacker at elev 4 should see over elev-0 trees")


func test_rocks_block_from_ground_level() -> void:
	# A(0,0) elev 0 — rocks(1,0) elev 0 — B(2,0) elev 0
	# Block height = 0 + 3 = 3.0 > sightline 1.0 → blocked
	var g := _linear_graph([
		[0, 0, 0, "grass"],
		[1, 0, 0, "rocks"],
		[2, 0, 0, "grass"],
	])
	assert_false(LineOfSight.has_los(g, Vector2i(0, 0), Vector2i(2, 0)),
		"rocks between equal-height tiles should block LoS")


func test_elevated_target_with_blocker() -> void:
	# A(0,0) elev 0 — trees(1,0) elev 0 — B(2,0) elev 3
	# ha = 0 + 1.0 = 1.0, hb = 3 + 1.0 = 4.0
	# Sightline at midpoint: lerp(1.0, 4.0, 0.5) = 2.5
	# Block height = 0 + 2 = 2.0 < 2.5 → clear
	var g := _linear_graph([
		[0, 0, 0, "grass"],
		[1, 0, 0, "trees"],
		[2, 0, 3, "grass"],
	])
	assert_true(LineOfSight.has_los(g, Vector2i(0, 0), Vector2i(2, 0)),
		"sightline to elevated target should clear low trees")


func test_non_blocking_terrain_does_not_block() -> void:
	# Brush has blocks_los=false — should not block LoS
	var g := _linear_graph([
		[0, 0, 0, "grass"],
		[1, 0, 0, "brush"],
		[2, 0, 0, "grass"],
	])
	assert_true(LineOfSight.has_los(g, Vector2i(0, 0), Vector2i(2, 0)),
		"brush (non-blocking) should not block LoS")


# --- Hex line tests ---

func test_hex_line_endpoints() -> void:
	var line := LineOfSight._hex_line(Vector2i(0, 0), Vector2i(3, 0))
	assert_eq(line[0], Vector2i(0, 0), "line should start at A")
	assert_eq(line[line.size() - 1], Vector2i(3, 0), "line should end at B")


func test_hex_line_length() -> void:
	var line := LineOfSight._hex_line(Vector2i(0, 0), Vector2i(3, 0))
	assert_eq(line.size(), 4, "line length should be distance + 1")


func test_hex_line_same_tile() -> void:
	var line := LineOfSight._hex_line(Vector2i(2, -1), Vector2i(2, -1))
	assert_eq(line.size(), 1, "line to self should have 1 element")
	assert_eq(line[0], Vector2i(2, -1))
