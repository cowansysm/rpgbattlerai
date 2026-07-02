class_name RunGraph
extends RefCounted
## Column-indexed directed acyclic graph for roguelike run traversal.
## Nodes are {id: String, column: int, row: int, kind: String}.
## Edges are {from: String, to: String}.

var nodes: Dictionary = {}      # id -> {id, column, row, kind}
var edges: Array = []           # [{from, to}]


func next_nodes(id: String) -> Array[String]:
	var out: Array[String] = []
	for e in edges:
		if str(e["from"]) == id:
			out.append(str(e["to"]))
	return out


func prev_nodes(id: String) -> Array[String]:
	var out: Array[String] = []
	for e in edges:
		if str(e["to"]) == id:
			out.append(str(e["from"]))
	return out


func node(id: String) -> Dictionary:
	return nodes.get(id, {})


func nodes_at_column(col: int) -> Array:
	var out: Array = []
	for n in nodes.values():
		if int(n["column"]) == col:
			out.append(n)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["row"]) < int(b["row"]))
	return out


func start_node() -> Dictionary:
	var col0: Array = nodes_at_column(0)
	return col0[0] if not col0.is_empty() else {}


func boss_node() -> Dictionary:
	var col_last: Array = nodes_at_column(max_column())
	return col_last[0] if not col_last.is_empty() else {}


func max_column() -> int:
	var mc: int = 0
	for n in nodes.values():
		mc = maxi(mc, int(n["column"]))
	return mc


## Validates the two-edge-node invariant: start is the only source (no incoming),
## boss is the only sink (no outgoing), and all edges flow forward (lower to higher column).
func is_valid_run_graph() -> bool:
	if nodes.is_empty():
		return false
	var start: Dictionary = start_node()
	var boss: Dictionary = boss_node()
	if start.is_empty() or boss.is_empty():
		return false

	var start_id: String = str(start["id"])
	var boss_id: String = str(boss["id"])

	# Check all edges flow forward (unidirectional progress)
	for e in edges:
		var from_n: Dictionary = node(str(e["from"]))
		var to_n: Dictionary = node(str(e["to"]))
		if from_n.is_empty() or to_n.is_empty():
			return false
		if int(from_n["column"]) >= int(to_n["column"]):
			return false

	# Check edge-node invariant: only start is a source, only boss is a sink
	for id in nodes.keys():
		var incoming: Array[String] = prev_nodes(id)
		var outgoing: Array[String] = next_nodes(id)
		if incoming.is_empty() and id != start_id:
			return false  # extra source
		if outgoing.is_empty() and id != boss_id:
			return false  # extra sink
		if not incoming.is_empty() and id == start_id:
			return false  # start has incoming edges
		if not outgoing.is_empty() and id == boss_id:
			return false  # boss has outgoing edges

	return true


func to_dict() -> Dictionary:
	var node_list: Array = []
	for n in nodes.values():
		node_list.append(n.duplicate())
	return {"nodes": node_list, "edges": edges.duplicate(true)}


static func from_dict(d: Dictionary) -> RunGraph:
	var g := RunGraph.new()
	var node_arr: Variant = d.get("nodes", [])
	if node_arr is Array:
		for entry in (node_arr as Array):
			if entry is Dictionary:
				var id: String = str(entry.get("id", ""))
				g.nodes[id] = {
					"id": id,
					"column": int(entry.get("column", 0)),
					"row": int(entry.get("row", 0)),
					"kind": str(entry.get("kind", "battle")),
				}
	var edge_arr: Variant = d.get("edges", [])
	if edge_arr is Array:
		for entry in (edge_arr as Array):
			if entry is Dictionary:
				g.edges.append({
					"from": str(entry.get("from", "")),
					"to": str(entry.get("to", "")),
				})
	return g
