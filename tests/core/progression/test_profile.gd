extends GutTest
## Unit tests for the Profile meta-progression model.


func test_profile_defaults() -> void:
	var p := Profile.new()
	assert_eq(p.profile_id, "default")
	assert_eq(p.completed_runs, 0)
	assert_true(p.unlocked_templates.is_empty())
	assert_true(p.unlocked_classes.is_empty())
	assert_true(p.meta_unlocks.is_empty())


func test_profile_round_trip() -> void:
	var p := Profile.new()
	p.profile_id = "test"
	p.completed_runs = 5
	p.unlocked_templates = ["human_warrior", "elf_archer"]
	p.unlocked_classes = ["sage", "ranger"]
	p.meta_unlocks = ["first_victory", "deep_delver"]

	var d: Dictionary = p.to_dict()
	var q: Profile = Profile.from_dict(d)

	assert_eq(q.profile_id, "test")
	assert_eq(q.completed_runs, 5)
	assert_eq(q.unlocked_templates.size(), 2)
	assert_true(q.has_template("human_warrior"))
	assert_true(q.has_template("elf_archer"))
	assert_eq(q.unlocked_classes.size(), 2)
	assert_true(q.has_class("sage"))
	assert_true(q.has_class("ranger"))
	assert_eq(q.meta_unlocks.size(), 2)
	assert_true(q.has_unlock("first_victory"))
	assert_true(q.has_unlock("deep_delver"))


func test_empty_dict_produces_defaults() -> void:
	var p: Profile = Profile.from_dict({})
	assert_eq(p.profile_id, "default")
	assert_eq(p.completed_runs, 0)
	assert_true(p.unlocked_templates.is_empty())
	assert_true(p.unlocked_classes.is_empty())
	assert_true(p.meta_unlocks.is_empty())


func test_grant_template_adds() -> void:
	var p := Profile.new()
	p.grant_template("warrior")
	assert_true(p.has_template("warrior"))
	assert_eq(p.unlocked_templates.size(), 1)


func test_grant_template_deduplicates() -> void:
	var p := Profile.new()
	p.grant_template("warrior")
	p.grant_template("warrior")
	assert_eq(p.unlocked_templates.size(), 1)


func test_grant_class_adds() -> void:
	var p := Profile.new()
	p.grant_class("sage")
	assert_true(p.has_class("sage"))
	assert_eq(p.unlocked_classes.size(), 1)


func test_grant_class_deduplicates() -> void:
	var p := Profile.new()
	p.grant_class("sage")
	p.grant_class("sage")
	assert_eq(p.unlocked_classes.size(), 1)


func test_grant_unlock_adds() -> void:
	var p := Profile.new()
	p.grant_unlock("first_victory")
	assert_true(p.has_unlock("first_victory"))


func test_grant_unlock_deduplicates() -> void:
	var p := Profile.new()
	p.grant_unlock("first_victory")
	p.grant_unlock("first_victory")
	assert_eq(p.meta_unlocks.size(), 1)


func test_has_returns_false_for_missing() -> void:
	var p := Profile.new()
	assert_false(p.has_template("nonexistent"))
	assert_false(p.has_class("nonexistent"))
	assert_false(p.has_unlock("nonexistent"))


func test_to_dict_does_not_alias() -> void:
	var p := Profile.new()
	p.grant_template("warrior")
	var d: Dictionary = p.to_dict()
	# Mutating the dict should not affect the profile
	(d["unlocked_templates"] as Array).append("rogue")
	assert_eq(p.unlocked_templates.size(), 1)
