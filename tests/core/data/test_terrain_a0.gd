extends GutTest
## Alpha A0: tests for new terrain types and effect fields loaded from data/terrain.json.

var _pipeline: DataPipeline


func before_all() -> void:
	_pipeline = DataPipeline.new()
	var errors := _pipeline.run("res://data")
	assert_eq(errors.size(), 0, "data pipeline should load without errors")


# --- New A0 terrains exist ---

func test_lava_terrain_exists() -> void:
	var tp := _pipeline.get_terrain("lava")
	assert_not_null(tp, "lava terrain should be loaded")
	assert_eq(tp.damage_per_turn, 4, "lava should deal 4 damage per turn")
	assert_eq(tp.damage_on_enter, 0, "lava should not deal enter damage")


func test_spikes_terrain_exists() -> void:
	var tp := _pipeline.get_terrain("spikes")
	assert_not_null(tp, "spikes terrain should be loaded")
	assert_eq(tp.damage_on_enter, 3, "spikes should deal 3 enter damage")
	assert_eq(tp.damage_per_turn, 0, "spikes should not deal per-turn damage")


func test_bog_terrain_exists() -> void:
	var tp := _pipeline.get_terrain("bog")
	assert_not_null(tp, "bog terrain should be loaded")
	assert_false(tp.status_on_enter.is_empty(), "bog should have status_on_enter")
	assert_eq(tp.status_on_enter.get("status_id", ""), "slowed")
	assert_eq(tp.status_on_enter.get("duration", 0), 1)
	assert_eq(tp.occupant_modifiers.size(), 1, "bog should have 1 occupant modifier")


# --- Existing terrains have neutral A0 defaults ---

func test_grass_has_neutral_defaults() -> void:
	var tp := _pipeline.get_terrain("grass")
	assert_eq(tp.damage_on_enter, 0)
	assert_eq(tp.damage_per_turn, 0)
	assert_true(tp.status_on_enter.is_empty())
	assert_eq(tp.occupant_modifiers.size(), 0)
	assert_false(tp.is_water)
	assert_eq(tp.terrain_tags.size(), 0)


func test_shallow_water_is_water() -> void:
	var tp := _pipeline.get_terrain("shallow_water")
	assert_true(tp.is_water, "shallow_water should have is_water = true")


func test_deep_water_is_water() -> void:
	var tp := _pipeline.get_terrain("deep_water")
	assert_true(tp.is_water, "deep_water should have is_water = true")


func test_trees_has_forest_tag() -> void:
	var tp := _pipeline.get_terrain("trees")
	assert_true("forest" in tp.terrain_tags, "trees should have 'forest' tag")


func test_brush_has_forest_tag() -> void:
	var tp := _pipeline.get_terrain("brush")
	assert_true("forest" in tp.terrain_tags, "brush should have 'forest' tag")


func test_lava_has_hazard_tag() -> void:
	var tp := _pipeline.get_terrain("lava")
	assert_true("hazard" in tp.terrain_tags, "lava should have 'hazard' tag")


# --- Total terrain count ---

func test_terrain_count() -> void:
	assert_eq(_pipeline.terrains.size(), 13, "should have 13 terrain types (10 MVP + 3 A0)")
