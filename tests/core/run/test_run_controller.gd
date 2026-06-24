extends GutTest

# --- Helpers ---

var _ctrl: RunController


func before_each() -> void:
	_ctrl = RunController.new()


func _make_instance(id: String, downs: int = 0) -> CharacterInstance:
	var ci := CharacterInstance.new()
	ci.instance_id = id
	ci.template_id = "tmpl_human"
	ci.name = "Hero " + id
	ci.race = "human"
	ci.level = 3
	ci.xp = 0
	ci.active_class = "vagabond"
	ci.unlocked_classes = ["vagabond"] as Array[String]
	ci.jp = {"vagabond": 0}
	ci.downs_this_run = downs
	return ci


func _make_band(instances: Array[CharacterInstance], gold: int = 200) -> BattleBand:
	var band := BattleBand.create("Test Band")
	band.gold = gold
	for ci in instances:
		band.add_instance(ci)
	return band


func _make_run_with_graph() -> RunState:
	# Build a simple manual graph: start -> battle -> boss
	var rs := RunState.new()
	rs.run_id = "test_run"
	rs.band_id = "bb_1"
	rs.seed_value = 42
	rs.down_limit = 2
	rs.depth = 0
	var g := RunGraph.new()
	g.nodes["s"] = {"id": "s", "column": 0, "row": 0, "kind": "start"}
	g.nodes["b1"] = {"id": "b1", "column": 1, "row": 0, "kind": "battle"}
	g.nodes["ev"] = {"id": "ev", "column": 1, "row": 1, "kind": "event"}
	g.nodes["sh"] = {"id": "sh", "column": 2, "row": 0, "kind": "shop"}
	g.nodes["re"] = {"id": "re", "column": 2, "row": 1, "kind": "rest"}
	g.nodes["bo"] = {"id": "bo", "column": 3, "row": 0, "kind": "boss"}
	g.edges = [
		{"from": "s", "to": "b1"}, {"from": "s", "to": "ev"},
		{"from": "b1", "to": "sh"}, {"from": "b1", "to": "re"},
		{"from": "ev", "to": "sh"}, {"from": "ev", "to": "re"},
		{"from": "sh", "to": "bo"}, {"from": "re", "to": "bo"},
	]
	rs.graph = g
	rs.position = "s"
	rs.visited = ["s"]
	return rs


func _make_template(id: String) -> CharacterData:
	var c := CharacterData.new()
	c.id = id
	c.race = "human"
	c.display_name = "Template " + id
	c.classes = ["vagabond"]
	c.abilities = []
	c.equipment = []
	return c


func _make_map(id: String, tier: String) -> MapData:
	var m := MapData.new()
	m.id = id
	m.tier = tier
	m.tiles = [TileRecord.new(0, 0, 0, "grass")]
	return m


func _stub_class(_id: String) -> ClassData:
	var cd := ClassData.new()
	cd.id = "vagabond"
	cd.display_name = "Vagabond"
	cd.stat_modifiers = {}
	cd.growth = {}
	return cd


func _test_ctx() -> Dictionary:
	var events_data: Dictionary = {
		"events": [{"id": "test_ev", "kind": "event", "text": "Test",
			"effects": [{"type": "gold", "value": 10}]}],
		"boons": [],
		"hazards": [],
	}
	return {
		"events_data": events_data,
		"providers": {
			"all_maps": func() -> Array: return [_make_map("m1", "skirmish")],
			"all_characters": func() -> Array: return [_make_template("t1")],
			"class_provider": _stub_class,
			"name_gen": func(_r: String) -> String: return "Enemy",
			"run_config": {
				"depth_bp_curve": [30, 40, 50],
				"boss_bp_multiplier": 1.5,
				"enemy_count_range": [2, 3],
				"depth_tier_map": {"0": "skirmish"},
				"xp_per_battle": 30,
				"jp_per_battle": 20,
				"loot_table_by_kind": {"battle": "standard_battle", "boss": "boss_battle"},
			},
		},
		"fielded_ids": [],
	}


# --- Tests ---

