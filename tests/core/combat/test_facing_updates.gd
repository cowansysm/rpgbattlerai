extends GutTest
## Tests for A19 facing state updates in TurnActions:
## - execute_move faces the final step direction
## - execute_attack faces the attacker toward target; no-move default
## - Self-target (range 0 ability) does not change facing


static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	return p


func _make_unit(id: String, team: String, rng: int = 1) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = []
	c.abilities = []
	var sb := StatBlock.new()
	sb.set_base("spd", 3)
	sb.set_base("hp", 20)
	sb.set_base("def", 1)
	sb.set_base("atk", 3)
	sb.set_base("rng", rng)
	sb.set_base("jump", 2)
	sb.set_base("move", 3)
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	return u


func _make_state(positions_a: Array, positions_b: Array) -> MatchState:
	var map := MapData.new()
	map.id = "test"
	var tiles: Array[TileRecord] = []
	for coord in Hex.hexes_in_range(Vector2i(0, 0), 6):
		tiles.append(TileRecord.new(coord.x, coord.y, 0, "grass"))
	map.tiles = tiles

	var party_a: Array[BattleUnit] = []
	var party_b: Array[BattleUnit] = []
	for i in range(positions_a.size()):
		var u: BattleUnit = _make_unit("a%d" % i, "playerA")
		party_a.append(u)
	for i in range(positions_b.size()):
		var u: BattleUnit = _make_unit("b%d" % i, "playerB")
		party_b.append(u)

	var state := MatchSetup.create(party_a, party_b, map, _stub_terrain)
	for i in range(positions_a.size()):
		var pos: Vector2i = positions_a[i] as Vector2i
		state.parties["playerA"][i].position = pos
		state.occupancy[pos] = state.parties["playerA"][i]
	for i in range(positions_b.size()):
		var pos: Vector2i = positions_b[i] as Vector2i
		state.parties["playerB"][i].position = pos
		state.occupancy[pos] = state.parties["playerB"][i]
	return state


# --- execute_move facing update ---

func test_move_updates_facing_toward_final_step() -> void:
	var state := _make_state([Vector2i(0, 0)], [Vector2i(5, 0)])
	var unit: BattleUnit = state.parties["playerA"][0]
	state.current_unit = unit
	unit.ap_remaining = 2
	unit.facing = 3  # Start facing away

	# Move to (2,0): path is (0,0)->(1,0)->(2,0); last step dir = direction_toward((1,0),(2,0))
	var expected_dir: int = Hex.direction_toward(Vector2i(1, 0), Vector2i(2, 0))
	var record := TurnActions.execute_move(state, Vector2i(2, 0))

	assert_false(record.has("error"), "Move should succeed")
	assert_eq(unit.facing, expected_dir, "Facing should point toward final step")
	assert_true(record.has("facing"), "Record should include facing")


func test_move_single_step_updates_facing() -> void:
	var state := _make_state([Vector2i(0, 0)], [Vector2i(5, 0)])
	var unit: BattleUnit = state.parties["playerA"][0]
	state.current_unit = unit
	unit.ap_remaining = 2

	# Single step to (1,0)
	var expected_dir: int = Hex.direction_toward(Vector2i(0, 0), Vector2i(1, 0))
	TurnActions.execute_move(state, Vector2i(1, 0))

	assert_eq(unit.facing, expected_dir, "Single step facing should use direction from origin")


# --- execute_attack facing update ---

func test_attack_faces_attacker_toward_target() -> void:
	var state := _make_state([Vector2i(0, 0)], [Vector2i(1, 0)])
	var attacker: BattleUnit = state.parties["playerA"][0]
	var target: BattleUnit = state.parties["playerB"][0]
	state.current_unit = attacker
	attacker.ap_remaining = 2
	attacker.facing = 3  # Start facing away from target

	var saved_dice: Callable = CombatResolver.dice_roller
	var saved_crit: Callable = CombatResolver.crit_roller
	CombatResolver.dice_roller = func() -> int: return 3
	CombatResolver.crit_roller = func() -> float: return 0.99

	TurnActions.execute_attack(state, Vector2i(1, 0))

	CombatResolver.dice_roller = saved_dice
	CombatResolver.crit_roller = saved_crit

	var expected_dir: int = Hex.direction_toward(Vector2i(0, 0), Vector2i(1, 0))
	assert_eq(attacker.facing, expected_dir, "Attacker should face toward target after attack")


func test_attack_record_includes_arc() -> void:
	var state := _make_state([Vector2i(0, 0)], [Vector2i(1, 0)])
	var attacker: BattleUnit = state.parties["playerA"][0]
	var target: BattleUnit = state.parties["playerB"][0]
	state.current_unit = attacker
	attacker.ap_remaining = 2
	target.facing = 3  # facing away -> attacker coming from FRONT

	var saved_dice: Callable = CombatResolver.dice_roller
	var saved_crit: Callable = CombatResolver.crit_roller
	CombatResolver.dice_roller = func() -> int: return 3
	CombatResolver.crit_roller = func() -> float: return 0.99

	var record := TurnActions.execute_attack(state, Vector2i(1, 0))

	CombatResolver.dice_roller = saved_dice
	CombatResolver.crit_roller = saved_crit

	assert_false(record.has("error"), "Attack should succeed")
	assert_true(record.has("arc"), "Record should include arc")


# --- Facing preserved when targets self ---

func test_self_target_ability_does_not_change_facing() -> void:
	## A self-targeted ability (range 0) should not change the caster's facing.
	var state := _make_state([Vector2i(0, 0)], [Vector2i(5, 0)])
	var unit: BattleUnit = state.parties["playerA"][0]
	state.current_unit = unit
	unit.ap_remaining = 2
	unit.facing = 2  # some initial facing

	# Build a self-heal ability
	var ab := AbilityData.new()
	ab.id = "self_heal"
	ab.ability_range = 0  # self-target
	ab.ap_cost = 1
	ab.wp_cost = 0
	ab.type = "spell"
	ab.mag_scaling = 0.0
	ab.area = {}
	ab.effect = {"effect_type": "heal", "value": 5}
	state.ability_provider = func(u: BattleUnit, ab_id: String) -> AbilityData:
		if ab_id == "self_heal":
			return ab
		return null

	TurnActions.execute_ability(state, "self_heal", unit.position)

	assert_eq(unit.facing, 2, "Self-targeted ability should not change facing")
