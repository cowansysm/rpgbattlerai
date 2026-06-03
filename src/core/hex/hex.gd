class_name Hex
extends RefCounted
## Pure hex coordinate math. Axial (q, r) is canonical;
## cube (x, y, z) is derived for distance and rounding.
## No scene-tree dependency — fully unit-testable.

# --- Direction vectors (axial, orientation-independent) ---

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

# --- Coordinate conversions ---

static func axial_to_cube(a: Vector2i) -> Vector3i:
	var x := a.x
	var z := a.y
	var y := -x - z
	return Vector3i(x, y, z)


static func cube_to_axial(c: Vector3i) -> Vector2i:
	return Vector2i(c.x, c.z)

# --- Neighbors ---

static func neighbor(a: Vector2i, dir: int) -> Vector2i:
	return a + DIRECTIONS[dir]


static func neighbors(a: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRECTIONS:
		out.append(a + d)
	return out

# --- Distance ---

static func distance(a: Vector2i, b: Vector2i) -> int:
	var ac := axial_to_cube(a)
	var bc := axial_to_cube(b)
	return (absi(ac.x - bc.x) + absi(ac.y - bc.y) + absi(ac.z - bc.z)) / 2

# --- Range query ---

static func hexes_in_range(center: Vector2i, n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dq in range(-n, n + 1):
		for dr in range(maxi(-n, -dq - n), mini(n, -dq + n) + 1):
			out.append(center + Vector2i(dq, dr))
	return out

# --- Cube rounding (fractional -> integer) ---

static func cube_round(fx: float, fy: float, fz: float) -> Vector3i:
	var rx := roundi(fx)
	var ry := roundi(fy)
	var rz := roundi(fz)
	var dx := absf(rx - fx)
	var dy := absf(ry - fy)
	var dz := absf(rz - fz)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector3i(rx, ry, rz)

# --- Elevation helper ---

static func elevation_step(from_elev: int, to_elev: int) -> int:
	return absi(to_elev - from_elev)
