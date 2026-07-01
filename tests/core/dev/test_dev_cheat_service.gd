extends GutTest
## Tests for DevCheatService: all cheat operations on CharacterInstance,
## BattleBand, and BattleUnit.


# ============================================================
# HELPERS
# ============================================================

func _make_template(race: String = "human") -> CharacterData:
	var c := CharacterData.new()
	c.id = "tmpl_" + race
	c.race = race
	c.display_name = "Template " + race
	return c


func _name_gen(race: String) -> String:
	return "Test %s" % race


func _make_class(id: String, growth: Dictionary = {}, jp_costs: Dictionary = {},
		prereqs: Dictionary = {}) -> ClassData:
	var cls := ClassData.new()
	cls.id = id
	cls.display_name = id.capitalize()
	cls.growth = growth
	cls.jp_costs = jp_costs
	cls.prerequisites = prereqs
	return cls


func _make_class_provider() -> Callable:
	var classes: Dictionary = {
		"vagabond": _make_class("vagabond",
			{"atk": 0.5, "def": 0.5, "hp": 1.0},
			{"basic_attack": 10}),
		"soldier": _make_class("soldier",
			{"atk": 1.0, "def": 0.8, "hp": 2.0},
			{"shield_bash": 20, "war_cry": 30},
			{"level": 3}),
		"thief": _make_class("thief",
			{"spd": 1.0, "atk": 0.7},
			{"steal": 15, "backstab": 25},
			{"level": 3}),
	}
	return func(id: String) -> ClassData: return classes.get(id, null)


func _make_instance() -> CharacterInstance:
	var t := _make_template("human")
	return CharacterInstance.generate(t, _name_gen)


func _make_battle_unit(hp: int = 50, wp: int = 10, team: String = "playerA") -> BattleUnit:
	var c := CharacterData.new()
	c.id = "test_unit"
	c.display_name = "Test Unit"
	c.race = "human"
	c.level = 1
	c.abilities = []
	c.equipment = []
	c.classes = ["vagabond"]
	c.base_stats = {}
	var sb := StatBlock.new()
	sb.set_base("hp", hp)
	sb.set_base("wp", wp)
	sb.set_base("atk", 10)
	sb.set_base("def", 10)
	sb.set_base("spd", 10)
	var unit := BattleUnit.from_character(c, sb)
	unit.team = team
	return unit


func _make_match_state() -> MatchState:
	var state := MatchState.new()
	var unit_a1 := _make_battle_unit(50, 10, "playerA")
	var unit_a2 := _make_battle_unit(40, 8, "playerA")
	var unit_b1 := _make_battle_unit(50, 10, "playerB")
	var unit_b2 := _make_battle_unit(45, 12, "playerB")
	state.parties = {
		"playerA": [unit_a1, unit_a2],
		"playerB": [unit_b1, unit_b2],
	}
	return state


# ============================================================
# CHARACTER INSTANCE TESTS
# ============================================================

func test_set_level_up() -> void:
	var ci := _make_instance()
	var prov := _make_class_provider()
	assert_eq(ci.character_level(), 1)
	DevCheatService.set_level(ci, 5, prov)
	assert_eq(ci.character_level(), 5, "level should be 5 after set_level")
	assert_true(ci.xp >= CharacterInstance.xp_for_level(5), "xp should be at or above threshold")


func test_set_level_down() -> void:
	var ci := _make_instance()
	var prov := _make_class_provider()
	DevCheatService.set_level(ci, 5, prov)
	DevCheatService.set_level(ci, 2, prov)
	assert_eq(ci.character_level(), 2, "level should be 2 after downleveling")


func test_set_level_clamped() -> void:
	var ci := _make_instance()
	var prov := _make_class_provider()
	DevCheatService.set_level(ci, 0, prov)
	assert_eq(ci.character_level(), 1, "level should be clamped to 1")
	DevCheatService.set_level(ci, 999, prov)
	assert_eq(ci.character_level(), 50, "level should be clamped to max_level (50)")


func test_add_xp() -> void:
	var ci := _make_instance()
	var prov := _make_class_provider()
	var levels := DevCheatService.add_xp(ci, 100, prov)
	assert_true(ci.xp >= 100, "xp should have increased")
	assert_true(levels >= 0, "should return non-negative levels gained")


func test_set_jp() -> void:
	var ci := _make_instance()
	DevCheatService.set_jp(ci, "vagabond", 500)
	assert_eq(int(ci.jp.get("vagabond", 0)), 500)


func test_set_jp_negative_clamped() -> void:
	var ci := _make_instance()
	DevCheatService.set_jp(ci, "vagabond", -10)
	assert_eq(int(ci.jp.get("vagabond", 0)), 0, "negative JP should be clamped to 0")


func test_add_jp() -> void:
	var ci := _make_instance()
	ci.jp["vagabond"] = 100
	DevCheatService.add_jp(ci, "vagabond", 50)
	assert_eq(int(ci.jp["vagabond"]), 150)


