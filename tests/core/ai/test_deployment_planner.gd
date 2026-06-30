extends GutTest
## Tests for DeploymentPlanner: role-based positioning, terrain scoring.


# --- Terrain providers ---

static func _grass_terrain(_id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = "grass"
	p.move_cost = 1
	return p


static func _mixed_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	match id:
		"cover_terrain":
			p.cover = 2
		"lava":
			p.damage_per_turn = 5
		"spikes":
			p.damage_on_enter = 3
	return p


# --- Helpers ---

func _make_unit(id: String, team: String, atk: int = 5, mag: int = 2,
	rng: int = 1) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = []
	c.abilities = []
	var sb := StatBlock.new()
	sb.set_base("spd", 3)
	sb.set_base("hp", 10)
	sb.set_base("def", 1)
	sb.set_base("atk", atk)
	sb.set_base("mag", mag)
	sb.set_base("rng", rng)
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	return u


func _build_state_with_tiles(
	tile_defs: Array,  # Array of [Vector2i, int, String] = [coord, elev, terrain]
	party_a: Array[BattleUnit],
	party_b: Array[BattleUnit],
	terrain_provider: Callable,
) -> MatchState:
	var map := MapData.new()
	map.id = "test"
	var tiles: Array[TileRecord] = []
	for td in tile_defs:
		tiles.append(TileRecord.new(td[0].x, td[0].y, td[1], td[2]))
	map.tiles = tiles
	return MatchSetup.create(party_a, party_b, map, terrain_provider)


var _default_weights: Dictionary = {
	"frontline": 6.0, "cover": 4.0, "elevation": 2.0,
	"hazard": 8.0, "spacing": 2.0,
}


# --- Tests ---

func test_melee_picks_forward_tile() -> void:
	# Two legal tiles: one close to enemy zone, one far
	var close := Vector2i(0, 0)
	var far := Vector2i(0, -3)
	var enemy_zone: Array[Vector2i] = [Vector2i(0, 3)]
	var tile_defs := [
		[close, 0, "grass"],
		[far, 0, "grass"],
		[Vector2i(0, 3), 0, "grass"],
	]
	var unit := _make_unit("melee", "playerA", 5, 2, 1)  # ATK > MAG, rng=1 = melee
	var state := _build_state_with_tiles(
		tile_defs, [unit], [_make_unit("e1", "playerB")], _grass_terrain)

	var legal: Array[Vector2i] = [close, far]
	var result := DeploymentPlanner.choose(state, "playerA", unit, legal, enemy_zone, _default_weights)
	assert_eq(result, close, "melee should pick tile closer to enemy")


func test_ranged_picks_back_tile() -> void:
	var close := Vector2i(0, 0)
	var far := Vector2i(0, -3)
	var enemy_zone: Array[Vector2i] = [Vector2i(0, 3)]
	var tile_defs := [
		[close, 0, "grass"],
		[far, 0, "grass"],
		[Vector2i(0, 3), 0, "grass"],
	]
	var unit := _make_unit("ranged", "playerA", 3, 2, 3)  # rng=3 = ranged
	var state := _build_state_with_tiles(
		tile_defs, [unit], [_make_unit("e1", "playerB")], _grass_terrain)

	var legal: Array[Vector2i] = [close, far]
	var result := DeploymentPlanner.choose(state, "playerA", unit, legal, enemy_zone, _default_weights)
	assert_eq(result, far, "ranged should pick tile farther from enemy")


func test_prefers_cover() -> void:
	var plain := Vector2i(0, -2)
	var covered := Vector2i(1, -2)
	var enemy_zone: Array[Vector2i] = [Vector2i(0, 3)]
	# Both tiles equidistant from enemy, but one has cover terrain
	var tile_defs := [
		[plain, 0, "grass"],
		[covered, 0, "cover_terrain"],
		[Vector2i(0, 3), 0, "grass"],
	]
	var unit := _make_unit("tank", "playerA", 5, 2, 1)
	var state := _build_state_with_tiles(
		tile_defs, [unit], [_make_unit("e1", "playerB")], _mixed_terrain)

	var legal: Array[Vector2i] = [plain, covered]
	var result := DeploymentPlanner.choose(state, "playerA", unit, legal, enemy_zone, _default_weights)
	assert_eq(result, covered, "should prefer tile with cover")


func test_prefers_elevation() -> void:
	var low := Vector2i(0, -2)
	var high := Vector2i(1, -2)
	var enemy_zone: Array[Vector2i] = [Vector2i(0, 3)]
	var tile_defs := [
		[low, 0, "grass"],
		[high, 2, "grass"],  # Elevated
		[Vector2i(0, 3), 0, "grass"],
	]
	var unit := _make_unit("archer", "playerA", 3, 2, 3)  # Ranged
	var state := _build_state_with_tiles(
		tile_defs, [unit], [_make_unit("e1", "playerB")], _grass_terrain)

	var legal: Array[Vector2i] = [low, high]
	# Both are roughly equidistant; high tile should win due to elevation bonus
	var result := DeploymentPlanner.choose(state, "playerA", unit, legal, enemy_zone, _default_weights)
	assert_eq(result, high, "should prefer elevated tile")


func test_avoids_hazard() -> void:
	var safe := Vector2i(0, -2)
	var hazard := Vector2i(1, -2)
	var enemy_zone: Array[Vector2i] = [Vector2i(0, 3)]
	var tile_defs := [
		[safe, 0, "grass"],
		[hazard, 0, "lava"],  # damage_per_turn = 5
		[Vector2i(0, 3), 0, "grass"],
	]
	var unit := _make_unit("tank", "playerA", 5, 2, 1)
	var state := _build_state_with_tiles(
		tile_defs, [unit], [_make_unit("e1", "playerB")], _mixed_terrain)

	var legal: Array[Vector2i] = [safe, hazard]
	var result := DeploymentPlanner.choose(state, "playerA", unit, legal, enemy_zone, _default_weights)
	assert_eq(result, safe, "should avoid hazardous tile")


func test_anti_clustering() -> void:
	var adjacent := Vector2i(1, 0)
	var spread := Vector2i(-2, 0)
	var enemy_zone: Array[Vector2i] = [Vector2i(0, 3)]
	var tile_defs := [
		[Vector2i(0, 0), 0, "grass"],  # Ally already placed here
		[adjacent, 0, "grass"],         # Adjacent to ally
		[spread, 0, "grass"],           # Far from ally
		[Vector2i(0, 3), 0, "grass"],
	]
	var ally := _make_unit("ally", "playerA", 5, 2, 1)
	var unit := _make_unit("next", "playerA", 5, 2, 1)
	var state := _build_state_with_tiles(
		tile_defs, [ally, unit], [_make_unit("e1", "playerB")], _grass_terrain)
	# Place the ally first
	ally.position = Vector2i(0, 0)
	state.occupancy[Vector2i(0, 0)] = ally

	var legal: Array[Vector2i] = [adjacent, spread]
	# Use high spacing weight to make anti-clustering dominant
	var weights := _default_weights.duplicate()
	weights["spacing"] = 20.0
	weights["frontline"] = 1.0  # Reduce frontline influence
	var result := DeploymentPlanner.choose(state, "playerA", unit, legal, enemy_zone, weights)
	assert_eq(result, spread, "should prefer tile away from allies")


func test_deterministic() -> void:
	var tile_a := Vector2i(0, -2)
	var tile_b := Vector2i(1, -2)
	var enemy_zone: Array[Vector2i] = [Vector2i(0, 3)]
	var tile_defs := [
		[tile_a, 0, "grass"],
		[tile_b, 0, "grass"],
		[Vector2i(0, 3), 0, "grass"],
	]
	var unit := _make_unit("tank", "playerA", 5, 2, 1)
	var state := _build_state_with_tiles(
		tile_defs, [unit], [_make_unit("e1", "playerB")], _grass_terrain)

	var legal: Array[Vector2i] = [tile_a, tile_b]
	var r1 := DeploymentPlanner.choose(state, "playerA", unit, legal, enemy_zone, _default_weights)
	var r2 := DeploymentPlanner.choose(state, "playerA", unit, legal, enemy_zone, _default_weights)
	assert_eq(r1, r2, "same inputs should produce same output")
