class_name HexWorld
extends RefCounted
## Flat-top hex → 3D world coordinate mapping.
## Consumes HexLayout.F0/F2/F3 constants from Phase 0.

const HEX_SIZE := 1.0   # Center-to-corner radius in world units.
const ELEV_UNIT := 0.5   # World Y per elevation step.


static func hex_to_world(q: int, r: int, elevation: int = 0) -> Vector3:
	var x := HEX_SIZE * (HexLayout.F0 * q + HexLayout.F1 * r)
	var z := HEX_SIZE * (HexLayout.F2 * q + HexLayout.F3 * r)
	var y := elevation * ELEV_UNIT
	return Vector3(x, y, z)
