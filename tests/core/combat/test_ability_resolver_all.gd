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


## Builds a throwaway unit with an explicit loadout/equipment/classes, without
## mutating shared pipeline CharacterData. Learn-via-JP means player skills reach
## combat through the slotted loadout (character.abilities).
func _unit_with(abilities: Array, equipment: Array = [], classes: Array = ["vagabond"]) -> BattleUnit:
	var c := CharacterData.new()
	c.id = "test_unit"
	c.display_name = "Test Unit"
	c.race = "human"
	var t_classes: Array[String] = []
	for x in classes:
		t_classes.append(str(x))
	var t_equip: Array[String] = []
	for x in equipment:
		t_equip.append(str(x))
	var t_ab: Array[String] = []
	for x in abilities:
		t_ab.append(str(x))
	c.classes = t_classes
	c.equipment = t_equip
	c.abilities = t_ab
	var sb := StatBlock.new()
	sb.set_base("hp", 10)
	sb.set_base("spd", 3)
	sb.set_base("atk", 3)
	sb.set_base("rng", 1)
	sb.set_base("def", 1)
	return BattleUnit.from_character(c, sb)


# --- Tests ---

func test_all_abilities_includes_loadout() -> void:
	# Learn-via-JP: a player unit's skills come from its slotted loadout (character.abilities).
	var unit := _unit_with(["basic_strike", "fire_1"])
	var abilities := _resolver.all_abilities(unit)
	assert_gt(abilities.size(), 0, "unit with a loadout should have abilities")
	var ids: Array = []
	for a in abilities:
		ids.append(a.id)
	assert_true("basic_strike" in ids, "should include slotted basic_strike")
	assert_true("fire_1" in ids, "should include slotted fire_1")


func test_all_abilities_includes_equipment_granted() -> void:
	# Equipment that grants abilities surfaces them (smoke_bomb_pouch -> smoke_bomb).
	var unit := _unit_with([], ["smoke_bomb_pouch"])
	var abilities := _resolver.all_abilities(unit)
	var ids: Array = []
	for a in abilities:
		ids.append(a.id)
	assert_true("smoke_bomb" in ids, "should include equipment-granted smoke_bomb")


func test_all_abilities_for_fighter() -> void:
	# A slotted physical skill surfaces for a fighter-style loadout.
	var unit := _unit_with(["power_strike"])
	var abilities := _resolver.all_abilities(unit)
	var ids: Array = []
	for a in abilities:
		ids.append(a.id)
	assert_true("power_strike" in ids, "should include slotted power_strike")


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


func test_all_abilities_aggregates_loadout_and_equipment() -> void:
	# all_abilities() aggregates across sources: slotted skills + equipment-granted.
	var unit := _unit_with(["fire_1", "cure_1"], ["smoke_bomb_pouch"])
	var abilities := _resolver.all_abilities(unit)
	var ids: Array = []
	for a in abilities:
		ids.append(a.id)
	assert_true("fire_1" in ids and "cure_1" in ids and "smoke_bomb" in ids,
		"should aggregate loadout + equipment abilities")


func test_resolve_and_all_abilities_consistent() -> void:
	# Every ability from all_abilities() should be resolvable via resolve()
	var unit := _make_unit("elf_black_mage")
	assert_not_null(unit)

	var abilities := _resolver.all_abilities(unit)
	for a in abilities:
		var resolved := _resolver.resolve(unit, a.id)
		assert_not_null(resolved,
			"resolve() should find '%s' that all_abilities() returned" % a.id)
