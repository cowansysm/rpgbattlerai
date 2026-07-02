class_name HexWorld
extends RefCounted
## Flat-top hex → 3D world coordinate mapping.
## Consumes HexLayout.F0/F2/F3 constants from Phase 0.

const HEX_SIZE := 0.525   # Center-to-corner radius in world units.
const ELEV_UNIT := 0.25   # World Y per elevation step.


static func hex_to_world(q: int, r: int, elevation: int = 0) -> Vector3:
	var x := HEX_SIZE * (HexLayout.F0 * q + HexLayout.F1 * r)
	var z := HEX_SIZE * (HexLayout.F2 * q + HexLayout.F3 * r)
	var y := elevation * ELEV_UNIT
	return Vector3(x, y, z)


## A19: Returns the yaw angle in degrees for a given Hex direction index (0-5).
## Direction 0 (q+1, r=0) maps to ~30° on flat-top; computed from the DIRECTIONS vector.
## Pure function: no scene-tree dependency. Testable without a running Godot instance.
static func direction_yaw(dir: int) -> float:
	var d: Vector2i = Hex.DIRECTIONS[((dir % 6) + 6) % 6]
	# Axial d → world XZ using the same flat-top transform as hex_to_world
	var wx: float = HEX_SIZE * (HexLayout.F0 * d.x + HexLayout.F1 * d.y)
	var wz: float = HEX_SIZE * (HexLayout.F2 * d.x + HexLayout.F3 * d.y)
	# atan2 in GDScript uses (x, y) convention; we want angle from +Z axis (GD forward)
	return rad_to_deg(atan2(wx, wz))


static func world_to_hex(world_pos: Vector3) -> Vector2i:
	var px := world_pos.x / HEX_SIZE
	var pz := world_pos.z / HEX_SIZE
	# Inverse of flat-top forward matrix [F0,F1; F2,F3]
	var q_frac := (2.0 / 3.0) * px
	var r_frac := (-1.0 / 3.0) * px + (1.0 / sqrt(3.0)) * pz
	# Convert fractional axial to cube, round, convert back
	var s_frac := -q_frac - r_frac
	return Hex.cube_to_axial(Hex.cube_round(q_frac, s_frac, r_frac))