func test_advance_to_battle_returns_encounter() -> void:
	var rs: RunState = _make_run_with_graph()
	var band: BattleBand = _make_band([_make_instance("ci_1")])
	var result: Dictionary = _ctrl.advance_to(rs, "b1", band, _test_ctx())
	assert_eq(str(result["kind"]), "battle")
	assert_true(result.has("encounter"))
	assert_eq(rs.position, "b1")
	assert_eq(rs.depth, 1)


func test_advance_to_event_applies_effects() -> void:
	var rs: RunState = _make_run_with_graph()
	var band: BattleBand = _make_band([_make_instance("ci_1")], 100)
	var result: Dictionary = _ctrl.advance_to(rs, "ev", band, _test_ctx())
	assert_eq(str(result["kind"]), "event")
	assert_true(result.has("outcome"))
	# Event gives +10 gold
	assert_eq(band.gold, 110)


func test_advance_to_shop_returns_shop() -> void:
	var rs: RunState = _make_run_with_graph()
	rs.position = "b1"  # move past start
	rs.visited.append("b1")
	var band: BattleBand = _make_band([_make_instance("ci_1")])
	var result: Dictionary = _ctrl.advance_to(rs, "sh", band, _test_ctx())
	assert_eq(str(result["kind"]), "shop")


func test_advance_to_rest_reduces_downs() -> void:
	var ci: CharacterInstance = _make_instance("ci_1", 2)
	var rs: RunState = _make_run_with_graph()
	rs.position = "b1"
	rs.visited.append("b1")
	var band: BattleBand = _make_band([ci])
	var result: Dictionary = _ctrl.advance_to(rs, "re", band, _test_ctx())
	assert_eq(str(result["kind"]), "rest")
	assert_eq(ci.downs_this_run, 1)  # reduced from 2
	assert_has(result["healed"] as Array, "ci_1")


func test_advance_to_invalid_returns_error() -> void:
	var rs: RunState = _make_run_with_graph()
	var band: BattleBand = _make_band([_make_instance("ci_1")])
	var result: Dictionary = _ctrl.advance_to(rs, "bo", band, _test_ctx())
	assert_eq(str(result["kind"]), "error")
	assert_eq(rs.position, "s")  # unchanged


func test_on_battle_end_win_returns_continue() -> void:
	var rs: RunState = _make_run_with_graph()
	rs.position = "b1"
	rs.depth = 1
	var band: BattleBand = _make_band([_make_instance("ci_1")])
	var battle_result: Dictionary = {
		"player_won": true,
		"downed_instance_ids": [],
	}
	var result: Dictionary = _ctrl.on_battle_end(rs, band, battle_result, _test_ctx())
	assert_eq(str(result["status"]), "continue")


func test_on_battle_end_loss_returns_defeat() -> void:
	var ci: CharacterInstance = _make_instance("ci_1", 2)
	var rs: RunState = _make_run_with_graph()
	rs.position = "b1"
	rs.depth = 1
	var band: BattleBand = _make_band([ci])
	var battle_result: Dictionary = {
		"player_won": false,
		"downed_instance_ids": ["ci_1"],
	}
	var result: Dictionary = _ctrl.on_battle_end(rs, band, battle_result, _test_ctx())
	# ci_1 goes from 2 to 3 downs (exceeds limit 2) → permadeath → roster empty → defeat
	assert_eq(str(result["status"]), "defeat")
	assert_has(result["deaths"] as Array, "ci_1")


func test_on_battle_end_boss_win_returns_victory() -> void:
	var rs: RunState = _make_run_with_graph()
	rs.position = "bo"  # at boss node
	rs.depth = 3
	var band: BattleBand = _make_band([_make_instance("ci_1")])
	var battle_result: Dictionary = {
		"player_won": true,
		"downed_instance_ids": [],
	}
	var result: Dictionary = _ctrl.on_battle_end(rs, band, battle_result, _test_ctx())
	assert_eq(str(result["status"]), "victory")


func test_on_battle_end_applies_downs() -> void:
	var ci: CharacterInstance = _make_instance("ci_1", 0)
	var rs: RunState = _make_run_with_graph()
	rs.position = "b1"
	rs.depth = 1
	var band: BattleBand = _make_band([ci])
	var battle_result: Dictionary = {
		"player_won": true,
		"downed_instance_ids": ["ci_1"],
	}
	_ctrl.on_battle_end(rs, band, battle_result, _test_ctx())
	assert_eq(ci.downs_this_run, 1)
