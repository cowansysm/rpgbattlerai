extends GutTest
## Tests for CharacterInstance progression: leveling, JP, class unlock, loadout, equip.


var _vagabond_cls: ClassData
var _soldier_cls: ClassData
var _thief_cls: ClassData
var _adept_cls: ClassData


func before_all() -> void:
	_vagabond_cls = ClassData.new()
	_vagabond_cls.id = "vagabond"
	_vagabond_cls.tier = "starting"
	_vagabond_cls.growth = {"hp": 1.2, "atk": 0.3, "def": 0.3, "spd": 0.2}
	_vagabond_cls.jp_costs = {"first_aid": 30}
	_vagabond_cls.prerequisites = {}
	_vagabond_cls.stat_modifiers = {"atk": 1, "def": 1, "hp": 5}
	_vagabond_cls.equipment_access = ["sword", "daggers", "staff", "sling", "light_armor"] as Array[String]
	_vagabond_cls.granted_abilities = ["basic_strike"] as Array[String]

	_soldier_cls = ClassData.new()
	_soldier_cls.id = "soldier"
	_soldier_cls.tier = "tier1"
	_soldier_cls.growth = {"hp": 1.5, "atk": 0.5, "def": 0.4}
	_soldier_cls.jp_costs = {"reckless_swing": 80, "rage": 60}
	_soldier_cls.prerequisites = {"level": 3}
	_soldier_cls.stat_modifiers = {"atk": 3, "def": 2, "hp": 10}
	_soldier_cls.equipment_access = ["sword", "greataxe", "medium_armor", "shield", "light_armor"] as Array[String]
	_soldier_cls.granted_abilities = ["power_strike"] as Array[String]

	_thief_cls = ClassData.new()
	_thief_cls.id = "thief"
	_thief_cls.tier = "tier1"
	_thief_cls.growth = {"hp": 1.0, "spd": 0.4, "atk": 0.4}
	_thief_cls.jp_costs = {"lullaby": 80}
	_thief_cls.prerequisites = {"level": 3}
	_thief_cls.stat_modifiers = {"spd": 2, "atk": 1, "jump": 1}
	_thief_cls.equipment_access = ["daggers", "sling", "light_armor"] as Array[String]
	_thief_cls.granted_abilities = ["backstab"] as Array[String]

	_adept_cls = ClassData.new()
	_adept_cls.id = "adept"
	_adept_cls.tier = "tier1"
	_adept_cls.growth = {"hp": 0.8, "mag": 0.5, "wp": 0.4}
	_adept_cls.jp_costs = {"cure_1": 60, "ice_1": 80}
	_adept_cls.prerequisites = {"level": 3}
	_adept_cls.stat_modifiers = {"mag": 3, "wp": 4, "res": 1}
	_adept_cls.equipment_access = ["staff", "sling"] as Array[String]
	_adept_cls.granted_abilities = ["fire_1"] as Array[String]


func _class_provider(class_id: String) -> ClassData:
	match class_id:
		"vagabond": return _vagabond_cls
		"soldier": return _soldier_cls
		"thief": return _thief_cls
		"adept": return _adept_cls
	return null


func _make_instance() -> CharacterInstance:
	var ci := CharacterInstance.new()
	ci.instance_id = "test_id"
	ci.template_id = "test_tmpl"
	ci.name = "Test"
	ci.race = "human"
	ci.level = 1
	ci.xp = 0
	ci.active_class = "vagabond"
	ci.unlocked_classes = ["vagabond"]
	return ci


func _level_to(ci: CharacterInstance, target_level: int) -> void:
	# Give enough XP to reach target level (quadratic curve: 10*N*N)
	while ci.level < target_level:
		var needed: int = ci.xp_for_next_level() - ci.xp + 1
		ci.gain_xp(needed, _class_provider)


# --- Leveling & Growth ---

