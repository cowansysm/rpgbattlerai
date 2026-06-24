extends GutTest

# --- Helpers ---

func _make_instance(id: String, downs: int = 0) -> CharacterInstance:
	var ci := CharacterInstance.new()
	ci.instance_id = id
	ci.template_id = "tmpl_human"
	ci.name = "Hero " + id
	ci.race = "human"
	ci.level = 3
	ci.active_class = "vagabond"
	ci.unlocked_classes = ["vagabond"] as Array[String]
	ci.downs_this_run = downs
	return ci


func _make_band(instances: Array[CharacterInstance]) -> BattleBand:
	var band := BattleBand.create("Test Band")
	for ci in instances:
		band.add_instance(ci)
	return band


func _make_run_state(down_limit: int = 2) -> RunState:
	var rs := RunState.new()
	rs.run_id = "test_run"
	rs.band_id = "bb_1"
	rs.down_limit = down_limit
	return rs


# --- Tests ---

func test_down_increments_on_downed_units() -> void:
	var ci: CharacterInstance = _make_instance("ci_1", 0)
	var band: BattleBand = _make_band([ci])
	var rs: RunState = _make_run_state()
	DeathModel.apply_post_battle(rs, band, ["ci_1"])
	assert_eq(ci.downs_this_run, 1)


func test_multiple_downs_increment() -> void:
	var ci: CharacterInstance = _make_instance("ci_1", 1)
	var band: BattleBand = _make_band([ci])
	var rs: RunState = _make_run_state()
	DeathModel.apply_post_battle(rs, band, ["ci_1"])
	assert_eq(ci.downs_this_run, 2)


func test_permadeath_on_exceeding_down_limit() -> void:
	# down_limit = 2, instance already at 2 downs, next down = permadeath
	var ci: CharacterInstance = _make_instance("ci_1", 2)
	var band: BattleBand = _make_band([ci])
	var rs: RunState = _make_run_state(2)
	var result: Dictionary = DeathModel.apply_post_battle(rs, band, ["ci_1"])
	assert_has(result["dead_ids"] as Array, "ci_1")
	assert_true(band.roster.is_empty(), "instance should be removed from roster")


func test_permadead_ids_returned() -> void:
	var ci1: CharacterInstance = _make_instance("ci_1", 2)
	var ci2: CharacterInstance = _make_instance("ci_2", 0)
	var band: BattleBand = _make_band([ci1, ci2])
	var rs: RunState = _make_run_state(2)
	var result: Dictionary = DeathModel.apply_post_battle(rs, band, ["ci_1", "ci_2"])
	# ci_1 exceeds limit (2+1=3 > 2), ci_2 does not (0+1=1 <= 2)
	assert_has(result["dead_ids"] as Array, "ci_1")
	assert_eq((result["dead_ids"] as Array).size(), 1)
	assert_eq(band.roster.size(), 1)  # only ci_2 survives


func test_run_lost_when_roster_empty() -> void:
	var ci: CharacterInstance = _make_instance("ci_1", 2)
	var band: BattleBand = _make_band([ci])
	var rs: RunState = _make_run_state(2)
	var result: Dictionary = DeathModel.apply_post_battle(rs, band, ["ci_1"])
	assert_true(result["run_lost"] as bool)


func test_run_not_lost_with_survivors() -> void:
	var ci1: CharacterInstance = _make_instance("ci_1", 0)
	var ci2: CharacterInstance = _make_instance("ci_2", 0)
	var band: BattleBand = _make_band([ci1, ci2])
	var rs: RunState = _make_run_state()
	var result: Dictionary = DeathModel.apply_post_battle(rs, band, ["ci_1"])
	assert_false(result["run_lost"] as bool)


func test_reset_downs() -> void:
	var ci1: CharacterInstance = _make_instance("ci_1", 2)
	var ci2: CharacterInstance = _make_instance("ci_2", 1)
	var band: BattleBand = _make_band([ci1, ci2])
	DeathModel.reset_downs(band)
	assert_eq(ci1.downs_this_run, 0)
	assert_eq(ci2.downs_this_run, 0)


func test_can_field_party_true_with_roster() -> void:
	var band: BattleBand = _make_band([_make_instance("ci_1")])
	assert_true(DeathModel.can_field_party(band))


func test_can_field_party_false_on_empty_roster() -> void:
	var band: BattleBand = _make_band([])
	assert_false(DeathModel.can_field_party(band))


func test_unknown_instance_id_ignored() -> void:
	var ci: CharacterInstance = _make_instance("ci_1", 0)
	var band: BattleBand = _make_band([ci])
	var rs: RunState = _make_run_state()
	# Pass an ID that doesn't exist in the band
	var result: Dictionary = DeathModel.apply_post_battle(rs, band, ["nonexistent"])
	assert_true((result["dead_ids"] as Array).is_empty())
	assert_eq(ci.downs_this_run, 0)  # unchanged
