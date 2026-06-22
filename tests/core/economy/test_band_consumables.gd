extends GutTest
## Tests for BattleBand consumable helpers: add/stack/remove/qty.


func test_add_consumable_creates_entry() -> void:
	var band := BattleBand.create("Test")
	band.add_consumable("potion", 1)
	assert_eq(band.consumable_qty("potion"), 1)
	assert_true(band.has_consumable("potion"))


func test_add_consumable_stacks() -> void:
	var band := BattleBand.create("Test")
	band.add_consumable("potion", 2)
	band.add_consumable("potion", 3)
	assert_eq(band.consumable_qty("potion"), 5)


func test_remove_consumable_decrements() -> void:
	var band := BattleBand.create("Test")
	band.add_consumable("potion", 3)
	assert_true(band.remove_consumable("potion", 1))
	assert_eq(band.consumable_qty("potion"), 2)


func test_remove_consumable_removes_entry_at_zero() -> void:
	var band := BattleBand.create("Test")
	band.add_consumable("potion", 2)
	assert_true(band.remove_consumable("potion", 2))
	assert_false(band.has_consumable("potion"))
	assert_eq(band.consumable_qty("potion"), 0)


func test_remove_consumable_rejects_insufficient() -> void:
	var band := BattleBand.create("Test")
	band.add_consumable("potion", 1)
	assert_false(band.remove_consumable("potion", 5))
	assert_eq(band.consumable_qty("potion"), 1)  # Unchanged


func test_remove_consumable_rejects_unheld() -> void:
	var band := BattleBand.create("Test")
	assert_false(band.remove_consumable("nonexistent"))


func test_consumable_qty_zero_for_unheld() -> void:
	var band := BattleBand.create("Test")
	assert_eq(band.consumable_qty("nonexistent"), 0)
	assert_false(band.has_consumable("nonexistent"))


func test_consumable_serialization_round_trip() -> void:
	var band := BattleBand.create("Test")
	band.add_consumable("potion", 3)
	band.add_consumable("antidote", 1)

	var d := band.to_dict()
	var restored := BattleBand.from_dict(d)

	assert_eq(restored.consumable_qty("potion"), 3)
	assert_eq(restored.consumable_qty("antidote"), 1)


func test_consumable_json_round_trip() -> void:
	var band := BattleBand.create("Test")
	band.add_consumable("potion", 5)
	var json_str := JSON.stringify(band.to_dict())
	var parsed: Variant = JSON.parse_string(json_str)
	assert_true(parsed is Dictionary)
	var restored := BattleBand.from_dict(parsed as Dictionary)
	assert_eq(restored.consumable_qty("potion"), 5)
