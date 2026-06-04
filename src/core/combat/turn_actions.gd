class_name TurnActions
extends RefCounted
## Validates and executes actions for the active unit during its turn.
## Each method checks preconditions (AP, range, LoS, occupancy), mutates
## BattleUnit state, and returns an action record Dictionary.
## A record with an "error" key indicates failure.
## Phase 4: Attack/Ability log records only — no damage resolution.
## Spec reference: phase4-spec.md §5


static func execute_move(state: MatchState, destination: Vector2i) -> Dictionary:
	var unit: BattleUnit = state.current_unit
	if not unit:
		return { "error": "No active unit" }
	if unit.ap_remaining < 1:
		return { "error": "Not enough AP" }

	var move: int = unit.stats.effective_move()
	var jump: int = unit.stats.effective_jump_climb()
	var reach := Movement.reachable(state.graph, unit.position, move, jump)

	# Filter out tiles occupied by other units
	for pos in state.occupancy.keys():
		if pos != unit.position and reach.has(pos):
			reach.erase(pos)

	if not reach.has(destination):
		return { "error": "Destination not reachable" }

	var old_pos: Vector2i = unit.position
	state.occupancy.erase(old_pos)
	unit.position = destination
	state.occupancy[destination] = unit
	unit.ap_remaining -= 1

	var record := {
		"action": "move",
		"actor": unit.character.id,
		"from": old_pos,
		"to": destination,
		"cost": int(reach[destination]),
	}
	state.turn_log.append(record)
	return record


static func execute_attack(state: MatchState, target_pos: Vector2i) -> Dictionary:
	var unit: BattleUnit = state.current_unit
	if not unit:
		return { "error": "No active unit" }
	if unit.ap_remaining < 1:
		return { "error": "Not enough AP" }

	var target: BattleUnit = state.unit_at(target_pos)
	if not target:
		return { "error": "No target at position" }
	if target.team == unit.team:
		return { "error": "Cannot attack friendly unit" }

	var rng: int = unit.stats.effective("rng")
	if RangeQuery.effective_range(unit.position, target_pos, state.graph) > rng:
		return { "error": "Target out of range" }
	if not LineOfSight.has_los(state.graph, unit.position, target_pos):
		return { "error": "No line of sight to target" }

	unit.ap_remaining -= 1

	var record := {
		"action": "attack",
		"actor": unit.character.id,
		"target": target.character.id,
		"target_pos": target_pos,
	}
	state.turn_log.append(record)
	return record


static func execute_ability(
	state: MatchState, ability_id: String, target_pos: Vector2i
) -> Dictionary:
	var unit: BattleUnit = state.current_unit
	if not unit:
		return { "error": "No active unit" }

	var ability: AbilityData = _resolve_ability(state, unit, ability_id)
	if not ability:
		return { "error": "Unit does not have ability '%s'" % ability_id }
	if unit.ap_remaining < ability.ap_cost:
		return { "error": "Not enough AP (need %d, have %d)" % [
			ability.ap_cost, unit.ap_remaining] }

	if RangeQuery.effective_range(unit.position, target_pos, state.graph) > ability.ability_range:
		return { "error": "Target out of ability range" }
	if not LineOfSight.has_los(state.graph, unit.position, target_pos):
		return { "error": "No line of sight to target" }

	unit.ap_remaining -= ability.ap_cost

	var record := {
		"action": "ability",
		"actor": unit.character.id,
		"ability": ability_id,
		"target_pos": target_pos,
		"ap_spent": ability.ap_cost,
	}
	state.turn_log.append(record)
	return record


static func execute_defend(state: MatchState) -> Dictionary:
	var unit: BattleUnit = state.current_unit
	if not unit:
		return { "error": "No active unit" }
	if unit.ap_remaining < 1:
		return { "error": "Not enough AP" }

	unit.stats.push_modifier(StatModifier.new("def", 2, "defend"))
	unit.ap_remaining -= 1

	var record := {
		"action": "defend",
		"actor": unit.character.id,
		"modifier": "+2 DEF",
	}
	state.turn_log.append(record)
	return record


static func execute_wait(state: MatchState) -> Dictionary:
	var unit: BattleUnit = state.current_unit
	if not unit:
		return { "error": "No active unit" }

	var record := {
		"action": "wait",
		"actor": unit.character.id,
		"ap_forfeited": unit.ap_remaining,
	}
	unit.ap_remaining = 0
	state.turn_log.append(record)
	return record


static func execute_use_item(
	state: MatchState, item_id: String, target_pos: Vector2i
) -> Dictionary:
	var unit: BattleUnit = state.current_unit
	if not unit:
		return { "error": "No active unit" }
	if unit.ap_remaining < 1:
		return { "error": "Not enough AP" }

	if item_id not in unit.character.equipment:
		return { "error": "Unit does not have item '%s'" % item_id }

	unit.ap_remaining -= 1

	var record := {
		"action": "use_item",
		"actor": unit.character.id,
		"item": item_id,
		"target_pos": target_pos,
	}
	state.turn_log.append(record)
	return record


# --- Helpers ---

static func _resolve_ability(
	state: MatchState, unit: BattleUnit, ability_id: String
) -> AbilityData:
	## Resolve an ability for a unit via the injected ability_provider.
	if state.ability_provider.is_valid():
		return state.ability_provider.call(unit, ability_id)
	return null
