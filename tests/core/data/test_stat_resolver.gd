extends GutTest
## Tests for StatResolver: derivation, multiclass stacking, Rogue jump_climb bonus.

func test_base_only_no_modifiers() -> void:
	var c := CharacterData.new()
	c.base_stats = {"spd": 3, "atk": 2, "rng": 2, "def": 1, "hp": 10}
	var race := RaceData.new()
	race.stat_modifiers = {}
	var cls := ClassData.new()
	cls.stat_modifiers = {}
	cls.derived_bonuses = {}
	var sb := StatResolver.resolve(c, race, [cls])
	assert_eq(sb.effective("spd"), 3)
	assert_eq(sb.effective("hp"), 10)
	assert_eq(sb.effective_move(), 3)
	assert_eq(sb.effective_jump_climb(), 2)  # floor(3/2)+1


func test_race_and_class_modifiers_applied() -> void:
	var c := CharacterData.new()
	c.base_stats = {"spd": 3, "atk": 2, "rng": 1, "def": 1, "hp": 10}
	var race := RaceData.new()
	race.stat_modifiers = {"spd": 1, "hp": -1}  # Elf
	var cls := ClassData.new()
	cls.stat_modifiers = {"atk": 1}
	cls.derived_bonuses = {}
	var sb := StatResolver.resolve(c, race, [cls])
	assert_eq(sb.effective("spd"), 4)   # 3 + 1
	assert_eq(sb.effective("atk"), 3)   # 2 + 1
	assert_eq(sb.effective("hp"), 9)    # 10 - 1


func test_multiclass_additive_stacking() -> void:
	var c := CharacterData.new()
	c.base_stats = {"spd": 3, "atk": 2, "rng": 1, "def": 1, "hp": 10}
	var race := RaceData.new()
	race.stat_modifiers = {}
	var cls_a := ClassData.new()
	cls_a.stat_modifiers = {"atk": 1}
	cls_a.derived_bonuses = {}
	var cls_b := ClassData.new()
	cls_b.stat_modifiers = {"atk": 2, "def": 1}
	cls_b.derived_bonuses = {}
	var sb := StatResolver.resolve(c, race, [cls_a, cls_b])
	assert_eq(sb.effective("atk"), 5)   # 2 + 1 + 2
	assert_eq(sb.effective("def"), 2)   # 1 + 0 + 1


func test_rogue_jump_climb_bonus() -> void:
	var c := CharacterData.new()
	c.base_stats = {"spd": 4, "atk": 2, "rng": 1, "def": 1, "hp": 11}
	var race := RaceData.new()
	race.stat_modifiers = {}
	var rogue := ClassData.new()
	rogue.stat_modifiers = {"spd": 1, "atk": 1, "def": -1}
	rogue.derived_bonuses = {"jump_climb": 1}
	var sb := StatResolver.resolve(c, race, [rogue])
	# spd = 4+1 = 5, jump_climb = floor(5/2)+1+1 = 2+1+1 = 4
	assert_eq(sb.effective("spd"), 5)
	assert_eq(sb.effective_jump_climb(), 4)