func test_grant_all_jp() -> void:
	var ci := _make_instance()
	ci.unlocked_classes = ["vagabond", "thief"]
	DevCheatService.grant_all_jp(ci, 999)
	assert_eq(int(ci.jp["vagabond"]), 999)
	assert_eq(int(ci.jp["thief"]), 999)


func test_force_unlock_class() -> void:
	var ci := _make_instance()
	assert_eq(ci.unlocked_classes.size(), 1)
	DevCheatService.force_unlock_class(ci, "soldier")
	assert_true(ci.unlocked_classes.has("soldier"), "soldier should be unlocked")
	assert_eq(ci.unlocked_classes.size(), 2)


func test_force_unlock_class_idempotent() -> void:
	var ci := _make_instance()
	DevCheatService.force_unlock_class(ci, "soldier")
	DevCheatService.force_unlock_class(ci, "soldier")
	var count: int = 0
	for c in ci.unlocked_classes:
		if c == "soldier":
			count += 1
	assert_eq(count, 1, "should not duplicate unlocked class")


func test_force_learn_ability() -> void:
	var ci := _make_instance()
	DevCheatService.force_learn_ability(ci, "fireball")
	assert_true(ci.learned_abilities.has("fireball"))


func test_force_learn_ability_idempotent() -> void:
	var ci := _make_instance()
	DevCheatService.force_learn_ability(ci, "fireball")
	DevCheatService.force_learn_ability(ci, "fireball")
	var count: int = 0
	for ab in ci.learned_abilities:
		if ab == "fireball":
			count += 1
	assert_eq(count, 1, "should not duplicate ability")


func test_force_learn_all_abilities() -> void:
	var ci := _make_instance()
	var prov := _make_class_provider()
	# Unlock thief so its abilities are also learned
	DevCheatService.force_unlock_class(ci, "thief")
	DevCheatService.force_learn_all_abilities(ci, prov)
	assert_true(ci.learned_abilities.has("basic_attack"), "should learn vagabond ability")
	assert_true(ci.learned_abilities.has("steal"), "should learn thief ability")
	assert_true(ci.learned_abilities.has("backstab"), "should learn thief ability")


func test_force_equip() -> void:
	var ci := _make_instance()
	DevCheatService.force_equip(ci, "weapon", "greatsword")
	assert_eq(str(ci.equipment.get("weapon", "")), "greatsword")


func test_reset_downs() -> void:
	var ci := _make_instance()
	ci.downs_this_run = 3
	DevCheatService.reset_downs(ci)
	assert_eq(ci.downs_this_run, 0)


# ============================================================
# BAND TESTS
# ============================================================

func test_set_gold() -> void:
	var band := BattleBand.create("Test")
	DevCheatService.set_gold(band, 5000)
	assert_eq(band.gold, 5000)


func test_set_gold_negative_clamped() -> void:
	var band := BattleBand.create("Test")
	DevCheatService.set_gold(band, -100)
	assert_eq(band.gold, 0, "gold should be clamped to 0")


func test_add_gold() -> void:
	var band := BattleBand.create("Test")
	band.gold = 100
	DevCheatService.add_gold(band, 500)
	assert_eq(band.gold, 600)


func test_add_gold_negative() -> void:
	var band := BattleBand.create("Test")
	band.gold = 100
	DevCheatService.add_gold(band, -50)
	assert_eq(band.gold, 50)


func test_add_gold_clamps_at_zero() -> void:
	var band := BattleBand.create("Test")
	band.gold = 100
	DevCheatService.add_gold(band, -200)
	assert_eq(band.gold, 0, "gold should not go below 0")


func test_add_item_to_inventory() -> void:
	var band := BattleBand.create("Test")
	DevCheatService.add_item_to_inventory(band, "sword")
	var equip_list: Array = band.inventory["equipment"] as Array
	assert_true(equip_list.has("sword"))


func test_free_recruit() -> void:
	var band := BattleBand.create("Test")
	band.gold = 0
	var template := _make_template("human")
	var result := DevCheatService.free_recruit(band, template, _name_gen)
	assert_eq(result["error"], "", "should succeed with 0 gold")
	assert_not_null(result["instance"])
	assert_eq(band.roster.size(), 1)
	assert_eq(band.gold, 0, "gold should not change")


# ============================================================
# BATTLEUNIT TESTS
# ============================================================

func test_set_unit_hp_clamped() -> void:
	var unit := _make_battle_unit(50)
	DevCheatService.set_unit_hp(unit, 999)
	assert_eq(unit.current_hp, 50, "should clamp to max HP")
	DevCheatService.set_unit_hp(unit, -10)
	assert_eq(unit.current_hp, 0, "should clamp to 0")
	assert_true(unit.is_downed, "should be downed when HP reaches 0")


func test_set_unit_wp_clamped() -> void:
	var unit := _make_battle_unit(50, 10)
	DevCheatService.set_unit_wp(unit, 999)
	assert_eq(unit.current_wp, 10, "should clamp to max WP")
	DevCheatService.set_unit_wp(unit, -5)
	assert_eq(unit.current_wp, 0, "should clamp to 0")


