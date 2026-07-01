extends GutTest
## Smoke test: loads full data/ directory and verifies everything works end to end.

var _pipeline: DataPipeline


func before_all() -> void:
	_pipeline = DataPipeline.new()
	var errors := _pipeline.run("res://data")
	assert_eq(errors.size(), 0, "full content should load with zero errors")


func test_entity_counts() -> void:
	assert_true(_pipeline.races.size() >= 4, ">=4 races expected, got %d" % _pipeline.races.size())
	assert_true(_pipeline.classes.size() >= 25, ">=25 classes expected, got %d" % _pipeline.classes.size())
	assert_true(_pipeline.abilities.size() >= 70, ">=70 abilities expected, got %d" % _pipeline.abilities.size())
	assert_true(_pipeline.items.size() >= 46, ">=46 items expected, got %d" % _pipeline.items.size())
	assert_true(_pipeline.characters.size() >= 20, ">=20 characters expected, got %d" % _pipeline.characters.size())
	assert_eq(_pipeline.maps.size(), 6, "6 maps expected")


func test_accessor_returns_correct_type() -> void:
	var human := _pipeline.get_race("human")
	assert_not_null(human)
	assert_eq(human.id, "human")
	var vagabond := _pipeline.get_job_class("vagabond")
	assert_not_null(vagabond)
	assert_eq(vagabond.id, "vagabond")
	var sword := _pipeline.get_item("sword")
	assert_not_null(sword)
	assert_eq(sword.id, "sword")
	var fire_1 := _pipeline.get_ability("fire_1")
	assert_not_null(fire_1)
	assert_eq(fire_1.effect_type, "damage")


func test_reference_resolution() -> void:
	var c := _pipeline.get_character("human_fighter")
	assert_not_null(c)
	assert_not_null(_pipeline.get_race(c.race), "race ref resolves")
	for cls_id in c.classes:
		assert_not_null(_pipeline.get_job_class(cls_id), "class ref '%s' resolves" % cls_id)
	for item_id in c.equipment:
		assert_not_null(_pipeline.get_item(item_id), "item ref '%s' resolves" % item_id)


func test_derived_stats_computed() -> void:
	# Human Fighter: base spd:10 + human(0) + vagabond(atk:1,def:1,hp:5) → spd:10, atk:11
	var sb := _pipeline.get_final_stats("human_fighter")
	assert_not_null(sb, "human_fighter should have final_stats")
	assert_eq(sb.effective("spd"), 10, "spd: 10 base, no race/class modifier")
	assert_eq(sb.effective("atk"), 11, "atk: 10 base + 1 vagabond")
	assert_eq(sb.effective("hp"), 55, "hp: 50 base + 5 vagabond")
	assert_eq(sb.effective_move(), 10, "move == spd")


func test_battle_unit_from_loaded_character() -> void:
	var c := _pipeline.get_character("human_fighter")
	var sb := _pipeline.get_final_stats("human_fighter")
	var unit := BattleUnit.from_character(c, sb)
	assert_true(unit.current_hp > 0, "BattleUnit HP should be positive")
	assert_eq(unit.ap_remaining, 2)
	assert_false(unit.is_activated)
	assert_eq(unit.character.id, "human_fighter")
