extends GutTest
## Tests for the hex coordinate math module (src/core/hex/hex.gd).

# --- Coordinate conversions (B2) ---

func test_axial_cube_roundtrip() -> void:
	var cases: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(2, -3), Vector2i(-1, 4), Vector2i(5, 5),
	]
	for a in cases:
		assert_eq(Hex.cube_to_axial(Hex.axial_to_cube(a)), a,
			"roundtrip for %s" % str(a))


func test_cube_constraint() -> void:
	var a := Vector2i(3, -2)
	var c := Hex.axial_to_cube(a)
	assert_eq(c.x + c.y + c.z, 0, "cube constraint x+y+z=0")


# --- Neighbors & directions (B3) ---

func test_neighbors_count() -> void:
	assert_eq(Hex.neighbors(Vector2i(0, 0)).size(), 6, "origin has 6 neighbors")


func test_neighbors_unique() -> void:
	var nbs := Hex.neighbors(Vector2i(0, 0))
	var unique := {}
	for nb in nbs:
		unique[nb] = true
	assert_eq(unique.size(), 6, "all 6 neighbors are unique")


func test_neighbor_by_direction() -> void:
	for i in range(6):
		var nb := Hex.neighbor(Vector2i(0, 0), i)
		assert_eq(Hex.distance(Vector2i(0, 0), nb), 1,
			"direction %d neighbor is at distance 1" % i)


# --- Distance (B4) ---

func test_distance_to_self() -> void:
	assert_eq(Hex.distance(Vector2i(3, -1), Vector2i(3, -1)), 0)


func test_distance_symmetry() -> void:
	var a := Vector2i(1, 2)
	var b := Vector2i(-2, 3)
	assert_eq(Hex.distance(a, b), Hex.distance(b, a), "distance is symmetric")


func test_distance_to_neighbor_is_one() -> void:
	for nb in Hex.neighbors(Vector2i(0, 0)):
		assert_eq(Hex.distance(Vector2i(0, 0), nb), 1,
			"distance to neighbor %s is 1" % str(nb))


func test_distance_known_value() -> void:
	# (0,0) to (2,-1): cube (0,0,0) to (2,-1,-1) -> (2+1+1)/2 = 2
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(2, -1)), 2)


# --- Range query (B5) ---

func test_range_cardinality() -> void:
	for n in [0, 1, 2, 3, 5]:
		var expected: int = 3 * n * (n + 1) + 1
		var actual: int = Hex.hexes_in_range(Vector2i(0, 0), n).size()
		assert_eq(actual, expected,
			"range %d: expected %d hexes, got %d" % [n, expected, actual])


func test_range_includes_center() -> void:
	var center := Vector2i(2, 3)
	var result := Hex.hexes_in_range(center, 1)
	assert_true(center in result, "range result includes center")


func test_range_zero_is_just_center() -> void:
	var center := Vector2i(1, -1)
	var result := Hex.hexes_in_range(center, 0)
	assert_eq(result.size(), 1)
	assert_eq(result[0], center)


# --- Cube rounding (B6) ---

func test_cube_round_exact() -> void:
	var result := Hex.cube_round(2.0, -3.0, 1.0)
	assert_eq(result, Vector3i(2, -3, 1))


func test_cube_round_fractional() -> void:
	var result := Hex.cube_round(0.3, -0.6, 0.3)
	assert_eq(result.x + result.y + result.z, 0, "rounded cube satisfies constraint")


func test_cube_round_near_boundary() -> void:
	var result := Hex.cube_round(0.49, -0.98, 0.49)
	assert_eq(result.x + result.y + result.z, 0, "constraint holds at boundary")


# --- Elevation helper (B7) ---

func test_elevation_step_positive() -> void:
	assert_eq(Hex.elevation_step(0, 3), 3)


func test_elevation_step_negative() -> void:
	assert_eq(Hex.elevation_step(5, 2), 3)


func test_elevation_step_zero() -> void:
	assert_eq(Hex.elevation_step(4, 4), 0)
