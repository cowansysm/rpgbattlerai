extends GutTest
## Tests for HexWorld.hex_to_world() coordinate mapping.

# --- Origin ---

func test_origin() -> void:
	var pos := HexWorld.hex_to_world(0, 0, 0)
	assert_almost_eq(pos.x, 0.0, 0.001, "origin x = 0")
	assert_almost_eq(pos.y, 0.0, 0.001, "origin y = 0")
	assert_almost_eq(pos.z, 0.0, 0.001, "origin z = 0")


# --- Q axis (flat-top: x = 1.5 * q, z = sqrt(3)/2 * q) ---

func test_q_axis() -> void:
	var pos := HexWorld.hex_to_world(1, 0, 0)
	assert_almost_eq(pos.x, 0.3938, 0.001, "q=1 x = 0.3938")
	assert_almost_eq(pos.z, 0.2273, 0.001, "q=1 z = sqrt(3)/2 * 0.2625")
	assert_almost_eq(pos.y, 0.0, 0.001, "q=1 y = 0")


# --- R axis (flat-top: x = 0, z = sqrt(3) * r) ---

func test_r_axis() -> void:
	var pos := HexWorld.hex_to_world(0, 1, 0)
	assert_almost_eq(pos.x, 0.0, 0.001, "r=1 x = 0")
	assert_almost_eq(pos.z, 0.4547, 0.001, "r=1 z = sqrt(3) * 0.2625")
	assert_almost_eq(pos.y, 0.0, 0.001, "r=1 y = 0")


# --- Elevation maps to Y ---

func test_elevation_scales_y() -> void:
	var pos := HexWorld.hex_to_world(0, 0, 4)
	assert_almost_eq(pos.y, 1.0, 0.001, "elev 4 → y = 1.0 (4 * 0.25)")
	assert_almost_eq(pos.x, 0.0, 0.001, "elev only, x = 0")
	assert_almost_eq(pos.z, 0.0, 0.001, "elev only, z = 0")


# --- Negative coordinates ---

func test_negative_coords() -> void:
	var pos := HexWorld.hex_to_world(-2, -1, 0)
	assert_almost_eq(pos.x, -0.7875, 0.001, "q=-2 x = -0.7875")
	# z = 0.2625 * (sqrt(3)/2 * (-2) + sqrt(3) * (-1)) = 0.2625 * -3.464 = -0.9093
	assert_almost_eq(pos.z, -0.9093, 0.001, "q=-2,r=-1 z = -0.9093")


# --- Combined q, r, elevation ---

func test_combined_q_r_elev() -> void:
	var pos := HexWorld.hex_to_world(2, 3, 2)
	# x = 0.2625 * 1.5 * 2 = 0.7875
	assert_almost_eq(pos.x, 0.7875, 0.001, "q=2 x = 0.7875")
	# z = 0.2625 * (sqrt(3)/2 * 2 + sqrt(3) * 3) = 0.2625 * 6.928 = 1.8187
	assert_almost_eq(pos.z, 1.8187, 0.001, "q=2,r=3 z = 1.8187")
	# y = 2 * 0.25 = 0.5
	assert_almost_eq(pos.y, 0.5, 0.001, "elev 2 → y = 0.5")


# --- Constants are correct ---

func test_hex_size_constant() -> void:
	assert_eq(HexWorld.HEX_SIZE, 0.2625, "HEX_SIZE = 0.2625")


func test_elev_unit_constant() -> void:
	assert_eq(HexWorld.ELEV_UNIT, 0.25, "ELEV_UNIT = 0.25")


# --- A19: direction_yaw helper ---

func test_direction_yaw_returns_float() -> void:
	var yaw := HexWorld.direction_yaw(0)
	assert_true(yaw is float, "direction_yaw should return a float")


func test_direction_yaw_opposite_directions_differ_by_180() -> void:
	## Directions 0 and 3 are opposite; their yaws should differ by 180 degrees.
	var yaw0 := HexWorld.direction_yaw(0)
	var yaw3 := HexWorld.direction_yaw(3)
	var diff := absf(yaw0 - yaw3)
	# Account for wrap-around
	if diff > 180.0:
		diff = 360.0 - diff
	assert_almost_eq(diff, 180.0, 1.0,
		"Opposite directions should differ by ~180 degrees")


func test_direction_yaw_all_six_unique() -> void:
	## All six directions should give distinct yaw angles.
	var yaws: Array[float] = []
	for i in range(6):
		yaws.append(HexWorld.direction_yaw(i))
	for i in range(6):
		for j in range(i + 1, 6):
			assert_true(absf(yaws[i] - yaws[j]) > 0.1,
				"Directions %d and %d should have different yaws" % [i, j])


func test_direction_yaw_normalizes_negative() -> void:
	## direction_yaw(-1) should behave the same as direction_yaw(5).
	var yaw_neg := HexWorld.direction_yaw(-1)
	var yaw_5 := HexWorld.direction_yaw(5)
	assert_almost_eq(yaw_neg, yaw_5, 0.001, "direction_yaw(-1) == direction_yaw(5)")
