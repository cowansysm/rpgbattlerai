extends GutTest
## Tests for BattleUnit: construction from character, field defaults, HP initialization.

func test_from_character_sets_hp() -> void:
	var c := CharacterData.new()
	c.id = "hero"
	c.base_stats = {"spd": 3, "atk": 2, "rng": 1, "def": 1, "hp": 15}
	var sb := StatBlock.new()
	for k in StatKey.all_strings():
		sb.set_base(k, int(c.base_stats.get(k, 0)))
	var unit := BattleUnit.from_character(c, sb)
	assert_eq(unit.current_hp, 15)
	assert_eq(unit.character.id, "hero")


func test_default_fields() -> void:
	var c := CharacterData.new()
	c.id = "test"
	c.base_stats = {"spd": 3, "atk": 2, "rng": 1, "def": 1, "hp": 10}
	var sb := StatBlock.new()
	for k in StatKey.all_strings():
		sb.set_base(k, int(c.base_stats.get(k, 0)))
	var unit := BattleUnit.from_character(c, sb)
	assert_eq(unit.ap_remaining, 2)
	assert_false(unit.is_activated)
	assert_eq(unit.team, "")
	assert_eq(unit.position, Vector2i.ZERO)


func test_stat_block_is_independent_copy() -> void:
	var c := CharacterData.new()
	c.id = "test"
	c.base_stats = {"spd": 3, "atk": 2, "rng": 1, "def": 1, "hp": 10}
	var sb := StatBlock.new()
	for k in StatKey.all_strings():
		sb.set_base(k, int(c.base_stats.get(k, 0)))
	var unit := BattleUnit.from_character(c, sb)
	unit.stats.push_modifier(StatModifier.new("atk", 5, "buff"))
	assert_eq(sb.effective("atk"), 2, "original stat block unaffected by unit's modifiers")
	assert_eq(unit.stats.effective("atk"), 7)
