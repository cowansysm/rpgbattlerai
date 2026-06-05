class_name TurnActions
extends RefCounted
## Validates and executes actions for the active unit during its turn.
## Each method checks preconditions (AP, range, LoS, occupancy), resolves
## effects via CombatResolver, and returns an action record Dictionary.
## A record with an "error" key indicates failure.
## Spec reference: phase4-spec.md §5, phase5-spec.md §4


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

	# Blind check: attack misses but still costs AP
	if unit.has_status("blind"):
		unit.ap_remaining -= 1
		var miss_record := {
			"action": "attack",
			"actor": unit.character.id,
			"target": target.character.id,
			"target_pos": target_pos,
			"missed": true,
			"reason": "blind",
		}
		state.turn_log.append(miss_record)
		return miss_record

	# Resolve damage
	var weapon_power: int = CombatResolver.get_weapon_power(unit, state.item_provider)
	var attacker_elev: int = state.graph.elevation(unit.position)
	var target_elev: int = state.graph.elevation(target_pos)
	var target_cover: int = state.graph.terrain_props(target_pos).cover
	var is_ranged: bool = rng > 1

	unit.ap_remaining -= 1

	var result := CombatResolver.resolve_attack(
		unit, target, weapon_power,
		attacker_elev, target_elev, target_cover, is_ranged)

	var record := {
		"action": "attack",
		"actor": unit.character.id,
		"target": target.character.id,
		"target_pos": target_pos,
		"damage": result["damage"],
		"target_hp_after": result["target_hp_after"],
		"is_downed": result["is_downed"],
	}

	if result["is_downed"]:
		_handle_downing(state, target)

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

	# Self-targeted abilities (range 0): target_pos must be caster position
	if ability.ability_range == 0:
		if target_pos != unit.position:
			return { "error": "Self-targeted ability must target caster position" }
	else:
		if RangeQuery.effective_range(unit.position, target_pos, state.graph) > ability.ability_range:
			return { "error": "Target out of ability range" }
		if not LineOfSight.has_los(state.graph, unit.position, target_pos):
			return { "error": "No line of sight to target" }

	unit.ap_remaining -= ability.ap_cost

	# Resolve effect on affected units
	var effect: Dictionary = ability.effect
	var effect_type: String = str(effect.get("effect_type", ""))
	var affected: Array = _collect_affected_units(state, target_pos, ability.area)

	var outcomes: Array = []
	for affected_unit: BattleUnit in affected:
		var outcome := _resolve_effect(
			state, unit, affected_unit, effect, effect_type, ability)
		outcomes.append(outcome)

	var record := {
		"action": "ability",
		"actor": unit.character.id,
		"ability": ability_id,
		"target_pos": target_pos,
		"ap_spent": ability.ap_cost,
		"outcomes": outcomes,
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

	# Look up the item and its granted ability
	var ability: AbilityData = null
	if state.item_provider.is_valid():
		var item: ItemData = state.item_provider.call(item_id)
		if item and not item.granted_abilities.is_empty():
			ability = _resolve_ability(state, unit, item.granted_abilities[0])

	unit.ap_remaining -= 1

	if ability:
		# Resolve the item's granted ability effect
		var effect: Dictionary = ability.effect
		var effect_type: String = str(effect.get("effect_type", ""))
		var affected: Array = _collect_affected_units(state, target_pos, ability.area)

		var outcomes: Array = []
		for affected_unit: BattleUnit in affected:
			var outcome := _resolve_effect(
				state, unit, affected_unit, effect, effect_type, ability)
			outcomes.append(outcome)

		var record := {
			"action": "use_item",
			"actor": unit.character.id,
			"item": item_id,
			"target_pos": target_pos,
			"outcomes": outcomes,
		}
		state.turn_log.append(record)
		return record

	# No resolvable ability — structural record only
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


static func _handle_downing(state: MatchState, unit: BattleUnit) -> void:
	## Remove a downed unit from occupancy.
	state.occupancy.erase(unit.position)


static func _collect_affected_units(
	state: MatchState, target_pos: Vector2i, area: Dictionary
) -> Array:
	## Collect all units affected by an ability at target_pos with the given area.
	## Single-target if no area; burst collects all units within radius.
	if area.is_empty() or not area.has("shape"):
		var u := state.unit_at(target_pos)
		return [u] if u else []

	if str(area.get("shape", "")) == "burst":
		var radius: int = int(area.get("radius", 0))
		var units: Array = []
		for hex in Hex.hexes_in_range(target_pos, radius):
			var u := state.unit_at(hex)
			if u:
				units.append(u)
		return units

	# Unknown shape — fall back to single target
	var u := state.unit_at(target_pos)
	return [u] if u else []


static func _resolve_effect(
	state: MatchState,
	caster: BattleUnit,
	target: BattleUnit,
	effect: Dictionary,
	effect_type: String,
	ability: AbilityData,
) -> Dictionary:
	## Dispatch to the correct CombatResolver method based on effect_type.
	var attacker_elev: int = state.graph.elevation(caster.position)
	var target_elev: int = state.graph.elevation(target.position)

	match effect_type:
		"damage":
			var value: int = int(effect.get("value", 0))
			var result := CombatResolver.resolve_damage(
				caster, target, value, ability.type,
				attacker_elev, target_elev)
			if result["is_downed"]:
				_handle_downing(state, target)
			var outcome := {
				"target": target.character.id,
				"damage": result["damage"],
				"target_hp_after": result["target_hp_after"],
				"is_downed": result["is_downed"],
			}
			if effect.has("element"):
				outcome["element"] = effect["element"]
			return outcome

		"heal":
			var value: int = int(effect.get("value", 0))
			var result := CombatResolver.resolve_heal(target, value)
			return {
				"target": target.character.id,
				"healing": result["healing"],
				"target_hp_after": result["target_hp_after"],
			}

		"buff":
			var stat: String = str(effect.get("stat", ""))
			var value: int = int(effect.get("value", 0))
			var duration: int = int(effect.get("duration", 1))
			var result := CombatResolver.resolve_buff(
				target, stat, value, ability.id)
			# Register buff duration for round-start cleanup
			state.buff_durations.append({
				"source_tag": result["source_tag"],
				"unit": target,
				"remaining": duration,
			})
			return {
				"target": target.character.id,
				"buff_stat": result["buff_stat"],
				"buff_value": result["buff_value"],
				"buff_duration": duration,
			}

		"status":
			var status_id: String = str(effect.get("status_id", ""))
			var duration: int = int(effect.get("duration", 1))
			var result := CombatResolver.resolve_status(
				target, status_id, duration, ability.id)
			return {
				"target": target.character.id,
				"status_id": result["status_id"],
				"status_duration": result["status_duration"],
				"refreshed": result["refreshed"],
			}

	# Unknown effect type — return empty outcome
	return { "target": target.character.id, "effect_type": effect_type }
