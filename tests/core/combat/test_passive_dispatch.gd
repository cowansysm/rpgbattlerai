extends GutTest
## A18: Tests for PassiveDispatch — reaction passive trigger, counter chain guard,
## Auto-Potion, Defend Reflex, downed unit guard.

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


# --- Helpers ---

func _make_unit(id: String, hp: int = 20, atk: int = 3, def_val: int = 1,
		rng: int = 1, reaction: String = "") -> BattleUnit:
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
	return BattleUnit.from_character(c, sb)


func _make_passive_ability(id: String, pk: String, trig: Dictionary) -> AbilityData:
	var ab := AbilityData.new()
	ab.id = id
	ab.type = "passive"
	ab.passive_kind = pk
	ab.trigger = trig
	ab.modifier = {}
	return ab


static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	p.cover = 0
	p.damage_per_turn = 0
	p.damage_on_enter = 0
	return p


func _make_state(attacker: BattleUnit, defender: BattleUnit) -> MatchState:
	var map := MapData.new()
	map.id = "test"
	map.tiles = [TileRecord.new(0, 0, 0, "grass"), TileRecord.new(1, 0, 0, "grass")]
	map.deployment_zones = {}
	var units_a: Array[BattleUnit] = [attacker]
	var units_b: Array[BattleUnit] = [defender]
	var state := MatchSetup.create(units_a, units_b, map, _stub_terrain)
	attacker.team = "a"
	defender.team = "b"
	attacker.position = Vector2i(0, 0)
	defender.position = Vector2i(1, 0)
	state.occupancy[Vector2i(0, 0)] = attacker
	state.occupancy[Vector2i(1, 0)] = defender

	# Wire ability provider — returns abilities by id ignoring unit
	state.ability_provider = func(_unit: BattleUnit, ab_id: String) -> AbilityData:
		match ab_id:
			"counter":
				return _make_passive_ability("counter", "reaction",
					{"event": "on_hit", "melee_only": true})
			"auto_potion":
				return _make_passive_ability("auto_potion", "reaction",
					{"event": "on_damaged"})
			"defend_reflex":
				return _make_passive_ability("defend_reflex", "reaction",
					{"event": "on_low_hp", "hp_pct": 0.25})
		return null
	return state


# --- Counter tests ---

func test_counter_fires_on_on_hit() -> void:
	var attacker := _make_unit("attacker", 20, 3, 1, 1)
	var defender := _make_unit("defender", 20, 3, 1, 1, "counter")
	var state := _make_state(attacker, defender)

	var ctx := {
		"state": state,
		"attacker": attacker,
	}
	var results: Array = PassiveDispatch.fire(PassiveDispatch.ON_HIT, defender, ctx)

	assert_eq(results.size(), 1)
	assert_eq(str(results[0]["reaction"]), "counter")
	assert_eq(str(results[0]["actor"]), "defender")
	assert_eq(str(results[0]["target"]), "attacker")
	assert_true(results[0].has("damage"))


func test_counter_does_not_fire_for_ranged_attack() -> void:
	## melee_only guard: attacker rng > 1 should not trigger counter
	var attacker := _make_unit("attacker", 20, 3, 1, 3)  # rng=3 ranged
	var defender := _make_unit("defender", 20, 3, 1, 1, "counter")
	var state := _make_state(attacker, defender)

	var ctx := {"state": state, "attacker": attacker}
	var results: Array = PassiveDispatch.fire(PassiveDispatch.ON_HIT, defender, ctx)
	assert_eq(results.size(), 0)


func test_counter_fires_at_most_once_per_event() -> void:
	## reaction_locked guard prevents counter-of-counter
	var attacker := _make_unit("attacker", 20, 3, 1, 1, "counter")
	var defender := _make_unit("defender", 20, 3, 1, 1, "counter")
	var state := _make_state(attacker, defender)

	# Fire once for defender
	var ctx := {"state": state, "attacker": attacker}
	var r1: Array = PassiveDispatch.fire(PassiveDispatch.ON_HIT, defender, ctx)
	assert_eq(r1.size(), 1, "First counter fires")

	# If defender had been counter-hit, attacker's reaction_locked should prevent chain
	# Simulate: lock attacker manually (as if it already reacted)
	attacker.reaction_locked = true
	var ctx2 := {"state": state, "attacker": defender}
	var r2: Array = PassiveDispatch.fire(PassiveDispatch.ON_HIT, attacker, ctx2)
	assert_eq(r2.size(), 0, "Counter chain blocked by reaction_locked")
	attacker.reaction_locked = false


func test_counter_does_not_fire_when_subject_is_downed() -> void:
	var attacker := _make_unit("attacker", 20, 3, 1, 1)
	var defender := _make_unit("defender", 20, 3, 1, 1, "counter")
	defender.is_downed = true
	defender.current_hp = 0
	var state := _make_state(attacker, defender)

	var ctx := {"state": state, "attacker": attacker}
	var results: Array = PassiveDispatch.fire(PassiveDispatch.ON_HIT, defender, ctx)
	assert_eq(results.size(), 0)


# --- Auto-Potion tests ---

func test_auto_potion_heals_when_unit_has_potion_equipment() -> void:
	var attacker := _make_unit("attacker")
	var c := CharacterData.new()
	c.id = "defender"
	c.display_name = "defender"
	c.classes = []
	c.equipment = ["potion"]  # unit has potion in equipment list
	c.abilities = []
	c.reaction_passive = "auto_potion"
	c.support_passive = ""
	c.movement_passive = ""
	var sb := StatBlock.new()
	sb.set_base("hp", 20)
	sb.set_base("atk", 2)
	sb.set_base("def", 1)
	sb.set_base("rng", 1)
	sb.set_base("spd", 3)
	sb.set_base("wp", 0)
	sb.set_base("jump", 1)
	var defender := BattleUnit.from_character(c, sb)
	defender.current_hp = 10  # has taken some damage

	var state := _make_state(attacker, defender)

	var ctx := {"state": state, "attacker": attacker}
	var results: Array = PassiveDispatch.fire(PassiveDispatch.ON_DAMAGED, defender, ctx)

	assert_eq(results.size(), 1)
	assert_eq(str(results[0]["reaction"]), "auto_potion")
	assert_true(int(results[0]["healing"]) > 0)


func test_auto_potion_no_item_returns_no_item_record() -> void:
	var attacker := _make_unit("attacker")
	var defender := _make_unit("defender", 20, 3, 1, 1, "auto_potion")
	defender.current_hp = 10

	var state := _make_state(attacker, defender)

	var ctx := {"state": state, "attacker": attacker}
	var results: Array = PassiveDispatch.fire(PassiveDispatch.ON_DAMAGED, defender, ctx)

	# No potion -> no_item record
	assert_eq(results.size(), 1)
	assert_true(results[0].get("no_item", false))


# --- Defend Reflex tests ---

func test_defend_reflex_fires_at_low_hp() -> void:
	var attacker := _make_unit("attacker")
	var defender := _make_unit("defender", 20, 2, 1, 1, "defend_reflex")
	defender.current_hp = 4  # 4/20 = 20% <= 25% threshold

	var state := _make_state(attacker, defender)
	var ctx := {"state": state, "attacker": attacker}
	var results: Array = PassiveDispatch.fire(PassiveDispatch.ON_LOW_HP, defender, ctx)

	assert_eq(results.size(), 1)
	assert_eq(str(results[0]["reaction"]), "defend_reflex")
	assert_true(defender.stats.has_modifier_from_source("defend_reflex"))


func test_defend_reflex_does_not_fire_above_threshold() -> void:
	var attacker := _make_unit("attacker")
	var defender := _make_unit("defender", 20, 2, 1, 1, "defend_reflex")
	defender.current_hp = 10  # 10/20 = 50% > 25%

	var state := _make_state(attacker, defender)
	var ctx := {"state": state, "attacker": attacker}
	var results: Array = PassiveDispatch.fire(PassiveDispatch.ON_LOW_HP, defender, ctx)
	assert_eq(results.size(), 0)


func test_defend_reflex_does_not_un_down() -> void:
	## A17 compatibility: Auto-Potion and Defend Reflex must not fire when hp=0
	var attacker := _make_unit("attacker")
	var defender := _make_unit("defender", 20, 2, 1, 1, "defend_reflex")
	defender.current_hp = 0
	defender.is_downed = true

	var state := _make_state(attacker, defender)
	var ctx := {"state": state, "attacker": attacker}
	var results: Array = PassiveDispatch.fire(PassiveDispatch.ON_LOW_HP, defender, ctx)
	assert_eq(results.size(), 0)
	# downed state unchanged
	assert_true(defender.is_downed)
	assert_eq(defender.current_hp, 0)
