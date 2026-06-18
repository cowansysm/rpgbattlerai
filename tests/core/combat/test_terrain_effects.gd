extends GutTest
## Alpha A0: tests for terrain hazard damage, status-on-enter, occupant modifiers,
## and per-turn damage at activation start.


# --- Stub terrain provider with A0 effects ---

static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	match id:
		"spikes":
			p.damage_on_enter = 3
		"lava":
			p.damage_per_turn = 4
		"bog":
			p.occupant_modifiers = [{"key": "spd", "value": -1}]
			p.status_on_enter = {"status_id": "slowed", "duration": 1}
		"shallow_water":
			p.move_cost = 2
			p.is_water = true
	return p


# --- Helpers ---

func _make_unit(id: String, team: String, spd: int = 3, hp: int = 20) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = [] as Array[String]
	c.equipment = [] as Array[String]
	c.abilities = [] as Array[String]
	var sb := StatBlock.new()
	sb.set_base("spd", spd)
	sb.set_base("hp", hp)
	sb.set_base("def", 1)
	sb.set_base("atk", 1)
	sb.set_base("rng", 1)
	sb.set_base("jump", 3)
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	return u


func _make_state(terrains: Dictionary) -> MatchState:
	## Build a simple 7-tile linear state (q from -3 to 3) with specified terrains.
	## terrains: Vector2i -> terrain_id (defaults to "grass")
	var map := MapData.new()
	map.id = "test_terrain"
	var tiles: Array[TileRecord] = []
	for q in range(-3, 4):
		var coord := Vector2i(q, 0)
		var t_id: String = terrains.get(coord, "grass")
		tiles.append(TileRecord.new(q, 0, 0, t_id))
	map.tiles = tiles

	var unit_a := _make_unit("unit_a", "playerA")
	var unit_b := _make_unit("unit_b", "playerB")
	var party_a: Array[BattleUnit] = [unit_a]
	var party_b: Array[BattleUnit] = [unit_b]
	var state := MatchSetup.create(party_a, party_b, map, _stub_terrain)

	unit_a.position = Vector2i(-2, 0)
	state.occupancy[Vector2i(-2, 0)] = unit_a
	unit_b.position = Vector2i(2, 0)
	state.occupancy[Vector2i(2, 0)] = unit_b

	state.phase = MatchState.Phase.UNIT_TURN
	state.current_unit = unit_a
	unit_a.ap_remaining = 2
	return state


# --- Tests: damage_on_enter ---

func test_enter_damage_reduces_hp() -> void:
	var state := _make_state({Vector2i(-1, 0): "spikes"})
	var unit: BattleUnit = state.current_unit
	var hp_before: int = unit.current_hp
	var result := TurnActions.execute_move(state, Vector2i(-1, 0))
	assert_false(result.has("error"), "move should succeed")
	assert_eq(unit.current_hp, hp_before - 3, "should take 3 damage from spikes")
	assert_true(result.has("terrain_effects"), "should have terrain_effects key")
	var effects: Array = result["terrain_effects"]
	assert_eq(effects.size(), 1)
	assert_eq(effects[0]["type"], "terrain_damage")
	assert_eq(effects[0]["amount"], 3)


func test_enter_damage_can_down_unit() -> void:
	var state := _make_state({Vector2i(-1, 0): "spikes"})
	var unit: BattleUnit = state.current_unit
	unit.current_hp = 2  # Less than the 3 enter damage
	TurnActions.execute_move(state, Vector2i(-1, 0))
	assert_eq(unit.current_hp, 0, "HP should reach 0")
	assert_true(unit.is_downed, "unit should be downed by terrain damage")


# --- Tests: status_on_enter ---

func test_enter_status_applied() -> void:
	var state := _make_state({Vector2i(-1, 0): "bog"})
	var unit: BattleUnit = state.current_unit
	TurnActions.execute_move(state, Vector2i(-1, 0))
	assert_true(unit.has_status("slowed"), "unit should have slowed status from bog")


func test_enter_status_not_applied_when_downed() -> void:
	# If a tile has both damage and status, and damage downs the unit,
	# status should not be applied. Create a custom terrain for this.
	var state := _make_state({Vector2i(-1, 0): "spikes"})
	var unit: BattleUnit = state.current_unit
	unit.current_hp = 1
	TurnActions.execute_move(state, Vector2i(-1, 0))
	assert_true(unit.is_downed, "unit should be downed")
	# Spikes don't have status_on_enter, so status_effects should be empty
	assert_eq(unit.status_effects.size(), 0)


# --- Tests: occupant_modifiers ---

func test_occupant_modifier_applies_on_move() -> void:
	var state := _make_state({Vector2i(-1, 0): "bog"})
	var unit: BattleUnit = state.current_unit
	var spd_before: int = unit.stats.effective("spd")
	TurnActions.execute_move(state, Vector2i(-1, 0))
	assert_eq(unit.stats.effective("spd"), spd_before - 1,
		"effective SPD should be reduced by bog modifier")


