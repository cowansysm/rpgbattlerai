class_name RunGraphGenerator
extends RefCounted
## Seeded generator for run graphs.
## Produces a column-indexed DAG with width capped at MAX_PARALLEL,
## sporadic cross-links, reachability repair, and weighted node-kind assignment.
## Enforces the two-edge-node invariant: start is the only source, boss is the
## only sink, and all edges flow strictly forward.

const NODE_KINDS: Array[String] = ["battle", "event", "boon", "hazard", "shop", "rest"]
const MAX_GENERATION_ATTEMPTS: int = 10


static func generate(rng: RandomNumberGenerator, cfg: Dictionary) -> RunGraph:
	for attempt in range(MAX_GENERATION_ATTEMPTS):
		var g: RunGraph = _generate_candidate(rng, cfg)
		if g.is_valid_run_graph():
			return g
	# Final attempt — if we still fail, emit a warning and return the last graph.
	# This should never happen with the current construction logic.
	push_error("RunGraphGenerator: failed to produce a valid graph after %d attempts" % MAX_GENERATION_ATTEMPTS)
	return _generate_candidate(rng, cfg)


static func _generate_candidate(rng: RandomNumberGenerator, cfg: Dictionary) -> RunGraph:
	var g := RunGraph.new()
	var L: int = int(cfg.get("run_length", 12))
	var maxw: int = int(cfg.get("max_parallel", 3))
	var cross_chance: float = float(cfg.get("cross_link_chance", 0.25))
	var spacing: int = int(cfg.get("shop_rest_spacing", 2))
	var weights: Dictionary = cfg.get("node_weights", {}) as Dictionary

	# Step 1: column widths
	var widths: Array[int] = [1]
	for c in range(1, L):
		widths.append(rng.randi_range(1, maxw))
	widths.append(1)  # boss column

	# Step 2: place nodes
	_place_nodes(g, widths)

	# Step 3: connect adjacent columns
	_connect_columns(g, widths, rng, cross_chance)

	# Step 4: reachability repair
	_repair_reachability(g, widths)

	# Step 5: assign node kinds
	_assign_kinds(g, L, rng, weights, spacing)

	return g


static func _place_nodes(g: RunGraph, widths: Array[int]) -> void:
	for c in range(widths.size()):
		var w: int = widths[c]
		for r in range(w):
			var id: String = "node_%d_%d" % [c, r]
			g.nodes[id] = {"id": id, "column": c, "row": r, "kind": ""}


static func _connect_columns(g: RunGraph, widths: Array[int],
		rng: RandomNumberGenerator, cross_chance: float) -> void:
	for c in range(widths.size() - 1):
		var w_from: int = widths[c]
		var w_to: int = widths[c + 1]
		var target_covered: Array[bool] = []
		for _i in range(w_to):
			target_covered.append(false)

		for r_from in range(w_from):
			var from_id: String = "node_%d_%d" % [c, r_from]
			# Primary edge: nearest row
			var primary_row: int = _nearest_row(r_from, w_from, w_to)
			var to_id: String = "node_%d_%d" % [c + 1, primary_row]
			_add_edge_if_new(g, from_id, to_id)
			target_covered[primary_row] = true

			# Secondary edge: cross-link
			if rng.randf() < cross_chance and w_to > 1:
				var alt_row: int = _pick_alt_row(primary_row, w_to, rng)
				if alt_row >= 0:
					var alt_id: String = "node_%d_%d" % [c + 1, alt_row]
					_add_edge_if_new(g, from_id, alt_id)
					target_covered[alt_row] = true

		# Ensure every target node has at least one incoming edge
		for r_to in range(w_to):
			if not target_covered[r_to]:
				var best_from: int = _nearest_row(r_to, w_to, w_from)
				var from_id: String = "node_%d_%d" % [c, best_from]
				var to_id: String = "node_%d_%d" % [c + 1, r_to]
				_add_edge_if_new(g, from_id, to_id)


