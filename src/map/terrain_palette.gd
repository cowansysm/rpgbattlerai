class_name TerrainPalette
extends RefCounted
## Maps terrain type strings to StandardMaterial3D instances.
## MVP flat colors; textures/shaders deferred to Phase 10.

const COLORS: Dictionary = {
	"grass":         Color(0.30, 0.60, 0.25),
	"road":          Color(0.50, 0.50, 0.50),
	"brush":         Color(0.45, 0.70, 0.35),
	"trees":         Color(0.20, 0.45, 0.20),
	"rocks":         Color(0.35, 0.35, 0.38),
	"shallow_water": Color(0.40, 0.70, 0.90, 0.70),
	"deep_water":    Color(0.15, 0.35, 0.70, 0.85),
	"cliff":         Color(0.40, 0.36, 0.32),
}


static func material_for(terrain: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var col: Color = COLORS.get(terrain, Color.MAGENTA)
	mat.albedo_color = col
	if col.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat
