extends GutTest

# --- Helpers ---

func _seeded(s: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	return rng


func _make_template(id: String, race: String = "human") -> CharacterData:
	var c := CharacterData.new()
	c.id = id
	c.race = race
	c.display_name = "Template " + id
	c.classes = ["vagabond"]
	c.abilities = []
	c.equipment = []
	return c


func _make_map(id: String, tier: String) -> MapData:
	var m := MapData.new()
	m.id = id
	m.tier = tier
	m.tiles = [TileRecord.new(0, 0, 0, "grass")]
	return m


func _stub_class(_id: String) -> ClassData:
	var cd := ClassData.new()
	cd.id = "vagabond"
	cd.display_name = "Vagabond"
	cd.stat_modifiers = {}
	cd.growth = {}
	return cd


func _stub_name_gen(_race: String) -> String:
	return "Test Name"


func _default_run_config() -> Dictionary:
	return {
		"depth_bp_curve": [30, 40, 50, 60, 75, 90, 105, 120, 140, 160, 185, 210, 250],
		"boss_bp_multiplier": 1.5,
		"enemy_count_range": [2, 4],
		"depth_tier_map": {"0": "skirmish", "4": "standard", "8": "large"},
	}


func _providers(maps: Array = [], templates: Array = []) -> Dictionary:
	if maps.is_empty():
		maps = [_make_map("m1", "skirmish"), _make_map("m2", "standard")]
	if templates.is_empty():
		templates = [_make_template("t1"), _make_template("t2")]
	return {
		"all_maps": func() -> Array: return maps,
		"all_characters": func() -> Array: return templates,
		"class_provider": _stub_class,
		"name_gen": _stub_name_gen,
		"run_config": _default_run_config(),
	}


# --- Tests ---

func test_generate_returns_map_and_instances() -> void:
	var result: Dictionary = EncounterGenerator.generate(0, _seeded(1), _providers())
	assert_true(result.has("map"))
	assert_true(result.has("enemy_instances"))
	assert_not_null(result["map"])
	var instances: Array = result["enemy_instances"] as Array
	assert_gte(instances.size(), 2)
	assert_lte(instances.size(), 4)


func test_determinism() -> void:
	var p: Dictionary = _providers()
	var r1: Dictionary = EncounterGenerator.generate(3, _seeded(42), p)
	var r2: Dictionary = EncounterGenerator.generate(3, _seeded(42), p)
	var inst1: Array = r1["enemy_instances"] as Array
	var inst2: Array = r2["enemy_instances"] as Array
	assert_eq(inst1.size(), inst2.size())
	for i in range(inst1.size()):
		assert_eq((inst1[i] as CharacterInstance).level,
			(inst2[i] as CharacterInstance).level)


func test_enemy_count_within_range() -> void:
	for s in range(10):
		var result: Dictionary = EncounterGenerator.generate(0, _seeded(s), _providers())
		var count: int = (result["enemy_instances"] as Array).size()
		assert_gte(count, 2, "seed %d: count below minimum" % s)
		assert_lte(count, 4, "seed %d: count above maximum" % s)


func test_depth_scaling_raises_level() -> void:
	var p: Dictionary = _providers()
	var r_low: Dictionary = EncounterGenerator.generate(0, _seeded(1), p)
	var r_high: Dictionary = EncounterGenerator.generate(10, _seeded(1), p)
	var low_instances: Array = r_low["enemy_instances"] as Array
	var high_instances: Array = r_high["enemy_instances"] as Array
	# Higher depth should produce higher level enemies on average
	var avg_low: float = 0.0
	for ci: CharacterInstance in low_instances:
		avg_low += ci.level
	avg_low /= low_instances.size()
	var avg_high: float = 0.0
	for ci: CharacterInstance in high_instances:
		avg_high += ci.level
	avg_high /= high_instances.size()
	assert_gt(avg_high, avg_low, "depth 10 should have higher level enemies than depth 0")


func test_boss_encounter_higher_target() -> void:
	var p: Dictionary = _providers()
	var normal: Dictionary = EncounterGenerator.generate(5, _seeded(1), p, false)
	var boss: Dictionary = EncounterGenerator.generate(5, _seeded(1), p, true)
	var normal_inst: Array = normal["enemy_instances"] as Array
	var boss_inst: Array = boss["enemy_instances"] as Array
	# Boss enemies should be higher level due to higher target BP
	var avg_normal: float = 0.0
	for ci: CharacterInstance in normal_inst:
		avg_normal += ci.level
	avg_normal /= normal_inst.size()
	var avg_boss: float = 0.0
	for ci: CharacterInstance in boss_inst:
		avg_boss += ci.level
	avg_boss /= boss_inst.size()
	assert_gte(avg_boss, avg_normal, "boss should have >= level enemies")


func test_tier_selection_skirmish_at_depth_0() -> void:
	var maps: Array = [_make_map("sk1", "skirmish"), _make_map("std1", "standard")]
	var p: Dictionary = _providers(maps)
	# At depth 0, should pick skirmish maps
	var result: Dictionary = EncounterGenerator.generate(0, _seeded(1), p)
	if result["map"] != null:
		assert_eq((result["map"] as MapData).tier, "skirmish")


func test_tier_selection_standard_at_depth_5() -> void:
	var maps: Array = [_make_map("sk1", "skirmish"), _make_map("std1", "standard")]
	var p: Dictionary = _providers(maps)
	var result: Dictionary = EncounterGenerator.generate(5, _seeded(1), p)
	if result["map"] != null:
		assert_eq((result["map"] as MapData).tier, "standard")


func test_fallback_to_any_map_when_no_tier_match() -> void:
	var maps: Array = [_make_map("m1", "special")]
	var p: Dictionary = _providers(maps)
	var result: Dictionary = EncounterGenerator.generate(0, _seeded(1), p)
	assert_not_null(result["map"])  # falls back to available maps


func test_empty_templates_returns_empty_instances() -> void:
	var p: Dictionary = _providers([], [])
	p["all_characters"] = func() -> Array: return []
	var result: Dictionary = EncounterGenerator.generate(0, _seeded(1), p)
	assert_true((result["enemy_instances"] as Array).is_empty())
