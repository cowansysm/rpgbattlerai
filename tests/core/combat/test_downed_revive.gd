extends GutTest
## Tests for the knockout & revive lifecycle (A17):
## downed state machine, is_active/is_living predicates, queue exclusion,
## revive legality + HP fraction, CT requeue, victory detection, permadeath.

var _default_roller: Callable


func before_each() -> void:
	_default_roller = CombatResolver.dice_roller
	CombatResolver.dice_roller = func() -> int: return 3


func after_each() -> void:
	CombatResolver.dice_roller = _default_roller


# --- Stub terrain provider ---

static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	return p


# --- Helpers ---

func _make_unit(id: String, spd: int = 3, hp: int = 10,
		atk: int = 2, def_val: int = 1, rng: int = 1, wp: int = 10) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = ["sword"]
	c.abilities = ["fire_1"]
	var sb := StatBlock.new()
	sb.set_base("spd", spd)
	sb.set_base("hp", hp)
	sb.set_base("atk", atk)
	sb.set_base("def", def_val)
	sb.set_base("rng", rng)
	sb.set_base("wp", wp)
	return BattleUnit.from_character(c, sb)


func _make_ability(id: String, ap: int, rng: int, etype: String,
		atype: String = "spell", effect: Dictionary = {},
		area: Dictionary = {}) -> AbilityData:
	var a := AbilityData.new()
	a.id = id
	a.display_name = id
	a.type = atype
	a.ap_cost = ap
	a.ability_range = rng
	a.effect = effect
	a.area = area
	return a


func _make_item(id: String, slot: String, wp: int = 0,
		granted: Array[String] = []) -> ItemData:
	var item := ItemData.new()
	item.id = id
	item.slot = slot
	item.weapon_power = wp
	item.granted_abilities = granted
	return item


func _setup_match() -> MatchState:
	var map := MapData.new()
	map.id = "test"
	var tiles: Array[TileRecord] = []
	for c in Hex.hexes_in_range(Vector2i(0, 0), 5):
		tiles.append(TileRecord.new(c.x, c.y, 0, "grass"))
	map.tiles = tiles

	var a0 := _make_unit("a0", 4, 16, 3, 3, 1)   # Fighter
	var a1 := _make_unit("a1", 3, 10, 2, 1, 3)    # Healer (range 3 for revive)
	var b0 := _make_unit("b0", 3, 12, 5, 0, 1)    # Strong attacker
	var b1 := _make_unit("b1", 2, 13, 0, 0, 1)    # Support

	var party_a: Array[BattleUnit] = [a0, a1]
	var party_b: Array[BattleUnit] = [b0, b1]

	var state := MatchSetup.create(party_a, party_b, map, _stub_terrain)

	# Manual deploy
	a0.position = Vector2i(-1, 0)
	state.occupancy[Vector2i(-1, 0)] = a0
	a1.position = Vector2i(-2, 0)
	state.occupancy[Vector2i(-2, 0)] = a1
	b0.position = Vector2i(1, 0)
	state.occupancy[Vector2i(1, 0)] = b0
	b1.position = Vector2i(2, 0)
	state.occupancy[Vector2i(2, 0)] = b1

	state.phase = MatchState.Phase.ROUND_START

	# Wire providers
	var sword := _make_item("sword", "weapon", 3)
	var items := { "sword": sword }
	state.item_provider = func(id: String) -> ItemData: return items.get(id, null)

	var fire_1 := _make_ability("fire_1", 1, 3, "damage", "spell",
		{ "effect_type": "damage", "value": 20 })  # High damage to guarantee downing
	var cure_1 := _make_ability("cure_1", 1, 3, "heal", "spell",
		{ "effect_type": "heal", "value": 4 })
	var revive_1 := _make_ability("revive_1", 1, 3, "revive", "spell",
		{ "effect_type": "revive", "value": 5 })
	var aoe_revive := _make_ability("aoe_revive", 1, 3, "revive", "spell",
		{ "effect_type": "revive", "value": 4 },
		{ "shape": "burst", "radius": 1 })
	var aoe_damage := _make_ability("aoe_damage", 1, 3, "damage", "spell",
		{ "effect_type": "damage", "value": 20 },
		{ "shape": "burst", "radius": 1 })
	var buff_1 := _make_ability("buff_1", 1, 3, "buff", "spell",
		{ "effect_type": "buff", "stat": "def", "value": 2, "duration": 3 })
	var lullaby := _make_ability("lullaby", 1, 3, "status", "skill",
		{ "effect_type": "status", "status_id": "sleep", "duration": 2 })

	var abilities := {
		"fire_1": fire_1, "cure_1": cure_1, "revive_1": revive_1,
		"aoe_revive": aoe_revive, "aoe_damage": aoe_damage,
		"buff_1": buff_1, "lullaby": lullaby,
	}
	state.ability_provider = func(_unit: BattleUnit, aid: String) -> AbilityData:
		return abilities.get(aid, null)

	return state


