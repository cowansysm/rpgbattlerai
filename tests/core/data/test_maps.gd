extends GutTest
const SharedPipeline = preload("res://tests/helpers/shared_pipeline.gd")
## Phase 6: Verify all maps load, have correct deployment zones, and meet tier sizing.

var _pipeline: DataPipeline

var _tier_max: Dictionary = {
	"skirmish": 5,
	"standard": 8,
	"large": 12,
}

var _map_ids: Array[String] = [
	"mountain_pass", "ruined_watchtower",
	"forest_clearing", "sunken_courtyard",
	"open_plains", "river_crossing",
]


func before_all() -> void:
	_pipeline = SharedPipeline.get_pipeline()
	assert_eq(SharedPipeline.load_errors().size(), 0, "data should load with zero errors")


# --- Map Loading ---

func test_all_maps_load() -> void:
	for id in _map_ids:
		var m := _pipeline.get_map(id)
		assert_not_null(m, "Map '%s' should load" % id)


func test_map_count() -> void:
	assert_eq(_pipeline.maps.size(), 6, "should have 6 maps total")


func test_two_maps_per_tier() -> void:
	var tier_counts: Dictionary = {}
	for id in _map_ids:
		var m := _pipeline.get_map(id)
		if not m:
			continue
		var t: String = m.tier
		tier_counts[t] = tier_counts.get(t, 0) + 1
	assert_eq(tier_counts.get("skirmish", 0), 2, "2 skirmish maps")
	assert_eq(tier_counts.get("standard", 0), 2, "2 standard maps")
	assert_eq(tier_counts.get("large", 0), 2, "2 large maps")


# --- Deployment Zone Sizing ---

func test_deployment_zones_meet_tier_max() -> void:
	for id in _map_ids:
		var m := _pipeline.get_map(id)
		if not m:
			continue
		var required: int = _tier_max.get(m.tier, 0)
		for team in ["playerA", "playerB"]:
			var zone: Array = m.deployment_zones.get(team, [])
			assert_gte(zone.size(), required,
				"Map '%s' (%s) %s zone should have >= %d tiles, has %d" % [
					id, m.tier, team, required, zone.size()])


func test_deployment_zone_tiles_exist_on_map() -> void:
	for id in _map_ids:
		var m := _pipeline.get_map(id)
		if not m:
			continue
		var tile_coords: Dictionary = {}
		for t: TileRecord in m.tiles:
			tile_coords[Vector2i(t.q, t.r)] = true
		for team in ["playerA", "playerB"]:
			var zone: Array = m.deployment_zones.get(team, [])
			for s in zone:
				var parts := str(s).split(",")
				var coord := Vector2i(int(parts[0]), int(parts[1]))
				assert_true(tile_coords.has(coord),
					"Map '%s' %s zone tile %s should exist in tile array" % [
						id, team, str(coord)])


func test_deployment_zone_tiles_are_traversable() -> void:
	for id in _map_ids:
		var m := _pipeline.get_map(id)
		if not m:
			continue
		var tile_terrain: Dictionary = {}
		for t: TileRecord in m.tiles:
			tile_terrain[Vector2i(t.q, t.r)] = t.terrain
		for team in ["playerA", "playerB"]:
			var zone: Array = m.deployment_zones.get(team, [])
			for s in zone:
				var parts := str(s).split(",")
				var coord := Vector2i(int(parts[0]), int(parts[1]))
				var terrain_id: String = tile_terrain.get(coord, "")
				var tp: TerrainProps = _pipeline.get_terrain(terrain_id)
				if tp:
					assert_false(tp.impassable,
						"Map '%s' %s zone tile %s ('%s') should be traversable" % [
							id, team, str(coord), terrain_id])


func test_deployment_zones_do_not_overlap() -> void:
	for id in _map_ids:
		var m := _pipeline.get_map(id)
		if not m:
			continue
		var zone_a: Array = m.deployment_zones.get("playerA", [])
		var zone_b: Array = m.deployment_zones.get("playerB", [])
		for s in zone_a:
			assert_false(zone_b.has(s),
				"Map '%s' tile %s should not be in both deployment zones" % [id, s])


# --- Map Tile Counts ---

func test_skirmish_map_sizes() -> void:
	for id in ["mountain_pass", "ruined_watchtower"]:
		var m := _pipeline.get_map(id)
		if not m:
			continue
		assert_gte(m.tiles.size(), 30,
			"Skirmish map '%s' should have >= 30 tiles" % id)
		assert_lte(m.tiles.size(), 50,
			"Skirmish map '%s' should have <= 50 tiles" % id)


func test_standard_map_sizes() -> void:
	for id in ["forest_clearing", "sunken_courtyard"]:
		var m := _pipeline.get_map(id)
		if not m:
			continue
		assert_gte(m.tiles.size(), 45,
			"Standard map '%s' should have >= 45 tiles" % id)
		assert_lte(m.tiles.size(), 80,
			"Standard map '%s' should have <= 80 tiles" % id)


func test_large_map_sizes() -> void:
	for id in ["open_plains", "river_crossing"]:
		var m := _pipeline.get_map(id)
		if not m:
			continue
		assert_gte(m.tiles.size(), 80,
			"Large map '%s' should have >= 80 tiles" % id)
		assert_lte(m.tiles.size(), 120,
			"Large map '%s' should have <= 120 tiles" % id)


# --- Tile Uniqueness ---

func test_no_duplicate_tile_coordinates() -> void:
	for id in _map_ids:
		var m := _pipeline.get_map(id)
		if not m:
			continue
		var seen: Dictionary = {}
		for t: TileRecord in m.tiles:
			var coord := Vector2i(t.q, t.r)
			assert_false(seen.has(coord),
				"Map '%s' has duplicate tile at %s" % [id, str(coord)])
			seen[coord] = true


# --- Terrain References ---

func test_all_tile_terrains_are_valid() -> void:
	for id in _map_ids:
		var m := _pipeline.get_map(id)
		if not m:
			continue
		for t: TileRecord in m.tiles:
			var tp := _pipeline.get_terrain(t.terrain)
			assert_not_null(tp,
				"Map '%s' tile (%d,%d) terrain '%s' should be valid" % [
					id, t.q, t.r, t.terrain])
