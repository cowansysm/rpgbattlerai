extends GutTest
## Tests for MatchState: state container queries and helpers.


# --- Helpers ---

func _make_unit(id: String, team: String, spd: int = 3, hp: int = 10) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = []
	c.abilities = []
	c.base_stats = { "spd": spd, "hp": hp }
	var sb := StatBlock.new()
	sb.set_base("spd", spd)
	sb.set_base("hp", hp)
	sb.set_base("def", 1)
	sb.set_base("atk", 2)
	sb.set_base("rng", 1)
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	return u


# --- Tests ---

func test_initial_phase_is_setup() -> void:
	var state := MatchState.new()
	assert_eq(state.phase, MatchState.Phase.SETUP)


func test_initial_round_is_zero() -> void:
	var state := MatchState.new()
	assert_eq(state.round_number, 0)


func test_living_units_returns_all_when_alive() -> void:
	var state := MatchState.new()
	var u1 := _make_unit("a1", "playerA")
	var u2 := _make_unit("a2", "playerA")
	state.parties = { "playerA": [u1, u2], "playerB": [] }
	assert_eq(state.living_units("playerA").size(), 2)


func test_living_units_excludes_downed() -> void:
	var state := MatchState.new()
	var u1 := _make_unit("a1", "playerA")
	var u2 := _make_unit("a2", "playerA")
	u2.current_hp = 0
	state.parties = { "playerA": [u1, u2], "playerB": [] }
	assert_eq(state.living_units("playerA").size(), 1)


func test_unactivated_units_excludes_activated() -> void:
	var state := MatchState.new()
	var u1 := _make_unit("a1", "playerA")
	var u2 := _make_unit("a2", "playerA")
	u1.is_activated = true
	state.parties = { "playerA": [u1, u2], "playerB": [] }
	assert_eq(state.unactivated_units("playerA").size(), 1)
	assert_eq(state.unactivated_units("playerA")[0], u2)


func test_occupancy_tracking() -> void:
	var state := MatchState.new()
	var u := _make_unit("a1", "playerA")
	state.occupancy[Vector2i(0, 0)] = u
	assert_true(state.is_occupied(Vector2i(0, 0)))
	assert_false(state.is_occupied(Vector2i(1, 0)))
	assert_eq(state.unit_at(Vector2i(0, 0)), u)
	assert_null(state.unit_at(Vector2i(1, 0)))


func test_other_team() -> void:
	var state := MatchState.new()
	assert_eq(state.other_team("playerA"), "playerB")
	assert_eq(state.other_team("playerB"), "playerA")


func test_all_living_units() -> void:
	var state := MatchState.new()
	var u1 := _make_unit("a1", "playerA")
	var u2 := _make_unit("b1", "playerB")
	var u3 := _make_unit("b2", "playerB")
	u3.current_hp = 0
	state.parties = { "playerA": [u1], "playerB": [u2, u3] }
	assert_eq(state.all_living_units().size(), 2)
