extends GutTest
## Tests for InstanceStatResolver: stat derivation from race + class + growth.


func _make_race() -> RaceData:
	var r := RaceData.new()
	r.id = "human"
	r.base_stats = {"spd": 5, "atk": 5, "rng": 1, "def": 5, "hp": 30, "jump": 2, "wp": 5, "mag": 3, "res": 3}
	return r


func _make_class() -> ClassData:
	var c := ClassData.new()
	c.id = "vagabond"
	c.stat_modifiers = {"atk": 1, "def": 1, "hp": 5}
	return c


func _race_provider(race_id: String) -> RaceData:
	return _make_race()


func _class_provider(class_id: String) -> ClassData:
	return _make_class()


func test_resolve_combines_race_class_growth() -> void:
	var ci := CharacterInstance.new()
	ci.race = "human"
	ci.active_class = "vagabond"
	ci.growth_accumulated = {"atk": 2, "hp": 5}

	var sb := InstanceStatResolver.resolve(ci, _race_provider, _class_provider)
	# atk = race(5) + class(1) + growth(2) = 8
	assert_eq(sb.effective("atk"), 8, "atk: 5 race + 1 class + 2 growth")
	# hp = race(30) + class(5) + growth(5) = 40
	assert_eq(sb.effective("hp"), 40, "hp: 30 race + 5 class + 5 growth")
	# spd = race(5) + class(0) + growth(0) = 5
	assert_eq(sb.effective("spd"), 5, "spd: 5 race, no class/growth")
	# def = race(5) + class(1) + growth(0) = 6
	assert_eq(sb.effective("def"), 6, "def: 5 race + 1 class")


func test_resolve_all_stat_keys() -> void:
	var ci := CharacterInstance.new()
	ci.race = "human"
	ci.active_class = "vagabond"
	ci.growth_accumulated = {}

	var sb := InstanceStatResolver.resolve(ci, _race_provider, _class_provider)
	for k in StatKey.all_strings():
		# All stat keys should be set (at least 0)
		assert_gte(sb.base(k), 0, "stat '%s' should be set" % k)

	# Verify specific values for race base_stats
	assert_eq(sb.base("mag"), 3, "mag should be 3 from race")
	assert_eq(sb.base("res"), 3, "res should be 3 from race")
	assert_eq(sb.base("wp"), 5, "wp should be 5 from race")
	assert_eq(sb.base("jump"), 2, "jump should be 2 from race")


func test_resolve_with_no_growth() -> void:
	var ci := CharacterInstance.new()
	ci.race = "human"
	ci.active_class = "vagabond"
	ci.growth_accumulated = {}

	var sb := InstanceStatResolver.resolve(ci, _race_provider, _class_provider)
	# Level 1 vagabond human: race + class only
	assert_eq(sb.base("atk"), 6, "atk: 5 race + 1 class")
	assert_eq(sb.base("def"), 6, "def: 5 race + 1 class")
	assert_eq(sb.base("hp"), 35, "hp: 30 race + 5 class")
