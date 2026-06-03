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
	assert_almost_eq(pos.x, 1.5, 0.001, "q=1 x = 1.5")
	assert_almost_eq(pos.z, 0.866, 0.001, "q=1 z = sqrt(3)/2")
	assert_almost_eq(pos.y, 0.0, 0.001, "q=1 y = 0")


# --- R axis (flat-top: x = 0, z = sqrt(3) * r) ---

func test_r_axis() -> void:
	var pos := HexWorld.hex_to_world(0, 1, 0)
	assert_almost_eq(pos.x, 0.0, 0.001, "r=1 x = 0")
	assert_almost_eq(pos.z, 1.732, 0.001, "r=1 z = sqrt(3)")
	assert_almost_eq(pos.y, 0.0, 0.001, "r=1 y = 0")


# --- Elevation maps to Y ---

func test_elevation_scales_y() -> void:
	var pos := HexWorld.hex_to_world(0, 0, 4)
	assert_almost_eq(pos.y, 2.0, 0.001, "elev 4 → y = 2.0 (4 * 0.5)")
	assert_almost_eq(pos.x, 0.0, 0.001, "elev only, x = 0")
	assert_almost_eq(pos.z, 0.0, 0.001, "elev only, z = 0")


# --- Negative coordinates ---

func test_negative_coords() -> void:
	var pos := HexWorld.hex_to_world(-2, -1, 0)
	assert_almost_eq(pos.x, -3.0, 0.001, "q=-2 x = -3.0")
	# z = sqrt(3)/2 * (-2) + sqrt(3) * (-1) = -1.732 - 1.732 = -3.464
	assert_almost_eq(pos.z, -3.464, 0.001, "q=-2,r=-1 z = -3.464")


# --- Combined q, r, elevation ---

func test_combined_q_r_elev() -> void:
	var pos := HexWorld.hex_to_world(2, 3, 2)
	# x = 1.5 * 2 = 3.0
	assert_almost_eq(pos.x, 3.0, 0.001, "q=2 x = 3.0")
	# z = sqrt(3)/2 * 2 + sqrt(3) * 3 = 1.732 + 5.196 = 6.928
	assert_almost_eq(pos.z, 6.928, 0.001, "q=2,r=3 z = 6.928")
	# y = 2 * 0.5 = 1.0
	assert_almost_eq(pos.y, 1.0, 0.001, "elev 2 → y = 1.0")


# --- Constants are correct ---

func test_hex_size_constant() -> void:
	assert_eq(HexWorld.HEX_SIZE, 1.0, "HEX_SIZE = 1.0")


func test_elev_unit_constant() -> void:
	assert_eq(HexWorld.ELEV_UNIT, 0.5, "ELEV_UNIT = 0.5")
