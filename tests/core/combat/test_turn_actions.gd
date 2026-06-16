extends GutTest
## Tests for TurnActions: action validation, AP enforcement, state mutation.
## Uses stub data — no autoload required.


# --- Stub terrain provider ---

static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	if id == "trees":
		p.blocks_los = true
		p.los_height = 2
	return p


# --- Helpers ---

func _make_unit(id: String, team: String, spd: int = 3, hp: int = 10,
		atk: int = 2, rng: int = 1, def: int = 1, wp: int = 0) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = ["sword"]
	c.abilities = []
	var sb := StatBlock.new()
	sb.set_base("spd", spd)
	sb.set_base("hp", hp)
	sb.set_base("def", def)
	sb.set_base("atk", atk)
	sb.set_base("rng", rng)
	sb.set_base("wp", wp)
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	return u


func _linear_state() -> MatchState:
	## Build a state with a line of tiles along q axis from -3 to 3.
	var map := MapData.new()
	map.id = "test_linear"
	var tiles: Array[TileRecord] = []
	for q in range(-3, 4):
		tiles.append(TileRecord.new(q, 0, 0, "grass"))
	map.tiles = tiles

	var attacker := _make_unit("atk", "playerA", 3, 10, 2, 2, 1)
	var defender := _make_unit("def", "playerB", 3, 10, 1, 1, 2)

	var party_a: Array[BattleUnit] = [attacker]
	var party_b: Array[BattleUnit] = [defender]
	var state := MatchSetup.create(party_a, party_b, map, _stub_terrain)

	# Manual placement
	attacker.position = Vector2i(-2, 0)
	state.occupancy[Vector2i(-2, 0)] = attacker
	defender.position = Vector2i(2, 0)
	state.occupancy[Vector2i(2, 0)] = defender

	state.phase = MatchState.Phase.UNIT_TURN
	state.current_unit = attacker
	attacker.ap_remaining = 2
	return state


func _adjacent_state() -> MatchState:
	## Build a state with attacker and defender on adjacent tiles.
	var map := MapData.new()
	map.id = "test_adjacent"
	var tiles: Array[TileRecord] = []
	for c in Hex.hexes_in_range(Vector2i(0, 0), 3):
		tiles.append(TileRecord.new(c.x, c.y, 0, "grass"))
	map.tiles = tiles

	var attacker := _make_unit("atk", "playerA", 3, 10, 2, 1, 1)
	var defender := _make_unit("def", "playerB", 3, 10, 1, 1, 2)

	var party_a: Array[BattleUnit] = [attacker]
	var party_b: Array[BattleUnit] = [defender]
	var state := MatchSetup.create(party_a, party_b, map, _stub_terrain)

	attacker.position = Vector2i(0, 0)
	state.occupancy[Vector2i(0, 0)] = attacker
	defender.position = Vector2i(1, 0)
	state.occupancy[Vector2i(1, 0)] = defender

	state.phase = MatchState.Phase.UNIT_TURN
	state.current_unit = attacker
	attacker.ap_remaining = 2
	return state


# --- Move tests ---

func test_move_to_adjacent_succeeds() -> void:
	var state := _adjacent_state()
	var unit := state.current_unit
	var dest := Vector2i(0, 1)	# Adjacent empty tile
	var result := TurnActions.execute_move(state, dest)
	assert_false(result.has("error"), "move to adjacent tile should succeed")
	assert_eq(unit.position, dest)
	assert_eq(unit.ap_remaining, 1)


func test_move_updates_occupancy() -> void:
	var state := _adjacent_state()
	var old_pos := state.current_unit.position
	var dest := Vector2i(0, 1)
	TurnActions.execute_move(state, dest)
	assert_false(state.is_occupied(old_pos), "old position should be clear")
	assert_true(state.is_occupied(dest), "new position should be occupied")
	assert_eq(state.unit_at(dest), state.current_unit)


func test_move_to_occupied_tile_fails() -> void:
	var state := _adjacent_state()
	var defender_pos := Vector2i(1, 0)
	var result := TurnActions.execute_move(state, defender_pos)
	assert_true(result.has("error"), "move to occupied tile should fail")


func test_move_to_unreachable_tile_fails() -> void:
	var state := _linear_state()
	# Move budget is SPD=3, destination is 5 tiles away
	var result := TurnActions.execute_move(state, Vector2i(3, 0))
	assert_true(result.has("error"), "move to unreachable tile should fail")


func test_move_with_no_ap_fails() -> void:
	var state := _adjacent_state()
	state.current_unit.ap_remaining = 0
	var result := TurnActions.execute_move(state, Vector2i(0, 1))
	assert_true(result.has("error"), "move with 0 AP should fail")