func _activate_unit(state: MatchState, unit: BattleUnit) -> void:
	var err := RoundManager.activate_unit(state, unit)
	assert_eq(err, "", "activation should succeed: %s" % err)


func _skip_all_activations(state: MatchState) -> void:
	while not RoundManager.is_round_over(state):
		var team := RoundManager.current_team(state)
		var available := state.activatable_units(team)
		if available.is_empty():
			state.current_index += 1
			continue
		_activate_unit(state, available[0])
		TurnActions.execute_wait(state)
		RoundManager.end_activation(state)


# ===================================================================
# Predicates (A17)
# ===================================================================

func test_new_unit_not_downed() -> void:
	var unit := _make_unit("test")
	assert_false(unit.is_downed)
	assert_eq(unit.downed_round, -1)


func test_is_active_true_for_healthy_unit() -> void:
	var unit := _make_unit("test")
	assert_true(unit.is_active())
	assert_true(unit.is_alive())  # alias


func test_is_active_false_for_downed_unit() -> void:
	var unit := _make_unit("test")
	unit.current_hp = 0
	unit.is_downed = true
	assert_false(unit.is_active())
	assert_false(unit.is_alive())


func test_is_living_true_for_active_unit() -> void:
	var unit := _make_unit("test")
	assert_true(unit.is_living())


func test_is_living_true_for_downed_unit() -> void:
	var unit := _make_unit("test")
	unit.current_hp = 0
	unit.is_downed = true
	assert_true(unit.is_living(), "downed unit is still living (on board)")


func test_is_living_false_for_dead_unit() -> void:
	var unit := _make_unit("test")
	unit.current_hp = 0
	unit.is_downed = false
	assert_false(unit.is_living(), "hp=0 and not downed = permanently dead")


# ===================================================================
# Downing Mechanics
# ===================================================================

func test_attack_sets_downed_state() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Set b0 to low HP so attack will down it
	state.parties["playerB"][0].current_hp = 1

	var unit: BattleUnit = state.unactivated_units(
		RoundManager.current_team(state))[0]
	_activate_unit(state, unit)
	TurnActions.execute_move(state, Vector2i(0, 0))

	var result := TurnActions.execute_attack(state, Vector2i(1, 0))
	assert_true(result["is_downed"])
	assert_true(state.parties["playerB"][0].is_downed)
	assert_eq(state.parties["playerB"][0].downed_round, 1)


func test_downed_unit_stays_in_occupancy() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	state.parties["playerB"][0].current_hp = 1

	var unit: BattleUnit = state.unactivated_units(
		RoundManager.current_team(state))[0]
	_activate_unit(state, unit)
	TurnActions.execute_move(state, Vector2i(0, 0))
	TurnActions.execute_attack(state, Vector2i(1, 0))

	# Downed unit still in occupancy (blocks hex)
	assert_true(state.is_occupied(Vector2i(1, 0)))
	assert_not_null(state.unit_at(Vector2i(1, 0)))


func test_downed_unit_blocks_hex() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Down b0
	state.parties["playerB"][0].current_hp = 1
	var unit: BattleUnit = state.unactivated_units(
		RoundManager.current_team(state))[0]
	_activate_unit(state, unit)
	TurnActions.execute_move(state, Vector2i(0, 0))
	TurnActions.execute_attack(state, Vector2i(1, 0))
	RoundManager.end_activation(state)

	# Try to move another unit onto the downed unit's hex
	var team := RoundManager.current_team(state)
	var available := state.unactivated_units(team)
	if not available.is_empty():
		_activate_unit(state, available[0])
		var move_result := TurnActions.execute_move(state, Vector2i(1, 0))
		assert_true(move_result.has("error"), "should not be able to move onto downed hex")


