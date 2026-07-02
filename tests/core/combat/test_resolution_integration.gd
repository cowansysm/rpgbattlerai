extends GutTest
## Integration tests for Phase 5 combat resolution through TurnActions.
## Tests attack damage, ability effects, AoE, downing, buff/status durations,
## sleep skip, blind miss, and round-start cleanup.

var _default_roller: Callable
var _default_crit_roller: Callable


func before_each() -> void:
	_default_roller = CombatResolver.dice_roller
	_default_crit_roller = CombatResolver.crit_roller
	CombatResolver.dice_roller = func() -> int: return 3
	# Pin crit roll above the crit threshold so crits never fire in deterministic tests
	CombatResolver.crit_roller = func() -> float: return 1.0


func after_each() -> void:
	CombatResolver.dice_roller = _default_roller
	CombatResolver.crit_roller = _default_crit_roller


# --- Stub terrain provider ---

static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	if id == "brush":
		p.cover = 1
		p.move_cost = 2
	if id == "trees":
		p.blocks_los = true
		p.cover = 1
		p.los_height = 2
		p.move_cost = 2
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


func _setup_match(terrain_at: Dictionary = {}) -> MatchState:
	## Create a deployed match with 2 units on opposite sides.
	var map := MapData.new()
	map.id = "test"
	var tiles: Array[TileRecord] = []
	for c in Hex.hexes_in_range(Vector2i(0, 0), 5):
		var t_id := "grass"
		if terrain_at.has(c):
			t_id = terrain_at[c]
		tiles.append(TileRecord.new(c.x, c.y, 0, t_id))
	map.tiles = tiles

	var a0 := _make_unit("a0", 4, 16, 3, 3, 1)  # Fighter: ATK=3, DEF=3, RNG=1
	var a1 := _make_unit("a1", 3, 10, 2, 1, 2)   # Archer: ATK=2, DEF=1, RNG=2
	var b0 := _make_unit("b0", 3, 12, 0, 0, 0)   # Mage: ATK=0, DEF=0
	var b1 := _make_unit("b1", 2, 13, 0, 0, 1)   # Healer: ATK=0, DEF=0

	var party_a: Array[BattleUnit] = [a0, a1]
	var party_b: Array[BattleUnit] = [b0, b1]

	var state := MatchSetup.create(party_a, party_b, map, _stub_terrain)

	# Manual deploy; A19: set facings toward opponents so arc = FRONT for existing tests
	a0.position = Vector2i(-1, 0)
	a0.set_facing(Hex.direction_toward(Vector2i(-1, 0), Vector2i(1, 0)))
	state.occupancy[Vector2i(-1, 0)] = a0
	a1.position = Vector2i(-2, 0)
	a1.set_facing(Hex.direction_toward(Vector2i(-2, 0), Vector2i(2, 0)))
	state.occupancy[Vector2i(-2, 0)] = a1
	b0.position = Vector2i(1, 0)
	b0.set_facing(Hex.direction_toward(Vector2i(1, 0), Vector2i(-1, 0)))
	state.occupancy[Vector2i(1, 0)] = b0
	b1.position = Vector2i(2, 0)
	b1.set_facing(Hex.direction_toward(Vector2i(2, 0), Vector2i(-2, 0)))
	state.occupancy[Vector2i(2, 0)] = b1

	state.phase = MatchState.Phase.ROUND_START

	# Wire providers
	var sword := _make_item("sword", "weapon", 3)
	var items := { "sword": sword }
	state.item_provider = func(id: String) -> ItemData: return items.get(id, null)

	var fire_1 := _make_ability("fire_1", 1, 3, "damage", "spell",
		{ "effect_type": "damage", "value": 4, "element": "fire" })
	var cure_1 := _make_ability("cure_1", 1, 3, "heal", "spell",
		{ "effect_type": "heal", "value": 4 })
	var shield_1 := _make_ability("shield_1", 1, 3, "buff", "spell",
		{ "effect_type": "buff", "stat": "def", "value": 2, "duration": 3 })
	var lullaby := _make_ability("lullaby", 1, 3, "status", "skill",
		{ "effect_type": "status", "status_id": "sleep", "duration": 2 })
	var inspire := _make_ability("inspire", 1, 3, "buff", "skill",
		{ "effect_type": "buff", "stat": "atk", "value": 2, "duration": 3 },
		{ "shape": "burst", "radius": 1 })
	var power_strike := _make_ability("power_strike", 1, 1, "damage", "skill",
		{ "effect_type": "damage", "value": 4 })
	var smoke_bomb := _make_ability("smoke_bomb", 1, 2, "status", "item",
		{ "effect_type": "status", "status_id": "blind", "duration": 2 },
		{ "shape": "burst", "radius": 1 })
	var rage := _make_ability("rage", 1, 0, "buff", "skill",
		{ "effect_type": "buff", "stat": "atk", "value": 3, "duration": 3 })

	var abilities := {
		"fire_1": fire_1, "cure_1": cure_1, "shield_1": shield_1,
		"lullaby": lullaby, "inspire": inspire, "power_strike": power_strike,
		"smoke_bomb": smoke_bomb, "rage": rage,
	}
	state.ability_provider = func(_unit: BattleUnit, aid: String) -> AbilityData:
		return abilities.get(aid, null)

	return state


