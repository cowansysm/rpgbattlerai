extends GutTest
## Tests for the CharacterInstance → BattleUnit bridge.


var _race: RaceData
var _cls: ClassData


func before_all() -> void:
	_race = RaceData.new()
	_race.id = "human"
	_race.base_stats = {"spd": 5, "atk": 5, "rng": 1, "def": 5, "hp": 30, "jump": 2, "wp": 5, "mag": 3, "res": 3}
	_race.stat_modifiers = {}

	_cls = ClassData.new()
	_cls.id = "vagabond"
	_cls.stat_modifiers = {"atk": 1, "def": 1, "hp": 5}
	_cls.equipment_access = ["sword"] as Array[String]
	_cls.granted_abilities = ["basic_strike"] as Array[String]


func _race_provider(race_id: String) -> RaceData:
	return _race


func _class_provider(class_id: String) -> ClassData:
	return _cls


func _make_instance() -> CharacterInstance:
	var ci := CharacterInstance.new()
	ci.instance_id = "ci_test_001"
	ci.template_id = "tmpl_human"
	ci.name = "Test Hero"
	ci.race = "human"
	ci.class_levels = {"vagabond": 3}
	ci.active_class = "vagabond"
	ci.unlocked_classes = ["vagabond"]
	ci.ability_loadout = ["basic_strike"]
	ci.equipment = {"weapon": "sword"}
	ci.growth_accumulated = {"atk": 1, "hp": 3}
	return ci


func test_to_character_data_snapshot() -> void:
	var ci := _make_instance()
	var sb := InstanceStatResolver.resolve(ci, _race_provider, _class_provider)
	var snap := ci.to_character_data(sb)

	assert_eq(snap.id, "ci_test_001")
	assert_eq(snap.display_name, "Test Hero")
	assert_eq(snap.race, "human")
	assert_eq(snap.classes[0], "vagabond")
	assert_eq(snap.level, 3)
	assert_true(snap.abilities.has("basic_strike"))
	assert_true(snap.equipment.has("sword"))
	# Base stats in snapshot should match derived values
	assert_eq(int(snap.base_stats.get("atk", 0)), sb.base("atk"))
	assert_eq(int(snap.base_stats.get("hp", 0)), sb.base("hp"))


func test_from_instance_produces_battle_unit() -> void:
	var ci := _make_instance()
	var unit := BattleUnit.from_instance(ci, _race_provider, _class_provider)

	assert_not_null(unit)
	# HP = race(30) + class(5) + growth(3) = 38
	assert_eq(unit.current_hp, 38, "HP should be derived from instance stats")
	# WP = race(5) + class(0) + growth(0) = 5
	assert_eq(unit.current_wp, 5, "WP should be derived from instance stats")
	assert_eq(unit.ap_remaining, 2)
	assert_false(unit.is_activated)
	assert_eq(unit.character.display_name, "Test Hero")


func test_bridge_combat_compat() -> void:
	var ci := _make_instance()
	var unit := BattleUnit.from_instance(ci, _race_provider, _class_provider)

	# The unit should have the same interface as one from from_character
	assert_true(unit.is_alive())
	assert_false(unit.is_downed)
	assert_eq(unit.character.classes[0], "vagabond")
	assert_eq(unit.stats.effective("atk"), 7, "atk: 5 race + 1 class + 1 growth")
	assert_eq(unit.stats.effective("hp"), 38, "hp: 30 race + 5 class + 3 growth")
