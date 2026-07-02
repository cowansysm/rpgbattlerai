extends GutTest
## Tests for A19 AIScorer: flank/rear plans score higher when bonuses apply,
## and rear approach suppresses counter_risk penalty.


static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	return p


func _make_unit(id: String, team: String, atk: int = 5, def: int = 2,
		hp: int = 20, rng: int = 1, spd: int = 3) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = []
	c.abilities = []
	var sb := StatBlock.new()
	sb.set_base("atk", atk)
	sb.set_base("def", def)
	sb.set_base("hp", hp)
	sb.set_base("mag", 0)
	sb.set_base("res", 0)
	sb.set_base("spd", spd)
	sb.set_base("rng", rng)
	sb.set_base("jump", 2)
	sb.set_base("move", 3)
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	return u


func _make_state(units_a: Array, units_b: Array) -> MatchState:
	var map := MapData.new()
	map.id = "test"
	var tiles: Array[TileRecord] = []
	for coord in Hex.hexes_in_range(Vector2i(0, 0), 8):
		tiles.append(TileRecord.new(coord.x, coord.y, 0, "grass"))
	map.tiles = tiles
	var party_a: Array[BattleUnit] = []
	party_a.assign(units_a)
	var party_b: Array[BattleUnit] = []
	party_b.assign(units_b)
	var state := MatchSetup.create(party_a, party_b, map, _stub_terrain)
	return state


## Place units in state at given positions.
func _place(state: MatchState, units: Array, positions: Array) -> void:
	for i in range(units.size()):
		var u: BattleUnit = units[i]
		var pos: Vector2i = positions[i] as Vector2i
		u.position = pos
		state.occupancy[pos] = u


func _weights() -> Dictionary:
	return {
		"damage": 10.0, "kill": 25.0, "exposure": 3.0,
		"cover": 4.0, "elev": 2.0, "hazard": 8.0,
		"target": 8.0, "ability": 6.0, "resource": 2.0,
		"counter_risk": 5.0, "rear_exposure": 4.0
	}


# --- Flank plan scores higher than front ---

func test_rear_attack_plan_scores_higher_than_front() -> void:
	## Build two attack plans from different positions relative to the target.
	## Target faces dir 0 (+q direction). Plan from REAR position vs FRONT position.
	var attacker := _make_unit("a", "playerA")
	var target := _make_unit("b", "playerB")
	var state := _make_state([attacker], [target])

	# Target at origin, facing dir 0 (+q)
	target.position = Vector2i(0, 0)
	target.facing = 0  # faces +q direction
	state.occupancy[Vector2i(0, 0)] = target

	# FRONT approach: attacker comes from +q side (same as facing), position (-1,0)
	# attack on (0,0) from (-1,0) -> incoming dir = direction_toward((0,0),(-1,0)) = dir 3
	# diff vs facing 0 = 3 -> REAR... wait let's recalculate
	# Actually: target faces dir 0. Attacker at (2,0) attacks target at (0,0).
	# arc_between(attacker=(2,0), target=(0,0), target_facing=0):
	#   incoming = direction_toward((0,0),(2,0)) = dir 0; diff = (0-0)%6 = 0 -> FRONT
	# Attacker at (-2,0) attacks target at (0,0):
	#   incoming = direction_toward((0,0),(-2,0)) = dir 3; diff = (3-0)%6 = 3 -> REAR

	attacker.position = Vector2i(-2, 0)
	state.occupancy[Vector2i(-2, 0)] = attacker
	state.current_unit = attacker

	# REAR plan: attacker at (-2,0) attacks target at (0,0) — this is REAR since target faces dir 0
	var rear_plan := AIPlan.new()
	rear_plan.steps = [{"kind": "attack", "target_pos": Vector2i(0, 0)}]

	# FRONT plan: attacker would need to be at (2,0); simulate by placing at (2,0)
	state.occupancy.erase(Vector2i(-2, 0))
	attacker.position = Vector2i(2, 0)
	state.occupancy[Vector2i(2, 0)] = attacker

	var front_plan := AIPlan.new()
	front_plan.steps = [{"kind": "attack", "target_pos": Vector2i(0, 0)}]

	var front_score := AIScorer.score(state, attacker, front_plan, _weights())

	# Now move attacker to rear position
	state.occupancy.erase(Vector2i(2, 0))
	attacker.position = Vector2i(-2, 0)
	state.occupancy[Vector2i(-2, 0)] = attacker

	var rear_score := AIScorer.score(state, attacker, rear_plan, _weights())

	assert_true(rear_score > front_score,
		"REAR plan should score higher than FRONT plan (damage bonus %f > %f)" % [rear_score, front_score])


# --- Counter risk suppressed from REAR ---

func test_counter_risk_suppressed_from_rear() -> void:
	## Attacking a Counter unit from REAR should have zero counter_risk.
	var attacker := _make_unit("a", "playerA")
	var target := _make_unit("b", "playerB")
	target.character.reaction_passive = "counter"
	var state := _make_state([attacker], [target])

	# Target at origin facing dir 0; attacker at (-2,0) -> REAR
	target.position = Vector2i(0, 0)
	target.facing = 0
	state.occupancy[Vector2i(0, 0)] = target
	attacker.position = Vector2i(-2, 0)
	state.occupancy[Vector2i(-2, 0)] = attacker
	state.current_unit = attacker

	var rear_plan := AIPlan.new()
	rear_plan.steps = [{"kind": "attack", "target_pos": Vector2i(0, 0)}]

	# Score with heavy counter_risk weight to make the difference obvious
	var w := _weights()
	w["counter_risk"] = 100.0
	var rear_score := AIScorer.score(state, attacker, rear_plan, w)

	# FRONT attack would pay the counter_risk penalty
	state.occupancy.erase(Vector2i(-2, 0))
	attacker.position = Vector2i(2, 0)
	state.occupancy[Vector2i(2, 0)] = attacker
	var front_plan := AIPlan.new()
	front_plan.steps = [{"kind": "attack", "target_pos": Vector2i(0, 0)}]
	var front_score := AIScorer.score(state, attacker, front_plan, w)

	assert_true(rear_score > front_score,
		"REAR approach to Counter unit should score higher (counter suppressed) %f > %f" % [rear_score, front_score])
