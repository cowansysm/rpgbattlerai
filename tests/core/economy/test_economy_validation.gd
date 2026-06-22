extends GutTest
## Tests for economy data validation: loot tables and shop pools.


func _make_items_registry() -> EntityRegistry:
	var reg := EntityRegistry.new()
	# Manually add items for testing
	var sword := ItemData.new()
	sword.id = "sword"
	var bow := ItemData.new()
	bow.id = "bow"
	reg._entries = {"sword": sword, "bow": bow}
	return reg


func test_valid_shop_pools_pass() -> void:
	var pools := {"weapons": ["sword", "bow"]}
	var items := _make_items_registry()
	var errors := Validator.validate_shop_pools(pools, items)
	assert_eq(errors.size(), 0)


func test_shop_pool_unknown_item_errors() -> void:
	var pools := {"weapons": ["sword", "nonexistent"]}
	var items := _make_items_registry()
	var errors := Validator.validate_shop_pools(pools, items)
	assert_eq(errors.size(), 1)
	assert_true(errors[0].find("nonexistent") >= 0)


func test_valid_loot_table_passes() -> void:
	var pools := {"weapons": ["sword", "bow"]}
	var items := _make_items_registry()
	var tables := {
		"test": {
			"gold": {"min": 5, "max": 10},
			"drops": [
				{"weight": 3, "kind": "equipment", "pool": "weapons"},
				{"weight": 2, "kind": "nothing"}
			],
			"rolls": 1
		}
	}
	var errors := Validator.validate_loot_tables(tables, pools, items)
	assert_eq(errors.size(), 0)


func test_loot_table_bad_gold_range_errors() -> void:
	var tables := {
		"test": {
			"gold": {"min": 20, "max": 5},
			"drops": [],
			"rolls": 1
		}
	}
	var errors := Validator.validate_loot_tables(tables, {}, _make_items_registry())
	assert_true(errors.size() > 0)


func test_loot_table_unknown_pool_errors() -> void:
	var tables := {
		"test": {
			"gold": {"min": 0, "max": 10},
			"drops": [{"weight": 1, "kind": "equipment", "pool": "nonexistent"}],
			"rolls": 1
		}
	}
	var errors := Validator.validate_loot_tables(tables, {}, _make_items_registry())
	assert_true(errors.size() > 0)
	assert_true(errors[0].find("nonexistent") >= 0)


func test_loot_table_unknown_kind_errors() -> void:
	var tables := {
		"test": {
			"gold": {"min": 0, "max": 10},
			"drops": [{"weight": 1, "kind": "magic"}],
			"rolls": 1
		}
	}
	var errors := Validator.validate_loot_tables(tables, {}, _make_items_registry())
	assert_true(errors.size() > 0)


func test_loot_table_consumable_missing_id_errors() -> void:
	var tables := {
		"test": {
			"gold": {"min": 0, "max": 10},
			"drops": [{"weight": 1, "kind": "consumable"}],
			"rolls": 1
		}
	}
	var errors := Validator.validate_loot_tables(tables, {}, _make_items_registry())
	assert_true(errors.size() > 0)