func test_gain_xp_levels_up() -> void:
	var ci := _make_instance()
	# Level 2 threshold = 10 * 2 * 2 = 40
	var gained := ci.gain_xp(40, _class_provider)
	assert_eq(ci.level, 2)
	assert_eq(gained, 1)


func test_gain_xp_multiple_levels() -> void:
	var ci := _make_instance()
	# Level 2 = 40, Level 3 = 90. Give 100 XP to get levels 2 and 3.
	var gained := ci.gain_xp(100, _class_provider)
	assert_eq(ci.level, 3)
	assert_eq(gained, 2)


func test_level_up_accumulates_growth() -> void:
	var ci := _make_instance()
	ci.gain_xp(40, _class_provider)  # Level up to 2
	# Vagabond growth: hp: 1.2, atk: 0.3, def: 0.3, spd: 0.2
	# After 1 level-up: hp = floor(0 + 1.2) = 1, atk = floor(0 + 0.3) = 0
	assert_eq(int(ci.growth_accumulated.get("hp", 0)), 1, "HP growth after 1 level-up")
	assert_eq(int(ci.growth_accumulated.get("atk", 0)), 0, "ATK growth after 1 level-up (0.3 floors to 0)")


func test_growth_accumulates_over_levels() -> void:
	var ci := _make_instance()
	_level_to(ci, 5)  # 4 level-ups
	# hp growth: floor(1.2) + floor(2.4) + floor(3.6) + floor(4.8) = 1 + 2 + 3 + 4 = 4
	# Wait - growth accumulates into growth_accumulated dict, and each level-up adds floor(current + rate)
	# Level 2: floor(0 + 1.2) = 1
	# Level 3: floor(1 + 1.2) = 2
	# Level 4: floor(2 + 1.2) = 3
	# Level 5: floor(3 + 1.2) = 4
	assert_eq(int(ci.growth_accumulated.get("hp", 0)), 4, "HP growth after 4 level-ups")


func test_level_caps_at_max() -> void:
	var ci := _make_instance()
	ci.level = 49
	ci.xp = 0
	var gained := ci.gain_xp(999999, _class_provider, 50)
	assert_eq(ci.level, 50, "level should cap at MAX_LEVEL")
	assert_eq(gained, 1)


# --- JP & Learning ---

func test_gain_jp_accumulates() -> void:
	var ci := _make_instance()
	ci.gain_jp("vagabond", 50)
	assert_eq(int(ci.jp.get("vagabond", 0)), 50)
	ci.gain_jp("vagabond", 30)
	assert_eq(int(ci.jp.get("vagabond", 0)), 80)


func test_learn_ability_deducts_jp() -> void:
	var ci := _make_instance()
	ci.gain_jp("vagabond", 50)
	var ok := ci.learn_ability("first_aid", "vagabond", _class_provider)
	assert_true(ok, "should learn first_aid for 30 JP")
	assert_eq(int(ci.jp.get("vagabond", 0)), 20, "JP should be deducted")
	assert_true(ci.learned_abilities.has("first_aid"))


func test_learn_ability_rejects_locked_class() -> void:
	var ci := _make_instance()
	ci.gain_jp("soldier", 100)
	var ok := ci.learn_ability("reckless_swing", "soldier", _class_provider)
	assert_false(ok, "can't learn from class not unlocked")


func test_learn_ability_rejects_insufficient_jp() -> void:
	var ci := _make_instance()
	ci.gain_jp("vagabond", 10)
	var ok := ci.learn_ability("first_aid", "vagabond", _class_provider)
	assert_false(ok, "can't learn if JP too low")


func test_learn_ability_no_duplicate() -> void:
	var ci := _make_instance()
	ci.gain_jp("vagabond", 100)
	ci.learn_ability("first_aid", "vagabond", _class_provider)
	ci.learn_ability("first_aid", "vagabond", _class_provider)
	var count: int = 0
	for ab in ci.learned_abilities:
		if ab == "first_aid":
			count += 1
	assert_eq(count, 1, "ability should not be duplicated")


