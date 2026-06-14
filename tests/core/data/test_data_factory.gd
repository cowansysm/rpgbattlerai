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
		"equipment_access": ["daggers"], "granted_abilities": ["backstab"]}
	var c := DataFactory.make_class(d)
	assert_eq(c.id, "rogue")
	assert_eq(c.abbr, "ROG")
	assert_eq(c.stat_modifiers["jump"], 1)
	assert_eq(c.granted_abilities[0], "backstab")


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
