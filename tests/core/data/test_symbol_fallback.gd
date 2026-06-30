extends GutTest
## Tests for SymbolAtlas.symbol_for_ability() fallback chain.


func _make_ability(id: String, effect: Dictionary = {},
		etype: String = "") -> AbilityData:
	var a := AbilityData.new()
	a.id = id
	a.effect = effect
	a.effect_type = etype
	return a


func test_exact_match_returns_ability_id() -> void:
	var ability := _make_ability("fire_1")
	assert_eq(SymbolAtlas.symbol_for_ability(ability), "fire_1",
		"ability with exact icon match should return its id")


func test_exact_match_skill() -> void:
	var ability := _make_ability("power_strike")
	assert_eq(SymbolAtlas.symbol_for_ability(ability), "power_strike",
		"skill with exact icon match should return its id")


func test_element_fallback_fire() -> void:
	var ability := _make_ability("flame_burst_99",
		{"element": "fire", "effect_type": "damage"})
	assert_eq(SymbolAtlas.symbol_for_ability(ability), "elem_fire",
		"unknown ability with fire element should fall back to elem_fire")


func test_element_fallback_ice() -> void:
	var ability := _make_ability("blizzard_99",
		{"element": "ice", "effect_type": "damage"})
	assert_eq(SymbolAtlas.symbol_for_ability(ability), "elem_ice",
		"unknown ability with ice element should fall back to elem_ice")


func test_element_fallback_lightning() -> void:
	var ability := _make_ability("shock_99",
		{"element": "lightning", "effect_type": "damage"})
	assert_eq(SymbolAtlas.symbol_for_ability(ability), "elem_lightning",
		"unknown ability with lightning element should fall back to elem_lightning")


func test_element_fallback_holy() -> void:
	var ability := _make_ability("smite_99",
		{"element": "holy", "effect_type": "damage"})
	assert_eq(SymbolAtlas.symbol_for_ability(ability), "elem_holy",
		"unknown ability with holy element should fall back to elem_holy")


func test_element_fallback_dark() -> void:
	var ability := _make_ability("shadow_99",
		{"element": "dark", "effect_type": "damage"})
	assert_eq(SymbolAtlas.symbol_for_ability(ability), "elem_dark",
		"unknown ability with dark element should fall back to elem_dark")


func test_effect_type_fallback_damage() -> void:
	var ability := _make_ability("generic_slash_99",
		{"effect_type": "damage"})
	assert_eq(SymbolAtlas.symbol_for_ability(ability), "fx_damage",
		"unknown ability with damage effect_type should fall back to fx_damage")


func test_effect_type_fallback_heal() -> void:
	var ability := _make_ability("generic_heal_99",
		{"effect_type": "heal"})
	assert_eq(SymbolAtlas.symbol_for_ability(ability), "fx_heal",
		"unknown ability with heal effect_type should fall back to fx_heal")


func test_effect_type_fallback_buff() -> void:
	var ability := _make_ability("generic_buff_99",
		{"effect_type": "buff"})
	assert_eq(SymbolAtlas.symbol_for_ability(ability), "fx_buff",
		"unknown ability with buff effect_type should fall back to fx_buff")


func test_effect_type_fallback_status() -> void:
	var ability := _make_ability("generic_hex_99",
		{"effect_type": "status"})
	assert_eq(SymbolAtlas.symbol_for_ability(ability), "fx_status",
		"unknown ability with status effect_type should fall back to fx_status")


func test_effect_type_fallback_revive() -> void:
	var ability := _make_ability("generic_revive_99",
		{"effect_type": "revive"})
	assert_eq(SymbolAtlas.symbol_for_ability(ability), "fx_revive",
		"unknown ability with revive effect_type should fall back to fx_revive")


func test_effect_type_from_field() -> void:
	# When effect dict has no effect_type but AbilityData.effect_type is set
	var ability := _make_ability("custom_99", {}, "heal")
	assert_eq(SymbolAtlas.symbol_for_ability(ability), "fx_heal",
		"should use AbilityData.effect_type when effect dict lacks it")


func test_default_fallback() -> void:
	var ability := _make_ability("completely_unknown_99")
	assert_eq(SymbolAtlas.symbol_for_ability(ability), "action_ability",
		"unknown ability with no element or effect_type should fall back to action_ability")


func test_null_ability_returns_default() -> void:
	assert_eq(SymbolAtlas.symbol_for_ability(null), "action_ability",
		"null ability should fall back to action_ability")


func test_element_takes_priority_over_effect_type() -> void:
	var ability := _make_ability("dual_99",
		{"element": "fire", "effect_type": "damage"})
	assert_eq(SymbolAtlas.symbol_for_ability(ability), "elem_fire",
		"element should take priority over effect_type in fallback chain")


func test_unknown_element_falls_to_effect_type() -> void:
	var ability := _make_ability("void_99",
		{"element": "void", "effect_type": "damage"})
	assert_eq(SymbolAtlas.symbol_for_ability(ability), "fx_damage",
		"unknown element should fall through to effect_type")


func test_unknown_element_and_type_falls_to_default() -> void:
	var ability := _make_ability("exotic_99",
		{"element": "void", "effect_type": "exotic"})
	assert_eq(SymbolAtlas.symbol_for_ability(ability), "action_ability",
		"unknown element and effect_type should fall to default")
