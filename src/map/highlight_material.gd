class_name HighlightMaterial
extends RefCounted
## Factory for the tile selection highlight material.

static func make() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.2, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.1)
	mat.emission_energy_multiplier = 0.8
	return mat
