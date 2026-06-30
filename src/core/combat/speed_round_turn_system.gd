class_name SpeedRoundTurnSystem
extends TurnSystem
## Four-stage single-player speed-round turn system.
## Stages: AI_PLANNING → PLAYER_PLANNING → RESOLUTION → ROUND_RESET.
## Actions resolve in descending SPD order with a validity policy for
## plans invalidated by earlier resolutions (fizzle / stop-short).
## Spec reference: alpha-phaseA15-spec.md §1, §2


enum Stage { AI_PLANNING, PLAYER_PLANNING, RESOLUTION, ROUND_RESET }


var _stage: int = Stage.AI_PLANNING
var _round_plan: RoundPlan = RoundPlan.new()
var _resolution_queue: Array = []  # sorted entries from RoundPlan
var _resolution_index: int = 0
var _tie_seed: int = 0
var _first_team_wins_ties: String = ""  # A13 hook: team that wins SPD ties in round 1
var _intents: Array = []  # Array[IntentPlan] — telegraphed AI plans


func begin_round(state: MatchState) -> void:
	RoundManager.do_round_start_bookkeeping(state)
	_round_plan.clear()
	_resolution_queue.clear()
	_resolution_index = 0
	_intents.clear()
	_stage = Stage.AI_PLANNING
	state.phase = MatchState.Phase.AI_PLANNING


func is_round_complete(_state: MatchState) -> bool:
	return _stage == Stage.ROUND_RESET


func advance(state: MatchState) -> void:
	match _stage:
		Stage.AI_PLANNING:
			_stage = Stage.PLAYER_PLANNING
			state.phase = MatchState.Phase.PLAYER_PLANNING
		Stage.PLAYER_PLANNING:
			_build_resolution_queue()
			_stage = Stage.RESOLUTION
			state.phase = MatchState.Phase.RESOLUTION
		Stage.RESOLUTION:
			pass  # Resolution is driven by resolve_next()
		Stage.ROUND_RESET:
			pass  # Controller handles starting the next round


func wants_telegraph() -> bool:
	return true


# --- Stage-specific methods ---

## Commit AI plans for all AI units at once.
func commit_ai_plans(plans: Dictionary, units: Array) -> void:
	for unit: BattleUnit in units:
		var plan: AIPlan = plans.get(unit.character.id)
		if plan:
			_round_plan.commit(unit, plan)


## Commit a single player unit's plan.
func commit_player_plan(unit: BattleUnit, plan: AIPlan) -> void:
	_round_plan.commit(unit, plan)


func get_intents() -> Array:
	return _intents


func set_intents(intents: Array) -> void:
	_intents = intents


func current_stage() -> int:
	return _stage


func get_round_plan() -> RoundPlan:
	return _round_plan


## Returns true if there are more units to resolve in the current round.
func has_next_resolution() -> bool:
	return _stage == Stage.RESOLUTION and _resolution_index < _resolution_queue.size()


