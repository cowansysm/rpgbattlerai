class_name AIPlanner
extends RefCounted
## Enumerates bounded, legal candidate plans for the active AI unit,
## scores them with AIScorer, and selects one with temperature sampling.
## Pure core — no scene-tree dependency.

const DEFAULT_MAX_TILES := 12


## Main entry point: plan an activation for the given unit.
## Returns an AIPlan ready for execution by AIController.
static func plan(
	state: MatchState, unit: BattleUnit,
	rng: RandomNumberGenerator, diff: Dictionary
) -> AIPlan:
	var max_tiles: int = int(diff.get("max_tiles", DEFAULT_MAX_TILES))
	var candidates := enumerate(state, unit, max_tiles)

	if candidates.is_empty():
		return AIPlan.make_wait()

	var w: Dictionary = diff.get("weights", _default_weights())
	var top_n: int = int(diff.get("top_n", 3))
	var temperature: float = float(diff.get("temperature", 1.0))

	return _select(candidates, state, unit, w, top_n, temperature, rng)


## Enumerate all bounded, legal candidate plans for the unit.
static func enumerate(state: MatchState, unit: BattleUnit, max_tiles: int) -> Array:
	var plans: Array = []
	var graph: HexGraph = state.graph
	var jump: int = unit.stats.effective("jump")
	var reach: Dictionary = Movement.reachable(graph, unit.position, unit.stats.effective_move(), jump)

	# Filter out tiles occupied by other units
	var reachable_tiles: Array = []
	for tile: Vector2i in reach.keys():
		if tile == unit.position or not state.is_occupied(tile):
			reachable_tiles.append(tile)

	# Prune to the most promising tiles
	var tiles: Array = _top_tiles(reachable_tiles, state, unit, max_tiles)

	# Ensure current position is always included
	if unit.position not in tiles:
		tiles.append(unit.position)

	# Get unit's available abilities
	var abilities: Array = _get_unit_abilities(state, unit)

	for tile: Vector2i in tiles:
		var is_stay: bool = (tile == unit.position)

		# Attack plans
		for target_pos: Vector2i in _legal_attack_targets(state, unit, tile):
			if is_stay:
				plans.append(AIPlan.make_attack_only(target_pos))
			else:
				plans.append(AIPlan.make_move_attack(tile, target_pos))

		# Ability plans
		for ability: AbilityData in abilities:
			# Check if we have enough AP: move (1) + ability.ap_cost must fit in 2
			var move_ap: int = 0 if is_stay else 1
			if move_ap + ability.ap_cost > unit.base_ap:
				continue
			for target_pos: Vector2i in _legal_ability_targets(state, unit, tile, ability):
				if is_stay:
					plans.append(AIPlan.make_ability_only(
						ability.id, target_pos, ability.ap_cost))
				else:
					plans.append(AIPlan.make_move_ability(
						tile, ability.id, target_pos, ability.ap_cost))

		# Move-only plans (reposition without acting)
		if not is_stay:
			plans.append(AIPlan.make_move_only(tile))

	# Fallbacks — always available
	plans.append(AIPlan.make_defend())
	plans.append(AIPlan.make_wait())

	return plans


# --- Legal-target helpers ---

static func _legal_attack_targets(
	state: MatchState, unit: BattleUnit, origin: Vector2i
) -> Array:
	## Returns positions of enemies the unit could legally attack from origin.
	## Mirrors TurnActions.execute_attack validation.
	var targets: Array = []
	var rng_stat: int = unit.stats.effective("rng")
	var enemy_team: String = state.other_team(unit.team)

	for enemy: BattleUnit in state.living_units(enemy_team):
		if enemy.is_downed:
			continue
		var dist: int = RangeQuery.effective_range(origin, enemy.position, state.graph)
		if dist > rng_stat:
			continue
		# Min range 2 for ranged weapons
		if rng_stat > 1 and dist < 2:
			continue
		if not LineOfSight.has_los(state.graph, origin, enemy.position):
			continue
		targets.append(enemy.position)

	return targets