func test_move_records_action() -> void:
	var state := _adjacent_state()
	var dest := Vector2i(0, 1)
	TurnActions.execute_move(state, dest)
	assert_eq(state.turn_log.size(), 1)
	assert_eq(state.turn_log[0]["action"], "move")
	assert_eq(state.turn_log[0]["to"], dest)


func test_move_sets_has_moved() -> void:
	var state := _adjacent_state()
	assert_false(state.current_unit.has_moved, "has_moved should start false")
	TurnActions.execute_move(state, Vector2i(0, 1))
	assert_true(state.current_unit.has_moved, "has_moved should be true after move")


func test_double_move() -> void:
	var state := _adjacent_state()
	# First move
	var result1 := TurnActions.execute_move(state, Vector2i(0, 1))
	assert_false(result1.has("error"))
	assert_eq(state.current_unit.ap_remaining, 1)
	# Second move
	var result2 := TurnActions.execute_move(state, Vector2i(0, 2))
	assert_false(result2.has("error"))
	assert_eq(state.current_unit.ap_remaining, 0)


# --- Attack tests ---

func test_attack_adjacent_enemy_succeeds() -> void:
	var state := _adjacent_state()
	var target_pos := Vector2i(1, 0)
	var result := TurnActions.execute_attack(state, target_pos)
	assert_false(result.has("error"), "attack adjacent enemy should succeed")
	assert_eq(state.current_unit.ap_remaining, 1)
	assert_eq(result["action"], "attack")
	assert_eq(result["target"], "def")


func test_attack_empty_tile_fails() -> void:
	var state := _adjacent_state()
	var result := TurnActions.execute_attack(state, Vector2i(0, 2))
	assert_true(result.has("error"), "attacking empty tile should fail")


func test_attack_friendly_fails() -> void:
	var state := _adjacent_state()
	# Place a friendly unit
	var ally := _make_unit("ally", "playerA")
	ally.position = Vector2i(-1, 0)
	state.occupancy[Vector2i(-1, 0)] = ally
	state.parties["playerA"].append(ally)
	var result := TurnActions.execute_attack(state, Vector2i(-1, 0))
	assert_true(result.has("error"), "attacking friendly should fail")


func test_attack_out_of_range_fails() -> void:
	var state := _linear_state()
	# Attacker at (-2,0) with RNG=2, defender at (2,0) — distance 4 > 2
	var result := TurnActions.execute_attack(state, Vector2i(2, 0))
	assert_true(result.has("error"), "attack out of range should fail")


func test_attack_no_los_fails() -> void:
	# Build a map with trees blocking LoS
	var map := MapData.new()
	map.id = "test_los"
	var tiles: Array[TileRecord] = []
	tiles.append(TileRecord.new(0, 0, 0, "grass"))
	tiles.append(TileRecord.new(1, 0, 0, "trees"))
	tiles.append(TileRecord.new(2, 0, 0, "grass"))
	map.tiles = tiles

	var atk := _make_unit("atk", "playerA", 3, 10, 2, 3, 1)	# RNG=3
	var def := _make_unit("def", "playerB")
	var party_a: Array[BattleUnit] = [atk]
	var party_b: Array[BattleUnit] = [def]
	var state := MatchSetup.create(party_a, party_b, map, _stub_terrain)

	atk.position = Vector2i(0, 0)
	state.occupancy[Vector2i(0, 0)] = atk
	def.position = Vector2i(2, 0)
	state.occupancy[Vector2i(2, 0)] = def

	state.phase = MatchState.Phase.UNIT_TURN
	state.current_unit = atk
	atk.ap_remaining = 2

	var result := TurnActions.execute_attack(state, Vector2i(2, 0))
	assert_true(result.has("error"), "attack with no LoS should fail")


func test_attack_with_no_ap_fails() -> void:
	var state := _adjacent_state()
	state.current_unit.ap_remaining = 0
	var result := TurnActions.execute_attack(state, Vector2i(1, 0))
	assert_true(result.has("error"))


func test_attack_records_action() -> void:
	var state := _adjacent_state()
	TurnActions.execute_attack(state, Vector2i(1, 0))
	assert_eq(state.turn_log.size(), 1)
	assert_eq(state.turn_log[0]["action"], "attack")


# --- Defend tests ---

func test_defend_pushes_modifier() -> void:
	var state := _adjacent_state()
	var base_def: int = state.current_unit.stats.effective("def")
	var result := TurnActions.execute_defend(state)
	assert_false(result.has("error"))
	assert_eq(state.current_unit.stats.effective("def"), base_def + 2)
	assert_eq(state.current_unit.ap_remaining, 1)