# --- Physical Attack Resolution ---

func test_attack_deals_damage() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Move a0 next to b0 (a0 at -1,0; b0 at 1,0 — distance 2, need to move)
	var team := RoundManager.current_team(state)
	var unit: BattleUnit = state.unactivated_units(team)[0]
	RoundManager.activate_unit(state, unit)

	# Move adjacent to b0
	TurnActions.execute_move(state, Vector2i(0, 0))

	# Attack b0 (now adjacent at 1,0)
	var result := TurnActions.execute_attack(state, Vector2i(1, 0))
	assert_false(result.has("error"), "attack should succeed")
	assert_true(result.has("damage"), "should have damage field")
	# damage = max(1, roll=3 + ATK=3 + weapon=3 + 0 - DEF=0) = 9  (no defense die)
	assert_eq(result["damage"], 9)
	assert_eq(result["target_hp_after"], 3)  # 12 - 9 = 3
	assert_false(result["is_downed"])


func test_attack_downs_target() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Set b0 to low HP
	state.parties["playerB"][0].current_hp = 2

	var unit: BattleUnit = state.unactivated_units(
		RoundManager.current_team(state))[0]
	RoundManager.activate_unit(state, unit)
	TurnActions.execute_move(state, Vector2i(0, 0))

	var result := TurnActions.execute_attack(state, Vector2i(1, 0))
	assert_true(result["is_downed"])
	assert_eq(result["target_hp_after"], 0)
	# Downed unit stays in occupancy (blocks hex) but is marked as downed
	assert_true(state.is_occupied(Vector2i(1, 0)))
	assert_true(state.parties["playerB"][0].is_downed)


func test_attack_blind_misses() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	var unit: BattleUnit = state.unactivated_units(
		RoundManager.current_team(state))[0]
	RoundManager.activate_unit(state, unit)
	TurnActions.execute_move(state, Vector2i(0, 0))

	# Apply blind
	CombatResolver.resolve_status(unit, "blind", 2, "smoke_bomb")

	var target_hp_before: int = state.parties["playerB"][0].current_hp
	var result := TurnActions.execute_attack(state, Vector2i(1, 0))
	assert_true(result.get("missed", false))
	assert_eq(result.get("reason", ""), "blind")
	# Target HP unchanged
	assert_eq(state.parties["playerB"][0].current_hp, target_hp_before)


# --- Ability Resolution ---

func test_spell_damage_ability() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Activate b0 (mage at 1,0)
	# Skip a0's activation first
	var t := RoundManager.current_team(state)
	var u: BattleUnit = state.unactivated_units(t)[0]
	RoundManager.activate_unit(state, u)
	TurnActions.execute_wait(state)
	RoundManager.end_activation(state)

	# Now b0's turn
	t = RoundManager.current_team(state)
	u = state.unactivated_units(t)[0]
	RoundManager.activate_unit(state, u)

	# Cast fire_1 at a0 (at -1,0; distance=2, range=3)
	var result := TurnActions.execute_ability(state, "fire_1", Vector2i(-1, 0))
	assert_false(result.has("error"), "ability should succeed: %s" % str(result))
	assert_true(result.has("outcomes"))
	var outcomes: Array = result["outcomes"]
	assert_eq(outcomes.size(), 1)
	# spell damage = 1d6(3) + 4 + 0 = 7 (flat ground, attack die only, ignores DEF)
	assert_eq(outcomes[0]["damage"], 7)
	assert_eq(outcomes[0]["target"], "a0")


