class_name CombatResolver
extends RefCounted
## Centralized combat resolution logic. Resolves damage, healing, buffs,
## and status effects. Called by TurnActions after validation passes.
## Accepts explicit constant overrides for testability (defaults to Constants autoload).
## Spec reference: phase5-spec.md §3, §4

## Injectable dice roller for testability. Default rolls 1d6.
## Tests can swap this to a fixed callable for deterministic results.
static var dice_roller: Callable = func() -> int: return randi() % 6 + 1

## Injectable crit roller for testability. Returns float in [0, 1).
## Crit occurs when roll < CRIT_CHANCE.
static var crit_roller: Callable = func() -> float: return randf()


static func roll_die() -> int:
	return dice_roller.call()


static func roll_crit() -> float:
	return crit_roller.call()


## Resolve a physical (basic weapon) attack.
## Returns {damage, atk_roll, def_roll, target_hp_after, is_downed}.
## Defense die only rolls when the target has used the Defend action.
static func resolve_attack(
	attacker: BattleUnit,
	target: BattleUnit,
	weapon_power: int,
	attacker_elev: int,
	target_elev: int,
	target_cover: int,
	is_ranged: bool,
	elev_bonus: int = -1,
	cover_def: int = -1,
) -> Dictionary:
	if elev_bonus < 0:
		elev_bonus = Constants.get_value("ELEV_BONUS", 1)
	if cover_def < 0:
		cover_def = Constants.get_value("COVER_DEF", 1)

	var atk: int = attacker.stats.effective("atk")
	var e_bonus: int = elev_bonus if attacker_elev > target_elev else 0
	var c_bonus: int = cover_def * target_cover if is_ranged else 0
	var target_def: int = target.stats.effective("def")
	var atk_roll: int = roll_die()
	var damage: int = max(1, atk_roll + atk + weapon_power + e_bonus - target_def - c_bonus)

	# Defend action grants a 1d6 defense roll against all damage
	var def_roll: int = 0
	if target.stats.has_modifier_from_source("defend"):
		def_roll = roll_die()
		damage = max(1, damage - def_roll)

	_wake_on_damage(target)
	target.current_hp = max(0, target.current_hp - damage)
	var is_downed: bool = target.current_hp <= 0

	return {
		"damage": damage,
		"atk_roll": atk_roll,
		"def_roll": def_roll,
		"target_hp_after": target.current_hp,
		"is_downed": is_downed,
	}


## Resolve a damage ability effect (spell or skill).
## type == "skill": reduced by DEF (physical).
## type == "spell": scales with MAG, reduced by RES (magical).
## Defense die only rolls when the target has used the Defend action,
## and applies to both spell and skill damage.
##
## A16: element/affinity scaling and critical hits.
## Order of operations: base formula → affinity mult → crit mult → defend die → floor.
## IMMUNE skips the floor (0 damage). ABSORB converts to healing and skips the floor.
static func resolve_damage(
	attacker: BattleUnit,
	target: BattleUnit,
	effect_value: int,
	ability_type: String,
	attacker_elev: int,
	target_elev: int,
	elev_bonus: int = -1,
	mag_scaling: float = 1.0,
	element: String = "",
	terrain_affinity_weight: int = 0,
) -> Dictionary:
	if elev_bonus < 0:
		elev_bonus = Constants.get_value("ELEV_BONUS", 1)

	var e_bonus: int = elev_bonus if attacker_elev > target_elev else 0
	var atk_roll: int = roll_die()
	var base: int

	if ability_type == "skill":
		var target_def: int = target.stats.effective("def")
		base = atk_roll + effect_value + e_bonus - target_def
	else:
		# Spells: scales with caster MAG, reduced by target RES
		var mag_bonus: int = int(round(mag_scaling * attacker.stats.effective("mag")))
		base = atk_roll + effect_value + mag_bonus + e_bonus - target.stats.effective("res")

	# A16: Affinity scaling
	var tier: int = target.effective_affinity(element, terrain_affinity_weight)
	var aff_mult: float = Affinity.multiplier(tier)
	var scaled: int = int(round(float(base) * aff_mult))

	# A16: Critical hit
	var crit_chance: float = float(Constants.get_value("CRIT_CHANCE", 0.0625))
	var crit_mult: float = float(Constants.get_value("CRIT_MULT", 1.5))
	var is_crit: bool = roll_crit() < crit_chance
	if is_crit:
		scaled = int(round(float(scaled) * crit_mult))

	# Defend action grants a 1d6 defense roll against all damage
	var def_roll: int = 0
	if target.stats.has_modifier_from_source("defend"):
		def_roll = roll_die()
		scaled = scaled - def_roll

	var affinity_name: String = Affinity.tier_to_name(tier)

	# ABSORB: convert to healing, skip damage floor
	if tier == Affinity.Tier.ABSORB:
		var heal_amount: int = max(0, scaled)
		var max_hp: int = target.stats.effective("hp")
		heal_amount = min(heal_amount, max_hp - target.current_hp)
		target.current_hp = min(target.current_hp + heal_amount, max_hp)
		return {
			"damage": 0,
			"healing": heal_amount,
			"atk_roll": atk_roll,
			"def_roll": def_roll,
			"target_hp_after": target.current_hp,
			"is_downed": false,
			"element": element,
			"affinity": affinity_name,
			"is_crit": is_crit,
			"pre_affinity_damage": base,
		}

	# IMMUNE: 0 damage, skip floor
	var damage: int
	if tier == Affinity.Tier.IMMUNE:
		damage = 0
	else:
		damage = max(1, scaled)

	_wake_on_damage(target)
	target.current_hp = max(0, target.current_hp - damage)
	var is_downed: bool = target.current_hp <= 0

	return {
		"damage": damage,
		"atk_roll": atk_roll,
		"def_roll": def_roll,
		"target_hp_after": target.current_hp,
		"is_downed": is_downed,
		"element": element,
		"affinity": affinity_name,
		"is_crit": is_crit,
		"pre_affinity_damage": base,
	}


