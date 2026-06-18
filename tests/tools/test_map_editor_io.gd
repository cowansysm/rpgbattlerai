extends GutTest
## Integration test for map editor save/load round-trip.
## Exercises: model -> MapData -> MapSerializer -> JSON -> DataFactory -> MapData -> model.


func test_save_and_reload_round_trip() -> void:
	var m := MapEditorModel.new()
	m.new_map("io_test", "standard", "rect", 4)
	m.set_terrain(Vector2i(0, 0), "road")
	m.set_elevation(Vector2i(1, 0), 3)
	m.set_zone(Vector2i(0, 0), "playerA", true)
	m.set_zone(Vector2i(1, 0), "playerB", true)

	# Serialize via MapSerializer
	var map_data := m.to_map_data()
	var json_str := MapSerializer.to_json(map_data)

	# Re-parse and reload
	var raw: Variant = JSON.parse_string(json_str)
	assert_not_null(raw, "JSON should parse successfully")
	var reloaded: MapData = DataFactory.make_map(raw)

	var m2 := MapEditorModel.new()
	m2.from_map_data(reloaded)

	assert_eq(m2.id, "io_test")
	assert_eq(m2.tier, "standard")
	assert_eq(m2.tiles[Vector2i(0, 0)]["terrain"], "road")
	assert_eq(m2.tiles[Vector2i(1, 0)]["elevation"], 3)
	assert_true(m2.zones["playerA"].has(Vector2i(0, 0)))
	assert_true(m2.zones["playerB"].has(Vector2i(1, 0)))
	assert_eq(m2.tile_count(), m.tile_count())


func test_round_trip_preserves_hex_map() -> void:
	var m := MapEditorModel.new()
	m.new_map("hex_io", "skirmish", "hex", 5)
	m.set_terrain(Vector2i(0, 0), "trees")
	m.set_elevation(Vector2i(1, -1), 2)

	var json_str := MapSerializer.to_json(m.to_map_data())
	var raw: Variant = JSON.parse_string(json_str)
	var reloaded: MapData = DataFactory.make_map(raw)

	var m2 := MapEditorModel.new()
	m2.from_map_data(reloaded)

	assert_eq(m2.id, "hex_io")
	assert_eq(m2.tier, "skirmish")
	assert_eq(m2.tile_count(), m.tile_count())
	assert_eq(m2.tiles[Vector2i(0, 0)]["terrain"], "trees")
	assert_eq(m2.tiles[Vector2i(1, -1)]["elevation"], 2)


func test_round_trip_condensed_format_is_minified() -> void:
	var m := MapEditorModel.new()
	m.new_map("min_test", "standard", "rect", 2)
	var json_str := MapSerializer.to_json(m.to_map_data())
	# Condensed minified JSON should not contain newlines
	assert_false(json_str.contains("\n"), "output should be minified (no newlines)")
	# Should contain the id
	assert_true(json_str.contains("\"min_test\""))
