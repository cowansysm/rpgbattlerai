extends GutTest
## Unit tests for MapEditorModel: mutations, undo/redo, batch,
## round-trip conversion, and validation.


# --- new_map ---

func test_new_map_rect_creates_expected_tile_count() -> void:
	var m := MapEditorModel.new()
	m.new_map("test", "standard", "rect", 4)
	assert_eq(m.tile_count(), 16, "4x4 rect should produce 16 tiles")


func test_new_map_rect_all_grass_elevation_zero() -> void:
	var m := MapEditorModel.new()
	m.new_map("test", "standard", "rect", 3)
	for coord: Vector2i in m.tiles.keys():
		assert_eq(m.tiles[coord]["terrain"], "grass")
		assert_eq(m.tiles[coord]["elevation"], 0)


func test_new_map_hex_creates_hexagonal_region() -> void:
	var m := MapEditorModel.new()
	m.new_map("test", "standard", "hex", 5)
	# hex size 5 -> radius 2 -> 1 + 6 + 12 = 19 tiles
	assert_eq(m.tile_count(), 19)


func test_new_map_clears_undo() -> void:
	var m := MapEditorModel.new()
	m.new_map("a", "standard", "rect", 2)
	m.set_terrain(Vector2i(0, 0), "road")
	assert_true(m.can_undo())
	m.new_map("b", "standard", "rect", 2)
	assert_false(m.can_undo())


# --- set_terrain ---

func test_set_terrain_changes_tile() -> void:
	var m := MapEditorModel.new()
	m.new_map("t", "standard", "rect", 2)
	m.set_terrain(Vector2i(0, 0), "road")
	assert_eq(m.tiles[Vector2i(0, 0)]["terrain"], "road")


func test_set_terrain_on_missing_tile_is_noop() -> void:
	var m := MapEditorModel.new()
	m.new_map("t", "standard", "rect", 2)
	m.set_terrain(Vector2i(99, 99), "road")
	assert_false(m.has_tile(Vector2i(99, 99)))


# --- set_elevation ---

func test_set_elevation_clamps_to_max() -> void:
	var m := MapEditorModel.new()
	m.new_map("t", "standard", "rect", 2)
	m.set_elevation(Vector2i(0, 0), 20)
	assert_eq(m.tiles[Vector2i(0, 0)]["elevation"], MapEditorModel.MAX_ELEVATION)


func test_set_elevation_clamps_to_min() -> void:
	var m := MapEditorModel.new()
	m.new_map("t", "standard", "rect", 2)
	m.set_elevation(Vector2i(0, 0), -5)
	assert_eq(m.tiles[Vector2i(0, 0)]["elevation"], MapEditorModel.MIN_ELEVATION)


func test_adjust_elevation_increments() -> void:
	var m := MapEditorModel.new()
	m.new_map("t", "standard", "rect", 2)
	m.adjust_elevation(Vector2i(0, 0), 3)
	assert_eq(m.tiles[Vector2i(0, 0)]["elevation"], 3)


# --- add/remove tile ---

func test_add_tile_creates_new_tile() -> void:
	var m := MapEditorModel.new()
	m.new_map("t", "standard", "rect", 2)
	var new_coord := Vector2i(10, 10)
	m.add_tile(new_coord, "brush", 2)
	assert_true(m.has_tile(new_coord))
	assert_eq(m.tiles[new_coord]["terrain"], "brush")
	assert_eq(m.tiles[new_coord]["elevation"], 2)


func test_add_existing_tile_is_noop() -> void:
	var m := MapEditorModel.new()
	m.new_map("t", "standard", "rect", 2)
	var coord := Vector2i(0, 0)
	m.add_tile(coord, "road")
	assert_eq(m.tiles[coord]["terrain"], "grass", "existing tile should not be overwritten")


func test_remove_tile_erases_from_tiles() -> void:
	var m := MapEditorModel.new()
	m.new_map("t", "standard", "rect", 2)
	m.remove_tile(Vector2i(0, 0))
	assert_false(m.has_tile(Vector2i(0, 0)))


func test_remove_tile_clears_from_zones() -> void:
	var m := MapEditorModel.new()
	m.new_map("t", "standard", "rect", 2)
	m.set_zone(Vector2i(0, 0), "playerA", true)
	assert_true(m.zones["playerA"].has(Vector2i(0, 0)))
	m.remove_tile(Vector2i(0, 0))
	assert_false(m.zones["playerA"].has(Vector2i(0, 0)))


# --- zones ---

func test_set_zone_adds_coord() -> void:
	var m := MapEditorModel.new()
	m.new_map("t", "standard", "rect", 2)
	m.set_zone(Vector2i(0, 0), "playerA", true)
	assert_true(m.zones["playerA"].has(Vector2i(0, 0)))


func test_set_zone_removes_coord() -> void:
	var m := MapEditorModel.new()
	m.new_map("t", "standard", "rect", 2)
	m.set_zone(Vector2i(0, 0), "playerA", true)
	m.set_zone(Vector2i(0, 0), "playerA", false)
	assert_false(m.zones["playerA"].has(Vector2i(0, 0)))


