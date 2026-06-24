extends GutTest

# --- Helpers ---

func _seeded(s: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	return rng


func _cfg(overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {
		"run_length": 8,
		"max_parallel": 3,
		"cross_link_chance": 0.25,
		"node_weights": {"battle": 50, "event": 15, "boon": 10, "hazard": 10, "shop": 8, "rest": 7},
		"shop_rest_spacing": 2,
	}
	base.merge(overrides, true)
	return base


func _col_counts(g: RunGraph) -> Dictionary:
	var counts: Dictionary = {}
	for n in g.nodes.values():
		var c: int = int(n["column"])
		counts[c] = int(counts.get(c, 0)) + 1
	return counts


func _bfs_reachable(g: RunGraph, start_id: String) -> Array[String]:
	var visited: Array[String] = []
	var queue: Array[String] = [start_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if visited.has(current):
			continue
		visited.append(current)
		for next_id in g.next_nodes(current):
			if not visited.has(next_id):
				queue.append(next_id)
	return visited


func _graph_signature(g: RunGraph) -> String:
	var d: Dictionary = g.to_dict()
	return JSON.stringify(d)


# --- RunGraph model tests ---

func test_next_nodes_returns_outgoing() -> void:
	var g := RunGraph.new()
	g.nodes["a"] = {"id": "a", "column": 0, "row": 0, "kind": "start"}
	g.nodes["b"] = {"id": "b", "column": 1, "row": 0, "kind": "battle"}
	g.nodes["c"] = {"id": "c", "column": 1, "row": 1, "kind": "battle"}
	g.edges = [{"from": "a", "to": "b"}, {"from": "a", "to": "c"}]
	var result: Array[String] = g.next_nodes("a")
	assert_eq(result.size(), 2)
	assert_has(result, "b")
	assert_has(result, "c")


func test_prev_nodes_returns_incoming() -> void:
	var g := RunGraph.new()
	g.nodes["a"] = {"id": "a", "column": 0, "row": 0, "kind": "start"}
	g.nodes["b"] = {"id": "b", "column": 0, "row": 1, "kind": "start"}
	g.nodes["c"] = {"id": "c", "column": 1, "row": 0, "kind": "battle"}
	g.edges = [{"from": "a", "to": "c"}, {"from": "b", "to": "c"}]
	var result: Array[String] = g.prev_nodes("c")
	assert_eq(result.size(), 2)
	assert_has(result, "a")
	assert_has(result, "b")


func test_nodes_at_column_sorted_by_row() -> void:
	var g := RunGraph.new()
	g.nodes["a"] = {"id": "a", "column": 1, "row": 2, "kind": "battle"}
	g.nodes["b"] = {"id": "b", "column": 1, "row": 0, "kind": "event"}
	g.nodes["c"] = {"id": "c", "column": 1, "row": 1, "kind": "shop"}
	var col1: Array = g.nodes_at_column(1)
	assert_eq(col1.size(), 3)
	assert_eq(str(col1[0]["id"]), "b")
	assert_eq(str(col1[1]["id"]), "c")
	assert_eq(str(col1[2]["id"]), "a")


func test_start_node_returns_column_zero() -> void:
	var g := RunGraph.new()
	g.nodes["s"] = {"id": "s", "column": 0, "row": 0, "kind": "start"}
	g.nodes["b"] = {"id": "b", "column": 1, "row": 0, "kind": "battle"}
	assert_eq(str(g.start_node()["id"]), "s")


func test_boss_node_returns_last_column() -> void:
	var g := RunGraph.new()
	g.nodes["s"] = {"id": "s", "column": 0, "row": 0, "kind": "start"}
	g.nodes["b"] = {"id": "b", "column": 5, "row": 0, "kind": "boss"}
	assert_eq(str(g.boss_node()["id"]), "b")


func test_empty_graph_returns_empty_dicts() -> void:
	var g := RunGraph.new()
	assert_true(g.start_node().is_empty())
	assert_true(g.boss_node().is_empty())
	assert_true(g.next_nodes("missing").is_empty())
	assert_true(g.prev_nodes("missing").is_empty())


func test_to_dict_from_dict_round_trip() -> void:
	var g := RunGraph.new()
	g.nodes["a"] = {"id": "a", "column": 0, "row": 0, "kind": "start"}
	g.nodes["b"] = {"id": "b", "column": 1, "row": 0, "kind": "battle"}
	g.edges = [{"from": "a", "to": "b"}]
	var restored: RunGraph = RunGraph.from_dict(g.to_dict())
	assert_eq(restored.nodes.size(), 2)
	assert_eq(restored.edges.size(), 1)
	assert_eq(str(restored.node("a")["kind"]), "start")
	assert_eq(str(restored.node("b")["kind"]), "battle")
	assert_eq(restored.next_nodes("a"), g.next_nodes("a"))


# --- Generator tests ---

func test_width_cap() -> void:
	for s in range(10):
		var g: RunGraph = RunGraphGenerator.generate(_seeded(s), _cfg())
		var counts: Dictionary = _col_counts(g)
		for c in counts:
			assert_lte(int(counts[c]), 3, "seed %d col %d exceeded width 3" % [s, c])


func test_start_and_boss_single_nodes() -> void:
	var g: RunGraph = RunGraphGenerator.generate(_seeded(1), _cfg())
	var counts: Dictionary = _col_counts(g)
	assert_eq(int(counts[0]), 1, "start column should have exactly 1 node")
	assert_eq(int(counts[g.max_column()]), 1, "boss column should have exactly 1 node")


func test_reachability_forward() -> void:
	for s in range(5):
		var g: RunGraph = RunGraphGenerator.generate(_seeded(s), _cfg())
		for id in g.nodes.keys():
			var n: Dictionary = g.nodes[id]
			if int(n["column"]) < g.max_column():
				assert_false(g.next_nodes(id).is_empty(),
					"seed %d node %s has no outgoing edges" % [s, id])


func test_reachability_backward() -> void:
	for s in range(5):
		var g: RunGraph = RunGraphGenerator.generate(_seeded(s), _cfg())
		for id in g.nodes.keys():
			var n: Dictionary = g.nodes[id]
			if int(n["column"]) > 0:
				assert_false(g.prev_nodes(id).is_empty(),
					"seed %d node %s has no incoming edges" % [s, id])


func test_start_reaches_boss() -> void:
	for s in range(5):
		var g: RunGraph = RunGraphGenerator.generate(_seeded(s), _cfg())
		var start_id: String = str(g.start_node()["id"])
		var boss_id: String = str(g.boss_node()["id"])
		var reachable: Array[String] = _bfs_reachable(g, start_id)
		assert_has(reachable, boss_id,
			"seed %d: boss not reachable from start" % s)


func test_determinism() -> void:
	var cfg: Dictionary = _cfg()
	var sig1: String = _graph_signature(RunGraphGenerator.generate(_seeded(42), cfg))
	var sig2: String = _graph_signature(RunGraphGenerator.generate(_seeded(42), cfg))
	assert_eq(sig1, sig2, "same seed should produce identical graphs")


func test_different_seeds_differ() -> void:
	var cfg: Dictionary = _cfg()
	var sig1: String = _graph_signature(RunGraphGenerator.generate(_seeded(1), cfg))
	var sig2: String = _graph_signature(RunGraphGenerator.generate(_seeded(999), cfg))
	assert_ne(sig1, sig2, "different seeds should produce different graphs")


func test_node_kinds_assigned() -> void:
	var g: RunGraph = RunGraphGenerator.generate(_seeded(1), _cfg())
	var start: Dictionary = g.start_node()
	assert_eq(str(start["kind"]), "start")
	var boss: Dictionary = g.boss_node()
	assert_eq(str(boss["kind"]), "boss")
	# All interior nodes have a valid kind
	var valid_kinds: Array[String] = ["battle", "event", "boon", "hazard", "shop", "rest"]
	for id in g.nodes.keys():
		var n: Dictionary = g.nodes[id]
		var col: int = int(n["column"])
		if col > 0 and col < g.max_column():
			assert_has(valid_kinds, str(n["kind"]),
				"node %s has invalid kind '%s'" % [id, str(n["kind"])])


func test_not_all_battles() -> void:
	# Over multiple seeds, interior nodes should not be exclusively battles
	for s in range(10):
		var g: RunGraph = RunGraphGenerator.generate(_seeded(s), _cfg())
		var has_non_battle: bool = false
		for id in g.nodes.keys():
			var n: Dictionary = g.nodes[id]
			var col: int = int(n["column"])
			if col > 0 and col < g.max_column() and str(n["kind"]) != "battle":
				has_non_battle = true
				break
		assert_true(has_non_battle,
			"seed %d: all interior nodes are battles" % s)


func test_cross_links_present_with_high_chance() -> void:
	var cfg: Dictionary = _cfg({"cross_link_chance": 1.0})
	var g: RunGraph = RunGraphGenerator.generate(_seeded(1), cfg)
	# With 100% cross link chance, some nodes should have 2+ outgoing edges
	var has_multi_out: bool = false
	for id in g.nodes.keys():
		if g.next_nodes(id).size() > 1:
			has_multi_out = true
			break
	assert_true(has_multi_out, "expected cross-links with 100% chance")


func test_generated_graph_round_trips_through_json() -> void:
	var g: RunGraph = RunGraphGenerator.generate(_seeded(7), _cfg())
	var json_str: String = JSON.stringify(g.to_dict())
	var parsed: Variant = JSON.parse_string(json_str)
	assert_true(parsed is Dictionary)
	var restored: RunGraph = RunGraph.from_dict(parsed as Dictionary)
	assert_eq(restored.nodes.size(), g.nodes.size())
	assert_eq(restored.edges.size(), g.edges.size())
	# Verify start and boss survive
	assert_eq(str(restored.start_node()["kind"]), "start")
	assert_eq(str(restored.boss_node()["kind"]), "boss")
