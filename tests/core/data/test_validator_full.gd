extends GutTest
## Tests for all structural validators. Includes migrated Phase 0 character validation tests.

# --- Character validation (migrated from Phase 0 test_loader.gd) ---

func test_valid_character_passes() -> void:
	var d := {"id": "test", "race": "human", "classes": ["fighter"], "level": 1, "bp": 5,
		"base_stats": {"spd": 3, "atk": 2, "rng": 2, "def": 1, "hp": 10}}
	assert_eq(Validator.validate_character(d).size(), 0)


func test_character_missing_required_fields() -> void:
	var d := {"id": "broken"}
	assert_true(Validator.validate_character(d).size() > 0)


func test_character_missing_base_stats() -> void:
	var d := {"id": "no_stats", "race": "human", "classes": ["fighter"], "level": 1, "bp": 5}
	assert_true(Validator.validate_character(d).size() > 0)


func test_character_invalid_stat_key() -> void:
	var d := {"id": "bad_key", "race": "human", "classes": ["fighter"], "level": 1, "bp": 5,
		"base_stats": {"spd": 3, "magic_power": 5, "hp": 10}}
	assert_true(Validator.validate_character(d).size() > 0)


func test_character_zero_hp_rejected() -> void:
	var d := {"id": "dead", "race": "human", "classes": ["fighter"], "level": 1, "bp": 5,
		"base_stats": {"spd": 3, "atk": 2, "rng": 1, "def": 1, "hp": 0}}
	assert_true(Validator.validate_character(d).size() > 0)


# --- Race validation ---

func test_valid_race_passes() -> void:
	var d := {"id": "human", "display_name": "Human", "stat_modifiers": {}}
	assert_eq(Validator.validate_race(d).size(), 0)


func test_race_bad_stat_key() -> void:
	var d := {"id": "bad", "display_name": "Bad", "stat_modifiers": {"magic": 1}}
	assert_true(Validator.validate_race(d).size() > 0)


# --- Class validation ---

func test_valid_class_passes() -> void:
	var d := {"id": "fighter", "stat_modifiers": {"atk": 1}}
	assert_eq(Validator.validate_class(d).size(), 0)


func test_valid_class_with_level_max_and_required_classes() -> void:
	var d := {"id": "knight", "stats": {"atk": 2},
		"level_max": 5, "required_classes": [["fighter", 2]]}
	assert_eq(Validator.validate_class(d).size(), 0)


func test_class_level_max_zero_rejected() -> void:
	var d := {"id": "bad", "stats": {}, "level_max": 0}
	assert_true(Validator.validate_class(d).size() > 0, "level_max 0 should be rejected")


func test_class_level_max_negative_rejected() -> void:
	var d := {"id": "bad", "stats": {}, "level_max": -1}
	assert_true(Validator.validate_class(d).size() > 0, "negative level_max should be rejected")


func test_class_required_classes_bad_structure_rejected() -> void:
	var d := {"id": "bad", "stats": {}, "required_classes": "not_an_array"}
	assert_true(Validator.validate_class(d).size() > 0, "non-array required_classes should be rejected")


func test_class_required_classes_bad_pair_rejected() -> void:
	var d := {"id": "bad", "stats": {}, "required_classes": [["fighter"]]}
	assert_true(Validator.validate_class(d).size() > 0, "pair with wrong element count should be rejected")


func test_class_required_classes_bad_level_rejected() -> void:
	var d := {"id": "bad", "stats": {}, "required_classes": [["fighter", 0]]}
	assert_true(Validator.validate_class(d).size() > 0, "pair with level 0 should be rejected")


# --- Ability validation ---

func test_valid_ability_passes() -> void:
	var d := {"id": "fire_1", "type": "spell", "effect": {"effect_type": "damage", "value": 4}}
	assert_eq(Validator.validate_ability(d).size(), 0)


func test_ability_bad_type_rejected() -> void:
	var d := {"id": "bad", "type": "unknown_type"}
	assert_true(Validator.validate_ability(d).size() > 0)


func test_passive_ability_exempt_from_effect_validation() -> void:
	var d := {"id": "aura", "type": "passive", "effect": {}}
	assert_eq(Validator.validate_ability(d).size(), 0, "passive abilities skip effect validation")


func test_ability_missing_effect_type() -> void:
	var d := {"id": "bad", "type": "skill", "effect": {"value": 5}}
	var errors := Validator.validate_ability(d)
	assert_true(errors.size() > 0, "non-passive ability with effect missing effect_type should fail")


func test_ability_unknown_effect_type() -> void:
	var d := {"id": "bad", "type": "spell", "effect": {"effect_type": "explode"}}
	assert_true(Validator.validate_ability(d).size() > 0)


func test_damage_effect_missing_value() -> void:
	var e := Validator.validate_ability_effect({"effect_type": "damage"}, "test")
	assert_true(e.size() > 0)


func test_buff_effect_missing_fields() -> void:
	var e := Validator.validate_ability_effect({"effect_type": "buff"}, "test")
	assert_true(e.size() > 0, "buff effect without stat/value/duration should fail")


func test_buff_effect_bad_stat() -> void:
	var e := Validator.validate_ability_effect(
		{"effect_type": "buff", "stat": "magic", "value": 2, "duration": 3}, "test")
	assert_true(e.size() > 0, "buff targeting unknown stat should fail")


func test_status_effect_missing_fields() -> void:
	var e := Validator.validate_ability_effect({"effect_type": "status"}, "test")
	assert_true(e.size() > 0, "status effect without status_id/duration should fail")


# --- Item validation ---

func test_valid_item_passes() -> void:
	var d := {"id": "bow", "slot": "weapon", "bp_value": 2}
	assert_eq(Validator.validate_item(d).size(), 0)


func test_item_bad_slot_rejected() -> void:
	var d := {"id": "bad", "slot": "helmet", "bp_value": 1}
	assert_true(Validator.validate_item(d).size() > 0)


func test_item_non_numeric_passive_rejected() -> void:
	var d := {"id": "bad", "slot": "accessory", "bp_value": 1, "passive": {"accuracy": "+1"}}
	assert_true(Validator.validate_item(d).size() > 0, "string passive value should fail")


func test_item_numeric_passive_accepted() -> void:
	var d := {"id": "bracer", "slot": "accessory", "bp_value": 2, "passive": {"accuracy": 1}}
	assert_eq(Validator.validate_item(d).size(), 0)


# --- Map validation ---

func test_valid_map_passes() -> void:
	var d := {"id": "test", "tiles": [{"q": 0, "r": 0, "elevation": 0, "terrain": "grass"}],
		"deployment_zones": {"playerA": ["0,0"]}}
	assert_eq(Validator.validate_map(d).size(), 0)


func test_map_bad_terrain_rejected() -> void:
	var d := {"id": "bad", "tiles": [{"q": 0, "r": 0, "elevation": 0, "terrain": "lava"}]}
	assert_true(Validator.validate_map(d).size() > 0)


func test_map_deployment_zone_dangling_coord() -> void:
	var d := {"id": "bad", "tiles": [{"q": 0, "r": 0, "elevation": 0, "terrain": "grass"}],
		"deployment_zones": {"playerA": ["5,5"]}}
	assert_true(Validator.validate_map(d).size() > 0)
