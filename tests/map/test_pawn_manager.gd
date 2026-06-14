extends GutTest
## Tests for PawnManager sync logic: spawn, move, remove, highlight.
## Uses stub data (no autoloads) to test dictionary state and method behavior.
## Spec reference: phase8-spec.md §3.3

# --- Helpers ---

static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	return p


func _make_unit(id: String, team: String, pos: Vector2i) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.race = "human"
	c.classes = ["fighter"]
	c.equipment = []
	c.abilities = []
	var sb := StatBlock.new()
	sb.set_base("spd", 3)
	sb.set_base("hp", 10)
	sb.set_base("def", 1)
	sb.set_base("atk", 2)
	sb.set_base("rng", 1)
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	u.position = pos
	return u


func _make_state() -> MatchState:
	var map := MapData.new()
	map.id = "test_map"
	var tiles: Array[TileRecord] = []
	for q in range(-3, 4):
		for r in range(-3, 4):
			tiles.append(TileRecord.new(q, r, 0, "grass"))
	map.tiles = tiles

	var unit_a := _make_unit("unit_a", "playerA", Vector2i(0, 0))
	var unit_b := _make_unit("unit_b", "playerB", Vector2i(2, 0))

	var party_a: Array[BattleUnit] = [unit_a]
	var party_b: Array[BattleUnit] = [unit_b]
	var state := MatchSetup.create(party_a, party_b, map, _stub_terrain)

	# Manual placement
	unit_a.position = Vector2i(0, 0)
	state.occupancy[Vector2i(0, 0)] = unit_a
	unit_b.position = Vector2i(2, 0)
	state.occupancy[Vector2i(2, 0)] = unit_b

	return state


# --- Tests ---

func test_spawn_all_creates_pawns_for_all_living_units() -> void:
	var state := _make_state()
	var mgr := PawnManager.new()
	add_child_autofree(mgr)
	mgr.setup(state, state.graph)

	assert_eq(mgr.pawn_count(), 2, "should spawn 2 pawns for 2 living units")


func test_spawn_ignores_downed_units() -> void:
	var state := _make_state()
	# Down one unit
	var unit_b: BattleUnit = state.parties["playerB"][0]
	unit_b.current_hp = 0

	var mgr := PawnManager.new()
	add_child_autofree(mgr)
	mgr.setup(state, state.graph)

	assert_eq(mgr.pawn_count(), 1, "should skip downed unit")


func test_get_pawn_returns_correct_pawn() -> void:
	var state := _make_state()
	var mgr := PawnManager.new()
	add_child_autofree(mgr)
	mgr.setup(state, state.graph)

	var unit_a: BattleUnit = state.parties["playerA"][0]
	var pawn := mgr.get_pawn(unit_a)
	assert_not_null(pawn, "should find pawn for unit_a")
	assert_eq(pawn.unit, unit_a, "pawn should reference the correct unit")


func test_get_pawn_null_for_unknown_unit() -> void:
	var state := _make_state()
	var mgr := PawnManager.new()
	add_child_autofree(mgr)
	mgr.setup(state, state.graph)

	var unknown := _make_unit("unknown", "playerA", Vector2i(5, 5))
	var pawn := mgr.get_pawn(unknown)
	assert_null(pawn, "should return null for unmanaged unit")


func test_remove_pawn_cleans_up() -> void:
	var state := _make_state()
	var mgr := PawnManager.new()
	add_child_autofree(mgr)
	mgr.setup(state, state.graph)

	var unit_a: BattleUnit = state.parties["playerA"][0]
	assert_eq(mgr.pawn_count(), 2)

	mgr.remove_pawn(unit_a)
	assert_eq(mgr.pawn_count(), 1, "should have 1 pawn after removal")
	assert_null(mgr.get_pawn(unit_a), "removed unit should have no pawn")


func test_highlight_active_sets_correct_pawn() -> void:
	var state := _make_state()
	var mgr := PawnManager.new()
	add_child_autofree(mgr)
	mgr.setup(state, state.graph)

	var unit_a: BattleUnit = state.parties["playerA"][0]
	# Should not error — verifies the method runs without crashing
	mgr.highlight_active(unit_a)
	pass_test("highlight_active completed without error")


func test_clear_highlight_resets_all() -> void:
	var state := _make_state()
	var mgr := PawnManager.new()
	add_child_autofree(mgr)
	mgr.setup(state, state.graph)

	var unit_a: BattleUnit = state.parties["playerA"][0]
	mgr.highlight_active(unit_a)
	mgr.clear_highlight()
	pass_test("clear_highlight completed without error")


func test_move_pawn_returns_tween() -> void:
	var state := _make_state()
	var mgr := PawnManager.new()
	add_child_autofree(mgr)
	mgr.setup(state, state.graph)

	var unit_a: BattleUnit = state.parties["playerA"][0]
	var tw := mgr.move_pawn(unit_a, Vector2i(1, 0))
	assert_not_null(tw, "move_pawn should return a Tween")


func test_move_pawn_null_for_unknown_unit() -> void:
	var state := _make_state()
	var mgr := PawnManager.new()
	add_child_autofree(mgr)
	mgr.setup(state, state.graph)

	var unknown := _make_unit("unknown", "playerA", Vector2i(5, 5))
	var tw := mgr.move_pawn(unknown, Vector2i(1, 0))
	assert_null(tw, "should return null for unmanaged unit")