## Resolve a healing effect. Clamped to max HP.
## Optionally scales with caster MAG when mag_scaling > 0.
static func resolve_heal(
	target: BattleUnit,
	effect_value: int,
	caster: BattleUnit = null,
	mag_scaling: float = 0.0,
) -> Dictionary:
	var bonus: int = int(round(mag_scaling * caster.stats.effective("mag"))) if caster and mag_scaling > 0.0 else 0
	var max_hp: int = target.stats.effective("hp")
	var healing: int = max(0, min(effect_value + bonus, max_hp - target.current_hp))
	target.current_hp = min(target.current_hp + healing, max_hp)

	return {
		"healing": healing,
		"target_hp_after": target.current_hp,
	}


## Resolve a revive effect. Clears downed state and restores HP to REVIVE_HP_FRACTION.
## Returns {healing, target_hp_after}.
static func resolve_revive(
	target: BattleUnit,
	hp_fraction: float = -1.0,
) -> Dictionary:
	if hp_fraction < 0.0:
		hp_fraction = float(Constants.get_value("REVIVE_HP_FRACTION", 0.25))
	target.is_downed = false
	target.downed_round = -1
	var max_hp: int = target.stats.effective("hp")
	var healing: int = mini(max(1, int(round(float(max_hp) * hp_fraction))), max_hp)
	target.current_hp = healing

	return {
		"healing": healing,
		"target_hp_after": target.current_hp,
	}


## Resolve a buff effect. Pushes a StatModifier with a tracked source tag.
static func resolve_buff(
	target: BattleUnit,
	stat: String,
	value: int,
	ability_id: String,
) -> Dictionary:
	var source_tag: String = "buff:%s" % ability_id
	target.stats.push_modifier(StatModifier.new(stat, value, source_tag))

	return {
		"buff_stat": stat,
		"buff_value": value,
		"source_tag": source_tag,
	}


## Resolve a status effect. Adds or refreshes on the target.
static func resolve_status(
	target: BattleUnit,
	status_id: String,
	duration: int,
	source: String,
) -> Dictionary:
	# Refresh if already present
	for s in target.status_effects:
		if s["id"] == status_id:
			s["duration"] = duration
			s["source"] = source
			return {
				"status_id": status_id,
				"status_duration": duration,
				"refreshed": true,
			}

	# Add new status
	target.status_effects.append({
		"id": status_id,
		"duration": duration,
		"source": source,
	})

	return {
		"status_id": status_id,
		"status_duration": duration,
		"refreshed": false,
	}


## Look up weapon power for a unit via item_provider.
## Returns 0 if no weapon equipped or provider unavailable.
static func get_weapon_power(unit: BattleUnit, item_provider: Callable) -> int:
	if not item_provider.is_valid():
		return 0
	for eq_id in unit.character.equipment:
		var item: ItemData = item_provider.call(eq_id)
		if item and item.slot == "weapon":
			return item.weapon_power
	return 0


# --- Internal ---

## Remove sleep status if the target is sleeping (wake on damage).
static func _wake_on_damage(target: BattleUnit) -> void:
	if target.has_status("sleep"):
		target.remove_status("sleep")
