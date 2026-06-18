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
	"rubble":        Color(0.45, 0.40, 0.35),
	"barricade":     Color(0.55, 0.45, 0.30),
	"lava":          Color(0.85, 0.25, 0.10),
	"spikes":        Color(0.50, 0.50, 0.55),
	"bog":           Color(0.35, 0.45, 0.25),
}


static func material_for(terrain: String, elevation: int = 0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var col: Color = COLORS.get(terrain, Color.MAGENTA)
	col = _elevation_tint(col, elevation)
	mat.albedo_color = col
	if col.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


static func wall_material(terrain: String, elevation: int = 0) -> StandardMaterial3D:
	## Darkened, opaque material for the vertical side face of a hex tile.
	var mat := StandardMaterial3D.new()
	var col: Color = COLORS.get(terrain, Color.MAGENTA)
	col = _elevation_tint(col, elevation)
	col = col.darkened(0.35)
	col.a = 1.0
	mat.albedo_color = col
	return mat


static func _elevation_tint(color: Color, elevation: int) -> Color:
	## Darken low elevations, lighten high elevations for visual depth.
	## Elev 0 is slightly dark; each step lightens by 6%.
	var shift := -0.10 + elevation * 0.06
	if shift > 0.0:
		return color.lightened(minf(shift, 0.25))
	elif shift < 0.0:
		return color.darkened(minf(-shift, 0.25))
	return color
