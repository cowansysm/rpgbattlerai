class_name AIScorer
extends RefCounted
## Deterministic utility scorer for AI candidate plans.
## Evaluates a plan by its predicted end state: damage/kills, exposure,
## positioning (cover/elevation/hazard), target priority, ability value,
## and resource economy.  Uses expected values (avg die = 3.5); no randomness.

const AVG_DIE := 3.5


static func score(
	state: MatchState, unit: BattleUnit, plan: AIPlan, w: Dictionary
) -> float:
	var s := 0.0
	var end_pos: Vector2i = _end_position(unit, plan)

	s += float(w.get("damage", 0.0))       * _expected_damage(state, unit, plan)
	s += float(w.get("kill", 0.0))         * _expected_kills(state, unit, plan)
	s -= float(w.get("exposure", 0.0))     * _exposure(state, unit, end_pos)
	s += float(w.get("cover", 0.0))        * float(state.graph.effective_cover(end_pos))
	s += float(w.get("elev", 0.0))         * float(state.graph.elevation(end_pos))
	s -= float(w.get("hazard", 0.0))       * float(state.graph.damage_per_turn(end_pos))
	s += float(w.get("target", 0.0))       * _target_value(state, unit, plan)
	s += float(w.get("ability", 0.0))      * _ability_value(state, unit, plan)
	s -= float(w.get("resource", 0.0))     * _resource_cost(unit, plan)
	# A18: penalise meleeing a unit with Counter equipped (suppressed when approach is REAR — safe)
	s -= float(w.get("counter_risk", 5.0)) * _counter_risk(state, unit, plan)
	# A19: penalise plans that leave own rear exposed to enemies
	s -= float(w.get("rear_exposure", 4.0)) * _rear_exposure(state, unit, plan)
	return s


# --- Position helpers ---

static func _end_position(unit: BattleUnit, plan: AIPlan) -> Vector2i:
	for step in plan.steps:
		if str(step.get("kind", "")) == "move":
			return step["target_pos"] as Vector2i
	return unit.position


# --- Damage / kill estimation ---

static func _expected_damage(state: MatchState, unit: BattleUnit, plan: AIPlan) -> float:
	var total := 0.0
	for step in plan.steps:
		var kind: String = str(step.get("kind", ""))
		if kind == "attack":
			total += _estimate_attack_damage(state, unit, plan, step)
		elif kind == "ability":
			total += _estimate_ability_damage(state, unit, plan, step)
	return total


static func _expected_kills(state: MatchState, unit: BattleUnit, plan: AIPlan) -> float:
	var kills := 0.0
	for step in plan.steps:
		var kind: String = str(step.get("kind", ""))
		if kind == "attack":
			var target: BattleUnit = state.unit_at(step["target_pos"] as Vector2i)
			if target and target.is_alive():
				var dmg := _estimate_attack_damage(state, unit, plan, step)
				if dmg >= float(target.current_hp):
					kills += 1.0
		elif kind == "ability":
			var ability: AbilityData = _get_ability(state, step)
			if ability and str(ability.effect.get("effect_type", "")) == "damage":
				var target: BattleUnit = state.unit_at(step["target_pos"] as Vector2i)
				if target and target.is_alive():
					var dmg := _estimate_ability_damage(state, unit, plan, step)
					if dmg >= float(target.current_hp):
						kills += 1.0
	return kills


static func _estimate_attack_damage(
	state: MatchState, unit: BattleUnit, plan: AIPlan, step: Dictionary
) -> float:
	var target: BattleUnit = state.unit_at(step["target_pos"] as Vector2i)
	if not target or not target.is_alive():
		return 0.0
	var origin := _end_position(unit, plan)
	var weapon_power: int = CombatResolver.get_weapon_power(unit, state.item_provider)
	var atk: int = unit.stats.effective("atk")
	var target_def: int = target.stats.effective("def")
	var elev_bonus := 0.0
	if state.graph.elevation(origin) > state.graph.elevation(target.position):
		elev_bonus = float(Constants.get_value("ELEV_BONUS", 2))
	# A19: arc-based damage bonus from plan end position vs target current facing
	var arc: int = Hex.arc_between(origin, target.position, target.facing)
	var f_bonus: float = float(FacingBonus.damage_bonus(arc))
	var raw := AVG_DIE + float(atk) + float(weapon_power) + elev_bonus + f_bonus - float(target_def)
	return maxf(1.0, raw)


