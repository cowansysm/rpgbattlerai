extends GutTest
## Tests for BattleBand model: roster ops, inventory, serialization.


func _make_instance(id: String, template: String = "human_fighter") -> CharacterInstance:
	var ci := CharacterInstance.new()
	ci.instance_id = id
	ci.template_id = template
	ci.name = "Hero " + id
	ci.race = "human"
	ci.level = 3
	ci.active_class = "vagabond"
	ci.unlocked_classes = ["vagabond"] as Array[String]
	return ci


func test_create_generates_unique_id() -> void:
	var a := BattleBand.create("Band A")
	var b := BattleBand.create("Band B")
	assert_ne(a.band_id, b.band_id)
	assert_eq(a.name, "Band A")
	assert_eq(a.gold, 0)
	assert_eq(a.roster_size(), 0)


func test_add_instance_succeeds() -> void:
	var band := BattleBand.create("Test")
	var ci := _make_instance("ci_1")
	assert_true(band.add_instance(ci, 12))
	assert_eq(band.roster_size(), 1)
	assert_eq(band.roster[0].instance_id, "ci_1")


func test_add_instance_rejects_when_full() -> void:
	var band := BattleBand.create("Test")
	assert_true(band.add_instance(_make_instance("ci_1"), 2))
	assert_true(band.add_instance(_make_instance("ci_2"), 2))
	assert_false(band.add_instance(_make_instance("ci_3"), 2))
	assert_eq(band.roster_size(), 2)


func test_get_instance_by_id() -> void:
	var band := BattleBand.create("Test")
	band.add_instance(_make_instance("ci_1"), 12)
	band.add_instance(_make_instance("ci_2"), 12)
	var found := band.get_instance("ci_2")
	assert_not_null(found)
	assert_eq(found.instance_id, "ci_2")
	assert_null(band.get_instance("nonexistent"))


func test_remove_instance_returns_gear_to_inventory() -> void:
	var band := BattleBand.create("Test")
	var ci := _make_instance("ci_1")
	ci.equipment = {"weapon": "sword", "armor": "light_armor"}
	band.add_instance(ci, 12)
	var removed := band.remove_instance("ci_1")
	assert_not_null(removed)
	assert_eq(removed.instance_id, "ci_1")
	assert_eq(removed.equipment.size(), 0)
	assert_eq(band.roster_size(), 0)
	# Gear should be in inventory
	var equip: Array = band.inventory["equipment"]
	assert_true(equip.has("sword"))
	assert_true(equip.has("light_armor"))


func test_remove_instance_not_found() -> void:
	var band := BattleBand.create("Test")
	assert_null(band.remove_instance("nonexistent"))


func test_inventory_add_remove() -> void:
	var band := BattleBand.create("Test")
	band.add_to_inventory("sword")
	band.add_to_inventory("bow")
	var equip: Array = band.inventory["equipment"]
	assert_eq(equip.size(), 2)
	assert_true(band.remove_from_inventory("sword"))
	assert_eq(equip.size(), 1)
	assert_false(band.remove_from_inventory("nonexistent"))


func test_round_trip_to_dict_from_dict() -> void:
	var band := BattleBand.create("The Brave")
	band.gold = 150
	band.add_to_inventory("shield")
	band.add_to_inventory("staff")
	var ci1 := _make_instance("ci_1")
	ci1.equipment = {"weapon": "sword"}
	ci1.jp = {"vagabond": 25}
	band.add_instance(ci1, 12)
	band.add_instance(_make_instance("ci_2"), 12)

	var d := band.to_dict()
	var restored := BattleBand.from_dict(d)
	assert_eq(restored.band_id, band.band_id)
	assert_eq(restored.name, "The Brave")
	assert_eq(restored.gold, 150)
	assert_eq(restored.roster_size(), 2)
	assert_eq(restored.roster[0].instance_id, "ci_1")
	assert_eq(restored.roster[0].jp, {"vagabond": 25})
	assert_eq(restored.roster[0].equipment, {"weapon": "sword"})
	assert_eq(restored.roster[1].instance_id, "ci_2")
	var equip: Array = restored.inventory["equipment"]
	assert_eq(equip.size(), 2)
	assert_true(equip.has("shield"))
	assert_true(equip.has("staff"))


func test_round_trip_through_json() -> void:
	var band := BattleBand.create("JSON Test")
	band.gold = 99
	band.add_instance(_make_instance("ci_json"), 12)
	var json_str := JSON.stringify(band.to_dict())
	var parsed: Variant = JSON.parse_string(json_str)
	assert_true(parsed is Dictionary)
	var restored := BattleBand.from_dict(parsed as Dictionary)
	assert_eq(restored.name, "JSON Test")
	assert_eq(restored.gold, 99)
	assert_eq(restored.roster_size(), 1)


func test_from_dict_defaults_on_empty() -> void:
	var band := BattleBand.from_dict({})
	assert_eq(band.band_id, "")
	assert_eq(band.name, "New Band")
	assert_eq(band.gold, 0)
	assert_eq(band.roster_size(), 0)
	assert_true(band.inventory.has("equipment"))
	assert_true(band.inventory.has("consumables"))
