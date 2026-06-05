class_name CombatResolver
extends RefCounted
## Centralized combat resolution logic. Resolves damage, healing, buffs,
## and status effects. Called by TurnActions after validation passes.
## Accepts explicit constant overrides for testability (defaults to Constants autoload).
## Spec reference: phase5-spec.md §3, §4


## Resolve a physical (basic weapon) attack.
## Returns {damage, target_hp_after, is_downed}.
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
	var damage: int = max(1, atk + weapon_power + e_bonus - target_def - c_bonus)

	_wake_on_damage(target)
	target.current_hp = max(0, target.current_hp - damage)
	var is_downed: bool = target.current_hp <= 0

	return {
		"damage": damage,
		"target_hp_after": target.current_hp,
		"is_downed": is_downed,
	}


## Resolve a damage ability effect (spell or skill).
## type == "skill": reduced by DEF (physical). type == "spell": ignores DEF.
static func resolve_damage(
	attacker: BattleUnit,
	target: BattleUnit,
	effect_value: int,
	ability_type: String,
	attacker_elev: int,
	target_elev: int,
	elev_bonus: int = -1,
) -> Dictionary:
	if elev_bonus < 0:
		elev_bonus = Constants.get_value("ELEV_BONUS", 1)

	var e_bonus: int = elev_bonus if attacker_elev > target_elev else 0
	var damage: int

	if ability_type == "skill":
		var target_def: int = target.stats.effective("def")
		damage = max(1, effect_value + e_bonus - target_def)
	else:
		damage = effect_value + e_bonus

	_wake_on_damage(target)
	target.current_hp = max(0, target.current_hp - damage)
	var is_downed: bool = target.current_hp <= 0

	return {
		"damage": damage,
		"target_hp_after": target.current_hp,
		"is_downed": is_downed,
	}


## Resolve a healing effect. Clamped to max HP.
static func resolve_heal(
	target: BattleUnit,
	effect_value: int,
) -> Dictionary:
	var max_hp: int = target.stats.effective("hp")
	var healing: int = max(0, min(effect_value, max_hp - target.current_hp))
	target.current_hp = min(target.current_hp + healing, max_hp)

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
