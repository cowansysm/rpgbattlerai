extends GutTest
## Tests for PawnFactory atlas delegation (Phase 9 refactor).
## Verifies symbol_material() now returns atlas-backed materials via SymbolAtlas.
## Spec reference: phase9-spec.md §7.10


func before_all() -> void:
	# Ensure atlas is available
	SymbolAtlas._atlas = null
	SymbolAtlas._cache = {}


func test_symbol_material_returns_standard_material() -> void:
	var mat := PawnFactory.symbol_material("human", "fighter", "playerA")
	assert_not_null(mat)
	assert_true(mat is StandardMaterial3D, "should return StandardMaterial3D")


func test_symbol_material_applies_team_tint() -> void:
	var mat := PawnFactory.symbol_material("human", "fighter", "playerA")
	# Team A base color is (0.2, 0.4, 0.9), lightened by 0.3, alpha 0.8
	var expected := Color(0.2, 0.4, 0.9).lightened(0.3)
	expected.a = 0.8
	assert_eq(mat.albedo_color, expected,
		"material should have team-tinted albedo_color")


func test_symbol_material_uses_atlas_texture() -> void:
	var mat := PawnFactory.symbol_material("elf", "black_mage", "playerB")
	assert_not_null(mat.albedo_texture, "material should have a texture")
	assert_true(mat.albedo_texture is AtlasTexture,
		"texture should be an AtlasTexture from the atlas")


func test_symbol_material_is_unshaded() -> void:
	var mat := PawnFactory.symbol_material("human", "archer", "playerA")
	assert_eq(mat.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)


func test_symbol_material_has_alpha_scissor() -> void:
	var mat := PawnFactory.symbol_material("dwarf", "barbarian", "playerB")
	assert_eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)


func test_unknown_race_class_returns_fallback() -> void:
	var mat := PawnFactory.symbol_material("orc", "monk", "playerA")
	assert_not_null(mat, "should return a material even for unknown race+class")
	assert_true(mat.albedo_texture is AtlasTexture,
		"should still return atlas-backed texture (fallback)")
	# Fallback is at col 6, row 5 → region (384, 320, 64, 64)
	var tex: AtlasTexture = mat.albedo_texture
	assert_eq(tex.region, Rect2(384, 320, 64, 64),
		"unknown race+class should use fallback icon")