## Resolve the next unit's plan in SPD order.
## Sets state.current_unit, executes steps via TurnActions with validity policy,
## then clears current_unit.
## Returns a result dict: {unit_id, results, [fizzled, reason]}.
func resolve_next(state: MatchState) -> Dictionary:
	if _resolution_index >= _resolution_queue.size():
		_stage = Stage.ROUND_RESET
		return {"done": true}

	var entry: Dictionary = _resolution_queue[_resolution_index]
	_resolution_index += 1
	var unit: BattleUnit = entry["unit"]
	var plan: AIPlan = entry["plan"]

	# Skip dead/downed units — their planned action fizzles silently
	if unit.current_hp <= 0 or unit.is_downed:
		return {"fizzled": true, "reason": "unit_dead", "unit_id": unit.character.id}

	# Set up the unit for its resolution turn
	state.current_unit = unit
	unit.ap_remaining = unit.base_ap
	unit.has_moved = false
	state.turn_log = []

	# Clear defend modifier from previous round
	unit.stats.remove_modifiers_by_source("defend")

	# Apply per-turn terrain damage at the start of this unit's resolution
	var terrain_outcomes: Array = RoundManager.on_activation_start(state, unit)

	# If downed by terrain damage, fizzle
	if unit.current_hp <= 0 or unit.is_downed:
		state.match_log.append_array(state.turn_log)
		state.current_unit = null
		return {
			"unit_id": unit.character.id,
			"fizzled": true,
			"reason": "terrain_downed",
			"terrain_effects": terrain_outcomes,
		}

	var results: Array = []
	if not terrain_outcomes.is_empty():
		results.append_array(terrain_outcomes)

	for step in plan.steps:
		var kind: String = str(step.get("kind", ""))
		var result: Dictionary
		match kind:
			"move":
				result = _resolve_move(state, unit, step)
			"attack":
				result = _resolve_attack(state, unit, step)
			"ability":
				result = _resolve_ability(state, unit, step)
			"defend":
				result = TurnActions.execute_defend(state)
			"wait":
				result = TurnActions.execute_wait(state)
			"use_item":
				result = _resolve_use_item(state, unit, step)
			_:
				result = TurnActions.execute_wait(state)
		results.append(result)

	# Mark unit as activated and flush logs
	unit.is_activated = true
	state.match_log.append_array(state.turn_log)
	state.current_unit = null

	# Check if resolution is complete
	if _resolution_index >= _resolution_queue.size():
		_stage = Stage.ROUND_RESET

	return {"unit_id": unit.character.id, "results": results}


# --- Validity policy (the mechanical heart) ---

## Move: walk path tile-by-tile; stop short on first occupied/blocked tile.
func _resolve_move(state: MatchState, unit: BattleUnit, step: Dictionary) -> Dictionary:
	var dest: Vector2i = step.get("target_pos", unit.position)
	if dest == unit.position:
		return {"action": "move", "actor": unit.character.id, "skipped": true}

	# Compute the path from current position to planned destination
	var jump: int = unit.stats.effective("jump")
	var move_path: Array = Movement.path(state.graph, unit.position, dest, jump)

	if move_path.is_empty() or move_path.size() <= 1:
		# Can't even start moving — fizzle the move (AP spent)
		unit.ap_remaining -= 1
		var record := {
			"action": "move",
			"actor": unit.character.id,
			"fizzled": true,
			"reason": "path_blocked",
		}
		state.turn_log.append(record)
		return record

	# Walk the path and find the furthest reachable tile (stop short on occupied)
	var furthest: Vector2i = unit.position
	for i in range(1, move_path.size()):
		var tile: Vector2i = move_path[i]
		if state.is_occupied(tile) and state.unit_at(tile) != unit:
			break  # Stop short — tile is now occupied
		furthest = tile

	if furthest == unit.position:
		# Can't move at all — fizzle (AP spent)
		unit.ap_remaining -= 1
		var record := {
			"action": "move",
			"actor": unit.character.id,
			"fizzled": true,
			"reason": "blocked_by_unit",
		}
		state.turn_log.append(record)
		return record

	# Execute the move to the furthest reachable tile
	return TurnActions.execute_move(state, furthest)


## Attack: check target alive + in range/LoS from current position; fizzle if invalid.
func _resolve_attack(state: MatchState, unit: BattleUnit, step: Dictionary) -> Dictionary:
	var target_pos: Vector2i = step.get("target_pos", Vector2i.MAX)
	var target: BattleUnit = state.unit_at(target_pos)

	# Validity check: target must be alive, in range, and in LoS
	if not target or target.current_hp <= 0 or target.is_downed:
		return _fizzle_action(state, unit, "attack", 1, 0, "target_gone")
	if target.team == unit.team:
		return _fizzle_action(state, unit, "attack", 1, 0, "friendly_fire")

	var rng: int = unit.stats.effective("rng")
	var dist: int = RangeQuery.effective_range(unit.position, target_pos, state.graph)
	if dist > rng:
		return _fizzle_action(state, unit, "attack", 1, 0, "out_of_range")
	if rng > 1 and dist < 2:
		return _fizzle_action(state, unit, "attack", 1, 0, "too_close")
	if not LineOfSight.has_los(state.graph, unit.position, target_pos):
		return _fizzle_action(state, unit, "attack", 1, 0, "no_los")

	# Valid — execute normally
	return TurnActions.execute_attack(state, target_pos)


