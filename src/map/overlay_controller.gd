class_name OverlayController
extends Node
## Paints movement (two-tier) and target (in-range + LoS) overlays
## on Phase 2 HexTile overlay layers. Pure presentation over authoritative
## spatial computations — holds no rules state.

var graph: HexGraph
var builder: MapBuilder


## Show two-tier movement overlay from start tile.
func show_movement(start: Vector2i, move: int, jump: int) -> void:
	clear()
	var tiers := Movement.two_tier(graph, start, move, jump)
	var mat1 := OverlayMaterials.move_tier1()
	var mat2 := OverlayMaterials.move_tier2()
	for c in tiers["tier1"].keys():
		_paint(c, mat1)
	for c in tiers["tier2"].keys():
		_paint(c, mat2)


## Show target overlay from origin with given range.
func show_targets(origin: Vector2i, radius: int) -> void:
	clear()
	var mat_valid := OverlayMaterials.target_valid()
	var mat_blocked := OverlayMaterials.target_blocked()
	for c in RangeQuery.in_range(origin, radius, graph):
		if c == origin:
			continue
		if LineOfSight.has_los(graph, origin, c):
			_paint(c, mat_valid)
		else:
			_paint(c, mat_blocked)


## Clear all tile overlays.
func clear() -> void:
	for t in builder.tiles.values():
		t.clear_overlay()


func _paint(c: Vector2i, mat: StandardMaterial3D) -> void:
	if builder.tiles.has(c):
		builder.tiles[c].set_overlay(mat)
