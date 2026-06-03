class_name LineOfSight
extends RefCounted
## Hybrid line-of-sight: hex-line sampling (authoritative) with elevation
## interpolation. Higher attacker "sees over" lower obstacles automatically.
## Terrain data accessed through graph.terrain_props() (injected provider).

const UNIT_EYE := 1.0  ## Eye height above the tile surface.


## Returns true if tile A has clear line of sight to tile B.
## Samples intervening hexes; blocks if any obstacle exceeds the sightline.
static func has_los(graph: HexGraph, a: Vector2i, b: Vector2i) -> bool:
	var line := _hex_line(a, b)
	var n := line.size() - 1
	if n <= 1:
		return true  # Adjacent or same tile — always clear.
	var ha := float(graph.elevation(a)) + UNIT_EYE
	var hb := float(graph.elevation(b)) + UNIT_EYE
	for i in range(1, n):  # Intervening hexes only (exclude endpoints).
		var h: Vector2i = line[i]
		if not graph.has_tile(h):
			continue
		var sight_h: float = lerpf(ha, hb, float(i) / float(n))
		if _block_height(graph, h) > sight_h:
			return false
	return true


## Blocking height of a tile: elevation + obstacle height (if blocks_los).
static func _block_height(graph: HexGraph, c: Vector2i) -> float:
	var props: TerrainProps = graph.terrain_props(c)
	var h := float(graph.elevation(c))
	if props.blocks_los:
		h += float(props.los_height)
	return h


## Cube-interpolated hex line from A to B (inclusive).
## Returns Array[Vector2i] of axial coordinates.
static func _hex_line(a: Vector2i, b: Vector2i) -> Array:
	var n := Hex.distance(a, b)
	if n == 0:
		return [a]
	var ac := Hex.axial_to_cube(a)
	var bc := Hex.axial_to_cube(b)
	var out: Array = []
	for i in range(n + 1):
		var t := float(i) / float(n)
		var rx := lerpf(float(ac.x), float(bc.x), t)
		var ry := lerpf(float(ac.y), float(bc.y), t)
		var rz := lerpf(float(ac.z), float(bc.z), t)
		out.append(Hex.cube_to_axial(Hex.cube_round(rx, ry, rz)))
	return out


## Optional 3D raycast cross-check (debug diagnostic only, not authoritative).
## Returns true if the ray is clear (no intersection).
static func raycast_clear(space: PhysicsDirectSpaceState3D, from_w: Vector3, to_w: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from_w, to_w)
	return space.intersect_ray(query).is_empty()
