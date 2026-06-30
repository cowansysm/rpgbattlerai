class_name OutcomeProjection
extends RefCounted
## Pure min/mid/max damage/healing projection over CombatResolver math.
## Calls CombatResolver with fixed die rolls to extract projection ranges.
## No mutation of actual BattleUnit state.
## Spec reference: alpha-phaseA15-spec.md §2.5


## Project a basic weapon attack's damage range.
## Returns {min: int, mid: int, max: int}.
static func project_attack(
	attacker: BattleUnit,
	target: BattleUnit,
	weapon_power: int,
	attacker_elev: int,
	target_elev: int,
	target_cover: int,
	is_ranged: bool,
) -> Dictionary:
	var has_defend: bool = target.stats.has_modifier_from_source("defend")
	var e_bonus: int = Constants.get_value("ELEV_BONUS", 1) if attacker_elev > target_elev else 0
	var c_bonus: int = Constants.get_value("COVER_DEF", 1) * target_cover if is_ranged else 0
	var atk: int = attacker.stats.effective("atk")
	var target_def: int = target.stats.effective("def")

	# Min: attacker rolls 1, defender rolls 6 (if defending)
	var raw_min: int = max(1, 1 + atk + weapon_power + e_bonus - target_def - c_bonus)
	if has_defend:
		raw_min = max(1, raw_min - 6)

	# Max: attacker rolls 6, defender rolls 1 (if defending)
	var raw_max: int = max(1, 6 + atk + weapon_power + e_bonus - target_def - c_bonus)
	if has_defend:
		raw_max = max(1, raw_max - 1)

	var mid: int = (raw_min + raw_max) / 2
	return {"min": raw_min, "mid": mid, "max": raw_max}


## Project a damage ability's (skill or spell) damage range.
## Returns {min: int, mid: int, max: int}.
static func project_ability_damage(
	caster: BattleUnit,
	target: BattleUnit,
	effect_value: int,
	ability_type: String,
	caster_elev: int,
	target_elev: int,
	mag_scaling: float = 1.0,
) -> Dictionary:
	var has_defend: bool = target.stats.has_modifier_from_source("defend")
	var e_bonus: int = Constants.get_value("ELEV_BONUS", 1) if caster_elev > target_elev else 0

	var base_atk: int
	if ability_type == "skill":
		base_atk = effect_value + e_bonus - target.stats.effective("def")
	else:
		# Spell: scales with MAG, reduced by RES
		var mag_bonus: int = int(round(mag_scaling * caster.stats.effective("mag")))
		base_atk = effect_value + mag_bonus + e_bonus - target.stats.effective("res")

	# Min: attacker rolls 1, defender rolls 6 (if defending)
	var raw_min: int = max(1, 1 + base_atk)
	if has_defend:
		raw_min = max(1, raw_min - 6)

	# Max: attacker rolls 6, defender rolls 1 (if defending)
	var raw_max: int = max(1, 6 + base_atk)
	if has_defend:
		raw_max = max(1, raw_max - 1)

	var mid: int = (raw_min + raw_max) / 2
	return {"min": raw_min, "mid": mid, "max": raw_max}


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
