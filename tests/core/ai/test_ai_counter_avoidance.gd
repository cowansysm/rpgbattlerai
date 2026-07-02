extends GutTest
## A18: AIScorer penalises meleeing a target with Counter equipped.


func _make_unit(id: String, team: String, hp: int = 20, atk: int = 3,
		def_val: int = 1, rng: int = 1, reaction: String = "") -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = []
	c.abilities = []
	c.reaction_passive = reaction
	c.support_passive = ""
	c.movement_passive = ""
	var sb := StatBlock.new()
	sb.set_base("hp", hp)
	sb.set_base("atk", atk)
	sb.set_base("def", def_val)
	sb.set_base("rng", rng)
	sb.set_base("spd", 3)
	sb.set_base("wp", 0)
	sb.set_base("jump", 1)
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	return u


func _make_map() -> MapData:
	var map := MapData.new()
	map.id = "t"
	map.tiles = [
		TileRecord.new(0, 0, 0, "grass"),
		TileRecord.new(1, 0, 0, "grass"),
		TileRecord.new(2, 0, 0, "grass"),
	]
	map.deployment_zones = {}
	return map


static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	p.cover = 0
	p.damage_per_turn = 0
	p.damage_on_enter = 0
	return p


func _make_state(attacker: BattleUnit, target: BattleUnit) -> MatchState:
	var units_a: Array[BattleUnit] = [attacker]
	var units_b: Array[BattleUnit] = [target]
	var state := MatchSetup.create(units_a, units_b, _make_map(), _stub_terrain)
	attacker.position = Vector2i(0, 0)
	target.position = Vector2i(1, 0)
	state.occupancy[attacker.position] = attacker
	state.occupancy[target.position] = target
	# A19: set facings so approach is FRONT (target faces toward attacker)
	attacker.set_facing(Hex.direction_toward(Vector2i(0, 0), Vector2i(1, 0)))
	target.set_facing(Hex.direction_toward(Vector2i(1, 0), Vector2i(0, 0)))
	return state


func _make_weights() -> Dictionary:
	return {
		"damage": 10.0,
		"kill": 25.0,
		"exposure": 3.0,
		"cover": 4.0,
		"elev": 2.0,
		"hazard": 8.0,
		"target": 8.0,
		"ability": 6.0,
		"resource": 2.0,
		"counter_risk": 5.0,
	}


func _make_attack_plan(_pos: Vector2i, target_pos: Vector2i) -> AIPlan:
	return AIPlan.make_attack_only(target_pos)


func test_melee_vs_counter_target_scores_lower() -> void:
	var attacker := _make_unit("attacker", "a", 20, 3, 1, 1)
	var counter_target := _make_unit("counter_enemy", "b", 20, 3, 1, 1, "counter")
	var normal_target := _make_unit("normal_enemy", "b", 20, 3, 1, 1)

	var state_counter := _make_state(attacker, counter_target)
	var state_normal := _make_state(attacker, normal_target)

	var plan_vs_counter := _make_attack_plan(Vector2i(0, 0), Vector2i(1, 0))
	var plan_vs_normal := _make_attack_plan(Vector2i(0, 0), Vector2i(1, 0))
	var w := _make_weights()

	var score_counter: float = AIScorer.score(state_counter, attacker, plan_vs_counter, w)
	var score_normal: float = AIScorer.score(state_normal, attacker, plan_vs_normal, w)

	assert_true(score_normal > score_counter,
		"Meleeing a Counter target should score lower than meleeing a non-Counter target")


func test_ranged_vs_counter_no_penalty() -> void:
	## Ranged attackers (rng > 1) don't trigger Counter, so no penalty.
	var attacker := _make_unit("ranged_attacker", "a", 20, 3, 1, 3)  # rng=3
	var counter_target := _make_unit("counter_enemy", "b", 20, 3, 1, 1, "counter")

	var state := _make_state(attacker, counter_target)
	var plan := _make_attack_plan(Vector2i(0, 0), Vector2i(1, 0))
	plan.steps[0]["kind"] = "attack"

	# Ranged attack should not be penalised
	var w := _make_weights()
	var score_ranged: float = AIScorer.score(state, attacker, plan, w)

	# Also check melee version of same attacker
	var melee_attacker := _make_unit("melee_attacker", "a", 20, 3, 1, 1)
	var state2 := _make_state(melee_attacker, counter_target)
	var score_melee: float = AIScorer.score(state2, melee_attacker, plan, w)

	assert_true(score_ranged > score_melee,
		"Ranged attack vs Counter should score higher than melee vs Counter")


func test_no_counter_target_no_penalty() -> void:
	## When target has no reaction passive, counter_risk factor is 0.
	var attacker := _make_unit("attacker", "a")
	var target := _make_unit("target", "b")  # no reaction passive

	var state := _make_state(attacker, target)
	var plan := _make_attack_plan(Vector2i(0, 0), Vector2i(1, 0))
	var w := _make_weights()
	var w_no_counter_risk := w.duplicate()
	w_no_counter_risk["counter_risk"] = 0.0

	var score_with_weight: float = AIScorer.score(state, attacker, plan, w)
	var score_no_weight: float = AIScorer.score(state, attacker, plan, w_no_counter_risk)

	assert_eq(score_with_weight, score_no_weight,
		"No counter target: counter_risk weight makes no difference")
