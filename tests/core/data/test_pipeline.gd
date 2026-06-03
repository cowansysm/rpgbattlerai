extends GutTest
## Tests for DataPipeline: full cross-module wiring.
## G6: valid fixture, dangling ref rejection, bad effect rejection.

func test_full_pipeline_on_valid_fixture() -> void:
	var pipeline := DataPipeline.new()
	var errors := pipeline.run("res://tests/fixtures/valid_set")
	assert_eq(errors.size(), 0, "valid fixture set should produce zero errors")
	# Registry counts
	assert_eq(pipeline.races.size(), 1)
	assert_eq(pipeline.classes.size(), 1)
	assert_eq(pipeline.abilities.size(), 1)
	assert_eq(pipeline.items.size(), 1)
	assert_eq(pipeline.characters.size(), 1)
	assert_eq(pipeline.maps.size(), 1)
	# Character loaded correctly
	var c := pipeline.get_character("test_fighter")
	assert_not_null(c, "test_fighter should exist")
	assert_eq(c.race, "test_race")
	assert_eq(c.bp, 10)
	# Derived stats correct: base(spd:3,atk:2) + race(spd:1) + class(atk:1)
	var sb := pipeline.get_final_stats("test_fighter")
	assert_not_null(sb, "final_stats should be computed")
	assert_eq(sb.effective("spd"), 4, "spd: 3 base + 1 race")
	assert_eq(sb.effective("atk"), 3, "atk: 2 base + 1 class")
	assert_eq(sb.effective("hp"), 10, "hp: 10 base, no modifiers")
	assert_eq(sb.effective_move(), 4)
	assert_eq(sb.effective_jump_climb(), 3)  # floor(4/2)+1 = 3
	# BattleUnit instantiation
	var unit := BattleUnit.from_character(c, sb)
	assert_eq(unit.current_hp, sb.effective("hp"))
	assert_eq(unit.ap_remaining, 2)
	assert_false(unit.is_activated)


func test_pipeline_rejects_dangling_refs() -> void:
	var pipeline := DataPipeline.new()
	var errors := pipeline.run("res://tests/fixtures/dangling_ref")
	assert_true(errors.size() > 0, "dangling ref fixture should produce errors")


func test_pipeline_rejects_bad_effect() -> void:
	var pipeline := DataPipeline.new()
	var errors := pipeline.run("res://tests/fixtures/bad_effect")
	assert_true(errors.size() > 0, "bad effect fixture should produce errors")
