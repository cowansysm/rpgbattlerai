extends GutTest
## Phase 6 / A4: Verify all 8 templates instantiate correctly with vagabond class.
## Tests updated for A4 job-tree classes (vagabond, soldier, thief, adept).

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
	assert_true("basic_strike" in cls.granted_abilities)


func test_soldier_class_exists() -> void:
	var cls := _pipeline.get_job_class("soldier")
	assert_not_null(cls)
	assert_eq(cls.tier, 1)
	assert_eq(cls.archetype, "physical_attack")
	assert_true("power_strike" in cls.granted_abilities)


func test_thief_class_exists() -> void:
	var cls := _pipeline.get_job_class("thief")
	assert_not_null(cls)
	assert_eq(cls.tier, 1)
	assert_eq(cls.archetype, "control")
	assert_true("backstab" in cls.granted_abilities)


func test_adept_class_exists() -> void:
	var cls := _pipeline.get_job_class("adept")
	assert_not_null(cls)
	assert_eq(cls.tier, 1)
	assert_eq(cls.archetype, "magical_attack")
	assert_true("fire_1" in cls.granted_abilities)


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
	# Human Fighter: base def=10, vagabond def+1, human +0 = 11
	var fs := _pipeline.get_final_stats("human_fighter")
	assert_eq(fs.effective("def"), 11, "Fighter DEF should include vagabond modifier")


func test_fighter_atk_includes_vagabond() -> void:
	# Human Fighter: base atk=10, vagabond atk+1, human +0 = 11
	var fs := _pipeline.get_final_stats("human_fighter")
	assert_eq(fs.effective("atk"), 11, "Fighter ATK should include vagabond modifier")


# --- Ability Access ---

func test_vagabond_has_basic_strike() -> void:
	var cls := _pipeline.get_job_class("vagabond")
	assert_true("basic_strike" in cls.granted_abilities,
		"Vagabond class should grant basic_strike")


func test_soldier_has_power_strike() -> void:
	var cls := _pipeline.get_job_class("soldier")
	assert_true("power_strike" in cls.granted_abilities,
		"Soldier class should grant power_strike")


func test_adept_has_fire_1() -> void:
	var cls := _pipeline.get_job_class("adept")
	assert_true("fire_1" in cls.granted_abilities,
		"Adept class should grant fire_1")


func test_thief_has_backstab() -> void:
	var cls := _pipeline.get_job_class("thief")
	assert_true("backstab" in cls.granted_abilities,
		"Thief class should grant backstab")


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
	# human_fighter: base wp=12, human +0, vagabond +0 = 12
	var fs := _pipeline.get_final_stats("human_fighter")
	assert_eq(fs.effective("wp"), 12, "Fighter WP should be 12 base + 0 race + 0 class")


# --- Race Base Stats ---

func test_races_have_base_stats() -> void:
	for race_id in ["human", "dwarf", "elf", "halfling"]:
		var r := _pipeline.get_race(race_id)
		assert_not_null(r)
		assert_false(r.base_stats.is_empty(), "Race '%s' should have base_stats" % race_id)
		assert_true(r.base_stats.has("hp"), "Race '%s' base_stats should have hp" % race_id)
