extends GutTest
## A18: Tests for movement passives — Jump +1 expands reach; Ignore Hazards skips enter damage.


func _make_movement_ability(id: String, mod_kind: String, stat: String = "",
		value: int = 0) -> AbilityData:
	var ab := AbilityData.new()
	ab.id = id
	ab.type = "passive"
	ab.passive_kind = "movement"
	ab.trigger = {}
	var mod: Dictionary = {"kind": mod_kind}
	if not stat.is_empty():
		mod["stat"] = stat
	if value != 0:
		mod["value"] = value
	ab.modifier = mod
	return ab


func _ability_provider(ab_id: String) -> AbilityData:
	match ab_id:
		"jump_plus_1":
			return _make_movement_ability("jump_plus_1", "stat", "jump", 1)
		"move_plus_1":
			return _make_movement_ability("move_plus_1", "stat", "spd", 1)
		"ignore_hazards":
			return _make_movement_ability("ignore_hazards", "hazard_immune")
	return null


func _make_unit(id: String, spd: int, jump: int, hp: int = 20,
		movement_passive: String = "") -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = []
	c.abilities = []
	c.reaction_passive = ""
	c.support_passive = ""
	c.movement_passive = movement_passive
	var sb := StatBlock.new()
	sb.set_base("spd", spd)
	sb.set_base("jump", jump)
	sb.set_base("hp", hp)
	sb.set_base("atk", 2)
	sb.set_base("def", 1)
	sb.set_base("rng", 1)
	sb.set_base("wp", 0)
	return BattleUnit.from_character(c, sb, _ability_provider)


static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	p.impassable = false
	p.cover = 0
	p.damage_per_turn = 0
	p.damage_on_enter = 0
	return p


func _make_state(units: Array[BattleUnit], map: MapData) -> MatchState:
	var state := MatchSetup.create(units, [], map, _stub_terrain)
	for u in units:
		state.occupancy[u.position] = u
	return state


# --- Jump +1 expands reach ---

func test_jump_plus_1_expands_reachable_tiles() -> void:
	## Build a simple map: flat 0, elevated 1. Jump=0 can't cross; Jump+1 can.
	var map := MapData.new()
	map.id = "jump_test"
	map.tiles = [
		TileRecord.new(0, 0, 0, "grass"),  # start
		TileRecord.new(1, 0, 2, "grass"),  # elevated tile — needs jump >= 2 to reach
		TileRecord.new(2, 0, 0, "grass"),
	]
	map.deployment_zones = {}

	var unit_no_passive := _make_unit("no_passive", 3, 1)  # base jump=1, can cross elev diff 1 but not 2
	var unit_with_passive := _make_unit("with_passive", 3, 1, 20, "jump_plus_1")  # effective jump=2

	unit_no_passive.position = Vector2i(0, 0)
	unit_with_passive.position = Vector2i(0, 0)

	var state_a: Array[BattleUnit] = [unit_no_passive]
	var state_b: Array[BattleUnit] = [unit_with_passive]
	var state1 := _make_state(state_a, map)
	var state2 := _make_state(state_b, map)

	var reach_no_passive: Dictionary = Movement.reachable(
		state1.graph, unit_no_passive.position,
		unit_no_passive.stats.effective_move(),
		unit_no_passive.stats.effective("jump"))

	var reach_with_passive: Dictionary = Movement.reachable(
		state2.graph, unit_with_passive.position,
		unit_with_passive.stats.effective_move(),
		unit_with_passive.stats.effective("jump"))

	# Without Jump+1: base jump=1, elevation diff to tile (1,0)=2, should NOT reach
	assert_false(reach_no_passive.has(Vector2i(1, 0)),
		"Without Jump+1 should not reach elevated tile requiring jump >= 2")

	# With Jump+1: effective jump=2, should reach the elevated tile
	assert_true(reach_with_passive.has(Vector2i(1, 0)),
		"With Jump+1 should reach elevated tile requiring jump >= 2")


func test_move_plus_1_increases_spd() -> void:
	var unit := _make_unit("unit", 3, 1, 20, "move_plus_1")
	assert_eq(unit.stats.effective("spd"), 4, "Move+1 should add 1 to SPD")
	assert_eq(unit.stats.effective_move(), 4)


# --- Ignore Hazards ---

func test_ignore_hazards_flag_set() -> void:
	var unit := _make_unit("unit", 3, 1, 20, "ignore_hazards")
	assert_true(unit.ignores_hazards)


func test_ignore_hazards_takes_no_enter_damage() -> void:
	## Unit with ignore_hazards moving onto a damage_on_enter tile takes no damage.
	var map := MapData.new()
	map.id = "hazard_test"
	map.tiles = [
		TileRecord.new(0, 0, 0, "grass"),
		TileRecord.new(1, 0, 0, "spikes"),  # spikes have damage_on_enter
	]
	map.deployment_zones = {}

	var unit := _make_unit("unit", 3, 1, 20, "ignore_hazards")
	unit.team = "a"
	unit.position = Vector2i(0, 0)

	var tp := func(id: String) -> TerrainProps:
		if id == "spikes":
			var tp2 := TerrainProps.new()
			tp2.id = "spikes"
			tp2.damage_on_enter = 5
			return tp2
		var tp3 := TerrainProps.new()
		tp3.id = id
		return tp3

	var units: Array[BattleUnit] = [unit]
	var state := MatchSetup.create(units, [], map, tp)
	state.occupancy[Vector2i(0, 0)] = unit
	state.current_unit = unit
	unit.ap_remaining = 2

	var result := TurnActions.execute_move(state, Vector2i(1, 0))
	assert_false(result.has("error"), "Move should succeed")

	# HP should be unchanged — ignore_hazards skips spikes damage
	assert_eq(unit.current_hp, 20, "Ignore Hazards: no damage on enter")
	assert_false(result.has("terrain_effects") and not result["terrain_effects"].is_empty(),
		"No terrain damage outcome expected")


func test_no_hazard_flag_takes_enter_damage() -> void:
	## Verify the baseline: without ignore_hazards, spikes damage applies.
	var map := MapData.new()
	map.id = "hazard_test"
	map.tiles = [
		TileRecord.new(0, 0, 0, "grass"),
		TileRecord.new(1, 0, 0, "spikes"),
	]
	map.deployment_zones = {}

	var unit := _make_unit("unit", 3, 1, 20)  # no passive
	unit.team = "a"
	unit.position = Vector2i(0, 0)

	var tp := func(id: String) -> TerrainProps:
		if id == "spikes":
			var tp2 := TerrainProps.new()
			tp2.id = "spikes"
			tp2.damage_on_enter = 5
			return tp2
		var tp3 := TerrainProps.new()
		tp3.id = id
		return tp3

	var units: Array[BattleUnit] = [unit]
	var state := MatchSetup.create(units, [], map, tp)
	state.occupancy[Vector2i(0, 0)] = unit
	state.current_unit = unit
	unit.ap_remaining = 2

	var result := TurnActions.execute_move(state, Vector2i(1, 0))
	assert_false(result.has("error"))
	assert_eq(unit.current_hp, 15, "Without Ignore Hazards: 5 damage from spikes")
