extends GutTest
## Tests for RoundPlan: committed plan storage and SPD-sorted iteration.


func _make_unit(id: String, team: String, spd: int = 3) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = []
	c.abilities = []
	var sb := StatBlock.new()
	sb.set_base("spd", spd)
	sb.set_base("hp", 10)
	sb.set_base("def", 1)
	sb.set_base("atk", 2)
	sb.set_base("rng", 1)
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	return u


# --- Commit and retrieve ---

func test_commit_and_retrieve() -> void:
	var rp := RoundPlan.new()
	var unit := _make_unit("a0", "playerA")
	var plan := AIPlan.make_defend()
	rp.commit(unit, plan)
	assert_true(rp.has_plan(unit))
	assert_eq(rp.get_plan(unit), plan)


func test_size_after_commits() -> void:
	var rp := RoundPlan.new()
	assert_eq(rp.size(), 0)
	rp.commit(_make_unit("a0", "playerA"), AIPlan.make_defend())
	assert_eq(rp.size(), 1)
	rp.commit(_make_unit("b0", "playerB"), AIPlan.make_wait())
	assert_eq(rp.size(), 2)


func test_overwrite_plan() -> void:
	var rp := RoundPlan.new()
	var unit := _make_unit("a0", "playerA")
	var plan1 := AIPlan.make_defend()
	var plan2 := AIPlan.make_wait()
	rp.commit(unit, plan1)
	rp.commit(unit, plan2)
	assert_eq(rp.get_plan(unit), plan2, "Later commit should overwrite")
	assert_eq(rp.size(), 1)


func test_clear() -> void:
	var rp := RoundPlan.new()
	rp.commit(_make_unit("a0", "playerA"), AIPlan.make_defend())
	rp.commit(_make_unit("b0", "playerB"), AIPlan.make_wait())
	rp.clear()
	assert_eq(rp.size(), 0)


func test_has_plan_false_for_unknown() -> void:
	var rp := RoundPlan.new()
	var unit := _make_unit("a0", "playerA")
	assert_false(rp.has_plan(unit))


func test_get_plan_returns_null_for_unknown() -> void:
	var rp := RoundPlan.new()
	var unit := _make_unit("a0", "playerA")
	assert_null(rp.get_plan(unit))


# --- SPD ordering ---

func test_sorted_by_speed_descending() -> void:
	var rp := RoundPlan.new()
	var slow := _make_unit("slow", "playerA", 3)
	var fast := _make_unit("fast", "playerB", 7)
	var mid := _make_unit("mid", "playerA", 5)
	rp.commit(slow, AIPlan.make_defend())
	rp.commit(fast, AIPlan.make_defend())
	rp.commit(mid, AIPlan.make_defend())

	var sorted := rp.sorted_by_speed(42)
	assert_eq(sorted[0]["unit"].character.id, "fast")
	assert_eq(sorted[1]["unit"].character.id, "mid")
	assert_eq(sorted[2]["unit"].character.id, "slow")


func test_sorted_by_speed_seeded_ties_deterministic() -> void:
	var rp := RoundPlan.new()
	var a := _make_unit("a0", "playerA", 5)
	var b := _make_unit("b0", "playerB", 5)
	rp.commit(a, AIPlan.make_defend())
	rp.commit(b, AIPlan.make_defend())

	# Same seed should produce same order
	var sorted1 := rp.sorted_by_speed(123)
	var sorted2 := rp.sorted_by_speed(123)
	assert_eq(sorted1[0]["unit"].character.id, sorted2[0]["unit"].character.id,
		"Same seed should produce same tie-break order")


func test_sorted_by_speed_different_seeds_may_differ() -> void:
	# With enough units at equal SPD, different seeds should eventually produce
	# a different ordering. We just check that the function doesn't crash.
	var rp := RoundPlan.new()
	for i in range(5):
		rp.commit(_make_unit("u%d" % i, "playerA", 5), AIPlan.make_defend())
	var sorted1 := rp.sorted_by_speed(1)
	var sorted2 := rp.sorted_by_speed(999)
	# At least it should return 5 entries
	assert_eq(sorted1.size(), 5)
	assert_eq(sorted2.size(), 5)


func test_sorted_by_speed_first_team_wins_ties() -> void:
	var rp := RoundPlan.new()
	var a := _make_unit("a0", "playerA", 5)
	var b := _make_unit("b0", "playerB", 5)
	rp.commit(a, AIPlan.make_defend())
	rp.commit(b, AIPlan.make_defend())

	# playerA wins ties
	var sorted := rp.sorted_by_speed(42, "playerA")
	assert_eq(sorted[0]["unit"].character.id, "a0",
		"playerA should win ties when specified")
	assert_eq(sorted[1]["unit"].character.id, "b0")


func test_sorted_by_speed_first_team_wins_ties_reversed() -> void:
	var rp := RoundPlan.new()
	var a := _make_unit("a0", "playerA", 5)
	var b := _make_unit("b0", "playerB", 5)
	rp.commit(a, AIPlan.make_defend())
	rp.commit(b, AIPlan.make_defend())

	# playerB wins ties
	var sorted := rp.sorted_by_speed(42, "playerB")
	assert_eq(sorted[0]["unit"].character.id, "b0",
		"playerB should win ties when specified")
	assert_eq(sorted[1]["unit"].character.id, "a0")