func test_cannot_attack_downed_unit() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Manually down b0
	var b0: BattleUnit = state.parties["playerB"][0]
	b0.current_hp = 0
	b0.is_downed = true
	b0.downed_round = 1

	var unit: BattleUnit = state.unactivated_units(
		RoundManager.current_team(state))[0]
	_activate_unit(state, unit)
	TurnActions.execute_move(state, Vector2i(0, 0))

	var result := TurnActions.execute_attack(state, Vector2i(1, 0))
	assert_true(result.has("error"))
	assert_string_contains(result["error"], "downed")


func test_downed_unit_excluded_from_living() -> void:
	var state := _setup_match()
	var b0: BattleUnit = state.parties["playerB"][0]
	b0.current_hp = 0
	b0.is_downed = true
	assert_eq(state.living_units("playerB").size(), 1)


func test_downed_unit_in_downed_units() -> void:
	var state := _setup_match()
	var b0: BattleUnit = state.parties["playerB"][0]
	b0.current_hp = 0
	b0.is_downed = true
	assert_eq(state.downed_units("playerB").size(), 1)
	assert_eq(state.all_downed_units().size(), 1)


# ===================================================================
# Queue Exclusion (A17)
# ===================================================================

func test_downed_unit_excluded_from_activation_queue() -> void:
	var state := _setup_match()
	var b0: BattleUnit = state.parties["playerB"][0]
	b0.current_hp = 0
	b0.is_downed = true
	RoundManager.start_round(state)
	# 3 active units in queue (b0 excluded)
	assert_eq(state.activation_queue.size(), 3)


func test_downed_unit_stays_on_board_after_round() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Down b0 in round 1
	var b0: BattleUnit = state.parties["playerB"][0]
	b0.current_hp = 0
	b0.is_downed = true
	b0.downed_round = 1

	# Complete all activations — b0 never gets a turn (excluded from queue)
	_skip_all_activations(state)

	# b0 stays downed on the board
	assert_true(b0.is_downed, "downed unit stays downed")
	assert_eq(b0.current_hp, 0)
	assert_true(state.is_occupied(Vector2i(1, 0)), "downed unit stays on hex")


func test_downed_unit_cannot_be_activated() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Down a playerA unit so the team-order check passes (it's playerA's turn)
	var a0: BattleUnit = state.parties["playerA"][0]
	a0.current_hp = 0
	a0.is_downed = true
	a0.downed_round = 1

	var err := RoundManager.activate_unit(state, a0)
	assert_string_contains(err, "downed")


# ===================================================================
# Victory Detection (A17)
# ===================================================================

func test_all_downed_team_loses() -> void:
	var state := _setup_match()
	# Down all of playerB
	for u: BattleUnit in state.parties["playerB"]:
		u.current_hp = 0
		u.is_downed = true
	var winner := state.check_winner()
	assert_eq(winner, "playerA", "team with all units downed should lose")


func test_mix_downed_and_active_no_winner() -> void:
	var state := _setup_match()
	# Down one of playerB, keep other alive
	state.parties["playerB"][0].current_hp = 0
	state.parties["playerB"][0].is_downed = true
	var winner := state.check_winner()
	assert_eq(winner, "", "team with some active units should not lose")


# ===================================================================
# Heal Does Not Revive
# ===================================================================

func test_heal_skips_downed_unit() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Down b0 manually
	var b0: BattleUnit = state.parties["playerB"][0]
	b0.current_hp = 0
	b0.is_downed = true
	b0.downed_round = 1

	# Skip to a1's turn (healer)
	var t := RoundManager.current_team(state)
	var u: BattleUnit = state.unactivated_units(t)[0]
	_activate_unit(state, u)
	TurnActions.execute_wait(state)
	RoundManager.end_activation(state)

	t = RoundManager.current_team(state)
	u = state.unactivated_units(t)[0]
	_activate_unit(state, u)
	TurnActions.execute_wait(state)
	RoundManager.end_activation(state)

	# a1's turn
	t = RoundManager.current_team(state)
	u = state.unactivated_units(t)[0]
	assert_eq(u.character.id, "a1")
	_activate_unit(state, u)

	# Try to heal downed b0
	var result := TurnActions.execute_ability(state, "cure_1", Vector2i(1, 0))
	assert_false(result.has("error"), "ability should execute: %s" % str(result))
	var outcomes: Array = result["outcomes"]
	assert_eq(outcomes.size(), 1)
	assert_true(outcomes[0].get("skipped", false))
	assert_eq(outcomes[0].get("reason", ""), "downed")
	# b0 should still be downed
	assert_true(b0.is_downed)
	assert_eq(b0.current_hp, 0)


