extends GutTest
## A18: Baseline test — empty passive slots + fixed dice produce identical outcomes
## to pre-A18 results. Verifies the ctx={} default path is inert.

var _default_roller: Callable
var _default_crit_roller: Callable


func before_each() -> void:
	_default_roller = CombatResolver.dice_roller
	_default_crit_roller = CombatResolver.crit_roller
	CombatResolver.dice_roller = func() -> int: return 3
	CombatResolver.crit_roller = func() -> float: return 1.0  # never crits


func after_each() -> void:
	CombatResolver.dice_roller = _default_roller
	CombatResolver.crit_roller = _default_crit_roller


func _make_unit(id: String, hp: int = 10, atk: int = 2, def_val: int = 1,
		rng: int = 1) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = []
	c.abilities = []
	c.reaction_passive = ""
	c.support_passive = ""
	c.movement_passive = ""
	var sb := StatBlock.new()
	sb.set_base("spd", 3)
	sb.set_base("hp", hp)
	sb.set_base("atk", atk)
	sb.set_base("def", def_val)
	sb.set_base("rng", rng)
	sb.set_base("wp", 0)
	sb.set_base("jump", 1)
	return BattleUnit.from_character(c, sb)


func test_resolve_attack_no_passive_ctx_empty_matches_pre_a18() -> void:
	## With ctx={}, resolve_attack should not fire any passives.
	## damage = max(1, die(3) + atk(2) + power(3) + 0 - def(1)) = 7
	var attacker := _make_unit("a", 10, 2, 1)
	var target := _make_unit("b", 10, 2, 1)

	var result := CombatResolver.resolve_attack(
		attacker, target, 3, 0, 0, 0, false, 1, 1)

	assert_eq(result["damage"], 7)
	assert_eq(target.current_hp, 3)
	assert_false(result.has("reactions"), "No passive reactions should fire with ctx={}")


func test_resolve_damage_no_passive_ctx_empty_is_inert() -> void:
	## With ctx={}, resolve_damage should not fire any passives.
	## spell: die(3) + value(5) + mag_bonus(0) - res(0) = 8
	var caster := _make_unit("c", 10, 0, 0)
	var target := _make_unit("t", 20, 0, 0)

	var result := CombatResolver.resolve_damage(
		caster, target, 5, "spell", 0, 0, -1, 0.0)

	assert_eq(result["damage"], 8)
	assert_false(result.has("reactions"), "No reactions with empty ctx")


func test_resolve_attack_with_state_ctx_but_no_passive_still_correct_damage() -> void:
	## With ctx containing state, but target has NO reaction slot, no reaction fires.
	var attacker := _make_unit("a", 10, 2, 1)
	var target := _make_unit("b", 10, 2, 1)
	target.team = "b"
	attacker.team = "a"
	attacker.position = Vector2i(0, 0)
	target.position = Vector2i(1, 0)

	var map := MapData.new()
	map.id = "t"
	map.tiles = [TileRecord.new(0, 0, 0, "grass"), TileRecord.new(1, 0, 0, "grass")]
	map.deployment_zones = {}
	var tp := func(_id: String) -> TerrainProps: return null
	var units_a: Array[BattleUnit] = [attacker]
	var units_b: Array[BattleUnit] = [target]
	var state := MatchSetup.create(units_a, units_b, map, tp)
	state.occupancy[Vector2i(0, 0)] = attacker
	state.occupancy[Vector2i(1, 0)] = target

	var ctx := {"state": state}
	var result := CombatResolver.resolve_attack(
		attacker, target, 3, 0, 0, 0, false, 1, 1, ctx)

	assert_eq(result["damage"], 7)
	# No reaction slot -> no reactions array
	assert_false(result.has("reactions"), "No reactions with no passive equipped")


func test_from_character_no_provider_no_passive_modifiers() -> void:
	## from_character without ability_provider should not modify stats.
	var c := CharacterData.new()
	c.id = "test"
	c.display_name = "test"
	c.classes = []
	c.equipment = []
	c.abilities = []
	c.reaction_passive = ""
	c.support_passive = ""
	c.movement_passive = ""
	var sb := StatBlock.new()
	sb.set_base("hp", 15)
	sb.set_base("atk", 3)
	sb.set_base("def", 2)
	sb.set_base("mag", 4)
	sb.set_base("rng", 1)
	sb.set_base("spd", 3)
	sb.set_base("wp", 5)
	sb.set_base("jump", 1)

	var unit := BattleUnit.from_character(c, sb)
	assert_eq(unit.stats.effective("mag"), 4, "No passive applied, MAG unchanged")
	assert_eq(unit.stats.effective("atk"), 3)
	assert_eq(unit.wp_cost_mult, 1.0)
	assert_false(unit.ignores_hazards)
	assert_false(unit.reaction_locked)
