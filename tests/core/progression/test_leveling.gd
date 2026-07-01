extends GutTest
## Tests for Leveling service: XP thresholds and level-up.


var _vagabond_cls: ClassData


func before_all() -> void:
	_vagabond_cls = ClassData.new()
	_vagabond_cls.id = "vagabond"
	_vagabond_cls.tier = 0
	_vagabond_cls.growth = {"hp": 1.2, "atk": 0.3, "def": 0.3, "spd": 0.2}
	_vagabond_cls.prerequisites = {}


func _class_provider(class_id: String) -> ClassData:
	if class_id == "vagabond":
		return _vagabond_cls
	return null


func _make_ci() -> CharacterInstance:
	var ci := CharacterInstance.new()
	ci.instance_id = "test_lv"
	ci.template_id = "tmpl"
	ci.name = "Tester"
	ci.race = "human"
	ci.class_levels = {"vagabond": 1}
	ci.xp = 0
	ci.active_class = "vagabond"
	ci.unlocked_classes = ["vagabond"]
	return ci


func test_next_threshold_formula() -> void:
	# threshold = XP_CURVE_BASE(10) * level * (level + 1)
	assert_eq(Leveling.next_threshold(1), 20, "L1: 10 * 1 * 2 = 20")
	assert_eq(Leveling.next_threshold(2), 60, "L2: 10 * 2 * 3 = 60")
	assert_eq(Leveling.next_threshold(5), 300, "L5: 10 * 5 * 6 = 300")


func test_grant_xp_levels_up() -> void:
	var ci := _make_ci()
	# L1 threshold = 20
	var gained := Leveling.grant_xp(ci, 20, _class_provider)
	assert_eq(gained, 1)
	assert_eq(ci.character_level(), 2)
	assert_eq(ci.active_class_level(), 2)


func test_grant_xp_multiple_levels() -> void:
	var ci := _make_ci()
	# L1 threshold = 20, L2 threshold = 60. Need 80 for two levels.
	var gained := Leveling.grant_xp(ci, 80, _class_provider)
	assert_eq(gained, 2)
	assert_eq(ci.character_level(), 3)


func test_xp_discarded_at_cap() -> void:
	var ci := _make_ci()
	ci.class_levels = {"vagabond": 9}
	# Give enough to level to 10 and beyond
	var gained := Leveling.grant_xp(ci, 999999, _class_provider, 10)
	assert_eq(gained, 1)
	assert_eq(ci.active_class_level(), 10)
	assert_eq(ci.xp, 0, "overflow XP discarded at cap")


func test_returns_zero_when_no_level() -> void:
	var ci := _make_ci()
	# Give less than threshold (20)
	var gained := Leveling.grant_xp(ci, 5, _class_provider)
	assert_eq(gained, 0)
	assert_eq(ci.character_level(), 1)
	assert_eq(ci.xp, 5)


func test_growth_applied_on_level_up() -> void:
	var ci := _make_ci()
	Leveling.grant_xp(ci, 20, _class_provider)
	# Vagabond growth: hp 1.2 → floor(0 + 1.2) = 1
	assert_eq(int(ci.growth_accumulated.get("hp", 0)), 1)