func test_buff_skips_downed_unit() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	var b0: BattleUnit = state.parties["playerB"][0]
	b0.current_hp = 0
	b0.is_downed = true
	b0.downed_round = 1

	# Skip to a1 and try buff on downed b0
	var t := RoundManager.current_team(state)
	_activate_unit(state, state.unactivated_units(t)[0])
	TurnActions.execute_wait(state)
	RoundManager.end_activation(state)

	t = RoundManager.current_team(state)
	_activate_unit(state, state.unactivated_units(t)[0])
	TurnActions.execute_wait(state)
	RoundManager.end_activation(state)

	t = RoundManager.current_team(state)
	var u: BattleUnit = state.unactivated_units(t)[0]
	_activate_unit(state, u)

	var result := TurnActions.execute_ability(state, "buff_1", Vector2i(1, 0))
	var outcomes: Array = result["outcomes"]
	assert_true(outcomes[0].get("skipped", false))


func test_status_skips_downed_unit() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	var b0: BattleUnit = state.parties["playerB"][0]
	b0.current_hp = 0
	b0.is_downed = true
	b0.downed_round = 1

	var t := RoundManager.current_team(state)
	_activate_unit(state, state.unactivated_units(t)[0])
	TurnActions.execute_wait(state)
	RoundManager.end_activation(state)

	t = RoundManager.current_team(state)
	_activate_unit(state, state.unactivated_units(t)[0])
	TurnActions.execute_wait(state)
	RoundManager.end_activation(state)

	t = RoundManager.current_team(state)
	var u: BattleUnit = state.unactivated_units(t)[0]
	_activate_unit(state, u)

	var result := TurnActions.execute_ability(state, "lullaby", Vector2i(1, 0))
	var outcomes: Array = result["outcomes"]
	assert_true(outcomes[0].get("skipped", false))


# ===================================================================
# Revive Mechanics
# ===================================================================

func test_revive_restores_hp_fraction_and_clears_downed() -> void:
	var unit := _make_unit("test", 3, 10)
	unit.current_hp = 0
	unit.is_downed = true
	unit.downed_round = 1

	var result := CombatResolver.resolve_revive(unit, 0.5)
	assert_eq(result["healing"], 5)  # 50% of 10
	assert_eq(unit.current_hp, 5)
	assert_false(unit.is_downed)
	assert_eq(unit.downed_round, -1)


func test_revive_clamped_to_max_hp() -> void:
	var unit := _make_unit("test", 3, 10)
	unit.current_hp = 0
	unit.is_downed = true

	CombatResolver.resolve_revive(unit, 2.0)  # 200% — clamp to max
	assert_eq(unit.current_hp, 10)


func test_revive_uses_constant_fraction() -> void:
	## Default revive (no fraction arg) uses REVIVE_HP_FRACTION constant.
	var unit := _make_unit("test", 3, 20)
	unit.current_hp = 0
	unit.is_downed = true

	var result := CombatResolver.resolve_revive(unit)
	# REVIVE_HP_FRACTION = 0.25 → round(20 * 0.25) = 5
	assert_eq(result["healing"], 5)
	assert_eq(unit.current_hp, 5)
	assert_false(unit.is_downed)


func test_revive_minimum_1_hp() -> void:
	## Even with very low max HP, revive restores at least 1 HP.
	var unit := _make_unit("test", 3, 2)
	unit.current_hp = 0
	unit.is_downed = true

	var result := CombatResolver.resolve_revive(unit, 0.01)  # round(2 * 0.01) = 0 → max(1, 0) = 1
	assert_eq(result["healing"], 1)
	assert_eq(unit.current_hp, 1)