## Ability: single-target fizzles if target gone; ground AoE resolves on tile.
func _resolve_ability(state: MatchState, unit: BattleUnit, step: Dictionary) -> Dictionary:
	var ability_id: String = str(step.get("ability_id", ""))
	var target_pos: Vector2i = step.get("target_pos", Vector2i.MAX)
	var ap_cost: int = int(step.get("ap_cost", 1))

	# Resolve the ability data
	var ability: AbilityData = null
	if state.ability_provider.is_valid():
		ability = state.ability_provider.call(unit, ability_id)
	if not ability:
		return _fizzle_action(state, unit, "ability", ap_cost, 0, "ability_not_found")

	var wp_cost: int = ability.wp_cost

	# Check if it's an AoE (ground-targeted) vs single-target
	var is_aoe: bool = not ability.area.is_empty() and ability.area.has("shape")

	if not is_aoe:
		# Single-target: check target validity
		var target: BattleUnit = state.unit_at(target_pos)
		var effect_type: String = str(ability.effect.get("effect_type", ""))

		# For damage/status: target must be alive enemy
		if effect_type in ["damage", "status"]:
			if not target or target.current_hp <= 0 or target.is_downed:
				return _fizzle_action(state, unit, "ability", ap_cost, wp_cost, "target_gone")

		# For heal/buff: target must be alive ally
		elif effect_type in ["heal", "buff"]:
			if not target or target.current_hp <= 0:
				return _fizzle_action(state, unit, "ability", ap_cost, wp_cost, "target_gone")

		# For revive: target must be downed ally
		elif effect_type == "revive":
			if not target or not target.is_downed:
				return _fizzle_action(state, unit, "ability", ap_cost, wp_cost, "target_not_downed")

		# Range/LoS check from current position
		if ability.ability_range > 0:
			var dist: int = RangeQuery.effective_range(unit.position, target_pos, state.graph)
			if dist > ability.ability_range:
				return _fizzle_action(state, unit, "ability", ap_cost, wp_cost, "out_of_range")
			if not LineOfSight.has_los(state.graph, unit.position, target_pos):
				return _fizzle_action(state, unit, "ability", ap_cost, wp_cost, "no_los")

	# Ground-targeted AoE: always resolves on the tile (hits current occupants)
	# or single-target that passed validation
	return TurnActions.execute_ability(state, ability_id, target_pos)


## Use item: same validity logic as ability.
func _resolve_use_item(state: MatchState, unit: BattleUnit, step: Dictionary) -> Dictionary:
	var item_id: String = str(step.get("item_id", ""))
	var target_pos: Vector2i = step.get("target_pos", unit.position)
	return TurnActions.execute_use_item(state, item_id, target_pos)


## Create a fizzle record: AP/WP spent, action logged as fizzled.
func _fizzle_action(state: MatchState, unit: BattleUnit,
		action_type: String, ap_cost: int, wp_cost: int, reason: String) -> Dictionary:
	unit.ap_remaining = max(0, unit.ap_remaining - ap_cost)
	if wp_cost > 0:
		unit.current_wp = max(0, unit.current_wp - wp_cost)
	var record := {
		"action": action_type,
		"actor": unit.character.id,
		"fizzled": true,
		"reason": reason,
		"ap_spent": ap_cost,
		"wp_spent": wp_cost,
	}
	state.turn_log.append(record)
	return record


# --- Internal ---

func _build_resolution_queue() -> void:
	_resolution_queue = _round_plan.sorted_by_speed(_tie_seed, _first_team_wins_ties)
	_resolution_index = 0