func test_heal_ability() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Damage b1 (healer) so we can heal
	state.parties["playerB"][1].current_hp = 5

	# Skip to b1's activation
	for i in range(3):
		var t := RoundManager.current_team(state)
		var u: BattleUnit = state.unactivated_units(t)[0]
		RoundManager.activate_unit(state, u)
		TurnActions.execute_wait(state)
		RoundManager.end_activation(state)

	# b1's turn (healer at 2,0)
	var t := RoundManager.current_team(state)
	var u: BattleUnit = state.unactivated_units(t)[0]
	assert_eq(u.character.id, "b1")
	RoundManager.activate_unit(state, u)

	# Heal self
	var result := TurnActions.execute_ability(state, "cure_1", Vector2i(2, 0))
	assert_false(result.has("error"), "heal should succeed: %s" % str(result))
	var outcomes: Array = result["outcomes"]
	assert_eq(outcomes[0]["healing"], 4)
	assert_eq(u.current_hp, 9)  # 5 + 4


func test_buff_ability() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Skip to b1's turn
	for i in range(3):
		var t := RoundManager.current_team(state)
		var u: BattleUnit = state.unactivated_units(t)[0]
		RoundManager.activate_unit(state, u)
		TurnActions.execute_wait(state)
		RoundManager.end_activation(state)

	var t := RoundManager.current_team(state)
	var u: BattleUnit = state.unactivated_units(t)[0]
	RoundManager.activate_unit(state, u)

	var target: BattleUnit = state.parties["playerB"][0]
	var base_def: int = target.stats.effective("def")

	# Cast shield_1 on b0 (at 1,0)
	var result := TurnActions.execute_ability(state, "shield_1", Vector2i(1, 0))
	assert_false(result.has("error"), "buff should succeed: %s" % str(result))
	var outcomes: Array = result["outcomes"]
	assert_eq(outcomes[0]["buff_stat"], "def")
	assert_eq(outcomes[0]["buff_value"], 2)
	assert_eq(target.stats.effective("def"), base_def + 2)

	# Buff duration registered
	assert_eq(state.buff_durations.size(), 1)
	assert_eq(state.buff_durations[0]["remaining"], 3)


func test_status_ability() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Skip to b0's turn
	var t := RoundManager.current_team(state)
	var u: BattleUnit = state.unactivated_units(t)[0]
	RoundManager.activate_unit(state, u)
	TurnActions.execute_wait(state)
	RoundManager.end_activation(state)

	t = RoundManager.current_team(state)
	u = state.unactivated_units(t)[0]
	RoundManager.activate_unit(state, u)

	# Cast lullaby at a0 (-1,0)
	var result := TurnActions.execute_ability(state, "lullaby", Vector2i(-1, 0))
	assert_false(result.has("error"), "status should succeed: %s" % str(result))
	var outcomes: Array = result["outcomes"]
	assert_eq(outcomes[0]["status_id"], "sleep")
	assert_true(state.parties["playerA"][0].has_status("sleep"))


func test_self_targeted_ability() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	var t := RoundManager.current_team(state)
	var u: BattleUnit = state.unactivated_units(t)[0]
	RoundManager.activate_unit(state, u)

	var base_atk: int = u.stats.effective("atk")

	# Cast rage on self (range 0, target_pos must be own position)
	var result := TurnActions.execute_ability(state, "rage", u.position)
	assert_false(result.has("error"), "self-buff should succeed: %s" % str(result))
	assert_eq(u.stats.effective("atk"), base_atk + 3)


