extends GutTest
## Tests for RangeQuery: effective_range and in_range.


# --- Stub terrain provider ---

static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	return p


func _flat_graph(radius: int) -> HexGraph:
	var map := MapData.new()
	map.id = "test"
	var tiles: Array[TileRecord] = []
	for c in Hex.hexes_in_range(Vector2i(0, 0), radius):
		tiles.append(TileRecord.new(c.x, c.y, 0, "grass"))
	map.tiles = tiles
	var g := HexGraph.new()
	g.build(map, _stub_terrain)
	return g


# --- effective_range tests ---

func test_effective_range_equals_hex_distance() -> void:
	var g := _flat_graph(5)
	var a := Vector2i(0, 0)
	var b := Vector2i(2, -1)
	assert_eq(RangeQuery.effective_range(a, b, g), Hex.distance(a, b),
		"effective_range should equal hex distance (MVP)")


func test_effective_range_to_self_is_zero() -> void:
	var g := _flat_graph(1)
	assert_eq(RangeQuery.effective_range(Vector2i(0, 0), Vector2i(0, 0), g), 0)


# --- in_range tests ---

func test_in_range_matches_hex_range_on_full_map() -> void:
	var g := _flat_graph(5)
	var result := RangeQuery.in_range(Vector2i(0, 0), 2, g)
	var expected := Hex.hexes_in_range(Vector2i(0, 0), 2)
	assert_eq(result.size(), expected.size(),
		"in_range on full map should match hex_range cardinality")


func test_in_range_excludes_off_map_tiles() -> void:
	# Small map: only 7 tiles (center + 6 neighbors)
	var g := _flat_graph(1)
	var result := RangeQuery.in_range(Vector2i(0, 0), 3, g)
	# Range 3 has 37 theoretical tiles, but only 7 exist on map
	assert_eq(result.size(), 7, "in_range should only include on-map tiles")


func test_in_range_includes_origin() -> void:
	var g := _flat_graph(2)
	var result := RangeQuery.in_range(Vector2i(0, 0), 0, g)
	assert_eq(result.size(), 1, "range 0 should return just the origin")
	assert_eq(result[0], Vector2i(0, 0))


func test_in_range_radius_one() -> void:
	var g := _flat_graph(2)
	var result := RangeQuery.in_range(Vector2i(0, 0), 1, g)
	assert_eq(result.size(), 7, "range 1 should return origin + 6 neighbors")
