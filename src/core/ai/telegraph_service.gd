class_name TelegraphService
extends RefCounted
## Builds IntentPlan objects from the AI's committed AIPlan entries.
## Single plan source: the same AIPlan used for telegraph is the
## same one executed during resolution (no divergence).
## Spec reference: alpha-phaseA15-spec.md §2.5


## Build IntentPlans for all AI units in the round.
## ai_plans: Dictionary mapping unit_id -> AIPlan (from AIPlanner)
## ai_units: Array[BattleUnit]
## state: MatchState for spatial queries (path computation, AoE footprint)
static func build_intents(
	state: MatchState,
	ai_plans: Dictionary,
	ai_units: Array,
) -> Array:
	var intents: Array = []
	for unit: BattleUnit in ai_units:
		var plan: AIPlan = ai_plans.get(unit.character.id)
		if plan == null or plan.is_empty():
			continue
		var intent := _build_one(state, unit, plan)
		intents.append(intent)
	return intents


## Build a single IntentPlan from a unit and its AIPlan.
static func _build_one(state: MatchState, unit: BattleUnit, plan: AIPlan) -> IntentPlan:
	var intent := IntentPlan.new()
	intent.unit_id = unit.character.id
	intent.unit_ref = unit
	intent.move_to = unit.position
	intent.committed = true

	# Process plan steps
	for step in plan.steps:
		var kind: String = str(step.get("kind", ""))
		match kind:
			"move":
				var dest: Vector2i = step.get("target_pos", unit.position)
				intent.move_to = dest
				# Compute the path for visualization
				var jump: int = unit.stats.effective("jump")
				intent.path = Movement.path(state.graph, unit.position, dest, jump)

			"attack":
				intent.action_kind = "attack"
				intent.target_pos = step.get("target_pos", Vector2i.MAX)
				var target: BattleUnit = state.unit_at(intent.target_pos)
				if target:
					intent.target_unit_id = target.character.id
					# Project attack damage
					var weapon_power: int = CombatResolver.get_weapon_power(
						unit, state.item_provider)
					var attacker_elev: int = state.graph.elevation(intent.move_to)
					var target_elev: int = state.graph.elevation(intent.target_pos)
					var target_cover: int = state.graph.effective_cover(intent.target_pos)
					var is_ranged: bool = unit.stats.effective("rng") > 1
					intent.projection = OutcomeProjection.project_attack(
						unit, target, weapon_power,
						attacker_elev, target_elev, target_cover, is_ranged)

			"ability":
				intent.action_kind = "ability"
				intent.ability_id = str(step.get("ability_id", ""))
				intent.target_pos = step.get("target_pos", Vector2i.MAX)
				_compute_ability_intent(state, unit, intent)

			"defend":
				intent.action_kind = "defend"

			"wait":
				intent.action_kind = "wait"

			"use_item":
				intent.action_kind = "use_item"
				intent.item_id = str(step.get("item_id", ""))
				intent.target_pos = step.get("target_pos", Vector2i.MAX)

	return intent


## Compute AoE footprint and projection for ability intents.
static func _compute_ability_intent(
	state: MatchState, unit: BattleUnit, intent: IntentPlan
) -> void:
	# Look up the ability
	var ability: AbilityData = null
	if state.ability_provider.is_valid():
		ability = state.ability_provider.call(unit, intent.ability_id)
	if not ability:
		return

	# Compute AoE footprint if applicable
	if not ability.area.is_empty() and ability.area.has("shape"):
		intent.aoe_footprint = _compute_aoe_footprint(
			unit.position, intent.target_pos, ability.area)

	# Set target unit for single-target abilities
	var target: BattleUnit = state.unit_at(intent.target_pos)
	if target:
		intent.target_unit_id = target.character.id

	# Project damage/healing
	var effect_type: String = str(ability.effect.get("effect_type", ""))
	var effect_value: int = int(ability.effect.get("value", 0))
	var caster_elev: int = state.graph.elevation(intent.move_to)
	var target_elev: int = state.graph.elevation(intent.target_pos)

	# A16: element + terrain affinity for projection
	var element: String = str(ability.effect.get("element", ""))
	var terrain_aff_weight: int = 0
	if not element.is_empty() and target:
		var tprops: TerrainProps = state.graph.terrain_props(intent.target_pos)
		if tprops:
			terrain_aff_weight = Affinity.tier_to_weight(
				str(tprops.affinities.get(element, "neutral")))

	match effect_type:
		"damage":
			if target:
				intent.projection = OutcomeProjection.project_ability_damage(
					unit, target, effect_value, ability.type,
					caster_elev, target_elev, ability.mag_scaling,
					element, terrain_aff_weight)
		"heal":
			if target:
				intent.projection = OutcomeProjection.project_heal(
					target, effect_value, unit, ability.mag_scaling)


## Compute the set of hexes affected by an AoE ability.
static func _compute_aoe_footprint(
	caster_pos: Vector2i, target_pos: Vector2i, area: Dictionary
) -> Array:
	var shape: String = str(area.get("shape", ""))
	match shape:
		"burst":
			var radius: int = int(area.get("radius", 0))
			return Hex.hexes_in_range(target_pos, radius)
		"line":
			var length: int = int(area.get("length", 1))
			var direction: int = Hex.direction_toward(caster_pos, target_pos)
			return Hex.line_in_direction(target_pos, direction, length)
		"cone":
			var depth: int = int(area.get("depth", 1))
			var direction: int = Hex.direction_toward(caster_pos, target_pos)
			return Hex.cone_in_direction(target_pos, direction, depth)
		"ring":
			var radius: int = int(area.get("radius", 1))
			return Hex.ring(target_pos, radius)
	return []
