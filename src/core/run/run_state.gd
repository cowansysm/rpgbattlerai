class_name RunState
extends RefCounted
## Persistent state for a roguelike run. Saved in SaveManager.active_run.
## Tracks the graph, current position, depth, and visited nodes.

var run_id: String = ""
var band_id: String = ""
var seed_value: int = 0
var graph: RunGraph = null
var position: String = ""       # current node id
var depth: int = 0
var down_limit: int = 2
var visited: Array[String] = []


func to_dict() -> Dictionary:
	return {
		"run_id": run_id,
		"band_id": band_id,
		"seed_value": seed_value,
		"graph": graph.to_dict() if graph != null else {},
		"position": position,
		"depth": depth,
		"down_limit": down_limit,
		"visited": visited.duplicate(),
	}


static func from_dict(d: Dictionary) -> RunState:
	var rs := RunState.new()
	rs.run_id = str(d.get("run_id", ""))
	rs.band_id = str(d.get("band_id", ""))
	rs.seed_value = int(d.get("seed_value", 0))
	var graph_dict: Variant = d.get("graph", {})
	if graph_dict is Dictionary and not (graph_dict as Dictionary).is_empty():
		rs.graph = RunGraph.from_dict(graph_dict as Dictionary)
	else:
		rs.graph = RunGraph.new()
	rs.position = str(d.get("position", ""))
	rs.depth = int(d.get("depth", 0))
	rs.down_limit = int(d.get("down_limit", 2))
	var vis: Variant = d.get("visited", [])
	if vis is Array:
		for v in (vis as Array):
			rs.visited.append(str(v))
	return rs


func is_valid_next(node_id: String) -> bool:
	if graph == null:
		return false
	return graph.next_nodes(position).has(node_id)


func advance_to(node_id: String) -> bool:
	if not is_valid_next(node_id):
		return false
	position = node_id
	depth += 1
	if not visited.has(node_id):
		visited.append(node_id)
	return true


static func create_new(p_band_id: String, seed_val: int, cfg: Dictionary) -> RunState:
	var rs := RunState.new()
	rs.run_id = "run_%x_%x" % [Time.get_ticks_usec(), seed_val & 0xFFFF]
	rs.band_id = p_band_id
	rs.seed_value = seed_val
	rs.down_limit = int(Constants.get_value("DOWN_LIMIT", 2))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	rs.graph = RunGraphGenerator.generate(rng, cfg)
	rs.position = str(rs.graph.start_node().get("id", ""))
	rs.depth = 0
	rs.visited = [rs.position]
	return rs
