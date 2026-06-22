extends GutTest
## Tests for BpCalculator.compute.


func _make_item(id: String, bp: int) -> ItemData:
	var item := ItemData.new()
	item.id = id
	item.bp_value = bp
	item.slot = "weapon"
	return item


func _item_provider(items: Dictionary) -> Callable:
	return func(id: String) -> ItemData: return items.get(id, null)


func test_level_contributes_to_bp() -> void:
	var ci := CharacterInstance.new()
	ci.level = 1
	var bp1 := BpCalculator.compute(ci, _item_provider({}))
	ci.level = 5
	var bp5 := BpCalculator.compute(ci, _item_provider({}))
	assert_gt(bp5, bp1)
	assert_eq(bp1, 3)   # 1 * 3
	assert_eq(bp5, 15)  # 5 * 3


func test_equipment_adds_bp() -> void:
	var ci := CharacterInstance.new()
	ci.level = 1
	ci.equipment = {"weapon": "sword"}
	var items := {"sword": _make_item("sword", 5)}
	var bp := BpCalculator.compute(ci, _item_provider(items))
	assert_eq(bp, 8)  # 1*3 + 5


func test_loadout_adds_bp() -> void:
	var ci := CharacterInstance.new()
	ci.level = 1
	ci.ability_loadout = ["fire_1", "heal_1"] as Array[String]
	var bp := BpCalculator.compute(ci, _item_provider({}))
	assert_eq(bp, 7)  # 1*3 + 2*2


func test_combined() -> void:
	var ci := CharacterInstance.new()
	ci.level = 3
	ci.equipment = {"weapon": "sword", "armor": "plate"}
	ci.ability_loadout = ["fire_1"] as Array[String]
	var items := {"sword": _make_item("sword", 2), "plate": _make_item("plate", 3)}
	var bp := BpCalculator.compute(ci, _item_provider(items))
	assert_eq(bp, 16)  # 3*3 + 2 + 3 + 1*2


func test_missing_item_ignored() -> void:
	var ci := CharacterInstance.new()
	ci.level = 1
	ci.equipment = {"weapon": "nonexistent"}
	var bp := BpCalculator.compute(ci, _item_provider({}))
	assert_eq(bp, 3)  # Only level, missing item skipped
