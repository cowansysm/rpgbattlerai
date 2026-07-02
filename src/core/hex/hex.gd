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


# --- Direction helpers ---

## Returns the direction index (0-5) from `from` toward `to`.
## Uses floating-point angle matching against the 6 hex directions.
static func direction_toward(from: Vector2i, to: Vector2i) -> int:
	var diff := to - from
	if diff == Vector2i.ZERO:
		return 0
	# Convert axial diff to approximate angle and find closest direction
	var best_dir := 0
	var best_dot := -INF
	for i in range(6):
		var d := DIRECTIONS[i]
		var dot: float = float(diff.x * d.x + diff.y * d.y)
		if dot > best_dot:
			best_dot = dot
			best_dir = i
	return best_dir


## Rotates an axial offset by `steps` 60-degree increments (clockwise).
## Uses cube coordinate rotation: (x,y,z) -> (-z,-x,-y) per step.
static func rotate_offset(offset: Vector2i, steps: int) -> Vector2i:
	var c := axial_to_cube(offset)
	var s := ((steps % 6) + 6) % 6  # normalize to 0-5
	for _i in range(s):
		c = Vector3i(-c.z, -c.x, -c.y)
	return cube_to_axial(c)


# --- Shape queries ---

## Returns hexes forming a line from `from` to `to` (inclusive of both endpoints).
## Uses linear interpolation in cube space with rounding.
static func hex_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n := distance(from, to)
	if n == 0:
		out.append(from)
		return out
	var fc := axial_to_cube(from)
	var tc := axial_to_cube(to)
	for i in range(n + 1):
		var t: float = float(i) / float(n)
		var fx: float = fc.x + (tc.x - fc.x) * t
		var fy: float = fc.y + (tc.y - fc.y) * t
		var fz: float = fc.z + (tc.z - fc.z) * t
		out.append(cube_to_axial(cube_round(fx, fy, fz)))
	return out


## Returns the ring of hexes at exactly `radius` distance from `center`.
## For radius 0, returns just the center. For radius 1, returns 6 neighbors.
static func ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	if radius == 0:
		return [center]
	var out: Array[Vector2i] = []
	var hex := center + DIRECTIONS[4] * radius  # start at direction 4 scaled by radius
	for i in range(6):
		for _j in range(radius):
			out.append(hex)
			hex = neighbor(hex, i)
	return out


## Returns hexes forming a line of `length` hexes starting at `origin` and
## extending in the given direction index (0-5).
static func line_in_direction(origin: Vector2i, direction: int, length: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var pos := origin
	for _i in range(length):
		out.append(pos)
		pos = neighbor(pos, direction)
	return out


## Returns hexes forming a cone starting at `origin`, spreading in the
## given direction. depth=1 returns 1 hex, depth=2 returns 3 hexes (triangle).
static func cone_in_direction(origin: Vector2i, direction: int, depth: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var left_dir := (direction + 5) % 6  # one step counter-clockwise
	var pos := origin
	for row in range(depth):
		# Each row has (row + 1) hexes, spreading left from the center line
		var row_start := pos
		for _l in range(row):
			row_start = neighbor(row_start, left_dir)
		var current := row_start
		for _col in range(row + 1):
			out.append(current)
			current = neighbor(current, (direction + 1) % 6)  # step right
		pos = neighbor(pos, direction)
	return out

# --- A19: Facing / Arc classification ---

## Arc classification relative to a target's facing.
enum Arc { FRONT = 0, FLANK = 1, REAR = 2 }

## Classify the arc of an incoming attack.
## attacker_dir: the direction index FROM target TOWARD attacker (incoming bearing).
## target_facing: the direction index the target is facing.
## Returns Arc.FRONT (0/1/5 diff), Arc.FLANK (2/4 diff), Arc.REAR (3 diff).
static func arc_of(attacker_dir: int, target_facing: int) -> int:
	var diff: int = ((attacker_dir - target_facing) % 6 + 6) % 6
	match diff:
		0, 1, 5:
			return Arc.FRONT
		2, 4:
			return Arc.FLANK
		3:
			return Arc.REAR
	return Arc.FRONT


## Convenience: compute the arc of an attack FROM attacker_pos TOWARD target_pos,
## given target_pos and the target unit's facing direction index.
static func arc_between(attacker_pos: Vector2i, target_pos: Vector2i, target_facing: int) -> int:
	var incoming_dir: int = direction_toward(target_pos, attacker_pos)
	return arc_of(incoming_dir, target_facing)
