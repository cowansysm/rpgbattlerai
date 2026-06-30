extends GutTest
## Tests for DeploymentController: alternation, legal tiles, placement validation.


# --- Stub terrain provider ---

static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	return p


# --- Helpers ---

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


func _setup_state(count_a: int, count_b: int) -> MatchState:
	var map := MapData.new()
	map.id = "test"
	var tiles: Array[TileRecord] = []
	for c in Hex.hexes_in_range(Vector2i(0, 0), 4):
		tiles.append(TileRecord.new(c.x, c.y, 0, "grass"))
	map.tiles = tiles

	var party_a: Array[BattleUnit] = []
	var party_b: Array[BattleUnit] = []
	for i in range(count_a):
		party_a.append(_make_unit("a%d" % i, "playerA"))
	for i in range(count_b):
		party_b.append(_make_unit("b%d" % i, "playerB"))

	return MatchSetup.create(party_a, party_b, map, _stub_terrain)


func _begin(count_a: int, count_b: int, zones: Dictionary,
	ai_teams: Array = ["playerB"]) -> Dictionary:
	var state := _setup_state(count_a, count_b)
	var ctrl := DeploymentController.new()
	var errors := ctrl.begin(state, zones, ai_teams)
	return {"state": state, "ctrl": ctrl, "errors": errors}


## Simple positional planner for auto_complete tests.
static func _positional_planner(
	_state: MatchState, _team: String, _unit: BattleUnit,
	legal: Array[Vector2i], _enemy_zone: Array[Vector2i],
) -> Vector2i:
	return legal[0]


# --- Tests ---

func test_ai_first_alternation() -> void:
	var d := _begin(2, 2, {
		"playerA": ["0,-3", "1,-3"],
		"playerB": ["0,3", "-1,3"],
	}, ["playerB"])
	assert_eq(d.errors.size(), 0)
	var ctrl: DeploymentController = d.ctrl
	# AI (playerB) should go first
	assert_eq(ctrl.current_team(), "playerB")


func test_alternation_order() -> void:
	var d := _begin(2, 2, {
		"playerA": ["0,-3", "1,-3"],
		"playerB": ["0,3", "-1,3"],
	}, ["playerB"])
	var ctrl: DeploymentController = d.ctrl
	# B places first
	assert_eq(ctrl.current_team(), "playerB")
	ctrl.place_next("playerB", Vector2i(0, 3))
	# Then A
	assert_eq(ctrl.current_team(), "playerA")
	ctrl.place_next("playerA", Vector2i(0, -3))
	# Then B again
	assert_eq(ctrl.current_team(), "playerB")
	ctrl.place_next("playerB", Vector2i(-1, 3))
	# Then A again
	assert_eq(ctrl.current_team(), "playerA")
	ctrl.place_next("playerA", Vector2i(1, -3))
	assert_true(ctrl.is_complete())


func test_place_next_rejects_wrong_team() -> void:
	var d := _begin(1, 1, {
		"playerA": ["0,-3"],
		"playerB": ["0,3"],
	}, ["playerB"])
	var ctrl: DeploymentController = d.ctrl
	# playerB should go first, so playerA placing should fail
	var errs := ctrl.place_next("playerA", Vector2i(0, -3))
	assert_true(errs.size() > 0, "should reject wrong team")


func test_place_next_rejects_illegal_tile() -> void:
	var d := _begin(1, 1, {
		"playerA": ["0,-3"],
		"playerB": ["0,3"],
	}, ["playerB"])
	var ctrl: DeploymentController = d.ctrl
	# playerB trying to place on playerA's zone tile
	var errs := ctrl.place_next("playerB", Vector2i(0, -3))
	assert_true(errs.size() > 0, "should reject tile not in team's zone")


func test_legal_tiles_excludes_occupied() -> void:
	var d := _begin(2, 1, {
		"playerA": ["0,-3", "1,-3"],
		"playerB": ["0,3"],
	}, ["playerB"])
	var ctrl: DeploymentController = d.ctrl
	# Place playerB's unit
	ctrl.place_next("playerB", Vector2i(0, 3))
	# playerB should have no legal tiles left (only had 1 zone tile)
	assert_eq(ctrl.legal_tiles("playerB").size(), 0)


