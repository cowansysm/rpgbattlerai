extends GutTest
## Tests for MatchBuilder orchestration.
## Uses DataPipeline for real character/map data (integration test).
## Spec reference: phase7-spec.md §5

var _pipeline: DataPipeline
var _builder: MatchBuilder


func before_all() -> void:
	_pipeline = DataPipeline.new()
	var errors := _pipeline.run("res://data")
	assert_eq(errors.size(), 0, "data should load with zero errors")


func before_each() -> void:
	_builder = MatchBuilder.new(
		_pipeline.get_character,
		_pipeline.get_final_stats,
		_pipeline.maps.all,
		_pipeline.get_terrain,
		_pipeline.get_ability,
		_pipeline.get_job_class,
		_pipeline.get_item,
	)


# --- Tier config tests ---

func test_get_tier_config_skirmish() -> void:
	var config := _builder.get_tier_config("skirmish")
	assert_false(config.is_empty())
	assert_eq(int(config["bp_cap"]), 100)
	assert_eq(int(config["min"]), 3)
	assert_eq(int(config["max"]), 5)


func test_get_tier_config_standard() -> void:
	var config := _builder.get_tier_config("standard")
	assert_eq(int(config["bp_cap"]), 150)
	assert_eq(int(config["min"]), 4)
	assert_eq(int(config["max"]), 8)


func test_get_tier_config_large() -> void:
	var config := _builder.get_tier_config("large")
	assert_eq(int(config["bp_cap"]), 250)
	assert_eq(int(config["min"]), 6)
	assert_eq(int(config["max"]), 12)


func test_get_tier_config_invalid_returns_empty() -> void:
	var config := _builder.get_tier_config("nonexistent")
	assert_true(config.is_empty())


func test_get_tier_ids_returns_all_three() -> void:
	var ids := _builder.get_tier_ids()
	assert_gte(ids.size(), 3)
	assert_true("skirmish" in ids)
	assert_true("standard" in ids)
	assert_true("large" in ids)


# --- Map filtering tests ---

func test_get_maps_for_tier_filters_correctly() -> void:
	var maps := _builder.get_maps_for_tier("skirmish")
	assert_gte(maps.size(), 1, "should have at least 1 skirmish map")
	for m in maps:
		assert_eq(m.tier, "skirmish")


func test_get_maps_for_tier_standard() -> void:
	var maps := _builder.get_maps_for_tier("standard")
	assert_gte(maps.size(), 1)
	for m in maps:
		assert_eq(m.tier, "standard")


func test_get_maps_for_tier_nonexistent_returns_empty() -> void:
	var maps := _builder.get_maps_for_tier("mega")
	assert_eq(maps.size(), 0)


func test_select_random_map_returns_correct_tier() -> void:
	var m := _builder.select_random_map("standard")
	assert_not_null(m)
	assert_eq(m.tier, "standard")


func test_select_random_map_nonexistent_returns_null() -> void:
	var m := _builder.select_random_map("mega")
	assert_null(m)


# --- Draft creation tests ---

func test_create_draft_returns_valid_draft() -> void:
	var draft := _builder.create_draft("skirmish")
	assert_not_null(draft)
	assert_eq(draft.bp_cap(), 100)
	assert_eq(draft.min_characters(), 3)
	assert_eq(draft.max_characters(), 5)
	assert_eq(draft.state(), PartyDraft.State.EMPTY)


# --- Build match tests ---

func test_build_match_with_unconfirmed_drafts_errors() -> void:
	var draft_a := _builder.create_draft("skirmish")
	var draft_b := _builder.create_draft("skirmish")
	draft_a.add_character("human_fighter")
	# Neither confirmed
	var m := _builder.select_random_map("skirmish")
	var result := _builder.build_match(draft_a, draft_b, m)
	assert_false(result["errors"].is_empty())
	assert_null(result["state"])


