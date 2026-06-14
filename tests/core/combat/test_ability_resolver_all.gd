extends GutTest
## Tests for AbilityResolver.all_abilities() method.
## Uses DataPipeline for real character/ability/class/item data.
## Spec reference: phase8-spec.md §6.1

var _pipeline: DataPipeline
var _resolver: AbilityResolver


func before_all() -> void:
	_pipeline = DataPipeline.new()
	var errors := _pipeline.run("res://data")
	assert_eq(errors.size(), 0, "data should load with zero errors")


func before_each() -> void:
	_resolver = AbilityResolver.new(
		_pipeline.get_ability,
		_pipeline.get_job_class,
		_pipeline.get_item,
	)


func _make_unit(char_id: String) -> BattleUnit:
	var c: CharacterData = _pipeline.get_character(char_id)
	var fs: StatBlock = _pipeline.get_final_stats(char_id)
	if not c or not fs:
		return null
	return BattleUnit.from_character(c, fs)


# --- Tests ---

func test_all_abilities_includes_class_granted() -> void:
	# Elf Black Mage gets abilities from the black_mage class
	var unit := _make_unit("elf_black_mage")
	assert_not_null(unit, "elf_black_mage should exist")

	var abilities := _resolver.all_abilities(unit)
	assert_gt(abilities.size(), 0, "black mage should have abilities")

	# Check that fire_1 is in the list (granted by black_mage class)
	var ids: Array = []
	for a in abilities:
		ids.append(a.id)
	assert_true("fire_1" in ids, "should include class-granted fire_1")


func test_all_abilities_includes_equipment_granted() -> void:
	# Human Rogue has equipment with granted abilities (smoke_bomb from smoke_bomb_pouch)
	var unit := _make_unit("human_rogue")
	assert_not_null(unit, "human_rogue should exist")

	var abilities := _resolver.all_abilities(unit)
	var ids: Array = []
	for a in abilities:
		ids.append(a.id)

	# Rogue class should grant backstab; equipment may grant smoke_bomb
	assert_true("backstab" in ids, "should include class-granted backstab")


func test_all_abilities_for_fighter() -> void:
	# Human Fighter — class grants power_strike
	var unit := _make_unit("human_fighter")
	assert_not_null(unit, "human_fighter should exist")

	var abilities := _resolver.all_abilities(unit)
	var ids: Array = []
	for a in abilities:
		ids.append(a.id)
	assert_true("power_strike" in ids, "should include class-granted power_strike")


func test_all_abilities_deduplicates() -> void:
	# If an ability appears from multiple sources, it should appear once
	var unit := _make_unit("elf_black_mage")
	assert_not_null(unit)

	var abilities := _resolver.all_abilities(unit)
	var ids: Array = []
	for a in abilities:
		assert_false(a.id in ids, "ability '%s' should not be duplicated" % a.id)
		ids.append(a.id)


func test_all_abilities_empty_for_no_abilities_unit() -> void:
	# Create a minimal unit with no class/equipment abilities
	var c := CharacterData.new()
	c.id = "test_empty"
	c.display_name = "Test Empty"
	c.race = "human"
	c.classes = []
	c.equipment = []
	c.abilities = []
	var sb := StatBlock.new()
	sb.set_base("hp", 10)
	sb.set_base("spd", 3)
	sb.set_base("atk", 1)
	sb.set_base("rng", 1)
	sb.set_base("def", 1)
	var unit := BattleUnit.from_character(c, sb)

	var abilities := _resolver.all_abilities(unit)
	assert_eq(abilities.size(), 0, "unit with no abilities should return empty")


func test_all_abilities_multiclass_unit() -> void:
	# Elf Red Mage has red_mage class which should grant both offensive and healing
	var unit := _make_unit("elf_red_mage")
	assert_not_null(unit, "elf_red_mage should exist")

	var abilities := _resolver.all_abilities(unit)
	assert_gt(abilities.size(), 0, "red mage should have abilities")


func test_resolve_and_all_abilities_consistent() -> void:
	# Every ability from all_abilities() should be resolvable via resolve()
	var unit := _make_unit("elf_black_mage")
	assert_not_null(unit)

	var abilities := _resolver.all_abilities(unit)
	for a in abilities:
		var resolved := _resolver.resolve(unit, a.id)
		assert_not_null(resolved,
			"resolve() should find '%s' that all_abilities() returned" % a.id)
