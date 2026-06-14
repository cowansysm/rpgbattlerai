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
	assert_almost_eq(pos.x, 0.7875, 0.001, "q=1 x = 0.7875")
	assert_almost_eq(pos.z, 0.455, 0.001, "q=1 z = sqrt(3)/2 * 0.525")
	assert_almost_eq(pos.y, 0.0, 0.001, "q=1 y = 0")


# --- R axis (flat-top: x = 0, z = sqrt(3) * r) ---

func test_r_axis() -> void:
	var pos := HexWorld.hex_to_world(0, 1, 0)
	assert_almost_eq(pos.x, 0.0, 0.001, "r=1 x = 0")
	assert_almost_eq(pos.z, 0.909, 0.001, "r=1 z = sqrt(3) * 0.525")
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
	assert_almost_eq(pos.x, -1.575, 0.001, "q=-2 x = -1.575")
	# z = 0.525 * (sqrt(3)/2 * (-2) + sqrt(3) * (-1)) = 0.525 * -3.464 = -1.819
	assert_almost_eq(pos.z, -1.819, 0.001, "q=-2,r=-1 z = -1.819")


# --- Combined q, r, elevation ---

func test_combined_q_r_elev() -> void:
	var pos := HexWorld.hex_to_world(2, 3, 2)
	# x = 0.525 * 1.5 * 2 = 1.575
	assert_almost_eq(pos.x, 1.575, 0.001, "q=2 x = 1.575")
	# z = 0.525 * (sqrt(3)/2 * 2 + sqrt(3) * 3) = 0.525 * 6.928 = 3.637
	assert_almost_eq(pos.z, 3.637, 0.001, "q=2,r=3 z = 3.637")
	# y = 2 * 0.25 = 0.5
	assert_almost_eq(pos.y, 0.5, 0.001, "elev 2 → y = 0.5")


# --- Constants are correct ---

func test_hex_size_constant() -> void:
	assert_eq(HexWorld.HEX_SIZE, 0.525, "HEX_SIZE = 0.525")


func test_elev_unit_constant() -> void:
	assert_eq(HexWorld.ELEV_UNIT, 0.25, "ELEV_UNIT = 0.25")