static func _estimate_ability_damage(
	state: MatchState, unit: BattleUnit, plan: AIPlan, step: Dictionary
) -> float:
	var ability: AbilityData = _get_ability(state, step)
	if not ability:
		return 0.0
	var effect_type: String = str(ability.effect.get("effect_type", ""))
	if effect_type != "damage":
		return 0.0
	var effect_value: int = int(ability.effect.get("value", 0))
	var origin := _end_position(unit, plan)
	var target_pos: Vector2i = step["target_pos"] as Vector2i
	var elev_bonus := 0.0
	if state.graph.elevation(origin) > state.graph.elevation(target_pos):
		elev_bonus = float(Constants.get_value("ELEV_BONUS", 2))

	# A19: arc-based damage bonus from plan end position vs target current facing
	var target_unit: BattleUnit = state.unit_at(target_pos)
	var arc: int = Hex.Arc.FRONT
	if target_unit:
		arc = Hex.arc_between(origin, target_pos, target_unit.facing)
	var f_bonus: float = float(FacingBonus.damage_bonus(arc))
	var raw := AVG_DIE + float(effect_value) + elev_bonus + f_bonus
	if ability.type == "skill":
		var target_def: int = target_unit.stats.effective("def") if target_unit else 0
		raw -= float(target_def)
	else:
		# Spell: scales with MAG, reduced by RES
		var mag_bonus: float = ability.mag_scaling * float(unit.stats.effective("mag"))
		raw += mag_bonus
		var target_res: int = target_unit.stats.effective("res") if target_unit else 0
		raw -= float(target_res)
	return maxf(1.0, raw)


# --- Exposure ---

static func _exposure(state: MatchState, unit: BattleUnit, end_pos: Vector2i) -> float:
	## Count how many enemies could threaten the end position.
	var enemy_team: String = state.other_team(unit.team)
	var threats := 0.0
	for enemy: BattleUnit in state.living_units(enemy_team):
		var rng_stat: int = enemy.stats.effective("rng")
		var dist: int = RangeQuery.effective_range(enemy.position, end_pos, state.graph)
		# Enemy can attack from current position
		if dist <= rng_stat:
			if rng_stat <= 1 or dist >= 2:  # respect min range for ranged
				threats += 1.0
				continue
		# Enemy could move then attack — approximate with move + range reach
		var move_range: int = enemy.stats.effective_move()
		if dist <= move_range + rng_stat:
			threats += 0.5  # partial threat — enemy needs to move first
	return threats


# --- Target priority ---

static func _target_value(state: MatchState, unit: BattleUnit, plan: AIPlan) -> float:
	var value := 0.0
	for step in plan.steps:
		var kind: String = str(step.get("kind", ""))
		if kind == "attack" or kind == "ability":
			var target: BattleUnit = state.unit_at(step.get("target_pos", Vector2i.ZERO) as Vector2i)
			if target and target.is_alive() and target.team != unit.team:
				# Low HP ratio → higher priority (finish them off)
				var max_hp: int = target.stats.effective("hp")
				if max_hp > 0:
					var hp_ratio: float = float(target.current_hp) / float(max_hp)
					value += (1.0 - hp_ratio) * 2.0
				# Casters/support are high-value targets
				var mag: int = target.stats.effective("mag")
				if mag >= 3:
					value += 1.5
	return value


# --- Ability value ---

static func _ability_value(state: MatchState, unit: BattleUnit, plan: AIPlan) -> float:
	var value := 0.0
	for step in plan.steps:
		if str(step.get("kind", "")) != "ability":
			continue
		var ability: AbilityData = _get_ability(state, step)
		if not ability:
			continue
		var effect_type: String = str(ability.effect.get("effect_type", ""))
		match effect_type:
			"heal":
				var target: BattleUnit = state.unit_at(step.get("target_pos", Vector2i.ZERO) as Vector2i)
				if target and target.is_alive() and target.team == unit.team:
					var max_hp: int = target.stats.effective("hp")
					var missing_hp: float = float(max_hp - target.current_hp)
					var missing_ratio: float = missing_hp / float(max_hp) if max_hp > 0 else 0.0
					var heal_amount: float = AVG_DIE + float(ability.effect.get("value", 0))
					var actual_heal: float = minf(heal_amount, missing_hp)
					# Urgency (how badly they need it) + effectiveness (HP restored)
					value += missing_ratio * 2.0 + actual_heal * 0.3
			"buff":
				value += 1.5
			"status":
				value += 1.0
			"damage":
				# AoE damage bonus — count potential enemy hits
				if not ability.area.is_empty():
					var target_pos: Vector2i = step.get("target_pos", Vector2i.ZERO) as Vector2i
					var enemy_count := _count_enemies_in_area(state, unit, target_pos, ability.area)
					if enemy_count > 1:
						value += float(enemy_count - 1) * 2.0
	return value