func test_build_match_produces_valid_match_state() -> void:
	# Build two valid skirmish parties (3 chars each, BP <= 100)
	# human_fighter=18, human_archer=13, human_rogue=16 -> 47 BP
	var draft_a := _builder.create_draft("skirmish")
	draft_a.add_character("human_fighter")
	draft_a.add_character("human_archer")
	draft_a.add_character("human_rogue")
	draft_a.confirm()

	# human_bard=17, dwarf_barbarian=20, elf_red_mage=26 -> 63 BP
	var draft_b := _builder.create_draft("skirmish")
	draft_b.add_character("human_bard")
	draft_b.add_character("dwarf_barbarian")
	draft_b.add_character("elf_red_mage")
	draft_b.confirm()

	var m := _builder.select_random_map("skirmish")
	var result := _builder.build_match(draft_a, draft_b, m)

	assert_true(result["errors"].is_empty(),
		"Expected no errors, got: %s" % str(result["errors"]))
	var state: MatchState = result["state"]
	assert_not_null(state)

	# Verify parties
	assert_eq(state.parties["playerA"].size(), 3)
	assert_eq(state.parties["playerB"].size(), 3)

	# Verify teams assigned
	for u: BattleUnit in state.parties["playerA"]:
		assert_eq(u.team, "playerA")
	for u: BattleUnit in state.parties["playerB"]:
		assert_eq(u.team, "playerB")

	# Verify deployment (units have positions in occupancy)
	assert_gte(state.occupancy.size(), 6,
		"all 6 units should be deployed to occupancy tiles")

	# Verify round started
	assert_eq(state.phase, MatchState.Phase.AWAITING_ACTIVATION)
	assert_eq(state.round_number, 1)


func test_build_match_units_have_hp() -> void:
	var draft_a := _builder.create_draft("skirmish")
	draft_a.add_character("human_fighter")
	draft_a.add_character("human_archer")
	draft_a.add_character("human_rogue")
	draft_a.confirm()

	var draft_b := _builder.create_draft("skirmish")
	draft_b.add_character("human_bard")
	draft_b.add_character("dwarf_barbarian")
	draft_b.add_character("elf_red_mage")
	draft_b.confirm()

	var m := _builder.select_random_map("skirmish")
	var result := _builder.build_match(draft_a, draft_b, m)
	var state: MatchState = result["state"]

	# All units should have HP > 0
	for team in state.parties.keys():
		for u: BattleUnit in state.parties[team]:
			assert_gt(u.current_hp, 0,
				"%s should have HP > 0" % u.character.id)


func test_build_match_activation_possible() -> void:
	var draft_a := _builder.create_draft("skirmish")
	draft_a.add_character("human_fighter")
	draft_a.add_character("human_archer")
	draft_a.add_character("human_rogue")
	draft_a.confirm()

	var draft_b := _builder.create_draft("skirmish")
	draft_b.add_character("human_bard")
	draft_b.add_character("dwarf_barbarian")
	draft_b.add_character("elf_red_mage")
	draft_b.confirm()

	var m := _builder.select_random_map("skirmish")
	var result := _builder.build_match(draft_a, draft_b, m)
	var state: MatchState = result["state"]

	# Should be able to activate a unit
	var team := RoundManager.current_team(state)
	var available := state.unactivated_units(team)
	assert_gt(available.size(), 0, "should have units to activate")

	var unit: BattleUnit = available[0]
	var err := RoundManager.activate_unit(state, unit)
	assert_eq(err, "", "activation should succeed")
	assert_eq(state.phase, MatchState.Phase.UNIT_TURN)


func test_mirror_picks_allowed() -> void:
	# Both players can draft the same characters
	var draft_a := _builder.create_draft("skirmish")
	draft_a.add_character("human_fighter")
	draft_a.add_character("human_archer")
	draft_a.add_character("human_rogue")
	draft_a.confirm()

	var draft_b := _builder.create_draft("skirmish")
	draft_b.add_character("human_fighter")		# same as player A
	draft_b.add_character("human_archer")		# same as player A
	draft_b.add_character("dwarf_barbarian")
	draft_b.confirm()

	var m := _builder.select_random_map("skirmish")
	var result := _builder.build_match(draft_a, draft_b, m)

	assert_true(result["errors"].is_empty(),
		"Mirror picks should be allowed: %s" % str(result["errors"]))
	assert_not_null(result["state"])
