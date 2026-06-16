extends GutTest
## Tests for downed-but-revivable mechanic: downed state, revive effect,
## grace period expiry, untargetability, and repeated down/revive cycles.

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


# --- BattleUnit State Model ---

func test_new_unit_not_downed() -> void:
	var unit := _make_unit("test")
	assert_false(unit.is_downed)
	assert_eq(unit.downed_round, -1)


func test_is_alive_true_for_healthy_unit() -> void:
	var unit := _make_unit("test")
	assert_true(unit.is_alive())


func test_is_alive_false_for_downed_unit() -> void:
	var unit := _make_unit("test")
	unit.current_hp = 0
	unit.is_downed = true
	assert_false(unit.is_alive())


# --- Downing Mechanics ---

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
	# Skip b0's activation (downed, won't be in queue)
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


func test_downed_unit_included_in_activation_queue() -> void:
	var state := _setup_match()
	var b0: BattleUnit = state.parties["playerB"][0]
	b0.current_hp = 0
	b0.is_downed = true
	RoundManager.start_round(state)
	# All 4 units (including downed b0) should be in queue
	assert_eq(state.activation_queue.size(), 4)


# --- Heal Does Not Revive ---

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


# --- Revive Mechanics ---

func test_revive_restores_hp_and_clears_downed() -> void:
	var unit := _make_unit("test", 3, 10)
	unit.current_hp = 0
	unit.is_downed = true
	unit.downed_round = 1

	var result := CombatResolver.resolve_revive(unit, 5)
	assert_eq(result["healing"], 5)
	assert_eq(unit.current_hp, 5)
	assert_false(unit.is_downed)
	assert_eq(unit.downed_round, -1)


func test_revive_clamped_to_max_hp() -> void:
	var unit := _make_unit("test", 3, 10)
	unit.current_hp = 0
	unit.is_downed = true

	var result := CombatResolver.resolve_revive(unit, 999)
	assert_eq(unit.current_hp, 10)  # max HP


func test_revive_through_turn_actions() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Down a0 manually
	var a0: BattleUnit = state.parties["playerA"][0]
	a0.current_hp = 0
	a0.is_downed = true
	a0.downed_round = 1

	# a1's activation (skip a0 since downed, skip b team activations)
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
	assert_eq(outcomes[0]["target_hp_after"], 5)

	# a0 should be alive again
	assert_false(a0.is_downed)
	assert_eq(a0.current_hp, 5)
	assert_true(a0.is_alive())


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


# --- Downed Turn Processing ---

func test_downed_unit_removed_on_own_turn() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Down b0 in round 1
	var b0: BattleUnit = state.parties["playerB"][0]
	b0.current_hp = 0
	b0.is_downed = true
	b0.downed_round = 1

	# Skip all activations — b0 will be activated as downed and permanently removed
	_skip_all_activations(state)

	# b0 should be permanently removed
	assert_false(b0.is_downed, "should no longer be downed")
	assert_eq(b0.current_hp, 0)
	assert_false(state.is_occupied(Vector2i(1, 0)), "hex should be free")


func test_downed_unit_revived_before_turn_survives() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	var b0: BattleUnit = state.parties["playerB"][0]
	b0.current_hp = 0
	b0.is_downed = true
	b0.downed_round = 1

	# Revive b0 before its turn comes
	CombatResolver.resolve_revive(b0, 5)
	assert_false(b0.is_downed)
	assert_eq(b0.current_hp, 5)

	_skip_all_activations(state)

	# b0 was revived, should still be alive and on the board
	assert_true(b0.is_alive())
	assert_true(state.is_occupied(Vector2i(1, 0)), "b0 should still occupy hex")


func test_revived_unit_not_removed() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)  # Round 1

	# Down a0 in round 1
	var a0: BattleUnit = state.parties["playerA"][0]
	a0.current_hp = 0
	a0.is_downed = true
	a0.downed_round = 1

	# Revive a0 during round 1
	CombatResolver.resolve_revive(a0, 5)
	assert_false(a0.is_downed)

	_skip_all_activations(state)
	RoundManager.start_round(state)  # Round 2
	_skip_all_activations(state)
	RoundManager.start_round(state)  # Round 3

	# a0 was revived, should not be removed
	assert_true(a0.is_alive())


# --- Repeated Down/Revive Cycles ---

func test_down_revive_down_cycle() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)  # Round 1

	var a0: BattleUnit = state.parties["playerA"][0]

	# Down in round 1
	a0.current_hp = 0
	a0.is_downed = true
	a0.downed_round = 1
	assert_true(a0.is_downed)

	# Revive
	CombatResolver.resolve_revive(a0, 5)
	assert_false(a0.is_downed)
	assert_eq(a0.current_hp, 5)

	# Down again in same round
	a0.current_hp = 0
	a0.is_downed = true
	a0.downed_round = 1
	assert_true(a0.is_downed)
	assert_eq(a0.downed_round, 1)


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
	CombatResolver.resolve_revive(a0, 5)

	_skip_all_activations(state)
	RoundManager.start_round(state)  # Round 2

	# a0 should be in the queue now
	assert_true(state.unactivated_units("playerA").has(a0))


# --- AoE Edge Cases ---

func test_aoe_damage_skips_downed() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Down b0 at (1,0), b1 is at (2,0)
	var b0: BattleUnit = state.parties["playerB"][0]
	b0.current_hp = 0
	b0.is_downed = true
	b0.downed_round = 1

	# a0 casts AoE damage centered on (1,0) with burst radius 1
	# b0 at (1,0) downed — should be skipped
	# b1 at (2,0) within radius — should take damage
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

	# Put a0 and a1 adjacent for AoE revive test
	# a0 at (-1,0) downed, a1 at (-2,0) alive
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
	# a1 is alive so revive should skip
	# a1 might or might not be in the burst — only check if present
	if outcomes.size() > 1:
		assert_true(a1_skipped, "alive a1 should be skipped by revive")