static func _count_enemies_in_area(
	state: MatchState, unit: BattleUnit, target_pos: Vector2i, area: Dictionary
) -> int:
	var shape: String = str(area.get("shape", ""))
	var hexes: Array[Vector2i] = []
	match shape:
		"burst":
			var radius: int = int(area.get("radius", 0))
			hexes = Hex.hexes_in_range(target_pos, radius)
		_:
			hexes.append(target_pos)
	var count := 0
	var enemy_team: String = state.other_team(unit.team)
	for hex in hexes:
		var u: BattleUnit = state.unit_at(hex)
		if u and u.team == enemy_team and u.is_alive():
			count += 1
	return count


# --- Resource cost ---

static func _resource_cost(unit: BattleUnit, plan: AIPlan) -> float:
	var wp_spent := 0.0
	for step in plan.steps:
		if str(step.get("kind", "")) == "ability":
			var ability: AbilityData = GameData.get_ability(str(step.get("ability_id", "")))
			if ability:
				wp_spent += float(ability.wp_cost)
	# Normalize by total WP pool to penalize relative cost
	var max_wp: int = unit.stats.effective("wp")
	if max_wp > 0:
		return wp_spent / float(max_wp)
	return 0.0


# --- Utility ---

static func _get_ability(_state: MatchState, step: Dictionary) -> AbilityData:
	var ability_id: String = str(step.get("ability_id", ""))
	if ability_id.is_empty():
		return null
	return GameData.get_ability(ability_id)


# --- A18: Reaction risk ---

## Returns 1.0 if this plan contains a melee attack against a unit with Counter equipped,
## from a FRONT or FLANK arc. Returns 0.0 if the approach is REAR (counter is blocked)
## or if the target has no Counter reaction.
static func _counter_risk(state: MatchState, unit: BattleUnit, plan: AIPlan) -> float:
	for step in plan.steps:
		var kind: String = str(step.get("kind", ""))
		if kind != "attack":
			continue
		var target: BattleUnit = state.unit_at(step.get("target_pos", Vector2i.ZERO) as Vector2i)
		if target == null or not target.is_alive():
			continue
		# Only melee attacks trigger Counter
		var attacker_rng: int = unit.stats.effective("rng")
		if attacker_rng > 1:
			continue
		# Check if target has Counter in their reaction slot
		var target_reaction: String = target.equipped_passive("reaction")
		if target_reaction != "counter":
			continue
		# A19: REAR approach is safe -- Counter is blocked from REAR
		var origin: Vector2i = _end_position(unit, plan)
		var arc: int = Hex.arc_between(origin, target.position, target.facing)
		if arc == Hex.Arc.REAR:
			continue
		return 1.0
	return 0.0


## A19: Returns 1.0 if the plan's resulting facing would expose own rear to any enemy
## that could reach the unit. Used to penalise plans via the rear_exposure weight.
static func _rear_exposure(state: MatchState, unit: BattleUnit, plan: AIPlan) -> float:
	var end_pos: Vector2i = _end_position(unit, plan)
	# Estimate resulting facing: toward attack target if plan has one, else current facing
	var result_facing: int = unit.facing
	for step in plan.steps:
		var kind: String = str(step.get("kind", ""))
		if kind == "attack" or kind == "ability":
			var tpos: Vector2i = step.get("target_pos", end_pos) as Vector2i
			if tpos != end_pos:
				result_facing = Hex.direction_toward(end_pos, tpos)
			break

	var enemy_team: String = state.other_team(unit.team)
	for enemy: BattleUnit in state.living_units(enemy_team):
		var dist: int = RangeQuery.effective_range(enemy.position, end_pos, state.graph)
		var enemy_rng: int = enemy.stats.effective("rng")
		if dist > enemy_rng + enemy.stats.effective_move():
			continue
		# Is this enemy approaching from the unit's rear?
		var incoming_dir: int = Hex.direction_toward(end_pos, enemy.position)
		var arc: int = Hex.arc_of(incoming_dir, result_facing)
		if arc == Hex.Arc.REAR:
			return 1.0
	return 0.0
