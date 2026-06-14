class_name SymbolAtlas
extends RefCounted
## Static icon lookup from the procedurally generated symbol atlas.
## Provides AtlasTexture sub-regions for 2D UI and StandardMaterial3D
## for 3D world rendering. Lazy-loads the atlas PNG on first access.
## Spec reference: phase9-spec.md §5

const CELL_SIZE := 64
const ATLAS_PATH := "res://assets/icons/symbol_atlas.png"

# Maps icon ID → Vector2i(col, row) in the atlas grid.
# Rows 0-5: entity categories. Row 6: race+class identity.
const ICON_MAP := {
	# Spells (row 0)
	"fire_1":          Vector2i(0, 0),
	"fire_2":          Vector2i(1, 0),
	"ice_1":           Vector2i(2, 0),
	"thunder_1":       Vector2i(3, 0),
	"cure_1":          Vector2i(4, 0),
	"cure_2":          Vector2i(5, 0),
	"shield_1":        Vector2i(6, 0),
	# Skills (row 1)
	"power_strike":    Vector2i(0, 1),
	"backstab":        Vector2i(1, 1),
	"reckless_swing":  Vector2i(2, 1),
	"rage":            Vector2i(3, 1),
	"inspire":         Vector2i(4, 1),
	"lullaby":         Vector2i(5, 1),
	# Weapons (row 2)
	"sword":           Vector2i(0, 2),
	"daggers":         Vector2i(1, 2),
	"bow":             Vector2i(2, 2),
	"staff":           Vector2i(3, 2),
	"rapier":          Vector2i(4, 2),
	"greataxe":        Vector2i(5, 2),
	"sling":           Vector2i(6, 2),
	# Equipment (row 3)
	"light_armor":     Vector2i(0, 3),
	"medium_armor":    Vector2i(1, 3),
	"shield":          Vector2i(2, 3),
	"bracer_of_accuracy": Vector2i(3, 3),
	"smoke_bomb_pouch":Vector2i(4, 3),
	# Status effects (row 4)
	"sleep":           Vector2i(0, 4),
	"blind":           Vector2i(1, 4),
	"defend":          Vector2i(2, 4),
	# Actions + fallback (row 5)
	"action_move":     Vector2i(0, 5),
	"action_attack":   Vector2i(1, 5),
	"action_ability":  Vector2i(2, 5),
	"action_item":     Vector2i(3, 5),
	"action_defend":   Vector2i(4, 5),
	"action_wait":     Vector2i(5, 5),
	"_fallback":       Vector2i(6, 5),
	# Race+class identity (row 6)
	"human_fighter":       Vector2i(0, 6),
	"human_archer":        Vector2i(1, 6),
	"human_rogue":         Vector2i(2, 6),
	"human_bard":          Vector2i(3, 6),
	"elf_black_mage":      Vector2i(4, 6),
	"elf_red_mage":        Vector2i(5, 6),
	"halfling_white_mage": Vector2i(6, 6),
	"dwarf_barbarian":     Vector2i(7, 6),
}

static var _atlas: Texture2D = null
static var _cache: Dictionary = {}


static func get_icon(id: String) -> AtlasTexture:
	## Returns an AtlasTexture for the given icon ID.
	## Falls back to "_fallback" if the ID is unknown.
	_ensure_loaded()
	if not id in ICON_MAP:
		id = "_fallback"
	if _cache.has(id):
		return _cache[id]
	var pos: Vector2i = ICON_MAP[id]
	var tex := _make_region(pos.x, pos.y)
	_cache[id] = tex
	return tex


static func make_3d_material(id: String, tint: Color = Color.WHITE) -> StandardMaterial3D:
	## Returns an unshaded, alpha-scissor StandardMaterial3D for 3D meshes.
	## Uses the full atlas texture with UV offset/scale to select the correct
	## cell, because AtlasTexture sub-regions are ignored by the 3D renderer.
	_ensure_loaded()
	if not id in ICON_MAP:
		id = "_fallback"
	var pos: Vector2i = ICON_MAP[id]
	var cell_uv := 1.0 / 8.0  # 64 / 512 = 0.125

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _atlas
	mat.albedo_color = tint
	mat.uv1_scale = Vector3(cell_uv, cell_uv, 1.0)
	mat.uv1_offset = Vector3(float(pos.x) * cell_uv, float(pos.y) * cell_uv, 0.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.1
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


static func _ensure_loaded() -> void:
	if _atlas != null:
		return
	# Try resource load first (works in-engine), fall back to file load (headless tests)
	var tex = load(ATLAS_PATH)
	if tex:
		_atlas = tex
		return
	# File-based fallback for headless/test environments
	var img := Image.load_from_file(ATLAS_PATH)
	if img and not img.is_empty():
		_atlas = ImageTexture.create_from_image(img)
	else:
		# Generate on the fly if PNG doesn't exist yet
		_atlas = ImageTexture.create_from_image(IconAtlasGenerator.generate())


static func _make_region(col: int, row: int) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = _atlas
	tex.region = Rect2(col * CELL_SIZE, row * CELL_SIZE, CELL_SIZE, CELL_SIZE)
	return tex