func test_larger_side_finishes_remainder() -> void:
	var d := _begin(3, 1, {
		"playerA": ["0,-3", "1,-3", "-1,-3"],
		"playerB": ["0,3"],
	}, ["playerB"])
	var ctrl: DeploymentController = d.ctrl
	# B places first (1 unit)
	assert_eq(ctrl.current_team(), "playerB")
	ctrl.place_next("playerB", Vector2i(0, 3))
	# A places (1 of 3)
	assert_eq(ctrl.current_team(), "playerA")
	ctrl.place_next("playerA", Vector2i(0, -3))
	# B is empty, A continues (2 of 3)
	assert_eq(ctrl.current_team(), "playerA")
	ctrl.place_next("playerA", Vector2i(1, -3))
	# A continues (3 of 3)
	assert_eq(ctrl.current_team(), "playerA")
	ctrl.place_next("playerA", Vector2i(-1, -3))
	assert_true(ctrl.is_complete())


func test_is_complete_when_both_empty() -> void:
	var d := _begin(1, 1, {
		"playerA": ["0,-3"],
		"playerB": ["0,3"],
	}, ["playerB"])
	var ctrl: DeploymentController = d.ctrl
	assert_false(ctrl.is_complete())
	ctrl.place_next("playerB", Vector2i(0, 3))
	assert_false(ctrl.is_complete())
	ctrl.place_next("playerA", Vector2i(0, -3))
	assert_true(ctrl.is_complete())


func test_finish_transitions_to_round_start() -> void:
	var d := _begin(1, 1, {
		"playerA": ["0,-3"],
		"playerB": ["0,3"],
	}, ["playerB"])
	var ctrl: DeploymentController = d.ctrl
	var state: MatchState = d.state
	ctrl.place_next("playerB", Vector2i(0, 3))
	ctrl.place_next("playerA", Vector2i(0, -3))
	ctrl.finish()
	assert_eq(state.phase, MatchState.Phase.AWAITING_ACTIVATION)


func test_auto_complete_deploys_all() -> void:
	var d := _begin(2, 2, {
		"playerA": ["0,-3", "1,-3"],
		"playerB": ["0,3", "-1,3"],
	}, ["playerB"])
	var ctrl: DeploymentController = d.ctrl
	var state: MatchState = d.state
	ctrl.auto_complete(_positional_planner)
	assert_eq(state.phase, MatchState.Phase.AWAITING_ACTIVATION)
	# All units should have positions set
	for team in ["playerA", "playerB"]:
		for u: BattleUnit in state.parties[team]:
			assert_true(state.is_occupied(u.position),
				"%s should be at an occupied tile" % u.character.id)


func test_begin_errors_on_undersized_zone() -> void:
	var d := _begin(3, 1, {
		"playerA": ["0,-3", "1,-3"],  # Only 2 tiles for 3 units
		"playerB": ["0,3"],
	})
	assert_true(d.errors.size() > 0, "should error for undersized zone")


func test_begin_errors_on_offmap_zone_tile() -> void:
	var d := _begin(1, 1, {
		"playerA": ["99,99"],  # Not on the map
		"playerB": ["0,3"],
	})
	assert_true(d.errors.size() > 0, "should error for off-map zone tile")


func test_next_unit_returns_front_of_queue() -> void:
	var d := _begin(2, 1, {
		"playerA": ["0,-3", "1,-3"],
		"playerB": ["0,3"],
	}, ["playerB"])
	var ctrl: DeploymentController = d.ctrl
	var state: MatchState = d.state
	var first_b: BattleUnit = state.parties["playerB"][0]
	assert_eq(ctrl.next_unit("playerB").character.id, first_b.character.id)


func test_deployment_phase_set_on_begin() -> void:
	var d := _begin(1, 1, {
		"playerA": ["0,-3"],
		"playerB": ["0,3"],
	})
	assert_eq(d.state.phase, MatchState.Phase.DEPLOYMENT)
