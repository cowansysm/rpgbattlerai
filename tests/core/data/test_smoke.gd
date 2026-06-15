extends GutTest
## Smoke test: loads full data/ directory and verifies everything works end to end.

var _pipeline: DataPipeline


func before_all() -> void:
	_pipeline = DataPipeline.new()
	var errors := _pipeline.run("res://data")
	assert_eq(errors.size(), 0, "full content should load with zero errors")


func test_entity_counts() -> void:
	assert_eq(_pipeline.races.size(), 4, "4 races expected")
	assert_eq(_pipeline.classes.size(), 8, "8 classes expected")
	assert_eq(_pipeline.abilities.size(), 14, "14 abilities expected")
	assert_eq(_pipeline.items.size(), 12, "12 items expected")
	assert_eq(_pipeline.characters.size(), 8, "8 characters expected")
	assert_eq(_pipeline.maps.size(), 6, "6 maps expected")


func test_accessor_returns_correct_type() -> void:
	var human := _pipeline.get_race("human")
	assert_not_null(human)
	assert_eq(human.id, "human")
	var archer := _pipeline.get_job_class("archer")
	assert_not_null(archer)
	assert_eq(archer.id, "archer")
	var bow := _pipeline.get_item("bow")
	assert_not_null(bow)
	assert_eq(bow.id, "bow")
	var fire_1 := _pipeline.get_ability("fire_1")
	assert_not_null(fire_1)
	assert_eq(fire_1.effect_type, "damage")


func test_reference_resolution() -> void:
	var c := _pipeline.get_character("human_archer")
	assert_not_null(c)
	assert_not_null(_pipeline.get_race(c.race), "race ref resolves")
	for cls_id in c.classes:
		assert_not_null(_pipeline.get_job_class(cls_id), "class ref '%s' resolves" % cls_id)
	for item_id in c.equipment:
		assert_not_null(_pipeline.get_item(item_id), "item ref '%s' resolves" % item_id)


func test_derived_stats_computed() -> void:
	# Human Archer: base spd:3 + human(0) + archer(rng:1) → spd:3, rng:3
	var sb := _pipeline.get_final_stats("human_archer")
	assert_not_null(sb, "human_archer should have final_stats")
	assert_eq(sb.effective("spd"), 3, "spd: 3 base, no race/class modifier")
	assert_eq(sb.effective("rng"), 3, "rng: 2 base + 1 archer")
	assert_eq(sb.effective("hp"), 16, "hp: 16 base, no modifiers")
	assert_eq(sb.effective_move(), 3, "move == spd")


func test_battle_unit_from_loaded_character() -> void:
	var c := _pipeline.get_character("human_archer")
	var sb := _pipeline.get_final_stats("human_archer")
	var unit := BattleUnit.from_character(c, sb)
	assert_true(unit.current_hp > 0, "BattleUnit HP should be positive")
	assert_eq(unit.ap_remaining, 2)
	assert_false(unit.is_activated)
	assert_eq(unit.character.id, "human_archer")