func test_revive_through_turn_actions() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Down a0 manually (max HP = 16)
	var a0: BattleUnit = state.parties["playerA"][0]
	a0.current_hp = 0
	a0.is_downed = true
	a0.downed_round = 1

	# a1's activation (a0 downed so a1 is first activatable)
	var t := RoundManager.current_team(state)
	var u: BattleUnit = state.unactivated_units(t)[0]
	assert_eq(u.character.id, "a1", "a0 is downed, a1 should be first")
	_activate_unit(state, u)

	# Cast revive on downed a0
	var result := TurnActions.execute_ability(state, "revive_1", Vector2i(-1, 0))
	assert_false(result.has("error"), "revive should succeed: %s" % str(result))
	var outcomes: Array = result["outcomes"]
	assert_eq(outcomes.size(), 1)
	assert_true(outcomes[0].get("revived", false))
	# REVIVE_HP_FRACTION = 0.25 → round(16 * 0.25) = 4
	assert_eq(outcomes[0]["target_hp_after"], 4)

	# a0 should be alive again
	assert_false(a0.is_downed)
	assert_eq(a0.current_hp, 4)
	assert_true(a0.is_active())


func test_revive_on_alive_unit_skipped() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	var t := RoundManager.current_team(state)
	var u: BattleUnit = state.unactivated_units(t)[0]
	_activate_unit(state, u)

	# Try to revive alive a1 (at -2,0)
	var result := TurnActions.execute_ability(state, "revive_1", Vector2i(-2, 0))
	var outcomes: Array = result["outcomes"]
	assert_true(outcomes[0].get("skipped", false))
	assert_eq(outcomes[0].get("reason", ""), "not_downed")


func test_revive_on_enemy_skipped() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Down b0
	var b0: BattleUnit = state.parties["playerB"][0]
	b0.current_hp = 0
	b0.is_downed = true
	b0.downed_round = 1

	var t := RoundManager.current_team(state)
	var u: BattleUnit = state.unactivated_units(t)[0]
	_activate_unit(state, u)

	# Try to revive enemy downed unit
	var result := TurnActions.execute_ability(state, "revive_1", Vector2i(1, 0))
	var outcomes: Array = result["outcomes"]
	assert_true(outcomes[0].get("skipped", false))
	assert_eq(outcomes[0].get("reason", ""), "enemy")


# ===================================================================
# Revive + Queue Reinsertion
# ===================================================================

func test_revived_unit_in_next_round_queue() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)  # Round 1

	var a0: BattleUnit = state.parties["playerA"][0]
	a0.current_hp = 0
	a0.is_downed = true
	a0.downed_round = 1

	# a0 excluded from round 1 queue
	assert_false(state.unactivated_units("playerA").has(a0))

	# Revive a0
	CombatResolver.resolve_revive(a0)

	_skip_all_activations(state)
	RoundManager.start_round(state)  # Round 2

	# a0 should be in the queue now
	assert_true(state.unactivated_units("playerA").has(a0))


func test_downed_unit_revived_before_round_end_survives() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	var b0: BattleUnit = state.parties["playerB"][0]
	b0.current_hp = 0
	b0.is_downed = true
	b0.downed_round = 1

	# Revive b0 before round ends
	CombatResolver.resolve_revive(b0)
	assert_false(b0.is_downed)
	assert_true(b0.current_hp > 0)

	_skip_all_activations(state)

	# b0 was revived, should still be alive and on the board
	assert_true(b0.is_active())
	assert_true(state.is_occupied(Vector2i(1, 0)), "b0 should still occupy hex")


func test_revived_unit_persists_across_rounds() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)  # Round 1

	var a0: BattleUnit = state.parties["playerA"][0]
	a0.current_hp = 0
	a0.is_downed = true
	a0.downed_round = 1

	CombatResolver.resolve_revive(a0)
	assert_false(a0.is_downed)

	_skip_all_activations(state)
	RoundManager.start_round(state)  # Round 2
	_skip_all_activations(state)
	RoundManager.start_round(state)  # Round 3

	assert_true(a0.is_active())


# ===================================================================
# Repeated Down/Revive Cycles
# ===================================================================

