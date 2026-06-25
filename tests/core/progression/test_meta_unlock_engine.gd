extends GutTest
## Unit tests for the MetaUnlockEngine.


var _table: Dictionary


func before_each() -> void:
	_table = {
		"rules": [
			{
				"id": "first_run",
				"trigger": "runs_completed",
				"threshold": 1,
				"grants": {"templates": [], "classes": [], "meta_unlocks": ["first_run"]}
			},
			{
				"id": "first_victory",
				"trigger": "boss_kill",
				"grants": {"templates": ["elf_archer"], "classes": ["ranger"], "meta_unlocks": ["first_victory"]}
			},
			{
				"id": "deep_delver",
				"trigger": "depth_reached",
				"threshold": 10,
				"grants": {"templates": [], "classes": [], "meta_unlocks": ["deep_delver"]}
			},
			{
				"id": "always_fires",
				"trigger": "run_complete",
				"grants": {"templates": [], "classes": [], "meta_unlocks": ["ran_once"]}
			},
		],
		"starting_boons": [
			{"id": "bonus_gold", "requires": "first_victory", "effect": {"gold": 100}},
			{"id": "free_boon", "requires": "", "effect": {"gold": 50}},
		]
	}


func _make_run(depth: int = 5) -> RunState:
	var rs := RunState.new()
	rs.run_id = "test_run"
	rs.band_id = "test_band"
	rs.seed_value = 42
	rs.depth = depth
	rs.down_limit = 2
	return rs


func test_run_complete_increments_count() -> void:
	var p := Profile.new()
	assert_eq(p.completed_runs, 0)
	var _earned := MetaUnlockEngine.evaluate_run_end(p, "defeat", _make_run(), _table)
	assert_eq(p.completed_runs, 1)


func test_run_complete_increments_on_victory_too() -> void:
	var p := Profile.new()
	MetaUnlockEngine.evaluate_run_end(p, "victory", _make_run(), _table)
	assert_eq(p.completed_runs, 1)


func test_runs_completed_trigger() -> void:
	var p := Profile.new()
	var earned := MetaUnlockEngine.evaluate_run_end(p, "defeat", _make_run(), _table)
	# After 1st run, completed_runs=1, threshold=1 should match
	var rule_ids: Array[String] = []
	for e in earned:
		rule_ids.append(str(e.get("rule_id", "")))
	assert_true(rule_ids.has("first_run"), "first_run should fire after 1st run")


func test_boss_kill_grants_unlock_on_victory() -> void:
	var p := Profile.new()
	var earned := MetaUnlockEngine.evaluate_run_end(p, "victory", _make_run(), _table)
	var rule_ids: Array[String] = []
	for e in earned:
		rule_ids.append(str(e.get("rule_id", "")))
	assert_true(rule_ids.has("first_victory"), "first_victory should fire on victory")
	assert_true(p.has_template("elf_archer"))
	assert_true(p.has_class("ranger"))
	assert_true(p.has_unlock("first_victory"))


func test_boss_kill_does_not_fire_on_defeat() -> void:
	var p := Profile.new()
	var earned := MetaUnlockEngine.evaluate_run_end(p, "defeat", _make_run(), _table)
	var rule_ids: Array[String] = []
	for e in earned:
		rule_ids.append(str(e.get("rule_id", "")))
	assert_false(rule_ids.has("first_victory"), "first_victory should not fire on defeat")
	assert_false(p.has_template("elf_archer"))


func test_depth_reached_trigger() -> void:
	var p := Profile.new()
	var earned := MetaUnlockEngine.evaluate_run_end(p, "defeat", _make_run(12), _table)
	var rule_ids: Array[String] = []
	for e in earned:
		rule_ids.append(str(e.get("rule_id", "")))
	assert_true(rule_ids.has("deep_delver"), "deep_delver should fire at depth 12")


func test_depth_reached_not_met() -> void:
	var p := Profile.new()
	var earned := MetaUnlockEngine.evaluate_run_end(p, "defeat", _make_run(5), _table)
	var rule_ids: Array[String] = []
	for e in earned:
		rule_ids.append(str(e.get("rule_id", "")))
	assert_false(rule_ids.has("deep_delver"), "deep_delver should not fire at depth 5")


func test_run_complete_trigger_always_fires() -> void:
	var p := Profile.new()
	var earned := MetaUnlockEngine.evaluate_run_end(p, "defeat", _make_run(), _table)
	var rule_ids: Array[String] = []
	for e in earned:
		rule_ids.append(str(e.get("rule_id", "")))
	assert_true(rule_ids.has("always_fires"), "run_complete trigger should fire on any outcome")


func test_already_unlocked_not_duplicated() -> void:
	var p := Profile.new()
	p.grant_unlock("first_run")
	p.grant_unlock("ran_once")
	var earned := MetaUnlockEngine.evaluate_run_end(p, "defeat", _make_run(), _table)
	var rule_ids: Array[String] = []
	for e in earned:
		rule_ids.append(str(e.get("rule_id", "")))
	assert_false(rule_ids.has("first_run"), "first_run should not re-fire if already granted")
	assert_false(rule_ids.has("always_fires"), "always_fires should not re-fire if already granted")


func test_no_matching_rules_returns_empty() -> void:
	var p := Profile.new()
	# Pre-fill everything so nothing matches
	p.grant_unlock("first_run")
	p.grant_unlock("first_victory")
	p.grant_template("elf_archer")
	p.grant_class("ranger")
	p.grant_unlock("deep_delver")
	p.grant_unlock("ran_once")
	var earned := MetaUnlockEngine.evaluate_run_end(p, "victory", _make_run(12), _table)
	assert_eq(earned.size(), 0, "No new unlocks when everything already granted")


func test_empty_table_returns_empty() -> void:
	var p := Profile.new()
	var earned := MetaUnlockEngine.evaluate_run_end(p, "victory", _make_run(), {})
	assert_eq(earned.size(), 0)
	# completed_runs still increments
	assert_eq(p.completed_runs, 1)


func test_resolve_boons_with_qualifying_unlock() -> void:
	var p := Profile.new()
	p.grant_unlock("first_victory")
	var boons := MetaUnlockEngine.resolve_boons(p, _table)
	# Should get both: bonus_gold (requires first_victory) and free_boon (requires "")
	assert_eq(boons.size(), 2)
	var ids: Array[String] = []
	for b in boons:
		ids.append(str(b.get("id", "")))
	assert_true(ids.has("bonus_gold"))
	assert_true(ids.has("free_boon"))


func test_resolve_boons_without_qualifying_unlock() -> void:
	var p := Profile.new()
	var boons := MetaUnlockEngine.resolve_boons(p, _table)
	# Only free_boon (requires "") should qualify
	assert_eq(boons.size(), 1)
	assert_eq(str(boons[0].get("id", "")), "free_boon")


func test_resolve_boons_empty_table() -> void:
	var p := Profile.new()
	var boons := MetaUnlockEngine.resolve_boons(p, {})
	assert_eq(boons.size(), 0)
