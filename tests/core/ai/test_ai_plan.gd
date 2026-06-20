extends GutTest
## Tests for AIPlan: step model, AP cost, factory helpers.


func test_empty_plan_zero_cost() -> void:
	var plan := AIPlan.new()
	assert_eq(plan.total_ap_cost(), 0)
	assert_true(plan.is_empty())


func test_move_attack_cost() -> void:
	var plan := AIPlan.make_move_attack(Vector2i(1, 0), Vector2i(2, 0))
	assert_eq(plan.total_ap_cost(), 2)
	assert_eq(plan.steps.size(), 2)
	assert_eq(plan.steps[0]["kind"], "move")
	assert_eq(plan.steps[1]["kind"], "attack")


func test_attack_only_cost() -> void:
	var plan := AIPlan.make_attack_only(Vector2i(1, 0))
	assert_eq(plan.total_ap_cost(), 1)
	assert_eq(plan.steps.size(), 1)


func test_move_ability_cost_1ap() -> void:
	var plan := AIPlan.make_move_ability(Vector2i(1, 0), "fire_1", Vector2i(2, 0), 1)
	assert_eq(plan.total_ap_cost(), 2)
	assert_eq(plan.steps.size(), 2)
	assert_eq(plan.steps[1]["kind"], "ability")
	assert_eq(plan.steps[1]["ability_id"], "fire_1")


func test_ability_only_2ap() -> void:
	var plan := AIPlan.make_ability_only("fire_2", Vector2i(2, 0), 2)
	assert_eq(plan.total_ap_cost(), 2)
	assert_eq(plan.steps.size(), 1)
	assert_eq(plan.steps[0]["ap_cost"], 2)


func test_defend_cost() -> void:
	var plan := AIPlan.make_defend()
	assert_eq(plan.total_ap_cost(), 1)
	assert_eq(plan.steps[0]["kind"], "defend")


func test_wait_cost() -> void:
	var plan := AIPlan.make_wait()
	assert_eq(plan.total_ap_cost(), 0)
	assert_eq(plan.steps[0]["kind"], "wait")


func test_move_only_cost() -> void:
	var plan := AIPlan.make_move_only(Vector2i(1, 0))
	assert_eq(plan.total_ap_cost(), 1)
	assert_eq(plan.steps.size(), 1)
	assert_eq(plan.steps[0]["kind"], "move")


func test_add_step() -> void:
	var plan := AIPlan.new()
	plan.add_step({"kind": "move", "target_pos": Vector2i(1, 0)})
	plan.add_step({"kind": "attack", "target_pos": Vector2i(2, 0)})
	assert_eq(plan.steps.size(), 2)
	assert_eq(plan.total_ap_cost(), 2)
	assert_false(plan.is_empty())
