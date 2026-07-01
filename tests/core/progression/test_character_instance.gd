extends GutTest
## Tests for CharacterInstance: identity generation, factory method.


func _make_template(race: String = "human") -> CharacterData:
	var c := CharacterData.new()
	c.id = "tmpl_" + race
	c.race = race
	c.display_name = "Template " + race
	return c


func _name_gen(race: String) -> String:
	return "Test %s Name" % race


func test_generate_creates_vagabond_l1() -> void:
	var t := _make_template("human")
	var ci := CharacterInstance.generate(t, _name_gen)
	assert_eq(ci.active_class, "vagabond")
	assert_eq(ci.character_level(), 1)
	assert_eq(ci.xp, 0)
	assert_true(ci.unlocked_classes.has("vagabond"))
	assert_eq(ci.unlocked_classes.size(), 1)
	assert_eq(ci.template_id, "tmpl_human")
	assert_eq(ci.race, "human")


func test_generate_assigns_unique_id() -> void:
	var t := _make_template("human")
	var ci1 := CharacterInstance.generate(t, _name_gen)
	var ci2 := CharacterInstance.generate(t, _name_gen)
	assert_ne(ci1.instance_id, ci2.instance_id, "two instances should have different IDs")
	assert_ne(ci1.instance_id, "", "instance_id should not be empty")


func test_generate_name_from_race() -> void:
	var t := _make_template("elf")
	var ci := CharacterInstance.generate(t, _name_gen)
	assert_eq(ci.name, "Test elf Name")


func test_generate_starts_with_empty_state() -> void:
	var t := _make_template("dwarf")
	var ci := CharacterInstance.generate(t, _name_gen)
	assert_eq(ci.learned_abilities.size(), 0)
	assert_eq(ci.ability_loadout.size(), 0)
	assert_eq(ci.equipment.size(), 0)
	assert_eq(ci.growth_accumulated.size(), 0)
	assert_eq(ci.jp.size(), 0)
	assert_eq(ci.downs_this_run, 0)
