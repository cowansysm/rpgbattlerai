extends GutTest
const SharedPipeline = preload("res://tests/helpers/shared_pipeline.gd")
## A9: Full-library smoke test.
## Boots the entire data pipeline with the real content library and asserts
## structural invariants: clean load, content counts, cross-references, and
## A3-conformant ability authoring.


func test_full_library_boots_clean() -> void:
	var pipeline := SharedPipeline.get_pipeline()
	var errors := SharedPipeline.load_errors()
	assert_eq(errors.size(), 0, "full library should produce zero errors: %s" % str(errors))
	# Content count thresholds (per A9 targets)
	assert_true(pipeline.classes.size() >= 25,
		"expected >= 25 classes, got %d" % pipeline.classes.size())
	assert_true(pipeline.abilities.size() >= 70,
		"expected >= 70 abilities, got %d" % pipeline.abilities.size())
	assert_true(pipeline.items.size() >= 46,
		"expected >= 46 items, got %d" % pipeline.items.size())
	assert_true(pipeline.characters.size() >= 20,
		"expected >= 20 characters, got %d" % pipeline.characters.size())
	assert_true(pipeline.terrains.size() >= 17,
		"expected >= 17 terrain types, got %d" % pipeline.terrains.size())


func test_every_class_provides_ability_access() -> void:
	# Every class must expose an ability path: innate granted_abilities (monster/authored
	# kits) or a learnable jp_costs catalog (player learn-via-JP). Core actions
	# (attack/move/defend/wait) are intrinsic, so an empty granted set is still functional.
	var pipeline := SharedPipeline.get_pipeline()
	var errors := SharedPipeline.load_errors()
	assert_eq(errors.size(), 0, "pipeline should boot clean")
	for cls in pipeline.classes.all():
		assert_true(cls.granted_abilities.size() > 0 or cls.jp_costs.size() > 0,
			"class '%s' should grant or teach at least one ability" % cls.id)
		for ab_id in cls.granted_abilities:
			assert_true(pipeline.abilities.has(ab_id),
				"class '%s' grants unknown ability '%s'" % [cls.id, ab_id])


func test_every_class_jp_costs_resolve() -> void:
	var pipeline := SharedPipeline.get_pipeline()
	var errors := SharedPipeline.load_errors()
	assert_eq(errors.size(), 0, "pipeline should boot clean")
	for cls in pipeline.classes.all():
		for ab_id in cls.jp_costs.keys():
			assert_true(pipeline.abilities.has(str(ab_id)),
				"class '%s' jp_costs references unknown ability '%s'" % [cls.id, ab_id])


func test_equipment_access_resolves() -> void:
	var pipeline := SharedPipeline.get_pipeline()
	var errors := SharedPipeline.load_errors()
	assert_eq(errors.size(), 0, "pipeline should boot clean")
	for cls in pipeline.classes.all():
		for item_id in cls.equipment_access:
			assert_true(pipeline.items.has(item_id),
				"class '%s' equipment_access references unknown item '%s'" % [cls.id, item_id])


func test_job_tree_acyclic_and_rooted() -> void:
	var pipeline := SharedPipeline.get_pipeline()
	var errors := SharedPipeline.load_errors()
	assert_eq(errors.size(), 0, "pipeline should boot clean")
	var tree_errors := Validator.validate_job_tree(pipeline.classes)
	assert_eq(tree_errors.size(), 0,
		"job tree should be valid: %s" % str(tree_errors))


func test_no_physical_skill_has_mag_scaling() -> void:
	var pipeline := SharedPipeline.get_pipeline()
	var errors := SharedPipeline.load_errors()
	assert_eq(errors.size(), 0, "pipeline should boot clean")
	for ab in pipeline.abilities.all():
		if ab.type == "skill":
			assert_eq(ab.mag_scaling, 0.0,
				"skill '%s' should have mag_scaling 0.0, got %s" % [ab.id, ab.mag_scaling])


func test_all_damage_spells_have_mag_scaling() -> void:
	var pipeline := SharedPipeline.get_pipeline()
	var errors := SharedPipeline.load_errors()
	assert_eq(errors.size(), 0, "pipeline should boot clean")
	for ab in pipeline.abilities.all():
		if ab.type == "spell" and ab.effect_type == "damage":
			assert_true(ab.mag_scaling > 0.0,
				"damage spell '%s' should have mag_scaling > 0, got %s" % [ab.id, ab.mag_scaling])


func test_item_abilities_resolve() -> void:
	var pipeline := SharedPipeline.get_pipeline()
	var errors := SharedPipeline.load_errors()
	assert_eq(errors.size(), 0, "pipeline should boot clean")
	for it in pipeline.items.all():
		for ab_id in it.granted_abilities:
			assert_true(pipeline.abilities.has(ab_id),
				"item '%s' grants unknown ability '%s'" % [it.id, ab_id])