func test_set_unit_ap() -> void:
	var unit := _make_battle_unit()
	DevCheatService.set_unit_ap(unit, 5)
	assert_eq(unit.ap_remaining, 5)
	DevCheatService.set_unit_ap(unit, 0)
	assert_eq(unit.ap_remaining, 0)


func test_heal_unit_full() -> void:
	var unit := _make_battle_unit(50, 10)
	unit.current_hp = 10
	unit.current_wp = 3
	unit.is_downed = true
	unit.downed_round = 2
	DevCheatService.heal_unit_full(unit)
	assert_eq(unit.current_hp, 50, "HP should be max")
	assert_eq(unit.current_wp, 10, "WP should be max")
	assert_false(unit.is_downed, "should not be downed")
	assert_eq(unit.downed_round, -1)


func test_kill_unit() -> void:
	var unit := _make_battle_unit(50)
	DevCheatService.kill_unit(unit, 3)
	assert_eq(unit.current_hp, 0)
	assert_true(unit.is_downed)
	assert_eq(unit.downed_round, 3)


func test_revive_unit() -> void:
	var unit := _make_battle_unit(50)
	DevCheatService.kill_unit(unit, 2)
	DevCheatService.revive_unit(unit, 25)
	assert_false(unit.is_downed)
	assert_eq(unit.current_hp, 25)
	assert_eq(unit.downed_round, -1)


func test_revive_unit_default_full_hp() -> void:
	var unit := _make_battle_unit(50)
	DevCheatService.kill_unit(unit)
	DevCheatService.revive_unit(unit)
	assert_eq(unit.current_hp, 50, "should revive at full HP by default")


func test_push_dev_modifier() -> void:
	var unit := _make_battle_unit()
	var base_atk: int = unit.stats.effective("atk")
	DevCheatService.push_dev_modifier(unit, "atk", 5)
	assert_eq(unit.stats.effective("atk"), base_atk + 5)


func test_clear_dev_modifiers() -> void:
	var unit := _make_battle_unit()
	var base_atk: int = unit.stats.effective("atk")
	DevCheatService.push_dev_modifier(unit, "atk", 5)
	DevCheatService.clear_dev_modifiers(unit)
	assert_eq(unit.stats.effective("atk"), base_atk, "should return to base after clearing")


func test_clear_all_statuses() -> void:
	var unit := _make_battle_unit()
	unit.status_effects.append({"id": "poison", "duration": 3, "source": "test"})
	unit.status_effects.append({"id": "slow", "duration": 2, "source": "test"})
	DevCheatService.clear_all_statuses(unit)
	assert_eq(unit.status_effects.size(), 0, "all statuses should be cleared")


func test_force_win() -> void:
	var state := _make_match_state()
	# All units should be alive initially
	assert_eq(state.living_units("playerA").size(), 2)
	assert_eq(state.living_units("playerB").size(), 2)
	DevCheatService.force_win(state, "playerA")
	# Player B units should be dead (not just downed)
	assert_eq(state.living_units("playerB").size(), 0, "all playerB units should be dead")
	assert_eq(state.living_units("playerA").size(), 2, "playerA units should be untouched")
	# Verify they are permanently dead (not downed)
	for unit: BattleUnit in state.parties["playerB"]:
		assert_eq(unit.current_hp, 0)
		assert_false(unit.is_downed, "should be permanently dead, not downed")


func test_force_win_triggers_winner_detection() -> void:
	var state := _make_match_state()
	DevCheatService.force_win(state, "playerA")
	assert_eq(state.check_winner(), "playerA", "playerA should be detected as winner")


func test_restore_ap() -> void:
	var unit := _make_battle_unit()
	unit.ap_remaining = 0
	DevCheatService.restore_ap(unit, 3)
	assert_eq(unit.ap_remaining, 3)


# ============================================================
# PROFILE / META-PROGRESSION CHEATS
# ============================================================

func test_grant_profile_unlock() -> void:
	var p := Profile.new()
	DevCheatService.grant_profile_unlock(p, "test_key")
	assert_true(p.has_unlock("test_key"))


func test_grant_profile_template() -> void:
	var p := Profile.new()
	DevCheatService.grant_profile_template(p, "warrior")
	assert_true(p.has_template("warrior"))


func test_grant_profile_class() -> void:
	var p := Profile.new()
	DevCheatService.grant_profile_class(p, "sage")
	assert_true(p.has_class("sage"))


func test_set_completed_runs() -> void:
	var p := Profile.new()
	DevCheatService.set_completed_runs(p, 10)
	assert_eq(p.completed_runs, 10)


func test_set_completed_runs_negative_clamped() -> void:
	var p := Profile.new()
	DevCheatService.set_completed_runs(p, -5)
	assert_eq(p.completed_runs, 0)


func test_reset_profile() -> void:
	var p := Profile.new()
	p.grant_template("warrior")
	p.grant_class("sage")
	p.grant_unlock("first_victory")
	p.completed_runs = 10
	DevCheatService.reset_profile(p)
	assert_eq(p.completed_runs, 0)
	assert_true(p.unlocked_templates.is_empty())
	assert_true(p.unlocked_classes.is_empty())
	assert_true(p.meta_unlocks.is_empty())
