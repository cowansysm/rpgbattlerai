class_name OverlayMaterials
extends RefCounted
## Static factories for overlay materials used by the overlay controller.
## Four visually distinct materials for movement tiers and target states.


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## Tier 1 movement (single move action) — strong blue.
static func move_tier1() -> StandardMaterial3D:
	return _mat(Color(0.3, 0.5, 1.0, 0.7))


## Tier 2 movement (double move / both AP) — light blue.
static func move_tier2() -> StandardMaterial3D:
	return _mat(Color(0.5, 0.8, 1.0, 0.5))


## Valid target (in range + clear LoS) — red.
static func target_valid() -> StandardMaterial3D:
	return _mat(Color(1.0, 0.3, 0.3, 0.7))


## Blocked target (in range but no LoS) — grey.
static func target_blocked() -> StandardMaterial3D:
	return _mat(Color(0.5, 0.5, 0.5, 0.5))
