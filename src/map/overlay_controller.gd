class_name OverlayController
extends Node
## Paints movement (single-AP reach) and target (in-range + LoS) overlays
## on Phase 2 HexTile overlay layers. Pure presentation over authoritative
## spatial computations — holds no rules state.

var graph: HexGraph
var builder: MapBuilder


## Show single-AP movement overlay from start tile.
func show_movement(start: Vector2i, move: int, jump: int) -> void:
	clear()
	var reach := Movement.reachable(graph, start, move, jump)
	var mat1 := OverlayMaterials.move_tier1()
	for c in reach.keys():
		_paint(c, mat1)


## Show target overlay from origin with given range.
## min_range excludes hexes closer than the minimum (default 1 = no exclusion).
func show_targets(origin: Vector2i, radius: int, min_range: int = 1) -> void:
	clear()
	var mat_valid := OverlayMaterials.target_valid()
	var mat_blocked := OverlayMaterials.target_blocked()
	for c in RangeQuery.in_range(origin, radius, graph):
		if c == origin:
			continue
		if Hex.distance(origin, c) < min_range:
			continue
		if LineOfSight.has_los(graph, origin, c):
			_paint(c, mat_valid)
		else:
			_paint(c, mat_blocked)


## Show revive target overlay — highlights downed allies in range with LoS.
func show_revive_targets(origin: Vector2i, radius: int, state: MatchState, caster_team: String) -> void:
	clear()
	var mat := OverlayMaterials.revive_valid()
	for c in RangeQuery.in_range(origin, radius, graph):
		if c == origin:
			continue
		if not LineOfSight.has_los(graph, origin, c):
			continue
		var u: BattleUnit = state.unit_at(c)
		if u and u.is_downed and u.team == caster_team:
			_paint(c, mat)


## Show AoE shape preview from caster to target. Paints affected hexes.
func show_aoe_preview(caster_pos: Vector2i, target_pos: Vector2i, area: Dictionary) -> void:
	clear()
	var mat := OverlayMaterials.target_valid()
	var shape: String = str(area.get("shape", ""))
	var hexes: Array[Vector2i] = []

	match shape:
		"burst":
			var radius: int = int(area.get("radius", 0))
			hexes = Hex.hexes_in_range(target_pos, radius)
		"line":
			var length: int = int(area.get("length", 1))
			var direction: int = Hex.direction_toward(caster_pos, target_pos)
			hexes = Hex.line_in_direction(target_pos, direction, length)
		"cone":
			var depth: int = int(area.get("depth", 1))
			var direction: int = Hex.direction_toward(caster_pos, target_pos)
			hexes = Hex.cone_in_direction(target_pos, direction, depth)
		"ring":
			var radius: int = int(area.get("radius", 1))
			hexes = Hex.ring(target_pos, radius)

	for c in hexes:
		_paint(c, mat)


## Show selectable unit tiles (awaiting activation) — gold highlights.
func show_selectable(positions: Array) -> void:
	clear()
	var mat := OverlayMaterials.selectable()
	for pos in positions:
		_paint(pos, mat)


## Clear all tile overlays.
func clear() -> void:
	for t in builder.tiles.values():
		t.clear_overlay()


func _paint(c: Vector2i, mat: StandardMaterial3D) -> void:
	if builder.tiles.has(c):
		builder.tiles[c].set_overlay(mat)
