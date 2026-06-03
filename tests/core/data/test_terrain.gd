extends GutTest
## Tests for TerrainProps, TerrainRegistry, and terrain validation.


# --- TerrainRegistry loading ---

func test_load_from_valid_file() -> void:
	var reg := TerrainRegistry.new()
	var errors := reg.load_from("res://tests/fixtures/valid_set/terrain.json")
	assert_eq(errors.size(), 0, "valid terrain file should produce zero errors")
	assert_eq(reg.size(), 8, "should load 8 terrain types")


func test_loaded_terrain_has_correct_values() -> void:
	var reg := TerrainRegistry.new()
	reg.load_from("res://tests/fixtures/valid_set/terrain.json")
	var trees := reg.get_entry("trees")
	assert_not_null(trees, "trees terrain should exist")
	assert_eq(trees.id, "trees")
	assert_eq(trees.move_cost, 2)
	assert_false(trees.impassable)
	assert_true(trees.blocks_los)
	assert_eq(trees.cover, 1)
	assert_eq(trees.los_height, 2)


func test_impassable_terrain() -> void:
	var reg := TerrainRegistry.new()
	reg.load_from("res://tests/fixtures/valid_set/terrain.json")
	var rocks := reg.get_entry("rocks")
	assert_true(rocks.impassable, "rocks should be impassable")
	assert_true(rocks.blocks_los, "rocks should block LoS")
	assert_eq(rocks.los_height, 3)


func test_get_entry_unknown_falls_back_to_grass() -> void:
	var reg := TerrainRegistry.new()
	reg.load_from("res://tests/fixtures/valid_set/terrain.json")
	var fallback := reg.get_entry("nonexistent_terrain")
	assert_not_null(fallback, "unknown terrain should fall back to grass")
	assert_eq(fallback.id, "grass")


func test_has_returns_correct() -> void:
	var reg := TerrainRegistry.new()
	reg.load_from("res://tests/fixtures/valid_set/terrain.json")
	assert_true(reg.has("grass"))
	assert_true(reg.has("rocks"))
	assert_false(reg.has("lava"))


func test_load_missing_file_returns_error() -> void:
	var reg := TerrainRegistry.new()
	var errors := reg.load_from("res://nonexistent/terrain.json")
	assert_true(errors.size() > 0, "missing file should produce an error")


func test_all_terrain_ids() -> void:
	var reg := TerrainRegistry.new()
	reg.load_from("res://tests/fixtures/valid_set/terrain.json")
	var ids := reg.ids()
	assert_true("grass" in ids)
	assert_true("road" in ids)
	assert_true("brush" in ids)
	assert_true("trees" in ids)
	assert_true("rocks" in ids)
	assert_true("shallow_water" in ids)
	assert_true("deep_water" in ids)
	assert_true("cliff" in ids)


# --- Terrain referential validation ---

func test_terrain_ref_validation_passes_for_valid_set() -> void:
	var pipeline := DataPipeline.new()
	var errors := pipeline.run("res://tests/fixtures/valid_set")
	assert_eq(errors.size(), 0, "valid set should have no errors including terrain refs")