# --- Class Unlock & Upgrade ---

func test_tier1_unlocks_at_level_3() -> void:
	var ci := _make_instance()
	assert_false(ci.can_unlock("soldier", _class_provider), "can't unlock at level 1")
	_level_to(ci, 3)
	assert_true(ci.can_unlock("soldier", _class_provider), "can unlock at level 3")
	assert_true(ci.can_unlock("thief", _class_provider))
	assert_true(ci.can_unlock("adept", _class_provider))


func test_unlock_rejects_low_level() -> void:
	var ci := _make_instance()
	ci.level = 2
	assert_false(ci.can_unlock("soldier", _class_provider))
	var ok := ci.unlock_class("soldier", _class_provider)
	assert_false(ok, "unlock should fail at level 2")


func test_unlock_adds_to_unlocked() -> void:
	var ci := _make_instance()
	_level_to(ci, 3)
	var ok := ci.unlock_class("soldier", _class_provider)
	assert_true(ok)
	assert_true(ci.unlocked_classes.has("soldier"))


func test_unlock_already_unlocked_returns_false() -> void:
	var ci := _make_instance()
	assert_false(ci.can_unlock("vagabond", _class_provider), "already unlocked")


func test_set_active_class_requires_unlocked() -> void:
	var ci := _make_instance()
	assert_false(ci.set_active_class("soldier"), "can't set class not unlocked")
	_level_to(ci, 3)
	ci.unlock_class("soldier", _class_provider)
	assert_true(ci.set_active_class("soldier"))
	assert_eq(ci.active_class, "soldier")


# --- Loadout ---

func test_loadout_caps_at_ability_slots() -> void:
	var ci := _make_instance()
	ci.learned_abilities = ["a", "b", "c", "d", "e", "f", "g"]
	var ok := ci.set_loadout(["a", "b", "c", "d", "e", "f", "g"] as Array[String], 6)
	assert_false(ok, "7 abilities should exceed 6 slot cap")


func test_loadout_accepts_within_cap() -> void:
	var ci := _make_instance()
	ci.learned_abilities = ["a", "b", "c"]
	var ok := ci.set_loadout(["a", "b"] as Array[String], 6)
	assert_true(ok)
	assert_eq(ci.ability_loadout.size(), 2)


func test_loadout_rejects_unlearned() -> void:
	var ci := _make_instance()
	ci.learned_abilities = ["a", "b"]
	var ok := ci.set_loadout(["a", "c"] as Array[String], 6)
	assert_false(ok, "can't loadout ability not in learned_abilities")


# --- Equipment ---

func test_equip_respects_class_access() -> void:
	var ci := _make_instance()
	var sword_item := ItemData.new()
	sword_item.id = "sword"
	sword_item.slot = "weapon"
	var item_provider := func(id: String) -> ItemData:
		if id == "sword": return sword_item
		return null
	var ok := ci.equip("weapon", "sword", _class_provider, item_provider)
	assert_true(ok, "vagabond has sword in equipment_access")
	assert_eq(ci.equipment.get("weapon", ""), "sword")


func test_equip_rejects_inaccessible_item() -> void:
	var ci := _make_instance()
	var greataxe_item := ItemData.new()
	greataxe_item.id = "greataxe"
	greataxe_item.slot = "weapon"
	var item_provider := func(id: String) -> ItemData:
		if id == "greataxe": return greataxe_item
		return null
	var ok := ci.equip("weapon", "greataxe", _class_provider, item_provider)
	assert_false(ok, "vagabond does not have greataxe in equipment_access")


func test_unequip_removes_item() -> void:
	var ci := _make_instance()
	ci.equipment["weapon"] = "sword"
	ci.unequip("weapon")
	assert_false(ci.equipment.has("weapon"))