static func _nearest_row(r: int, w_from: int, w_to: int) -> int:
	if w_to == 1:
		return 0
	if w_from == 1:
		return w_to / 2
	var ratio: float = float(r) / float(w_from - 1)
	return clampi(int(round(ratio * (w_to - 1))), 0, w_to - 1)


static func _pick_alt_row(primary: int, w: int, rng: RandomNumberGenerator) -> int:
	var candidates: Array[int] = []
	if primary > 0:
		candidates.append(primary - 1)
	if primary < w - 1:
		candidates.append(primary + 1)
	if candidates.is_empty():
		return -1
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _add_edge_if_new(g: RunGraph, from_id: String, to_id: String) -> void:
	for e in g.edges:
		if str(e["from"]) == from_id and str(e["to"]) == to_id:
			return
	g.edges.append({"from": from_id, "to": to_id})


static func _repair_reachability(g: RunGraph, widths: Array[int]) -> void:
	var last_col: int = widths.size() - 1
	for c in range(widths.size()):
		for r in range(widths[c]):
			var id: String = "node_%d_%d" % [c, r]
			# Check outgoing (skip boss column)
			if c < last_col:
				if g.next_nodes(id).is_empty():
					var target_row: int = _nearest_row(r, widths[c], widths[c + 1])
					_add_edge_if_new(g, id, "node_%d_%d" % [c + 1, target_row])
			# Check incoming (skip start column)
			if c > 0:
				if g.prev_nodes(id).is_empty():
					var source_row: int = _nearest_row(r, widths[c], widths[c - 1])
					_add_edge_if_new(g, "node_%d_%d" % [c - 1, source_row], id)


static func _assign_kinds(g: RunGraph, run_length: int, rng: RandomNumberGenerator,
		weights: Dictionary, spacing: int) -> void:
	# Column 0 = start, column L = boss
	for id in g.nodes.keys():
		var n: Dictionary = g.nodes[id]
		var col: int = int(n["column"])
		if col == 0:
			n["kind"] = "start"
		elif col == run_length:
			n["kind"] = "boss"

	var last_shop_col: int = -spacing - 1
	var last_rest_col: int = -spacing - 1
	var battle_streak: int = 0

	for c in range(1, run_length):
		var col_nodes: Array = g.nodes_at_column(c)
		var col_has_non_battle: bool = false
		for n in col_nodes:
			var kind: String = _weighted_kind_pick(rng, weights, c,
				last_shop_col, last_rest_col, spacing)
			n["kind"] = kind
			g.nodes[str(n["id"])] = n
			if kind != "battle":
				col_has_non_battle = true
			if kind == "shop":
				last_shop_col = c
			elif kind == "rest":
				last_rest_col = c

		if not col_has_non_battle:
			battle_streak += 1
		else:
			battle_streak = 0

		# Not-all-battles guarantee: force a non-battle after 3 consecutive all-battle columns
		if battle_streak >= 3 and col_nodes.size() > 0:
			var forced: Dictionary = col_nodes[rng.randi_range(0, col_nodes.size() - 1)]
			var non_battle: Array[String] = ["event", "boon", "hazard"]
			forced["kind"] = non_battle[rng.randi_range(0, non_battle.size() - 1)]
			g.nodes[str(forced["id"])] = forced
			battle_streak = 0


static func _weighted_kind_pick(rng: RandomNumberGenerator, weights: Dictionary,
		col: int, last_shop_col: int, last_rest_col: int, spacing: int) -> String:
	var effective: Dictionary = {}
	for kind in NODE_KINDS:
		var w: float = float(weights.get(kind, 0))
		if kind == "shop" and (col - last_shop_col) < spacing:
			w = 0.0
		if kind == "rest" and (col - last_rest_col) < spacing:
			w = 0.0
		effective[kind] = w

	var total: float = 0.0
	for w in effective.values():
		total += float(w)
	if total <= 0.0:
		return "battle"

	var roll: float = rng.randf() * total
	var accum: float = 0.0
	for kind in NODE_KINDS:
		accum += float(effective[kind])
		if roll < accum:
			return kind
	return "battle"