func test_defend_with_no_ap_fails() -> void:
	var state := _adjacent_state()
	state.current_unit.ap_remaining = 0
	var result := TurnActions.execute_defend(state)
	assert_true(result.has("error"))


func test_defend_modifier_removed_at_round_start() -> void:
	var state := _adjacent_state()
	TurnActions.execute_defend(state)
	var base_def: int = state.current_unit.stats.base("def")
	# Simulate round start
	state.current_unit.stats.remove_modifiers_by_source("defend")
	assert_eq(state.current_unit.stats.effective("def"), base_def)


func test_defend_records_action() -> void:
	var state := _adjacent_state()
	TurnActions.execute_defend(state)
	assert_eq(state.turn_log.size(), 1)
	assert_eq(state.turn_log[0]["action"], "defend")


# --- Wait tests ---

func test_wait_sets_ap_to_zero() -> void:
	var state := _adjacent_state()
	var result := TurnActions.execute_wait(state)
	assert_false(result.has("error"))
	assert_eq(state.current_unit.ap_remaining, 0)


func test_wait_records_forfeited_ap() -> void:
	var state := _adjacent_state()
	TurnActions.execute_wait(state)
	assert_eq(state.turn_log[0]["ap_forfeited"], 2)


func test_wait_with_one_ap_records_one() -> void:
	var state := _adjacent_state()
	state.current_unit.ap_remaining = 1
	TurnActions.execute_wait(state)
	assert_eq(state.turn_log[0]["ap_forfeited"], 1)


# --- Use Item tests ---

func test_use_item_valid_item_succeeds() -> void:
	var state := _adjacent_state()
	# Unit has "sword" in equipment (set in _make_unit)
	var result := TurnActions.execute_use_item(state, "sword", Vector2i(1, 0))
	assert_false(result.has("error"))
	assert_eq(state.current_unit.ap_remaining, 1)


func test_use_item_unknown_item_fails() -> void:
	var state := _adjacent_state()
	var result := TurnActions.execute_use_item(state, "nonexistent", Vector2i(1, 0))
	assert_true(result.has("error"))


func test_use_item_with_no_ap_fails() -> void:
	var state := _adjacent_state()
	state.current_unit.ap_remaining = 0
	var result := TurnActions.execute_use_item(state, "sword", Vector2i(1, 0))
	assert_true(result.has("error"))


# --- Ability tests (without autoload, using ability_provider) ---

func _stub_ability_provider(unit: BattleUnit, ability_id: String) -> AbilityData:
	if ability_id == "fire_1" and "fire_1" in unit.character.abilities:
		var a := AbilityData.new()
		a.id = "fire_1"
		a.ap_cost = 1
		a.wp_cost = 2
		a.ability_range = 3
		return a
	if ability_id == "fire_2" and "fire_2" in unit.character.abilities:
		var a := AbilityData.new()
		a.id = "fire_2"
		a.ap_cost = 2
		a.wp_cost = 3
		a.ability_range = 4
		return a
	return null


func _ability_state() -> MatchState:
	var map := MapData.new()
	map.id = "test_ability"
	var tiles: Array[TileRecord] = []
	for c in Hex.hexes_in_range(Vector2i(0, 0), 5):
		tiles.append(TileRecord.new(c.x, c.y, 0, "grass"))
	map.tiles = tiles

	var caster := _make_unit("caster", "playerA", 3, 12, 0, 0, 0, 10)
	caster.character.abilities = ["fire_1", "fire_2"]
	var target := _make_unit("target", "playerB")
	target.position = Vector2i(2, 0)

	var party_a: Array[BattleUnit] = [caster]
	var party_b: Array[BattleUnit] = [target]
	var state := MatchSetup.create(party_a, party_b, map, _stub_terrain)

	caster.position = Vector2i(0, 0)
	state.occupancy[Vector2i(0, 0)] = caster
	state.occupancy[Vector2i(2, 0)] = target

	state.ability_provider = _stub_ability_provider
	state.phase = MatchState.Phase.UNIT_TURN
	state.current_unit = caster
	caster.ap_remaining = 2
	return state


func test_ability_in_range_succeeds() -> void:
	var state := _ability_state()
	var result := TurnActions.execute_ability(state, "fire_1", Vector2i(2, 0))
	assert_false(result.has("error"), "ability in range should succeed")
	assert_eq(state.current_unit.ap_remaining, 1)