func test_self_targeted_wrong_position_fails() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	var t := RoundManager.current_team(state)
	var u: BattleUnit = state.unactivated_units(t)[0]
	RoundManager.activate_unit(state, u)

	# Try to cast rage at a different position
	var result := TurnActions.execute_ability(state, "rage", Vector2i(0, 0))
	assert_true(result.has("error"))


# --- AoE Tests ---

func test_aoe_burst_hits_multiple_units() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Move b0 and b1 adjacent for AoE test
	# b0 at 1,0; b1 at 2,0 — they're 1 hex apart
	# a0's inspire (burst radius 1) centered on 1,0 would hit units at
	# distance <= 1 from (1,0). b0 is at (1,0), b1 at (2,0).

	# First, activate a0
	var t := RoundManager.current_team(state)
	var u: BattleUnit = state.unactivated_units(t)[0]
	RoundManager.activate_unit(state, u)

	# Cast inspire centered on a0's position (adjacent allies would get it)
	# a0 at (-1,0), a1 at (-2,0) — distance=1, within burst radius
	var result := TurnActions.execute_ability(state, "inspire", Vector2i(-1, 0))
	assert_false(result.has("error"), "AoE should succeed: %s" % str(result))
	var outcomes: Array = result["outcomes"]
	# Should hit a0 (at -1,0) and a1 (at -2,0, distance 1 from center)
	assert_eq(outcomes.size(), 2)


func test_aoe_friendly_fire() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Put a0 adjacent to b0 for AoE friendly fire test
	state.occupancy.erase(Vector2i(-1, 0))
	state.parties["playerA"][0].position = Vector2i(0, 0)
	state.occupancy[Vector2i(0, 0)] = state.parties["playerA"][0]

	# Skip to b0's turn
	var t := RoundManager.current_team(state)
	var u: BattleUnit = state.unactivated_units(t)[0]
	RoundManager.activate_unit(state, u)
	TurnActions.execute_wait(state)
	RoundManager.end_activation(state)

	t = RoundManager.current_team(state)
	u = state.unactivated_units(t)[0]
	RoundManager.activate_unit(state, u)

	# Cast smoke_bomb (burst radius 1, status=blind) at (0,0) — hits a0 AND b0
	# b0 is at (1,0), distance 1 from (0,0) = within burst
	var result := TurnActions.execute_ability(state, "smoke_bomb", Vector2i(0, 0))
	assert_false(result.has("error"), "AoE should succeed: %s" % str(result))
	var outcomes: Array = result["outcomes"]
	# Should hit a0 (at 0,0) and b0 (at 1,0)
	assert_true(outcomes.size() >= 2, "should hit at least 2 units")


# --- Downing Integration ---

func test_downed_unit_excluded_from_living() -> void:
	var state := _setup_match()
	state.parties["playerB"][0].current_hp = 0
	state.parties["playerB"][0].is_downed = true
	assert_eq(state.living_units("playerB").size(), 1)


func test_downed_unit_included_in_activation_queue() -> void:
	var state := _setup_match()
	state.parties["playerB"][0].current_hp = 0
	state.parties["playerB"][0].is_downed = true
	RoundManager.start_round(state)
	# All 4 units (including downed) should be in queue
	assert_eq(state.activation_queue.size(), 4)


# --- Round-Start Cleanup ---

func test_buff_expires_after_duration() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	var target: BattleUnit = state.parties["playerB"][0]
	var base_def: int = target.stats.effective("def")

	# Apply a buff with duration 2
	CombatResolver.resolve_buff(target, "def", 2, "shield_1")
	state.buff_durations.append({
		"source_tag": "buff:shield_1",
		"unit": target,
		"remaining": 2,
	})
	assert_eq(target.stats.effective("def"), base_def + 2)

	# Complete the round
	for i in range(4):
		var t := RoundManager.current_team(state)
		var u: BattleUnit = state.unactivated_units(t)[0]
		RoundManager.activate_unit(state, u)
		TurnActions.execute_wait(state)
		RoundManager.end_activation(state)

	# Round 2: buff remaining = 2-1 = 1 (still active)
	RoundManager.start_round(state)
	assert_eq(target.stats.effective("def"), base_def + 2)
	assert_eq(state.buff_durations.size(), 1)

	# Complete round 2
	for i in range(4):
		var t := RoundManager.current_team(state)
		var u: BattleUnit = state.unactivated_units(t)[0]
		RoundManager.activate_unit(state, u)
		TurnActions.execute_wait(state)
		RoundManager.end_activation(state)

	# Round 3: buff remaining = 1-1 = 0 (expires)
	RoundManager.start_round(state)
	assert_eq(target.stats.effective("def"), base_def)
	assert_eq(state.buff_durations.size(), 0)


