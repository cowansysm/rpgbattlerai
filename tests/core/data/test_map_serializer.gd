extends GutTest
## Alpha A0: tests for condensed map format — MapSerializer round-trip,
## dual-form parsing (condensed and verbose), and geometry preservation.


# --- Round-trip: condensed write → load preserves tiles ---

func test_round_trip_preserves_tiles() -> void:
	var original := MapData.new()
	original.id = "test_rt"
	original.tier = "standard"
	original.deployment_zones = {"playerA": ["0,0"], "playerB": ["1,0"]}
	var tiles: Array[TileRecord] = []
	tiles.append(TileRecord.new(0, 0, 2, "grass"))
	tiles.append(TileRecord.new(1, 0, 1, "brush"))
	tiles.append(TileRecord.new(2, 0, 0, "road"))
	original.tiles = tiles

	var json_str := MapSerializer.to_json(original)
	var parsed: Variant = JSON.parse_string(json_str)
	assert_not_null(parsed, "JSON should parse")
	var reparsed := DataFactory.make_map(parsed)

	assert_eq(reparsed.id, "test_rt")
	assert_eq(reparsed.tier, "standard")
	assert_eq(reparsed.tiles.size(), 3, "should have 3 tiles")
	for i in range(3):
		var ot: TileRecord = original.tiles[i]
		var rt: TileRecord = reparsed.tiles[i]
		assert_eq(rt.q, ot.q, "tile %d q should match" % i)
		assert_eq(rt.r, ot.r, "tile %d r should match" % i)
		assert_eq(rt.elevation, ot.elevation, "tile %d elevation should match" % i)
		assert_eq(rt.terrain, ot.terrain, "tile %d terrain should match" % i)


func test_round_trip_preserves_tile_tags() -> void:
	var original := MapData.new()
	original.id = "test_tags"
	original.tier = "standard"
	var tiles: Array[TileRecord] = []
	tiles.append(TileRecord.new(0, 0, 0, "grass", ["rough", "cover"] as Array[String]))
	tiles.append(TileRecord.new(1, 0, 0, "road"))
	original.tiles = tiles

	var json_str := MapSerializer.to_json(original)
	var reparsed := DataFactory.make_map(JSON.parse_string(json_str))

	assert_eq(reparsed.tiles[0].tags.size(), 2, "tagged tile should have 2 tags")
	assert_true("rough" in reparsed.tiles[0].tags)
	assert_true("cover" in reparsed.tiles[0].tags)
	assert_eq(reparsed.tiles[1].tags.size(), 0, "untagged tile should have 0 tags")


func test_round_trip_preserves_deployment_zones() -> void:
	var original := MapData.new()
	original.id = "test_zones"
	original.tier = "standard"
	original.deployment_zones = {"playerA": ["0,0", "1,0"], "playerB": ["2,0"]}
	var tiles: Array[TileRecord] = []
	tiles.append(TileRecord.new(0, 0, 0, "grass"))
	tiles.append(TileRecord.new(1, 0, 0, "grass"))
	tiles.append(TileRecord.new(2, 0, 0, "grass"))
	original.tiles = tiles

	var json_str := MapSerializer.to_json(original)
	var reparsed := DataFactory.make_map(JSON.parse_string(json_str))
	assert_eq(reparsed.deployment_zones.size(), 2)
	assert_eq(reparsed.deployment_zones["playerA"].size(), 2)
	assert_eq(reparsed.deployment_zones["playerB"].size(), 1)


# --- Dual-form parsing ---

func test_condensed_and_verbose_parse_equal() -> void:
	var verbose := {"id": "t", "tier": "standard",
		"tiles": [{"q": 1, "r": 2, "elevation": 3, "terrain": "grass"}],
		"deployment_zones": {}}
	var condensed := {"id": "t", "tier": "standard",
		"tiles": [[1, 2, 3, "grass"]],
		"deployment_zones": {}}
	var m_v := DataFactory.make_map(verbose)
	var m_c := DataFactory.make_map(condensed)
	assert_eq(m_v.tiles[0].coord(), m_c.tiles[0].coord())
	assert_eq(m_v.tiles[0].elevation, m_c.tiles[0].elevation)
	assert_eq(m_v.tiles[0].terrain, m_c.tiles[0].terrain)


func test_condensed_with_tags_parses() -> void:
	var data := {"id": "t", "tier": "standard",
		"tiles": [[0, 0, 1, "grass", ["rough"]]],
		"deployment_zones": {}}
	var m := DataFactory.make_map(data)
	assert_eq(m.tiles[0].tags.size(), 1)
	assert_eq(m.tiles[0].tags[0], "rough")


func test_condensed_without_tags_has_empty_tags() -> void:
	var data := {"id": "t", "tier": "standard",
		"tiles": [[0, 0, 1, "grass"]],
		"deployment_zones": {}}
	var m := DataFactory.make_map(data)
	assert_eq(m.tiles[0].tags.size(), 0)


# --- Output format ---

func test_serializer_produces_minified_json() -> void:
	var m := MapData.new()
	m.id = "test_min"
	m.tier = "standard"
	var tiles: Array[TileRecord] = []
	tiles.append(TileRecord.new(0, 0, 0, "grass"))
	m.tiles = tiles
	m.deployment_zones = {}
	var json_str := MapSerializer.to_json(m)
	assert_false("\n" in json_str, "output should be minified (no newlines)")
	assert_false("  " in json_str, "output should be minified (no indentation)")
