extends GutTest
## Tests for EncounterSelector: eligibility filtering, weighted pick, enemy scaling.


var _cls: ClassData
var _template: CharacterData


func before_all() -> void:
	_cls = ClassData.new()
	_cls.id = "goblin_grunt"
	_cls.tier = 0
	_cls.growth = {"hp": 1.0, "atk": 0.3}
	_cls.prerequisites = {}
	_cls.granted_abilities = ["basic_strike"]
	_cls.equipment_access = []

	_template = CharacterData.new()
	_template.id = "goblin_grunt"
	_template.race = "goblin"
	_template.classes = ["goblin_grunt"] as Array[String]
	_template.level = 1
	_template.bp = 3
	_template.base_stats = {"hp": 20, "atk": 4, "def": 3, "spd": 5}


func _class_prov(class_id: String) -> ClassData:
	if class_id == "goblin_grunt":
		return _cls
	return null


func _char_prov(char_id: String) -> CharacterData:
	if char_id == "goblin_grunt":
		return _template
	return null


func _make_encounter(id: String, min_bl: int, weight: float = 1.0) -> EncounterData:
	var enc := EncounterData.new()
	enc.id = id
	enc.name = id
	enc.min_band_level = min_bl
	enc.enemies = [{"character": "goblin_grunt", "count": 2}]
	enc.weight = weight
	return enc


func _providers() -> Dictionary:
	return {
		"character_provider": _char_prov,
		"class_provider": _class_prov,
		"name_gen": func(_r: String) -> String: return "Goblin",
	}


func test_respects_min_band_level() -> void:
	var enc_l1 := _make_encounter("e1", 1)
	var enc_l3 := _make_encounter("e3", 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	# Band level 2 should only see enc_l1
	var result := EncounterSelector.select(2, rng, [enc_l1, enc_l3], _providers())
	assert_false(result.is_empty(), "should find an eligible encounter")
	assert_eq((result["encounter"] as EncounterData).id, "e1")


func test_empty_when_no_eligible() -> void:
	var enc := _make_encounter("e5", 5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var result := EncounterSelector.select(1, rng, [enc], _providers())
	assert_true(result.is_empty(), "no eligible encounter at band_level 1")


func test_enemy_count_matches_entries() -> void:
	var enc := _make_encounter("e1", 1)
	enc.enemies = [
		{"character": "goblin_grunt", "count": 2},
		{"character": "goblin_grunt", "count": 1},
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var result := EncounterSelector.select(1, rng, [enc], _providers())
	var enemies: Array = result.get("enemies", [])
	assert_eq(enemies.size(), 3, "2 + 1 = 3 enemies")


func test_weighted_pick_deterministic() -> void:
	var enc_a := _make_encounter("a", 1, 10.0)
	var enc_b := _make_encounter("b", 1, 0.001)
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 99
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 99
	var r1 := EncounterSelector.select(1, rng1, [enc_a, enc_b], _providers())
	var r2 := EncounterSelector.select(1, rng2, [enc_a, enc_b], _providers())
	assert_eq((r1["encounter"] as EncounterData).id,
		(r2["encounter"] as EncounterData).id, "same seed = same pick")


func test_level_offset_applied() -> void:
	var enc := _make_encounter("e_off", 1)
	enc.level_offset = 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var result := EncounterSelector.select(3, rng, [enc], _providers())
	# band_level=3 + offset=2 = target 5, clamped to [1, 10]
	var enemies: Array = result.get("enemies", [])
	assert_false(enemies.is_empty())
	# Enemies should be scaled to level 5
	var ci: CharacterInstance = enemies[0]
	assert_eq(ci.character_level(), 5, "enemy should be scaled to band_level + offset")


func test_enemies_scaled_to_target_level() -> void:
	var enc := _make_encounter("e_scale", 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var result := EncounterSelector.select(4, rng, [enc], _providers())
	var enemies: Array = result.get("enemies", [])
	assert_false(enemies.is_empty())
	var ci: CharacterInstance = enemies[0]
	assert_eq(ci.character_level(), 4, "enemy should be scaled to band_level")
