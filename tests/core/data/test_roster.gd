extends GutTest
## Phase 6 / A4 + content redesign: verify playable templates instantiate with the
## vagabond root class under the 10-tier job tree (tier-1: squire/apprentice/acolyte/
## cutpurse/footman/page/slinger/tinker; abilities learned via jp_costs, not granted).

var _pipeline: DataPipeline

var _character_ids: Array[String] = [
	"human_fighter", "human_archer", "human_rogue", "human_bard",
	"dwarf_barbarian", "elf_black_mage", "elf_red_mage", "halfling_white_mage"
]


func before_all() -> void:
	_pipeline = DataPipeline.new()
	var errors := _pipeline.run("res://data")
	assert_eq(errors.size(), 0, "data should load with zero errors")


# --- Character Loading ---

func test_all_characters_load() -> void:
	for id in _character_ids:
		var c := _pipeline.get_character(id)
		assert_not_null(c, "Character '%s' should load" % id)


func test_all_characters_have_final_stats() -> void:
	for id in _character_ids:
		var fs := _pipeline.get_final_stats(id)
		assert_not_null(fs, "Character '%s' should have final stats" % id)
		assert_gt(fs.effective("hp"), 0, "'%s' HP should be > 0" % id)
		assert_gt(fs.effective_move(), 0, "'%s' move should be > 0" % id)


func test_all_characters_create_battle_units() -> void:
	for id in _character_ids:
		var c := _pipeline.get_character(id)
		var fs := _pipeline.get_final_stats(id)
		var u := BattleUnit.from_character(c, fs)
		assert_not_null(u, "BattleUnit for '%s' should create" % id)
		assert_eq(u.character.id, id)
		assert_gt(u.current_hp, 0)
		assert_eq(u.ap_remaining, 2)
		assert_false(u.is_activated)


func test_all_characters_are_vagabond() -> void:
	for id in _character_ids:
		var c := _pipeline.get_character(id)
		assert_eq(c.classes[0], "vagabond", "'%s' should be vagabond class" % id)


func test_all_characters_have_recommended_path() -> void:
	for id in _character_ids:
		var c := _pipeline.get_character(id)
		assert_ne(c.recommended_path, "", "'%s' should have recommended_path" % id)


# --- Job Tree Classes ---

func test_vagabond_class_exists() -> void:
	var cls := _pipeline.get_job_class("vagabond")
	assert_not_null(cls)
	assert_eq(cls.tier, 0)
	# Learn-via-JP: player classes teach through jp_costs, not granted_abilities.
	assert_true("basic_strike" in cls.jp_costs)


func test_soldier_class_exists() -> void:
	var cls := _pipeline.get_job_class("soldier")
	assert_not_null(cls)
	assert_eq(cls.tier, 2)
	assert_eq(cls.archetype, "physical_attack")
	assert_true("backstab" in cls.jp_costs)


func test_thief_class_exists() -> void:
	var cls := _pipeline.get_job_class("thief")
	assert_not_null(cls)
	assert_eq(cls.tier, 2)
	assert_eq(cls.archetype, "control")
	assert_true("poison_strike" in cls.jp_costs)


func test_apprentice_class_exists() -> void:
	# Replaces the removed "adept": apprentice is the tier-1 magical_attack root.
	var cls := _pipeline.get_job_class("apprentice")
	assert_not_null(cls)
	assert_eq(cls.tier, 1)
	assert_eq(cls.archetype, "magical_attack")
	assert_true("fire_1" in cls.jp_costs)


# --- Weapon Power ---

func test_weapon_power_melee() -> void:
	var expected: Dictionary = {
		"human_fighter": 5,    # sword
		"human_rogue": 3,      # daggers
	}
	for id in expected.keys():
		var c := _pipeline.get_character(id)
		var fs := _pipeline.get_final_stats(id)
		var u := BattleUnit.from_character(c, fs)
		var wp: int = CombatResolver.get_weapon_power(u, _pipeline.get_item)
		assert_eq(wp, int(expected[id]),
			"'%s' weapon power should be %d" % [id, expected[id]])