func test_down_revive_down_cycle() -> void:
	var a0 := _make_unit("a0", 3, 10)

	# Down
	a0.current_hp = 0
	a0.is_downed = true
	a0.downed_round = 1
	assert_true(a0.is_downed)
	assert_false(a0.is_active())

	# Revive at 50%
	CombatResolver.resolve_revive(a0, 0.5)
	assert_false(a0.is_downed)
	assert_eq(a0.current_hp, 5)
	assert_true(a0.is_active())

	# Down again
	a0.current_hp = 0
	a0.is_downed = true
	a0.downed_round = 2
	assert_true(a0.is_downed)
	assert_false(a0.is_active())
	assert_true(a0.is_living())


# ===================================================================
# AoE Edge Cases
# ===================================================================

func test_aoe_damage_skips_downed() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Down b0 at (1,0), b1 is at (2,0)
	var b0: BattleUnit = state.parties["playerB"][0]
	b0.current_hp = 0
	b0.is_downed = true
	b0.downed_round = 1

	var t := RoundManager.current_team(state)
	var u: BattleUnit = state.unactivated_units(t)[0]
	_activate_unit(state, u)

	var result := TurnActions.execute_ability(state, "aoe_damage", Vector2i(1, 0))
	assert_false(result.has("error"), "AoE should succeed: %s" % str(result))
	var outcomes: Array = result["outcomes"]

	var b0_skipped := false
	var b1_hit := false
	for outcome in outcomes:
		if outcome["target"] == "b0":
			b0_skipped = outcome.get("skipped", false)
		if outcome["target"] == "b1" and outcome.has("damage"):
			b1_hit = true

	assert_true(b0_skipped, "downed b0 should be skipped by damage")
	assert_true(b1_hit, "alive b1 should take damage")


func test_aoe_revive_targets_downed_only() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	var a0: BattleUnit = state.parties["playerA"][0]
	a0.current_hp = 0
	a0.is_downed = true
	a0.downed_round = 1

	# Skip to a1
	var t := RoundManager.current_team(state)
	var u: BattleUnit = state.unactivated_units(t)[0]
	assert_eq(u.character.id, "a1")
	_activate_unit(state, u)

	# Cast AoE revive centered on (-1,0)
	var result := TurnActions.execute_ability(state, "aoe_revive", Vector2i(-1, 0))
	assert_false(result.has("error"), "AoE revive should succeed: %s" % str(result))
	var outcomes: Array = result["outcomes"]

	var a0_revived := false
	var a1_skipped := false
	for outcome in outcomes:
		if outcome["target"] == "a0" and outcome.get("revived", false):
			a0_revived = true
		if outcome["target"] == "a1" and outcome.get("skipped", false):
			a1_skipped = true

	assert_true(a0_revived, "downed a0 should be revived")
	if outcomes.size() > 1:
		assert_true(a1_skipped, "alive a1 should be skipped by revive")


# ===================================================================
# CT Scheduler Integration (A17 + A20)
# ===================================================================

func test_ct_scheduler_skips_downed_unit() -> void:
	## Downed units don't accrue CT and are never picked by tick().
	var a := _make_unit("a", 5, 10)
	a.team = "playerA"
	var b := _make_unit("b", 3, 10)
	b.team = "playerB"

	var scheduler := TurnScheduler.new()
	scheduler.setup([a, b], 42)

	# Down unit b
	b.current_hp = 0
	b.is_downed = true

	# Tick until someone crosses threshold — should always be 'a'
	var activated: BattleUnit = null
	for _i in range(200):
		activated = scheduler.tick()
		if activated:
			break

	assert_eq(activated, a, "downed unit should never be picked")


func test_ct_requeue_after_revive() -> void:
	## requeue_unit resets CT to 0 so the revived unit starts accruing fresh.
	var a := _make_unit("a", 5, 10)
	a.team = "playerA"
	var b := _make_unit("b", 3, 10)
	b.team = "playerB"

	var scheduler := TurnScheduler.new()
	scheduler.setup([a, b], 42)

	# Down b, then revive
	b.current_hp = 0
	b.is_downed = true
	scheduler.requeue_unit(b)

	assert_eq(scheduler.get_ct(b), 0.0, "requeued unit CT should be 0")

	# Un-down b (simulate revive restoring state)
	b.is_downed = false
	b.current_hp = 5

	# Now both should accrue CT — b should eventually activate
	var b_activated := false
	for _i in range(200):
		var unit := scheduler.tick()
		if unit == b:
			b_activated = true
			break
		if unit:
			scheduler.on_acted(unit, false)

	assert_true(b_activated, "revived unit should eventually activate via CT")


