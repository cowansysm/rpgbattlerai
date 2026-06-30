class_name OverlayMaterials
extends RefCounted
## Static factories for overlay materials used by the overlay controller.
## Four visually distinct materials for movement tiers and target states.


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## Tier 1 movement (single move action) — vivid blue.
static func move_tier1() -> StandardMaterial3D:
	return _mat(Color(0.3, 0.55, 1.0, 0.85))


## Tier 2 movement (double move / both AP) — bright cyan-blue.
static func move_tier2() -> StandardMaterial3D:
	return _mat(Color(0.5, 0.8, 1.0, 0.65))


## Valid target (in range + clear LoS) — vivid red.
static func target_valid() -> StandardMaterial3D:
	return _mat(Color(1.0, 0.3, 0.3, 0.85))


## Blocked target (in range but no LoS) — muted grey.
static func target_blocked() -> StandardMaterial3D:
	return _mat(Color(0.6, 0.6, 0.6, 0.6))


## Valid revive target (downed ally in range + clear LoS) — vivid green.
static func revive_valid() -> StandardMaterial3D:
	return _mat(Color(0.3, 1.0, 0.4, 0.85))


## Selectable unit tile (awaiting activation) — gold/yellow.
static func selectable() -> StandardMaterial3D:
	return _mat(Color(1.0, 0.85, 0.2, 0.7))


## Telegraph intent path — faded cyan (distinct from regular movement blue).
static func telegraph_path() -> StandardMaterial3D:
	return _mat(Color(0.4, 0.8, 0.9, 0.5))


## Telegraph intent destination — teal.
static func telegraph_destination() -> StandardMaterial3D:
	return _mat(Color(0.2, 0.9, 0.8, 0.7))


## Telegraph intent target — amber/orange (distinct from regular target red).
static func telegraph_target() -> StandardMaterial3D:
	return _mat(Color(1.0, 0.6, 0.15, 0.75))


## Telegraph AoE footprint — warm orange, softer.
static func telegraph_aoe() -> StandardMaterial3D:
	return _mat(Color(1.0, 0.5, 0.2, 0.55))