func test_weapon_power_ranged() -> void:
	var expected: Dictionary = {
		"human_archer": 2,   # sling
		"human_bard": 2,     # sling
	}
	for id in expected.keys():
		var c := _pipeline.get_character(id)
		var fs := _pipeline.get_final_stats(id)
		var u := BattleUnit.from_character(c, fs)
		var wp: int = CombatResolver.get_weapon_power(u, _pipeline.get_item)
		assert_eq(wp, int(expected[id]),
			"'%s' weapon power should be %d" % [id, expected[id]])


func test_caster_weapon_power() -> void:
	for id in ["elf_black_mage", "halfling_white_mage"]:
		var c := _pipeline.get_character(id)
		var fs := _pipeline.get_final_stats(id)
		var u := BattleUnit.from_character(c, fs)
		var wp: int = CombatResolver.get_weapon_power(u, _pipeline.get_item)
		assert_eq(wp, 2, "'%s' weapon power (staff) should be 2" % id)


# --- Vagabond Stat Modifiers ---

func test_fighter_def_includes_vagabond() -> void:
	# human_fighter derived DEF under the redesigned balance (vagabond adds no def mod).
	var fs := _pipeline.get_final_stats("human_fighter")
	assert_eq(fs.effective("def"), 10, "Fighter DEF under new balance")


func test_fighter_atk_includes_vagabond() -> void:
	# human_fighter derived ATK under the redesigned balance (vagabond adds no atk mod).
	var fs := _pipeline.get_final_stats("human_fighter")
	assert_eq(fs.effective("atk"), 10, "Fighter ATK under new balance")


# --- Ability Access ---

func test_vagabond_teaches_basic_strike() -> void:
	var cls := _pipeline.get_job_class("vagabond")
	assert_true("basic_strike" in cls.jp_costs,
		"Vagabond should teach basic_strike via JP")


func test_squire_teaches_power_strike() -> void:
	# power_strike moved to the tier-1 squire under the new tree.
	var cls := _pipeline.get_job_class("squire")
	assert_true("power_strike" in cls.jp_costs,
		"Squire should teach power_strike via JP")


func test_apprentice_teaches_fire_1() -> void:
	var cls := _pipeline.get_job_class("apprentice")
	assert_true("fire_1" in cls.jp_costs,
		"Apprentice should teach fire_1 via JP")


func test_soldier_teaches_backstab() -> void:
	# backstab lives on the tier-2 soldier under the new tree.
	var cls := _pipeline.get_job_class("soldier")
	assert_true("backstab" in cls.jp_costs,
		"Soldier should teach backstab via JP")


func test_smoke_bomb_granted_by_item() -> void:
	var item := _pipeline.get_item("smoke_bomb_pouch")
	assert_not_null(item)
	assert_true("smoke_bomb" in item.granted_abilities,
		"smoke_bomb_pouch should grant smoke_bomb ability")


func test_all_abilities_resolve() -> void:
	var ability_ids: Array[String] = [
		"basic_strike", "first_aid",
		"fire_1", "fire_2", "ice_1", "thunder_1",
		"cure_1", "cure_2", "shield_1",
		"power_strike", "reckless_swing", "rage",
		"backstab", "inspire", "lullaby", "smoke_bomb"
	]
	for id in ability_ids:
		var a := _pipeline.get_ability(id)
		assert_not_null(a, "Ability '%s' should exist" % id)
		assert_ne(a.effect_type, "", "Ability '%s' should have an effect_type" % id)


# --- Willpower (WP) Derivation ---

func test_all_characters_have_wp() -> void:
	for id in _character_ids:
		var fs := _pipeline.get_final_stats(id)
		assert_gt(fs.effective("wp"), 0, "'%s' WP should be > 0" % id)


func test_fighter_wp_with_vagabond() -> void:
	# human_fighter derived WP under the redesigned balance (incl. vagabond wp mod).
	var fs := _pipeline.get_final_stats("human_fighter")
	assert_eq(fs.effective("wp"), 13, "Fighter WP under new balance")


# --- Race Base Stats ---

func test_races_have_base_stats() -> void:
	for race_id in ["human", "dwarf", "elf", "halfling"]:
		var r := _pipeline.get_race(race_id)
		assert_not_null(r)
		assert_false(r.base_stats.is_empty(), "Race '%s' should have base_stats" % race_id)
		assert_true(r.base_stats.has("hp"), "Race '%s' base_stats should have hp" % race_id)
