class_name OutcomeProjection
extends RefCounted
## Pure min/mid/max damage/healing projection over CombatResolver math.
## Calls CombatResolver with fixed die rolls to extract projection ranges.
## No mutation of actual BattleUnit state.
## A16: affinity-scaled ranges and crit-inclusive max.
## Spec reference: alpha-phaseA15-spec.md §2.5, alpha-phaseA16-spec.md §2


## Project a basic weapon attack's damage range.
## Returns {min: int, mid: int, max: int}.
## A19: arc param adds FacingBonus to damage and gates the crit-inclusive max behind
##      crit_bonus(arc) > 0 (fixes pre-existing bug where FRONT max included crit).
static func project_attack(
	attacker: BattleUnit,
	target: BattleUnit,
	weapon_power: int,
	attacker_elev: int,
	target_elev: int,
	target_cover: int,
	is_ranged: bool,
	arc: int = 0,
) -> Dictionary:
	var has_defend: bool = target.stats.has_modifier_from_source("defend")
	var e_bonus: int = Constants.get_value("ELEV_BONUS", 1) if attacker_elev > target_elev else 0
	var f_bonus: int = FacingBonus.damage_bonus(arc)
	var c_bonus: int = Constants.get_value("COVER_DEF", 1) * target_cover if is_ranged else 0
	var atk: int = attacker.stats.effective("atk")
	var target_def: int = target.stats.effective("def")

	# Min: attacker rolls 1, defender rolls 6 (if defending)
	var raw_min: int = max(1, 1 + atk + weapon_power + e_bonus + f_bonus - target_def - c_bonus)
	if has_defend:
		raw_min = max(1, raw_min - 6)

	# Max: attacker rolls 6, defender rolls 1 (if defending)
	var raw_max: int = max(1, 6 + atk + weapon_power + e_bonus + f_bonus - target_def - c_bonus)
	if has_defend:
		raw_max = max(1, raw_max - 1)

	# A19: crit-inclusive max gated behind crit_bonus(arc) -- FRONT (arc=0) skips crit entirely
	var cc: float = FacingBonus.crit_bonus(arc)
	if cc > 0.0:
		var crit_mult: float = float(Constants.get_value("CRIT_MULT", 1.5))
		raw_max = int(round(float(raw_max) * crit_mult))

	var mid: int = (raw_min + raw_max) / 2
	return {"min": raw_min, "mid": mid, "max": raw_max}


## Project a damage ability's (skill or spell) damage range.
## Returns {min: int, mid: int, max: int, affinity: String}.
## A16: applies affinity multiplier and crit-inclusive max.
## A19: arc adds FacingBonus to base damage; total crit_chance = CRIT_CHANCE + crit_bonus(arc).
static func project_ability_damage(
	caster: BattleUnit,
	target: BattleUnit,
	effect_value: int,
	ability_type: String,
	caster_elev: int,
	target_elev: int,
	mag_scaling: float = 1.0,
	element: String = "",
	terrain_affinity_weight: int = 0,
	arc: int = 0,
) -> Dictionary:
	var has_defend: bool = target.stats.has_modifier_from_source("defend")
	var e_bonus: int = Constants.get_value("ELEV_BONUS", 1) if caster_elev > target_elev else 0
	var f_bonus: int = FacingBonus.damage_bonus(arc)

	var base_atk: int
	if ability_type == "skill":
		base_atk = effect_value + e_bonus + f_bonus - target.stats.effective("def")
	else:
		# Spell: scales with MAG, reduced by RES
		var mag_bonus: int = int(round(mag_scaling * caster.stats.effective("mag")))
		base_atk = effect_value + mag_bonus + e_bonus + f_bonus - target.stats.effective("res")

	# A16: Affinity
	var tier: int = target.effective_affinity(element, terrain_affinity_weight)
	var aff_mult: float = Affinity.multiplier(tier)
	var affinity_name: String = Affinity.tier_to_name(tier)

	# IMMUNE → 0 damage
	if tier == Affinity.Tier.IMMUNE:
		return {"min": 0, "mid": 0, "max": 0, "affinity": affinity_name}

	# ABSORB → healing (negative damage conceptually; return as positive heal values)
	if tier == Affinity.Tier.ABSORB:
		var heal_min: int = max(0, int(round(float(1 + base_atk) * aff_mult)))
		var heal_max: int = max(0, int(round(float(6 + base_atk) * aff_mult)))
		var heal_mid: int = (heal_min + heal_max) / 2
		return {"min": heal_min, "mid": heal_mid, "max": heal_max,
				"affinity": affinity_name, "is_heal": true}

	# Min: attacker rolls 1, defender rolls 6 (if defending), no crit
	var raw_min: int = max(1, int(round(float(1 + base_atk) * aff_mult)))
	if has_defend:
		raw_min = max(1, raw_min - 6)

	# Max: attacker rolls 6, defender rolls 1 (if defending), with crit (additive arc bonus)
	var base_crit: float = float(Constants.get_value("CRIT_CHANCE", 0.0625))
	var arc_crit: float = FacingBonus.crit_bonus(arc)
	var crit_mult: float = float(Constants.get_value("CRIT_MULT", 1.5))
	var raw_max: int = max(1, int(round(float(6 + base_atk) * aff_mult)))
	if base_crit + arc_crit > 0.0:
		raw_max = int(round(float(raw_max) * crit_mult))
	if has_defend:
		raw_max = max(1, raw_max - 1)

	var mid: int = (raw_min + raw_max) / 2
	return {"min": raw_min, "mid": mid, "max": raw_max, "affinity": affinity_name}


## Project a healing effect's range.
## Returns {min: int, mid: int, max: int}.
## Healing has no die roll; it's deterministic (value + MAG bonus, capped at missing HP).
static func project_heal(
	target: BattleUnit,
	effect_value: int,
	caster: BattleUnit = null,
	mag_scaling: float = 0.0,
) -> Dictionary:
	var bonus: int = int(round(mag_scaling * caster.stats.effective("mag"))) if caster and mag_scaling > 0.0 else 0
	var max_hp: int = target.stats.effective("hp")
	var missing: int = max_hp - target.current_hp
	var healing: int = max(0, min(effect_value + bonus, missing))
	# Healing is deterministic — min == mid == max
	return {"min": healing, "mid": healing, "max": healing}
