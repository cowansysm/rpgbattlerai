class_name Movement
extends RefCounted
## Movement computations: reachable set (cost-bounded Dijkstra),
## two-tier reach (action economy), and shortest path (AStar3D).
## All static — no scene-tree dependency.

const INF_COST := 1 << 30


## Returns {Vector2i: min_cost} for all tiles reachable from start
## within max_cost, honoring terrain move cost, impassability, and Jump/Climb.
static func reachable(graph: HexGraph, start: Vector2i, max_cost: int, jump: int) -> Dictionary:
	var dist := {start: 0}
	var frontier: Array = [[0, start]]
	while not frontier.is_empty():
		frontier.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var top: Array = frontier.pop_front()
		var cost: int = top[0]
		var cur: Vector2i = top[1]
		if cost > int(dist.get(cur, INF_COST)):
			continue
		for nb in Hex.neighbors(cur):
			if not graph.has_tile(nb) or graph.is_impassable(nb):
				continue
			if absi(graph.elevation(nb) - graph.elevation(cur)) > jump:
				continue
			var nc: int = cost + graph.move_cost(nb)
			if nc <= max_cost and nc < int(dist.get(nb, INF_COST)):
				dist[nb] = nc
				frontier.append([nc, nb])
	return dist


## Two-tier reach per the 2-AP action economy (spec §7.4).
## Returns {"tier1": {Vector2i: cost}, "tier2": {Vector2i: cost}}.
## Tier 1 = budget move (single action); Tier 2 = budget 2*move minus Tier 1.
static func two_tier(graph: HexGraph, start: Vector2i, move: int, jump: int) -> Dictionary:
	var t1 := reachable(graph, start, move, jump)
	var t2_full := reachable(graph, start, move * 2, jump)
	var t2_only := {}
	for c in t2_full.keys():
		if not t1.has(c):
			t2_only[c] = t2_full[c]
	return {"tier1": t1, "tier2": t2_only}


## Shortest path between two tiles via AStar3D. Returns ordered Array[Vector2i].
## Sets mover edges before pathing.
static func path(graph: HexGraph, start: Vector2i, goal: Vector2i, jump: int) -> Array:
	graph.set_mover(jump)
	var start_id := graph.id_of(start)
	var goal_id := graph.id_of(goal)
	if start_id < 0 or goal_id < 0:
		return []
	var ids := graph.get_id_path(start_id, goal_id)
	var out: Array = []
	for id in ids:
		out.append(graph.coord_of(int(id)))
	return out
