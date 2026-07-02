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
	var jump: int = unit.stats.effective("jump")
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
	unit.has_moved = true

	# Alpha A0: apply terrain effects on entering the destination tile
	_apply_terrain_modifiers(unit, state.graph, destination)
	var terrain_outcomes: Array = _apply_enter_effects(state, unit, destination)

	var record := {
		"action": "move",
		"actor": unit.character.id,
		"from": old_pos,
		"to": destination,
		"cost": int(reach[destination]),
	}
	if not terrain_outcomes.is_empty():
		record["terrain_effects"] = terrain_outcomes
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
	if target.is_downed:
		return { "error": "Cannot attack downed unit" }
	if target.team == unit.team:
		return { "error": "Cannot attack friendly unit" }

	var rng: int = unit.stats.effective("rng")
	var dist: int = RangeQuery.effective_range(unit.position, target_pos, state.graph)
	if dist > rng:
		return { "error": "Target out of range" }
	# Ranged attacks (range > 1) cannot target adjacent hexes
	if rng > 1 and dist < 2:
		return { "error": "Target too close for ranged attack" }
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
	var target_cover: int = state.graph.effective_cover(target_pos)
	var is_ranged: bool = rng > 1

	unit.ap_remaining -= 1

	# A18: build dispatch context for passive reactions
	var attack_ctx := {"state": state}

	var result := CombatResolver.resolve_attack(
		unit, target, weapon_power,
		attacker_elev, target_elev, target_cover, is_ranged,
		-1, -1, attack_ctx)

	var record := {
		"action": "attack",
		"actor": unit.character.id,
		"target": target.character.id,
		"target_pos": target_pos,
		"damage": result["damage"],
		"atk_roll": result["atk_roll"],
		"def_roll": result["def_roll"],
		"target_hp_after": result["target_hp_after"],
		"is_downed": result["is_downed"],
	}
	if result.has("reactions"):
		record["reactions"] = result["reactions"]

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
	# A18: apply Half WP multiplier (rounds up, min 0)
	var effective_wp_cost: int = _effective_wp_cost(unit, ability.wp_cost)
	if effective_wp_cost > 0 and unit.current_wp < effective_wp_cost:
		return { "error": "Not enough WP (need %d, have %d)" % [
			effective_wp_cost, unit.current_wp] }

	# Self-targeted abilities (range 0): target_pos must be caster position
	if ability.ability_range == 0:
		if target_pos != unit.position:
			return { "error": "Self-targeted ability must target caster position" }
	else:
		var ability_dist: int = RangeQuery.effective_range(unit.position, target_pos, state.graph)
		if ability_dist > ability.ability_range:
			return { "error": "Target out of ability range" }
		if not LineOfSight.has_los(state.graph, unit.position, target_pos):
			return { "error": "No line of sight to target" }

	unit.ap_remaining -= ability.ap_cost
	unit.current_wp -= effective_wp_cost

	# Resolve effect on affected units
	var effect: Dictionary = ability.effect
	var effect_type: String = str(effect.get("effect_type", ""))
	var affected: Array = _collect_affected_units(state, unit.position, target_pos, ability.area)

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

	unit.stats.push_modifier(StatModifier.new("def", 3, "defend"))
	unit.ap_remaining -= 1

	var record := {
		"action": "defend",
		"actor": unit.character.id,
		"modifier": "+3 DEF",
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

	if ability and ability.wp_cost > 0 and unit.current_wp < ability.wp_cost:
		return { "error": "Not enough WP (need %d, have %d)" % [
			ability.wp_cost, unit.current_wp] }

	unit.ap_remaining -= 1
	if ability:
		unit.current_wp -= ability.wp_cost

	if ability:
		# Resolve the item's granted ability effect
		var effect: Dictionary = ability.effect
		var effect_type: String = str(effect.get("effect_type", ""))
		var affected: Array = _collect_affected_units(state, unit.position, target_pos, ability.area)

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
	## Mark a unit as downed. Unit stays in occupancy (blocks hex).
	unit.is_downed = true
	unit.downed_round = state.round_number


static func _collect_affected_units(
	state: MatchState, caster_pos: Vector2i, target_pos: Vector2i, area: Dictionary
) -> Array:
	## Collect all units affected by an ability at target_pos with the given area.
	## Single-target if no area. Shapes: burst, line, cone, ring.
	## Directional shapes (line, cone) orient from caster toward target.
	if area.is_empty() or not area.has("shape"):
		var u := state.unit_at(target_pos)
		return [u] if u else []

	var shape: String = str(area.get("shape", ""))
	var hexes: Array[Vector2i] = []

	match shape:
		"burst":
			var radius: int = int(area.get("radius", 0))
			hexes = Hex.hexes_in_range(target_pos, radius)
		"line":
			var length: int = int(area.get("length", 1))
			var direction: int = Hex.direction_toward(caster_pos, target_pos)
			hexes = Hex.line_in_direction(target_pos, direction, length)
		"cone":
			var depth: int = int(area.get("depth", 1))
			var direction: int = Hex.direction_toward(caster_pos, target_pos)
			hexes = Hex.cone_in_direction(target_pos, direction, depth)
		"ring":
			var radius: int = int(area.get("radius", 1))
			hexes = Hex.ring(target_pos, radius)

	if hexes.is_empty():
		var u := state.unit_at(target_pos)
		return [u] if u else []

	var units: Array = []
	for hex in hexes:
		var u := state.unit_at(hex)
		if u:
			units.append(u)
	return units


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
			if target.is_downed:
				return { "target": target.character.id, "skipped": true, "reason": "downed" }
			var value: int = int(effect.get("value", 0))
			var element: String = str(effect.get("element", ""))
			# A16: Resolve terrain affinity weight at target position
			var terrain_aff_weight: int = 0
			if not element.is_empty() and state.graph:
				var tprops: TerrainProps = state.graph.terrain_props(target.position)
				if tprops:
					terrain_aff_weight = Affinity.tier_to_weight(
						str(tprops.affinities.get(element, "neutral")))
			var result := CombatResolver.resolve_damage(
				caster, target, value, ability.type,
				attacker_elev, target_elev, -1, ability.mag_scaling,
				element, terrain_aff_weight)
			if result["is_downed"]:
				_handle_downing(state, target)
			var outcome := {
				"target": target.character.id,
				"damage": result["damage"],
				"atk_roll": result["atk_roll"],
				"def_roll": result["def_roll"],
				"target_hp_after": result["target_hp_after"],
				"is_downed": result["is_downed"],
				"element": result.get("element", ""),
				"affinity": result.get("affinity", "neutral"),
				"is_crit": result.get("is_crit", false),
			}
			if result.has("healing"):
				outcome["healing"] = result["healing"]
			return outcome

		"heal":
			if target.is_downed:
				return { "target": target.character.id, "skipped": true, "reason": "downed" }
			var value: int = int(effect.get("value", 0))
			var result := CombatResolver.resolve_heal(target, value, caster, ability.mag_scaling)
			return {
				"target": target.character.id,
				"healing": result["healing"],
				"target_hp_after": result["target_hp_after"],
			}

		"buff":
			if target.is_downed:
				return { "target": target.character.id, "skipped": true, "reason": "downed" }
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
			if target.is_downed:
				return { "target": target.character.id, "skipped": true, "reason": "downed" }
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

		"revive":
			if not target.is_downed:
				return { "target": target.character.id, "skipped": true, "reason": "not_downed" }
			if target.team != caster.team:
				return { "target": target.character.id, "skipped": true, "reason": "enemy" }
			var value: int = int(effect.get("value", 1))
			var result := CombatResolver.resolve_revive(target, value)
			return {
				"target": target.character.id,
				"revived": true,
				"healing": result["healing"],
				"target_hp_after": result["target_hp_after"],
			}

	# Unknown effect type — return empty outcome
	return { "target": target.character.id, "effect_type": effect_type }


# --- Alpha A0: terrain effect helpers ---

static func _apply_terrain_modifiers(unit: BattleUnit, g: HexGraph, c: Vector2i) -> void:
	## Clear existing terrain modifiers and reapply from the destination tile.
	unit.stats.remove_modifiers_by_source("terrain")
	for m in g.occupant_modifiers(c):
		unit.stats.push_modifier(StatModifier.new(str(m["key"]), int(m["value"]), "terrain"))


static func _apply_enter_effects(state: MatchState, unit: BattleUnit, c: Vector2i) -> Array:
	## Apply damage_on_enter and status_on_enter from the destination tile.
	## A18: damage_on_enter is skipped when unit.ignores_hazards is true.
	## Returns an array of outcome dicts for the action record.
	var outcomes: Array = []
	var g: HexGraph = state.graph

	var dmg: int = g.damage_on_enter(c)
	if dmg > 0 and unit.current_hp > 0 and not unit.ignores_hazards:
		unit.current_hp = max(0, unit.current_hp - dmg)
		outcomes.append({"target": unit.character.id, "type": "terrain_damage", "amount": dmg,
			"target_hp_after": unit.current_hp})
		if unit.current_hp <= 0:
			_handle_downing(state, unit)

	var st: Dictionary = g.status_on_enter(c)
	if not st.is_empty() and unit.current_hp > 0:
		var status_id: String = str(st.get("status_id", ""))
		var duration: int = int(st.get("duration", 1))
		if not status_id.is_empty():
			CombatResolver.resolve_status(unit, status_id, duration, "terrain")
			outcomes.append({"target": unit.character.id, "type": "terrain_status",
				"status_id": status_id, "duration": duration})

	return outcomes


static func apply_terrain_modifiers_on_deploy(unit: BattleUnit, g: HexGraph) -> void:
	## Apply occupant modifiers for the unit's current position at deployment.
	_apply_terrain_modifiers(unit, g, unit.position)


## A18: Apply wp_cost_mult from a support passive (Half WP = 0.5).
## Rounds down, minimum 0.
static func _effective_wp_cost(unit: BattleUnit, base_cost: int) -> int:
	if base_cost <= 0:
		return 0
	return maxi(0, int(floor(float(base_cost) * unit.wp_cost_mult)))