static func _legal_ability_targets(
	state: MatchState, unit: BattleUnit, origin: Vector2i, ability: AbilityData
) -> Array:
	## Returns legal target positions for an ability used from origin.
	## Matches TurnActions.execute_ability validation + effect targeting rules.
	var targets: Array = []

	# Check WP cost
	if ability.wp_cost > 0 and unit.current_wp < ability.wp_cost:
		return targets

	# Self-targeted abilities (range 0)
	if ability.ability_range == 0:
		# Self-target: only valid at the caster's planned position
		var effect_type: String = str(ability.effect.get("effect_type", ""))
		# Self-buff/heal are useful; self-damage is not
		if effect_type in ["buff", "heal", "status"]:
			targets.append(origin)
		return targets

	var effect_type: String = str(ability.effect.get("effect_type", ""))

	# Determine valid target set based on effect type
	match effect_type:
		"damage":
			# Target enemy-occupied hexes (or AoE center near enemies)
			var enemy_team: String = state.other_team(unit.team)
			if ability.area.is_empty():
				# Single-target: must target an enemy
				for enemy: BattleUnit in state.living_units(enemy_team):
					if enemy.is_downed:
						continue
					var dist: int = RangeQuery.effective_range(origin, enemy.position, state.graph)
					if dist > ability.ability_range:
						continue
					if not LineOfSight.has_los(state.graph, origin, enemy.position):
						continue
					targets.append(enemy.position)
			else:
				# AoE: target positions near enemies for maximum hits
				_add_aoe_damage_targets(state, unit, origin, ability, targets)

		"heal", "revive":
			# Target friendly units
			for ally: BattleUnit in state.living_units(unit.team):
				if effect_type == "heal" and ally.is_downed:
					continue
				if effect_type == "revive" and not ally.is_downed:
					continue
				# Don't heal at full HP
				if effect_type == "heal" and ally.current_hp >= ally.stats.effective("hp"):
					continue
				var dist: int = RangeQuery.effective_range(origin, ally.position, state.graph)
				if dist > ability.ability_range:
					continue
				if not LineOfSight.has_los(state.graph, origin, ally.position):
					continue
				targets.append(ally.position)

		"buff":
			# Target friendly units (including self)
			for ally: BattleUnit in state.living_units(unit.team):
				if ally.is_downed:
					continue
				var dist: int = RangeQuery.effective_range(origin, ally.position, state.graph)
				if dist > ability.ability_range:
					continue
				if not LineOfSight.has_los(state.graph, origin, ally.position):
					continue
				targets.append(ally.position)

		"status":
			# Target enemies (debuffs)
			var enemy_team: String = state.other_team(unit.team)
			for enemy: BattleUnit in state.living_units(enemy_team):
				if enemy.is_downed:
					continue
				var dist: int = RangeQuery.effective_range(origin, enemy.position, state.graph)
				if dist > ability.ability_range:
					continue
				if not LineOfSight.has_los(state.graph, origin, enemy.position):
					continue
				targets.append(enemy.position)

	return targets


static func _add_aoe_damage_targets(
	state: MatchState, unit: BattleUnit, origin: Vector2i,
	ability: AbilityData, targets: Array
) -> void:
	## For AoE damage, find target positions that hit at least one enemy.
	## To keep enumeration bounded, only consider enemy positions as AoE centers.
	var enemy_team: String = state.other_team(unit.team)
	for enemy: BattleUnit in state.living_units(enemy_team):
		if enemy.is_downed:
			continue
		var dist: int = RangeQuery.effective_range(origin, enemy.position, state.graph)
		if dist > ability.ability_range:
			continue
		if not LineOfSight.has_los(state.graph, origin, enemy.position):
			continue
		if enemy.position not in targets:
			targets.append(enemy.position)


# --- Tile pruning ---

static func _top_tiles(
	tiles: Array, state: MatchState, unit: BattleUnit, max_count: int
) -> Array:
	## Score tiles by tactical promise and return the top max_count.
	if tiles.size() <= max_count:
		return tiles.duplicate()

	var enemy_team: String = state.other_team(unit.team)
	var enemies: Array = state.living_units(enemy_team)

	var scored: Array = []
	for tile: Vector2i in tiles:
		var tile_score := 0.0
		# Prefer tiles near enemies (proximity)
		var min_dist := 999
		for enemy: BattleUnit in enemies:
			var d: int = Hex.distance(tile, enemy.position)
			if d < min_dist:
				min_dist = d
		tile_score -= float(min_dist)
		# Bonus for cover and elevation
		tile_score += float(state.graph.effective_cover(tile)) * 2.0
		tile_score += float(state.graph.elevation(tile))
		# Penalty for hazards
		tile_score -= float(state.graph.damage_per_turn(tile)) * 3.0
		scored.append([tile_score, tile])

	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var result: Array = []
	for i in range(mini(max_count, scored.size())):
		result.append(scored[i][1])
	return result


