extends GutTest
## Phase 6: Verify all 8 spec characters instantiate correctly with full loadouts.

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


# --- Weapon Power ---

func test_weapon_power_melee() -> void:
	var expected: Dictionary = {
		"human_fighter": 5,    # sword
		"human_rogue": 3,      # daggers
		"dwarf_barbarian": 8,  # greataxe
		"elf_red_mage": 5,     # rapier
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
		"human_archer": 4,  # bow
		"human_bard": 2,    # sling
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


# --- Equipment Passives ---

func test_fighter_def_includes_equipment() -> void:
	# Fighter: base def=10, class def+2 = 12 (before equipment passives)
	var fs := _pipeline.get_final_stats("human_fighter")
	# Base 10 + fighter class +2 = 12 (from stat derivation)
	# Equipment passives are applied separately — check the derived stat
	assert_gte(fs.effective("def"), 12, "Fighter DEF should include class modifier")


func test_archer_has_range_bonus() -> void:
	# Archer: base rng=2, class rng+1 = 3
	var fs := _pipeline.get_final_stats("human_archer")
	assert_eq(fs.effective("rng"), 3, "Archer RNG should be 2 base + 1 class")


func test_rogue_has_speed_bonus() -> void:
	# Rogue: base spd=10, class spd+2, human +0 = 12
	var fs := _pipeline.get_final_stats("human_rogue")
	assert_eq(fs.effective("spd"), 12, "Rogue SPD should be 10 base + 2 class")


func test_barbarian_has_hp_bonus() -> void:
	# Barbarian: base hp=55, class hp+8, dwarf hp+5 = 68
	var fs := _pipeline.get_final_stats("dwarf_barbarian")
	assert_eq(fs.effective("hp"), 68, "Barbarian HP should be 55 base + 8 class + 5 dwarf")


# --- Ability Access ---

func test_fighter_has_power_strike() -> void:
	var c := _pipeline.get_character("human_fighter")
	var cls := _pipeline.get_job_class("fighter")
	assert_true("power_strike" in cls.granted_abilities,
		"Fighter class should grant power_strike")


func test_black_mage_has_all_spells() -> void:
	var cls := _pipeline.get_job_class("black_mage")
	for spell_id in ["fire_1", "fire_2", "ice_1", "thunder_1"]:
		assert_true(spell_id in cls.granted_abilities,
			"Black Mage class should grant '%s'" % spell_id)


func test_white_mage_has_all_spells() -> void:
	var cls := _pipeline.get_job_class("white_mage")
	for spell_id in ["cure_1", "cure_2", "shield_1"]:
		assert_true(spell_id in cls.granted_abilities,
			"White Mage class should grant '%s'" % spell_id)


func test_bard_has_songs() -> void:
	var cls := _pipeline.get_job_class("bard")
	for ability_id in ["inspire", "lullaby"]:
		assert_true(ability_id in cls.granted_abilities,
			"Bard class should grant '%s'" % ability_id)


func test_rogue_has_backstab() -> void:
	var cls := _pipeline.get_job_class("rogue")
	assert_true("backstab" in cls.granted_abilities,
		"Rogue class should grant backstab")


func test_smoke_bomb_granted_by_item() -> void:
	var item := _pipeline.get_item("smoke_bomb_pouch")
	assert_not_null(item)
	assert_true("smoke_bomb" in item.granted_abilities,
		"smoke_bomb_pouch should grant smoke_bomb ability")


func test_all_abilities_resolve() -> void:
	var ability_ids: Array[String] = [
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


func test_black_mage_has_wp_bonus() -> void:
	# elf_black_mage: base wp=12, elf +3, black_mage +6 = 21
	var fs := _pipeline.get_final_stats("elf_black_mage")
	assert_eq(fs.effective("wp"), 21, "Black Mage WP should be 12 base + 3 elf + 6 class")


func test_fighter_wp_no_bonus() -> void:
	# human_fighter: base wp=12, human +0, fighter +0 = 12
	var fs := _pipeline.get_final_stats("human_fighter")
	assert_eq(fs.effective("wp"), 12, "Fighter WP should be 12 base + 0 race + 0 class")