func test_status_expires_after_duration() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	var target: BattleUnit = state.parties["playerA"][0]
	CombatResolver.resolve_status(target, "sleep", 1, "lullaby")
	assert_true(target.has_status("sleep"))

	# Complete round
	for i in range(4):
		var t := RoundManager.current_team(state)
		var u: BattleUnit = state.unactivated_units(t)[0]
		RoundManager.activate_unit(state, u)
		TurnActions.execute_wait(state)
		RoundManager.end_activation(state)

	# Round 2: sleep duration 1-1 = 0, should be removed
	RoundManager.start_round(state)
	assert_false(target.has_status("sleep"))


func test_defend_persists_until_next_activation() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	var t := RoundManager.current_team(state)
	var u: BattleUnit = state.unactivated_units(t)[0]
	RoundManager.activate_unit(state, u)

	var base_def: int = u.stats.base("def")
	TurnActions.execute_defend(state)
	assert_eq(u.stats.effective("def"), base_def + 3)

	TurnActions.execute_wait(state)
	RoundManager.end_activation(state)

	# Complete remaining activations — defend should persist throughout
	for i in range(3):
		t = RoundManager.current_team(state)
		var u2: BattleUnit = state.unactivated_units(t)[0]
		RoundManager.activate_unit(state, u2)
		TurnActions.execute_wait(state)
		RoundManager.end_activation(state)

	# Defend persists through round start
	RoundManager.start_round(state)
	assert_eq(u.stats.effective("def"), base_def + 3,
		"defend should persist through round start")

	# Defend cleared when unit activates again
	t = RoundManager.current_team(state)
	if t != u.team:
		# Skip other team's activation to reach our unit's turn
		var skip_u: BattleUnit = state.unactivated_units(t)[0]
		RoundManager.activate_unit(state, skip_u)
		TurnActions.execute_wait(state)
		RoundManager.end_activation(state)
	RoundManager.activate_unit(state, u)
	assert_eq(u.stats.effective("def"), base_def,
		"defend should be removed on next activation")


# --- Sleep Skip ---

func test_sleeping_unit_detected() -> void:
	var unit := _make_unit("test", 3, 10, 2, 1, 1)
	CombatResolver.resolve_status(unit, "sleep", 2, "lullaby")
	assert_true(RoundManager.is_sleeping(unit))


func test_non_sleeping_unit_not_detected() -> void:
	var unit := _make_unit("test", 3, 10, 2, 1, 1)
	assert_false(RoundManager.is_sleeping(unit))


# --- Skill Damage (reduced by DEF) ---

func test_skill_damage_through_turn_actions() -> void:
	var state := _setup_match()
	RoundManager.start_round(state)

	# Activate a0 (fighter)
	var t := RoundManager.current_team(state)
	var u: BattleUnit = state.unactivated_units(t)[0]
	RoundManager.activate_unit(state, u)

	# Move adjacent to b0
	TurnActions.execute_move(state, Vector2i(0, 0))

	# Use power_strike (skill, damage=4, DEF reduces)
	var b0_hp: int = state.parties["playerB"][0].current_hp
	var b0_def: int = state.parties["playerB"][0].stats.effective("def")
	var result := TurnActions.execute_ability(state, "power_strike", Vector2i(1, 0))
	assert_false(result.has("error"), "power_strike should succeed: %s" % str(result))
	var outcomes: Array = result["outcomes"]
	# skill damage = max(1, roll(3) + 4 + 0 - DEF)  (no defense die)
	var expected_damage: int = max(1, 3 + 4 - b0_def)
	assert_eq(outcomes[0]["damage"], expected_damage)
