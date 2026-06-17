class_name Movement
extends RefCounted
## Movement computations: reachable set (cost-bounded Dijkstra),
## two-tier reach (action economy), and shortest path.
## Jump is a cumulative budget — the total absolute elevation change
## across all steps of a path must not exceed the mover's jump stat.
## All static — no scene-tree dependency.

const INF_COST := 1 << 30


## Returns {Vector2i: min_cost} for all tiles reachable from start
## within max_cost, honoring terrain move cost, impassability, and
## cumulative elevation budget (jump).
static func reachable(graph: HexGraph, start: Vector2i, max_cost: int, jump: int) -> Dictionary:
	# Track best cost per (tile, cumulative_elevation) pair.
	# best[tile][cum_elev] = min movement cost to reach tile using cum_elev budget.
	var best := {}
	best[start] = {0: 0}
	var frontier: Array = [[0, 0, start]]  # [cost, cum_elev, tile]
	while not frontier.is_empty():
		frontier.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var top: Array = frontier.pop_front()
		var cost: int = top[0]
		var cum_elev: int = top[1]
		var cur: Vector2i = top[2]
		if cost > int(best.get(cur, {}).get(cum_elev, INF_COST)):
			continue
		for nb in Hex.neighbors(cur):
			if not graph.has_tile(nb) or graph.is_impassable(nb):
				continue
			var step_elev: int = absi(graph.elevation(nb) - graph.elevation(cur))
			var new_elev: int = cum_elev + step_elev
			if new_elev > jump:
				continue
			var nc: int = cost + graph.move_cost(nb)
			if nc > max_cost:
				continue
			if not best.has(nb):
				best[nb] = {}
			if nc < int(best[nb].get(new_elev, INF_COST)):
				best[nb][new_elev] = nc
				frontier.append([nc, new_elev, nb])
	# Collapse to {tile: min_cost} across all cumulative elevation levels
	var dist := {}
	for tile in best.keys():
		var min_cost: int = INF_COST
		for elev_cost in best[tile].values():
			if elev_cost < min_cost:
				min_cost = elev_cost
		dist[tile] = min_cost
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


## Shortest path between two tiles honoring cumulative elevation budget.
## Returns ordered Array[Vector2i], or empty if no valid path exists.
static func path(graph: HexGraph, start: Vector2i, goal: Vector2i, jump: int) -> Array:
	if not graph.has_tile(start) or not graph.has_tile(goal):
		return []
	if start == goal:
		return [start]
	# Dijkstra with (cost, cum_elev) state and predecessor tracking
	var best := {}
	best[start] = {0: 0}
	var prev := {}  # {tile: {cum_elev: [prev_tile, prev_cum_elev]}}
	var frontier: Array = [[0, 0, start]]
	while not frontier.is_empty():
		frontier.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var top: Array = frontier.pop_front()
		var cost: int = top[0]
		var cum_elev: int = top[1]
		var cur: Vector2i = top[2]
		if cost > int(best.get(cur, {}).get(cum_elev, INF_COST)):
			continue
		if cur == goal:
			return _reconstruct(prev, goal, cum_elev)
		for nb in Hex.neighbors(cur):
			if not graph.has_tile(nb) or graph.is_impassable(nb):
				continue
			var step_elev: int = absi(graph.elevation(nb) - graph.elevation(cur))
			var new_elev: int = cum_elev + step_elev
			if new_elev > jump:
				continue
			var nc: int = cost + graph.move_cost(nb)
			if not best.has(nb):
				best[nb] = {}
			if nc < int(best[nb].get(new_elev, INF_COST)):
				best[nb][new_elev] = nc
				if not prev.has(nb):
					prev[nb] = {}
				prev[nb][new_elev] = [cur, cum_elev]
				frontier.append([nc, new_elev, nb])
	return []


static func _reconstruct(prev: Dictionary, goal: Vector2i, cum_elev: int) -> Array:
	var out: Array = [goal]
	var cur := goal
	var elev := cum_elev
	while prev.has(cur) and prev[cur].has(elev):
		var p: Array = prev[cur][elev]
		cur = p[0]
		elev = p[1]
		out.push_front(cur)
	return out