func test_ability_out_of_range_fails() -> void:
	var state := _ability_state()
	# Target at distance 5, fire_1 range is 3
	var far := _make_unit("far", "playerB")
	far.position = Vector2i(5, 0)
	state.occupancy[Vector2i(5, 0)] = far
	var result := TurnActions.execute_ability(state, "fire_1", Vector2i(5, 0))
	assert_true(result.has("error"), "ability out of range should fail")


func test_ability_unknown_fails() -> void:
	var state := _ability_state()
	var result := TurnActions.execute_ability(state, "ice_1", Vector2i(2, 0))
	assert_true(result.has("error"), "ability not owned should fail")


func test_ability_costs_2ap() -> void:
	var state := _ability_state()
	var result := TurnActions.execute_ability(state, "fire_2", Vector2i(2, 0))
	assert_false(result.has("error"), "2-AP ability with 2 AP should succeed")
	assert_eq(state.current_unit.ap_remaining, 0)


func test_ability_insufficient_ap_fails() -> void:
	var state := _ability_state()
	state.current_unit.ap_remaining = 1
	var result := TurnActions.execute_ability(state, "fire_2", Vector2i(2, 0))
	assert_true(result.has("error"), "2-AP ability with 1 AP should fail")


func test_ability_records_action() -> void:
	var state := _ability_state()
	TurnActions.execute_ability(state, "fire_1", Vector2i(2, 0))
	assert_eq(state.turn_log.size(), 1)
	assert_eq(state.turn_log[0]["action"], "ability")
	assert_eq(state.turn_log[0]["ability"], "fire_1")
	assert_eq(state.turn_log[0]["ap_spent"], 1)


# --- Willpower (WP) tests ---

func test_ability_deducts_wp() -> void:
	var state := _ability_state()
	var wp_before: int = state.current_unit.current_wp
	TurnActions.execute_ability(state, "fire_1", Vector2i(2, 0))
	assert_eq(state.current_unit.current_wp, wp_before - 2)


func test_ability_insufficient_wp_fails() -> void:
	var state := _ability_state()
	state.current_unit.current_wp = 1  # fire_1 costs 2 WP
	var result := TurnActions.execute_ability(state, "fire_1", Vector2i(2, 0))
	assert_true(result.has("error"), "ability with insufficient WP should fail")
	assert_string_contains(result["error"], "WP")


func test_attack_does_not_cost_wp() -> void:
	var state := _adjacent_state()
	state.current_unit.current_wp = 5
	var wp_before: int = state.current_unit.current_wp
	TurnActions.execute_attack(state, Vector2i(1, 0))
	assert_eq(state.current_unit.current_wp, wp_before, "attack should not cost WP")


func test_use_item_deducts_wp() -> void:
	var state := _adjacent_state()
	var unit := state.current_unit
	unit.current_wp = 5
	# Wire an item provider with a granted ability that costs WP
	var smoke := ItemData.new()
	smoke.id = "smoke_bomb_pouch"
	smoke.slot = "accessory"
	smoke.granted_abilities = ["smoke_bomb"]
	unit.character.equipment = ["smoke_bomb_pouch"]
	state.item_provider = func(id: String) -> ItemData:
		if id == "smoke_bomb_pouch": return smoke
		return null
	var sb_ability := AbilityData.new()
	sb_ability.id = "smoke_bomb"
	sb_ability.ap_cost = 1
	sb_ability.wp_cost = 1
	sb_ability.ability_range = 2
	sb_ability.effect = { "effect_type": "status", "status_id": "blind", "duration": 2 }
	state.ability_provider = func(_u: BattleUnit, aid: String) -> AbilityData:
		if aid == "smoke_bomb": return sb_ability
		return null
	var result := TurnActions.execute_use_item(state, "smoke_bomb_pouch", Vector2i(1, 0))
	assert_false(result.has("error"), "use item should succeed: %s" % str(result))
	assert_eq(unit.current_wp, 4, "WP should be deducted by item ability cost")


# --- No active unit tests ---

func test_no_active_unit_move_fails() -> void:
	var state := _adjacent_state()
	state.current_unit = null
	var result := TurnActions.execute_move(state, Vector2i(0, 1))
	assert_true(result.has("error"))


func test_no_active_unit_attack_fails() -> void:
	var state := _adjacent_state()
	state.current_unit = null
	var result := TurnActions.execute_attack(state, Vector2i(1, 0))
	assert_true(result.has("error"))


func test_no_active_unit_defend_fails() -> void:
	var state := _adjacent_state()
	state.current_unit = null
	var result := TurnActions.execute_defend(state)
	assert_true(result.has("error"))


func test_no_active_unit_wait_fails() -> void:
	var state := _adjacent_state()
	state.current_unit = null
	var result := TurnActions.execute_wait(state)
	assert_true(result.has("error"))
