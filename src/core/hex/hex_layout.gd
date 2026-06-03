class_name HexLayout
extends RefCounted
## Flat-top hex layout constants.
## Pixel/layout math is consumed in Phase 2 (rendering);
## defined here so the orientation decision is committed in Phase 0.

const ORIENTATION := "flat_top"

# Flat-top forward conversion matrix (size applied in Phase 2):
#   x = size * (F0 * q + F1 * r)
#   z = size * (F2 * q + F3 * r)
const F0 := 1.5                     # 3/2
const F1 := 0.0
const F2 := 0.8660254037844386      # sqrt(3)/2
const F3 := 1.7320508075688772      # sqrt(3)
