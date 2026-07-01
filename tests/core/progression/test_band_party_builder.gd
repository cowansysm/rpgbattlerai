extends GutTest
## Tests for BandPartyBuilder: converting instances to BattleUnits.


func _make_race() -> RaceData:
	var r := RaceData.new()
	r.id = "human"
	r.base_stats = {"spd": 5, "atk": 5, "rng": 1, "def": 5, "hp": 30, "jump": 2, "wp": 5, "mag": 3, "res": 3}
	return r


func _make_class() -> ClassData:
	var c := ClassData.new()
	c.id = "vagabond"
	c.stat_modifiers = {"atk": 1, "def": 1, "hp": 5}
	c.growth = {}
	c.jp_costs = {}
	c.prerequisites = {}
	c.equipment_access = []
	c.granted_abilities = []
	return c


func _make_instance(id: String) -> CharacterInstance:
	var ci := CharacterInstance.new()
	ci.instance_id = id
	ci.template_id = "human_fighter"
	ci.name = "Hero " + id
	ci.race = "human"
	ci.class_levels = {"vagabond": 3}
	ci.active_class = "vagabond"
	ci.unlocked_classes = ["vagabond"] as Array[String]
	ci.ability_loadout = [] as Array[String]
	ci.equipment = {}
	ci.growth_accumulated = {}
	return ci


func _race_provider(_id: String) -> RaceData:
	return _make_race()


func _class_provider(_id: String) -> ClassData:
	return _make_class()


func test_build_party_creates_battle_units() -> void:
	var instances: Array[CharacterInstance] = [
		_make_instance("ci_1"),
		_make_instance("ci_2"),
	]
	var party := BandPartyBuilder.build_party(instances, _race_provider, _class_provider)
	assert_eq(party.size(), 2)
	for u: BattleUnit in party:
		assert_gt(u.current_hp, 0)
		assert_eq(u.ap_remaining, 2)


func test_build_party_empty() -> void:
	var empty: Array[CharacterInstance] = []
	var party := BandPartyBuilder.build_party(empty, _race_provider, _class_provider)
	assert_eq(party.size(), 0)


func test_built_units_have_correct_names() -> void:
	var instances: Array[CharacterInstance] = [_make_instance("ci_named")]
	instances[0].name = "Aldric"
	var party := BandPartyBuilder.build_party(instances, _race_provider, _class_provider)
	assert_eq(party[0].character.display_name, "Aldric")


func test_generate_opponent_instances() -> void:
	var t1 := CharacterData.new()
	t1.id = "t1"
	t1.race = "human"
	var t2 := CharacterData.new()
	t2.id = "t2"
	t2.race = "elf"
	var name_gen := func(race: String) -> String: return "Opp " + race
	var opp := BandPartyBuilder.generate_opponent_instances([t1, t2], name_gen, 2)
	assert_eq(opp.size(), 2)
	assert_eq(opp[0].race, "human")
	assert_eq(opp[1].race, "elf")
