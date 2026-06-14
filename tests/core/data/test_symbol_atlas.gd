extends GutTest
## Tests for SymbolAtlas — icon lookup and 3D material generation.
## Generates the atlas on-the-fly via IconAtlasGenerator if needed.
## Spec reference: phase9-spec.md §5


func before_all() -> void:
	# Ensure atlas is generated (SymbolAtlas._ensure_loaded falls back to generate)
	SymbolAtlas._atlas = null
	SymbolAtlas._cache = {}


# --- get_icon basic ---

func test_get_icon_returns_atlas_texture_for_known_ability() -> void:
	var tex := SymbolAtlas.get_icon("fire_1")
	assert_not_null(tex, "should return a texture for fire_1")
	assert_true(tex is AtlasTexture, "should be AtlasTexture")
	var region: Rect2 = tex.region
	assert_eq(region, Rect2(0, 0, 64, 64), "fire_1 should be at (0,0)")


func test_get_icon_returns_atlas_texture_for_known_item() -> void:
	var tex := SymbolAtlas.get_icon("sword")
	assert_not_null(tex)
	assert_true(tex is AtlasTexture)
	var region: Rect2 = tex.region
	assert_eq(region, Rect2(0, 128, 64, 64), "sword should be at row 2, col 0")


func test_get_icon_returns_atlas_texture_for_known_status() -> void:
	var tex := SymbolAtlas.get_icon("sleep")
	assert_not_null(tex)
	assert_true(tex is AtlasTexture)
	var region: Rect2 = tex.region
	assert_eq(region, Rect2(0, 256, 64, 64), "sleep should be at row 4, col 0")


# --- Race+class icons ---

func test_get_icon_returns_atlas_texture_for_race_class() -> void:
	var ids := [
		"human_fighter", "human_archer", "human_rogue", "human_bard",
		"elf_black_mage", "elf_red_mage", "halfling_white_mage", "dwarf_barbarian",
	]
	for i in range(ids.size()):
		var tex := SymbolAtlas.get_icon(ids[i])
		assert_not_null(tex, "%s should return non-null" % ids[i])
		assert_true(tex is AtlasTexture, "%s should be AtlasTexture" % ids[i])
		var expected := Rect2(i * 64, 384, 64, 64)  # row 6
		assert_eq(tex.region, expected, "%s region should match" % ids[i])


# --- Fallback ---

func test_get_icon_fallback_for_unknown_id() -> void:
	var tex := SymbolAtlas.get_icon("nonexistent_ability")
	assert_not_null(tex, "fallback should return a valid texture")
	assert_true(tex is AtlasTexture, "fallback should be AtlasTexture")
	# Fallback is at col 6, row 5
	var expected := Rect2(384, 320, 64, 64)
	assert_eq(tex.region, expected, "fallback region should match _fallback position")


# --- Caching ---

func test_get_icon_caches_results() -> void:
	var tex_a := SymbolAtlas.get_icon("fire_1")
	var tex_b := SymbolAtlas.get_icon("fire_1")
	assert_same(tex_a, tex_b, "repeated calls should return the same cached instance")


# --- Coverage: all abilities have icons ---

func test_all_ability_ids_have_icons() -> void:
	var ability_ids := ["fire_1", "fire_2", "ice_1", "thunder_1", "cure_1", "cure_2",
		"shield_1", "power_strike", "backstab", "reckless_swing", "rage", "inspire", "lullaby"]
	for id in ability_ids:
		var tex := SymbolAtlas.get_icon(id)
		assert_not_null(tex, "ability '%s' should have an icon" % id)
		# Verify it's not the fallback
		var fallback_region := Rect2(384, 320, 64, 64)
		assert_ne(tex.region, fallback_region,
			"ability '%s' should not use fallback icon" % id)


func test_all_item_ids_have_icons() -> void:
	var item_ids := ["sword", "daggers", "bow", "staff", "rapier", "greataxe", "sling",
		"light_armor", "medium_armor", "shield", "bracer_of_accuracy", "smoke_bomb_pouch"]
	for id in item_ids:
		var tex := SymbolAtlas.get_icon(id)
		assert_not_null(tex, "item '%s' should have an icon" % id)
		var fallback_region := Rect2(384, 320, 64, 64)
		assert_ne(tex.region, fallback_region,
			"item '%s' should not use fallback icon" % id)


# --- make_3d_material ---

func test_make_3d_material_returns_standard_material() -> void:
	var mat := SymbolAtlas.make_3d_material("sword")
	assert_not_null(mat)
	assert_true(mat is StandardMaterial3D)
	assert_eq(mat.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)


func test_make_3d_material_applies_tint() -> void:
	var tint := Color(0.2, 0.4, 0.9, 0.8)
	var mat := SymbolAtlas.make_3d_material("human_fighter", tint)
	assert_eq(mat.albedo_color, tint, "tint should be applied as albedo_color")
