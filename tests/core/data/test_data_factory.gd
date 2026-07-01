extends GutTest
## Tests for DataFactory: each factory produces a correct Resource from a raw dict.

func test_make_race() -> void:
	var d := {"id": "elf", "display_name": "Elf", "stat_modifiers": {"spd": 1, "hp": -1}, "flavor": "Nimble."}
	var r := DataFactory.make_race(d)
	assert_eq(r.id, "elf")
	assert_eq(r.display_name, "Elf")
	assert_eq(r.stat_modifiers["spd"], 1)
	assert_eq(r.flavor, "Nimble.")


func test_make_class() -> void:
	var d := {"id": "rogue", "display_name": "Rogue", "abbr": "ROG",
		"stat_modifiers": {"spd": 1, "jump": 1}, "derived_bonuses": {},
		"equipment_access": ["daggers"], "granted_abilities": ["backstab"],
		"level_max": 3, "required_classes": [["fighter", 2]]}
	var c := DataFactory.make_class(d)
	assert_eq(c.id, "rogue")
	assert_eq(c.abbr, "ROG")
	assert_eq(c.stat_modifiers["jump"], 1)
	assert_eq(c.granted_abilities[0], "backstab")
	assert_eq(c.level_max, 3)
	assert_eq(c.required_classes.size(), 1)
	assert_eq(c.required_classes[0][0], "fighter")
	assert_eq(c.required_classes[0][1], 2)


func test_make_class_with_a4_fields() -> void:
	var d := {"id": "soldier", "name": "Soldier", "abbr": "SLD",
		"stats": {"atk": 3, "def": 2, "hp": 10},
		"archetype": "physical_attack", "branch": "melee", "tier": 1,
		"growth": {"hp": 1.5, "atk": 0.5},
		"jp_costs": {"reckless_swing": 80, "rage": 60},
		"prerequisites": {"classes": [["vagabond", 3]]},
		"equipment_access": ["sword"], "granted_abilities": ["power_strike"],
		"level_max": 10, "required_classes": []}
	var c := DataFactory.make_class(d)
	assert_eq(c.archetype, "physical_attack")
	assert_eq(c.branch, "melee")
	assert_eq(c.tier, 1)
	assert_eq(c.growth["hp"], 1.5)
	assert_eq(c.growth["atk"], 0.5)
	assert_eq(int(c.jp_costs["reckless_swing"]), 80)
	assert_eq(int(c.jp_costs["rage"]), 60)
	assert_true(c.prerequisites.has("classes"), "prerequisites should have classes key")


func test_make_class_folds_required_classes_into_prerequisites() -> void:
	var d := {"id": "knight", "stats": {},
		"required_classes": [["fighter", 2]]}
	var c := DataFactory.make_class(d)
	assert_eq(c.required_classes.size(), 1)
	# prerequisites should be populated from required_classes
	assert_true(c.prerequisites.has("classes"))


func test_make_race_with_base_stats() -> void:
	var d := {"id": "dwarf", "name": "Dwarf", "stats": {"def": 2},
		"base_stats": {"spd": 3, "hp": 35, "def": 7}, "flavor": ""}
	var r := DataFactory.make_race(d)
	assert_eq(int(r.base_stats.get("spd", 0)), 3)
	assert_eq(int(r.base_stats.get("hp", 0)), 35)
	assert_eq(int(r.base_stats.get("def", 0)), 7)


func test_make_character_with_recommended_path() -> void:
	var d := {"id": "hero", "name": "Hero", "race": "human", "classes": ["vagabond"],
		"level": 1, "bp": 10, "stats": {"hp": 30, "spd": 5, "atk": 5, "rng": 1, "def": 5},
		"equipment": [], "abilities": [], "recommended_path": "physical"}
	var c := DataFactory.make_character(d)
	assert_eq(c.recommended_path, "physical")


func test_make_class_defaults() -> void:
	var d := {"id": "basic", "stats": {}}
	var c := DataFactory.make_class(d)
	assert_eq(c.level_max, 1, "level_max should default to 1")
	assert_eq(c.required_classes.size(), 0, "required_classes should default to empty")


func test_make_ability_maps_range() -> void:
	var d := {"id": "fire_1", "display_name": "Fire 1", "type": "spell", "ap_cost": 1,
		"range": 3, "area": {}, "effect": {"effect_type": "damage", "value": 4, "element": "fire"},
		"source": "class"}
	var a := DataFactory.make_ability(d)
	assert_eq(a.id, "fire_1")
	assert_eq(a.ability_range, 3, "JSON 'range' should map to ability_range")
	assert_eq(a.effect_type, "damage", "effect_type extracted from effect dict")


func test_make_item() -> void:
	var d := {"id": "bow", "display_name": "Bow", "slot": "weapon", "bp_value": 2,
		"passive": {}, "granted_abilities": [], "weapon_power": 2, "weapon_range": 2}
	var i := DataFactory.make_item(d)
	assert_eq(i.id, "bow")
	assert_eq(i.weapon_power, 2)
	assert_eq(i.weapon_range, 2)


func test_make_character() -> void:
	var d := {"id": "hero", "display_name": "Hero", "race": "human", "classes": ["fighter"],
		"level": 3, "bp": 18, "base_stats": {"spd": 3, "atk": 3, "rng": 1, "def": 3, "hp": 16},
		"equipment": ["sword"], "abilities": []}
	var c := DataFactory.make_character(d)
	assert_eq(c.id, "hero")
	assert_eq(c.race, "human")
	assert_eq(c.bp, 18)
	assert_eq(c.base_stats["hp"], 16)


func test_make_map_converts_tiles() -> void:
	var d := {"id": "test_map", "tier": "skirmish",
		"tiles": [{"q": 0, "r": 0, "elevation": 2, "terrain": "grass"},
		          {"q": 1, "r": 0, "elevation": 0, "terrain": "trees"}],
		"deployment_zones": {"playerA": ["0,0"], "playerB": ["1,0"]}}
	var m := DataFactory.make_map(d)
	assert_eq(m.id, "test_map")
	assert_eq(m.tiles.size(), 2)
	assert_eq(m.tiles[0].elevation, 2)
	assert_eq(m.tiles[1].terrain, "trees")
