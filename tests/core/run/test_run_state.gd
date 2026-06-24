extends GutTest

# --- Helpers ---

func _make_graph() -> RunGraph:
	var g := RunGraph.new()
	g.nodes["s"] = {"id": "s", "column": 0, "row": 0, "kind": "start"}
	g.nodes["a"] = {"id": "a", "column": 1, "row": 0, "kind": "battle"}
	g.nodes["b"] = {"id": "b", "column": 1, "row": 1, "kind": "shop"}
	g.nodes["c"] = {"id": "c", "column": 2, "row": 0, "kind": "boss"}
	g.edges = [
		{"from": "s", "to": "a"}, {"from": "s", "to": "b"},
		{"from": "a", "to": "c"}, {"from": "b", "to": "c"},
	]
	return g


func _make_run_state() -> RunState:
	var rs := RunState.new()
	rs.run_id = "test_run_1"
	rs.band_id = "bb_1"
	rs.seed_value = 12345
	rs.graph = _make_graph()
	rs.position = "s"
	rs.depth = 0
	rs.down_limit = 2
	rs.visited = ["s"]
	return rs


# --- Tests ---

func test_to_dict_from_dict_round_trip() -> void:
	var rs: RunState = _make_run_state()
	var d: Dictionary = rs.to_dict()
	var restored: RunState = RunState.from_dict(d)
	assert_eq(restored.run_id, "test_run_1")
	assert_eq(restored.band_id, "bb_1")
	assert_eq(restored.seed_value, 12345)
	assert_eq(restored.position, "s")
	assert_eq(restored.depth, 0)
	assert_eq(restored.down_limit, 2)
	assert_eq(restored.visited.size(), 1)
	assert_eq(restored.visited[0], "s")
	# Graph preserved
	assert_eq(restored.graph.nodes.size(), 4)
	assert_eq(restored.graph.edges.size(), 4)
	assert_eq(str(restored.graph.start_node()["kind"]), "start")


func test_round_trip_through_json() -> void:
	var rs: RunState = _make_run_state()
	var json_str: String = JSON.stringify(rs.to_dict())
	var parsed: Variant = JSON.parse_string(json_str)
	assert_true(parsed is Dictionary)
	var restored: RunState = RunState.from_dict(parsed as Dictionary)
	assert_eq(restored.run_id, rs.run_id)
	assert_eq(restored.band_id, rs.band_id)
	assert_eq(restored.seed_value, rs.seed_value)
	assert_eq(restored.position, rs.position)
	assert_eq(restored.graph.nodes.size(), rs.graph.nodes.size())


func test_is_valid_next() -> void:
	var rs: RunState = _make_run_state()
	# From start, can go to a or b
	assert_true(rs.is_valid_next("a"))
	assert_true(rs.is_valid_next("b"))
	# Cannot go directly to boss
	assert_false(rs.is_valid_next("c"))
	# Cannot go to nonexistent
	assert_false(rs.is_valid_next("missing"))


func test_advance_to_updates_position_and_depth() -> void:
	var rs: RunState = _make_run_state()
	var ok: bool = rs.advance_to("a")
	assert_true(ok)
	assert_eq(rs.position, "a")
	assert_eq(rs.depth, 1)
	assert_has(rs.visited, "a")
	assert_has(rs.visited, "s")


func test_advance_to_invalid_returns_false() -> void:
	var rs: RunState = _make_run_state()
	var ok: bool = rs.advance_to("c")  # not adjacent to start
	assert_false(ok)
	assert_eq(rs.position, "s")  # unchanged
	assert_eq(rs.depth, 0)


func test_advance_does_not_duplicate_visited() -> void:
	var rs: RunState = _make_run_state()
	rs.advance_to("a")
	# Force position back for test (simulate going back)
	rs.position = "s"
	rs.advance_to("a")
	var count: int = 0
	for v in rs.visited:
		if v == "a":
			count += 1
	assert_eq(count, 1, "should not duplicate visited entries")


func test_from_dict_defaults_on_empty() -> void:
	var rs: RunState = RunState.from_dict({})
	assert_eq(rs.run_id, "")
	assert_eq(rs.band_id, "")
	assert_eq(rs.seed_value, 0)
	assert_eq(rs.position, "")
	assert_eq(rs.depth, 0)
	assert_eq(rs.down_limit, 2)
	assert_true(rs.visited.is_empty())
	assert_not_null(rs.graph)
	assert_true(rs.graph.nodes.is_empty())


func test_null_graph_is_valid_next_returns_false() -> void:
	var rs := RunState.new()
	rs.graph = null
	assert_false(rs.is_valid_next("anything"))
