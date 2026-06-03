class_name RangeQuery
extends RefCounted
## Range queries for weapons/abilities.
## effective_range() is the designated extension point for vertical range;
## currently returns 2D hex distance. All range consumers call this,
## not Hex.distance() directly.

## Extension point for vertical range: currently returns 2D hex distance.
## When elevation-adjusted range is needed, only this function changes.
static func effective_range(a: Vector2i, b: Vector2i, _graph: HexGraph) -> int:
	return Hex.distance(a, b)


## Returns all on-map tiles within radius of origin (via effective_range).
static func in_range(origin: Vector2i, radius: int, graph: HexGraph) -> Array:
	var out: Array = []
	for c in Hex.hexes_in_range(origin, radius):
		if graph.has_tile(c) and effective_range(origin, c, graph) <= radius:
			out.append(c)
	return out
