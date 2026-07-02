extends GutTest
## Tests for A18×A19 Counter reaction arc gate:
## Counter fires from FRONT/FLANK, blocked from REAR.


static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	return p


func _make_counter_unit(id: String, team: String) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = []
	c.abilities = ["counter"]
	c.reaction_passive = "counter"
	var sb := StatBlock.new()
	sb.set_base("spd", 3)
	sb.set_base("hp", 30)
	sb.set_base("def", 2)
	sb.set_base("atk", 4)
	sb.set_base("rng", 1)
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	return u


func _make_unit(id: String, team: String) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = []
	c.abilities = []
	var sb := StatBlock.new()
	sb.set_base("spd", 3)
	sb.set_base("hp", 30)
	sb.set_base("def", 2)
	sb.set_base("atk", 4)
	sb.set_base("rng", 1)
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	return u


func _make_state(attacker: BattleUnit, defender: BattleUnit,
		atk_pos: Vector2i, def_pos: Vector2i) -> MatchState:
	var map := MapData.new()
	map.id = "test"
	var tiles: Array[TileRecord] = []
	for coord in Hex.hexes_in_range(Vector2i(0, 0), 6):
		tiles.append(TileRecord.new(coord.x, coord.y, 0, "grass"))
	map.tiles = tiles
	var party_a: Array[BattleUnit] = [attacker]
	var party_b: Array[BattleUnit] = [defender]
	var state := MatchSetup.create(party_a, party_b, map, _stub_terrain)
	attacker.position = atk_pos
	state.occupancy[atk_pos] = attacker
	defender.position = def_pos
	state.occupancy[def_pos] = defender

	# Provide ability_provider that returns Counter ability
	var counter_ab := AbilityData.new()
	counter_ab.id = "counter"
	counter_ab.type = "passive"
	counter_ab.passive_kind = "reaction"
	counter_ab.trigger = {"event": "on_hit", "melee_only": true}
	counter_ab.ap_cost = 0
	counter_ab.wp_cost = 0
	counter_ab.mag_scaling = 0.0
	counter_ab.area = {}
	counter_ab.effect = {}
	state.ability_provider = func(_u: BattleUnit, ab_id: String) -> AbilityData:
		if ab_id == "counter":
			return counter_ab
		return null
	return state


func _fire_counter_with_arc(attacker: BattleUnit, subject: BattleUnit,
		state: MatchState, arc: int) -> Array:
	var ctx := {
		"state": state,
		"attacker": attacker,
		"arc": arc,
	}
	return PassiveDispatch.fire(PassiveDispatch.ON_HIT, subject, ctx)


# --- Counter fires from FRONT ---

func test_counter_fires_from_front() -> void:
	var attacker := _make_unit("a", "playerA")
	var defender := _make_counter_unit("b", "playerB")
	var state := _make_state(attacker, defender, Vector2i(0, 0), Vector2i(1, 0))
	defender.facing = 0  # faces dir 0

	var saved_dice: Callable = CombatResolver.dice_roller
	var saved_crit: Callable = CombatResolver.crit_roller
	CombatResolver.dice_roller = func() -> int: return 3
	CombatResolver.crit_roller = func() -> float: return 0.99

	var reactions := _fire_counter_with_arc(attacker, defender, state, Hex.Arc.FRONT)

	CombatResolver.dice_roller = saved_dice
	CombatResolver.crit_roller = saved_crit

	assert_true(reactions.size() > 0, "Counter should fire from FRONT")
	assert_eq(str(reactions[0].get("reaction", "")), "counter")


# --- Counter fires from FLANK ---

func test_counter_fires_from_flank() -> void:
	var attacker := _make_unit("a", "playerA")
	var defender := _make_counter_unit("b", "playerB")
	var state := _make_state(attacker, defender, Vector2i(0, 0), Vector2i(1, 0))
	defender.facing = 0

	var saved_dice: Callable = CombatResolver.dice_roller
	var saved_crit: Callable = CombatResolver.crit_roller
	CombatResolver.dice_roller = func() -> int: return 3
	CombatResolver.crit_roller = func() -> float: return 0.99

	var reactions := _fire_counter_with_arc(attacker, defender, state, Hex.Arc.FLANK)

	CombatResolver.dice_roller = saved_dice
	CombatResolver.crit_roller = saved_crit

	assert_true(reactions.size() > 0, "Counter should fire from FLANK")


# --- Counter blocked from REAR ---

func test_counter_blocked_from_rear() -> void:
	var attacker := _make_unit("a", "playerA")
	var defender := _make_counter_unit("b", "playerB")
	var state := _make_state(attacker, defender, Vector2i(0, 0), Vector2i(1, 0))
	defender.facing = 0

	var saved_dice: Callable = CombatResolver.dice_roller
	var saved_crit: Callable = CombatResolver.crit_roller
	CombatResolver.dice_roller = func() -> int: return 3
	CombatResolver.crit_roller = func() -> float: return 0.99

	var reactions := _fire_counter_with_arc(attacker, defender, state, Hex.Arc.REAR)

	CombatResolver.dice_roller = saved_dice
	CombatResolver.crit_roller = saved_crit

	assert_true(reactions.is_empty(), "Counter should NOT fire from REAR")