# ===================================================================
# Speed-Round Fizzle (A17 + A15)
# ===================================================================

func test_speed_round_fizzle_downed_unit() -> void:
	## A downed unit's plan fizzles during speed-round resolution.
	var state := _setup_match()
	var sr := SpeedRoundTurnSystem.new()
	state.turn_system = sr

	sr.begin_round(state)
	sr.advance(state)  # AI_PLANNING → PLAYER_PLANNING

	# Build plans for all units
	var a0: BattleUnit = state.parties["playerA"][0]
	var a1: BattleUnit = state.parties["playerA"][1]
	var b0: BattleUnit = state.parties["playerB"][0]
	var b1: BattleUnit = state.parties["playerB"][1]

	var wait_plan := AIPlan.new()
	wait_plan.steps.append({"kind": "wait"})

	sr.commit_player_plan(a0, wait_plan)
	sr.commit_player_plan(a1, wait_plan)
	sr.commit_player_plan(b0, wait_plan)
	sr.commit_player_plan(b1, wait_plan)

	sr.advance(state)  # PLAYER_PLANNING → RESOLUTION

	# Down b0 before resolution starts
	b0.current_hp = 0
	b0.is_downed = true

	# Resolve all — b0's plan should fizzle
	var b0_fizzled := false
	while sr.has_next_resolution():
		var result := sr.resolve_next(state)
		if result.get("unit_id") == "b0":
			b0_fizzled = result.get("fizzled", false)

	assert_true(b0_fizzled, "downed unit's plan should fizzle in speed-round")


# ===================================================================
# Permadeath Handoff (A17)
# ===================================================================

func test_death_model_extract_downed_ids() -> void:
	## extract_downed_ids returns IDs of units still downed at battle end.
	var state := _setup_match()
	var a0: BattleUnit = state.parties["playerA"][0]
	var a1: BattleUnit = state.parties["playerA"][1]

	# a0 downed, a1 alive
	a0.current_hp = 0
	a0.is_downed = true

	var downed := DeathModel.extract_downed_ids(state, "playerA")
	assert_eq(downed.size(), 1)
	assert_eq(downed[0], "a0")


func test_death_model_extract_excludes_revived() -> void:
	## A revived unit (is_downed = false) is NOT in downed IDs.
	var state := _setup_match()
	var a0: BattleUnit = state.parties["playerA"][0]

	# Down then revive
	a0.current_hp = 0
	a0.is_downed = true
	CombatResolver.resolve_revive(a0)

	var downed := DeathModel.extract_downed_ids(state, "playerA")
	assert_eq(downed.size(), 0, "revived unit should not be in downed list")


func test_death_model_permadeath_on_down_limit() -> void:
	## downs_this_run exceeding down_limit removes the instance from the band.
	var band := BattleBand.new()
	band.band_id = "test_band"
	var ci := CharacterInstance.new()
	ci.instance_id = "hero_1"
	ci.downs_this_run = 2  # Already downed twice
	band.roster.append(ci)

	var run := RunState.new()
	run.down_limit = 2  # 3rd down = permadeath

	var result := DeathModel.apply_post_battle(run, band, ["hero_1"] as Array[String])
	assert_eq(result["dead_ids"].size(), 1)
	assert_eq(result["dead_ids"][0], "hero_1")
	assert_eq(band.roster.size(), 0, "permadead character removed from roster")


func test_death_model_survives_within_down_limit() -> void:
	## downs_this_run within limit keeps the instance alive.
	var band := BattleBand.new()
	band.band_id = "test_band"
	var ci := CharacterInstance.new()
	ci.instance_id = "hero_1"
	ci.downs_this_run = 0
	band.roster.append(ci)

	var run := RunState.new()
	run.down_limit = 2

	var result := DeathModel.apply_post_battle(run, band, ["hero_1"] as Array[String])
	assert_eq(result["dead_ids"].size(), 0)
	assert_eq(band.roster.size(), 1, "character should survive within down limit")
	assert_eq(ci.downs_this_run, 1)