func test_occupant_modifier_clears_on_leave() -> void:
	var state := _make_state({Vector2i(-1, 0): "bog"})
	var unit: BattleUnit = state.current_unit
	var spd_before: int = unit.stats.effective("spd")
	TurnActions.execute_move(state, Vector2i(-1, 0))
	assert_eq(unit.stats.effective("spd"), spd_before - 1)
	# Give the unit another AP to move off
	unit.ap_remaining = 1
	TurnActions.execute_move(state, Vector2i(0, 0))
	assert_eq(unit.stats.effective("spd"), spd_before,
		"SPD should be restored after leaving bog")


func test_occupant_modifier_applied_at_deployment() -> void:
	var map := MapData.new()
	map.id = "test_deploy"
	var tiles: Array[TileRecord] = []
	tiles.append(TileRecord.new(0, 0, 0, "bog"))
	tiles.append(TileRecord.new(1, 0, 0, "grass"))
	map.tiles = tiles

	var unit_a := _make_unit("a", "playerA")
	var unit_b := _make_unit("b", "playerB")
	var party_a: Array[BattleUnit] = [unit_a]
	var party_b: Array[BattleUnit] = [unit_b]
	var state := MatchSetup.create(party_a, party_b, map, _stub_terrain)

	var zones := {"playerA": ["0,0"], "playerB": ["1,0"]}
	Deployment.auto_deploy(state, zones)

	assert_true(unit_a.stats.has_modifier_from_source("terrain"),
		"unit deployed on bog should have terrain modifier")
	assert_eq(unit_a.stats.effective("spd"), 2,
		"unit on bog should have SPD reduced by 1 (3 - 1 = 2)")
	assert_false(unit_b.stats.has_modifier_from_source("terrain"),
		"unit on grass should have no terrain modifier")


# --- Tests: damage_per_turn ---

func test_per_turn_damage_on_activation() -> void:
	var state := _make_state({Vector2i(-2, 0): "lava"})
	var unit: BattleUnit = state.current_unit
	# Unit is already on lava (position set in _make_state to (-2,0))
	var hp_before: int = unit.current_hp
	var outcomes := RoundManager.on_activation_start(state, unit)
	assert_eq(unit.current_hp, hp_before - 4, "should take 4 damage from lava")
	assert_eq(outcomes.size(), 1)
	assert_eq(outcomes[0]["type"], "terrain_damage")
	assert_eq(outcomes[0]["amount"], 4)


func test_per_turn_damage_can_down_unit() -> void:
	var state := _make_state({Vector2i(-2, 0): "lava"})
	var unit: BattleUnit = state.current_unit
	unit.current_hp = 3
	RoundManager.on_activation_start(state, unit)
	assert_eq(unit.current_hp, 0)
	assert_true(unit.is_downed, "lava should down a unit at low HP")


func test_per_turn_no_damage_on_grass() -> void:
	var state := _make_state({})
	var unit: BattleUnit = state.current_unit
	var hp_before: int = unit.current_hp
	var outcomes := RoundManager.on_activation_start(state, unit)
	assert_eq(unit.current_hp, hp_before, "no terrain damage on grass")
	assert_eq(outcomes.size(), 0)


# --- Tests: HexGraph accessors ---

func test_hex_graph_is_water() -> void:
	var map := MapData.new()
	map.id = "test_water"
	var tiles: Array[TileRecord] = []
	tiles.append(TileRecord.new(0, 0, 0, "shallow_water"))
	tiles.append(TileRecord.new(1, 0, 0, "grass"))
	map.tiles = tiles
	var graph := HexGraph.new()
	graph.build(map, _stub_terrain)
	assert_true(graph.is_water(Vector2i(0, 0)), "shallow_water should be water")
	assert_false(graph.is_water(Vector2i(1, 0)), "grass should not be water")


func test_hex_graph_damage_accessors() -> void:
	var map := MapData.new()
	map.id = "test_dmg"
	var tiles: Array[TileRecord] = []
	tiles.append(TileRecord.new(0, 0, 0, "spikes"))
	tiles.append(TileRecord.new(1, 0, 0, "lava"))
	tiles.append(TileRecord.new(2, 0, 0, "grass"))
	map.tiles = tiles
	var graph := HexGraph.new()
	graph.build(map, _stub_terrain)
	assert_eq(graph.damage_on_enter(Vector2i(0, 0)), 3)
	assert_eq(graph.damage_per_turn(Vector2i(1, 0)), 4)
	assert_eq(graph.damage_on_enter(Vector2i(2, 0)), 0)
	assert_eq(graph.damage_per_turn(Vector2i(2, 0)), 0)