# --- Ability access ---

static func _get_unit_abilities(_state: MatchState, unit: BattleUnit) -> Array:
	## Get all abilities the unit can use.
	## Mirrors AbilityResolver.all_abilities logic using GameData directly.
	var seen: Dictionary = {}
	var all: Array = []
	# Character abilities
	for ability_id in unit.character.abilities:
		if not seen.has(ability_id):
			var a: AbilityData = GameData.get_ability(ability_id)
			if a and a.is_active():
				all.append(a)
				seen[ability_id] = true
	# Class-granted abilities
	for cls_id in unit.character.classes:
		var cls: ClassData = GameData.get_job_class(cls_id)
		if cls:
			for ability_id in cls.granted_abilities:
				if not seen.has(ability_id):
					var a: AbilityData = GameData.get_ability(ability_id)
					if a and a.is_active():
						all.append(a)
						seen[ability_id] = true
	# Equipment-granted abilities
	for eq_id in unit.character.equipment:
		var item: ItemData = GameData.get_item(eq_id)
		if item:
			for ability_id in item.granted_abilities:
				if not seen.has(ability_id):
					var a: AbilityData = GameData.get_ability(ability_id)
					if a and a.is_active():
						all.append(a)
						seen[ability_id] = true
	return all


# --- Selection with temperature sampling ---

static func _select(
	candidates: Array, state: MatchState, unit: BattleUnit,
	w: Dictionary, top_n: int, temperature: float,
	rng: RandomNumberGenerator
) -> AIPlan:
	if candidates.is_empty():
		return AIPlan.make_wait()

	# Score all candidates
	var scored: Array = []  # [[score, plan], ...]
	for plan in candidates:
		var s: float = AIScorer.score(state, unit, plan as AIPlan, w)
		scored.append([s, plan])

	# Sort descending by score
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])

	# Take top N
	var n: int = mini(top_n, scored.size())
	var top: Array = scored.slice(0, n)

	if n == 1 or temperature <= 0.0:
		return top[0][1] as AIPlan

	# Temperature sampling: softmax-like weighting
	# Normalize scores relative to the best to avoid overflow
	var best_score: float = top[0][0]
	var weights: Array = []
	var total_weight := 0.0
	for entry in top:
		var diff: float = (entry[0] as float - best_score) / maxf(temperature, 0.01)
		var weight: float = exp(diff)
		weights.append(weight)
		total_weight += weight

	# Weighted random pick
	var roll: float = rng.randf() * total_weight
	var cumulative := 0.0
	for i in range(weights.size()):
		cumulative += weights[i]
		if roll <= cumulative:
			return top[i][1] as AIPlan

	# Fallback (rounding edge case)
	return top[0][1] as AIPlan


# --- Difficulty presets ---

static func difficulty_preset(name: String) -> Dictionary:
	match name:
		"easy":
			return {
				"top_n": 5,
				"temperature": 2.0,
				"max_tiles": 8,
				"weights": {
					"damage": 6.0, "kill": 15.0, "exposure": 1.0,
					"cover": 2.0, "elev": 1.0, "hazard": 4.0,
					"target": 4.0, "ability": 3.0, "resource": 1.0,
				},
			}
		"hard":
			return {
				"top_n": 2,
				"temperature": 0.3,
				"max_tiles": 16,
				"weights": {
					"damage": 12.0, "kill": 30.0, "exposure": 5.0,
					"cover": 6.0, "elev": 3.0, "hazard": 10.0,
					"target": 10.0, "ability": 8.0, "resource": 3.0,
				},
			}
		_:  # "normal"
			return {
				"top_n": 3,
				"temperature": 1.0,
				"max_tiles": 12,
				"weights": _default_weights(),
			}


static func _default_weights() -> Dictionary:
	return {
		"damage": 10.0, "kill": 25.0, "exposure": 3.0,
		"cover": 4.0, "elev": 2.0, "hazard": 8.0,
		"target": 8.0, "ability": 6.0, "resource": 2.0,
	}
