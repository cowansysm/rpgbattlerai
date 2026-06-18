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


func test_symbol_material_uses_atlas_with_uv_offset() -> void:
	var mat := PawnFactory.symbol_material("elf", "black_mage", "playerB")
	assert_not_null(mat.albedo_texture, "material should have a texture")
	# make_3d_material uses full atlas + UV offset/scale (not AtlasTexture,
	# which is ignored by the 3D renderer)
	var cell_uv := 1.0 / 8.0  # 64 / 512
	assert_eq(mat.uv1_scale, Vector3(cell_uv, cell_uv, 1.0),
		"UV scale should select one cell from atlas")
	# elf_black_mage is at col 4, row 6
	assert_eq(mat.uv1_offset, Vector3(4.0 * cell_uv, 6.0 * cell_uv, 0.0),
		"UV offset should point to elf_black_mage cell")


func test_symbol_material_is_unshaded() -> void:
	var mat := PawnFactory.symbol_material("human", "archer", "playerA")
	assert_eq(mat.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)


func test_symbol_material_has_alpha_scissor() -> void:
	var mat := PawnFactory.symbol_material("dwarf", "barbarian", "playerB")
	assert_eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)


func test_unknown_race_class_returns_fallback() -> void:
	var mat := PawnFactory.symbol_material("orc", "monk", "playerA")
	assert_not_null(mat, "should return a material even for unknown race+class")
	assert_not_null(mat.albedo_texture, "should have atlas texture for fallback")
	# Fallback "_fallback" is at col 6, row 5 → UV offset (0.75, 0.625, 0)
	var cell_uv := 1.0 / 8.0
	assert_eq(mat.uv1_offset, Vector3(6.0 * cell_uv, 5.0 * cell_uv, 0.0),
		"unknown race+class should use fallback UV offset")