func test_set_zone_on_missing_tile_is_noop() -> void:
	var m := MapEditorModel.new()
	m.new_map("t", "standard", "rect", 2)
	m.set_zone(Vector2i(99, 99), "playerA", true)
	assert_false(m.zones.has("playerA") and m.zones["playerA"].has(Vector2i(99, 99)),
		"zone should not contain a coord for a tile that does not exist")


# --- undo/redo ---

func test_undo_reverts_terrain_change() -> void:
	var m := MapEditorModel.new()
	m.new_map("t", "standard", "rect", 2)
	m.set_terrain(Vector2i(0, 0), "road")
	m.undo()
	assert_eq(m.tiles[Vector2i(0, 0)]["terrain"], "grass")


func test_redo_reapplies_terrain_change() -> void:
	var m := MapEditorModel.new()
	m.new_map("t", "standard", "rect", 2)
	m.set_terrain(Vector2i(0, 0), "road")
	m.undo()
	m.redo()
	assert_eq(m.tiles[Vector2i(0, 0)]["terrain"], "road")


func test_undo_on_empty_stack_returns_false() -> void:
	var m := MapEditorModel.new()
	m.new_map("t", "standard", "rect", 2)
	assert_false(m.undo())


func test_new_mutation_clears_redo() -> void:
	var m := MapEditorModel.new()
	m.new_map("t", "standard", "rect", 2)
	m.set_terrain(Vector2i(0, 0), "road")
	m.undo()
	assert_true(m.can_redo())
	m.set_terrain(Vector2i(0, 0), "brush")
	assert_false(m.can_redo())


func test_undo_stack_bounded_at_max() -> void:
	var m := MapEditorModel.new()
	m.new_map("t", "standard", "rect", 2)
	for i in range(MapEditorModel.MAX_UNDO + 10):
		m.set_terrain(Vector2i(0, 0), "road" if i % 2 == 0 else "grass")
	assert_eq(m._undo.size(), MapEditorModel.MAX_UNDO)


# --- batch ---

func test_batch_creates_single_undo_entry() -> void:
	var m := MapEditorModel.new()
	m.new_map("t", "standard", "rect", 4)
	m.begin_batch()
	m.set_terrain(Vector2i(0, 0), "road")
	m.set_terrain(Vector2i(1, 0), "road")
	m.set_terrain(Vector2i(0, 1), "road")
	m.end_batch()
	assert_eq(m._undo.size(), 1, "batch should produce exactly one undo entry")
	m.undo()
	assert_eq(m.tiles[Vector2i(0, 0)]["terrain"], "grass")
	assert_eq(m.tiles[Vector2i(1, 0)]["terrain"], "grass")
	assert_eq(m.tiles[Vector2i(0, 1)]["terrain"], "grass")


# --- round-trip ---

func test_round_trip_preserves_tiles() -> void:
	var m := MapEditorModel.new()
	m.new_map("rt_test", "standard", "rect", 3)
	m.set_terrain(Vector2i(0, 0), "brush")
	m.set_elevation(Vector2i(1, 0), 4)
	var copy := MapEditorModel.new()
	copy.from_map_data(m.to_map_data())
	assert_eq(copy.id, "rt_test")
	assert_eq(copy.tiles[Vector2i(0, 0)]["terrain"], "brush")
	assert_eq(copy.tiles[Vector2i(1, 0)]["elevation"], 4)
	assert_eq(copy.tile_count(), m.tile_count())


func test_round_trip_preserves_zones() -> void:
	var m := MapEditorModel.new()
	m.new_map("rt_z", "standard", "rect", 3)
	m.set_zone(Vector2i(0, 0), "playerA", true)
	m.set_zone(Vector2i(1, 0), "playerB", true)
	var copy := MapEditorModel.new()
	copy.from_map_data(m.to_map_data())
	assert_true(copy.zones["playerA"].has(Vector2i(0, 0)))
	assert_true(copy.zones["playerB"].has(Vector2i(1, 0)))


# --- validate ---

func test_validate_empty_id_returns_error() -> void:
	var m := MapEditorModel.new()
	m.new_map("", "standard", "rect", 2)
	var errors := m.validate()
	assert_gt(errors.size(), 0)


func test_validate_clean_map_returns_no_errors() -> void:
	var m := MapEditorModel.new()
	m.new_map("valid_map", "standard", "rect", 3)
	var errors := m.validate()
	assert_eq(errors.size(), 0)


func test_validate_dangling_zone_returns_error() -> void:
	var m := MapEditorModel.new()
	m.new_map("t", "standard", "rect", 2)
	var dangling: Array[Vector2i] = [Vector2i(99, 99)]
	m.zones["playerA"] = dangling
	var errors := m.validate()
	assert_gt(errors.size(), 0)


# --- metadata ---

func test_set_metadata_changes_id_and_tier() -> void:
	var m := MapEditorModel.new()
	m.new_map("old", "standard", "rect", 2)
	m.set_metadata("new_id", "large")
	assert_eq(m.id, "new_id")
	assert_eq(m.tier, "large")


func test_set_metadata_is_undoable() -> void:
	var m := MapEditorModel.new()
	m.new_map("old", "standard", "rect", 2)
	m.set_metadata("new_id", "large")
	m.undo()
	assert_eq(m.id, "old")
	assert_eq(m.tier, "standard")
