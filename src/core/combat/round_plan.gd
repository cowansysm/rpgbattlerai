class_name RoundPlan
extends RefCounted
## Holds committed per-unit plans for both teams in a round.
## Provides SPD-sorted iteration for resolution.
## Spec reference: alpha-phaseA15-spec.md §2.2


var _plans: Dictionary = {}  # unit_id (String) -> {unit: BattleUnit, plan: AIPlan}


func commit(unit: BattleUnit, plan: AIPlan) -> void:
	## Commit a unit's plan for this round. Overwrites any previous plan for this unit.
	_plans[unit.character.id] = {"unit": unit, "plan": plan}


func has_plan(unit: BattleUnit) -> bool:
	return _plans.has(unit.character.id)


func get_plan(unit: BattleUnit) -> AIPlan:
	var entry: Dictionary = _plans.get(unit.character.id, {})
	return entry.get("plan", null)


func all_entries() -> Array:
	return _plans.values()


## Returns entries sorted by descending effective SPD.
## tie_seed: seeded RNG for deterministic tie-breaks.
## first_team_wins_ties: team string that wins SPD ties in round 1
## (from A13 coin flip; empty string = use seeded fallback).
func sorted_by_speed(tie_seed: int, first_team_wins_ties: String = "") -> Array:
	var entries: Array = _plans.values().duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = tie_seed
	# Pre-assign a tiebreak value to each entry
	for entry in entries:
		entry["_tiebreak"] = rng.randf()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var spd_a: int = a["unit"].stats.effective("spd")
		var spd_b: int = b["unit"].stats.effective("spd")
		if spd_a != spd_b:
			return spd_a > spd_b  # Higher SPD goes first
		# SPD tie: if first_team_wins_ties is set, that team wins
		if not first_team_wins_ties.is_empty():
			if a["unit"].team == first_team_wins_ties and b["unit"].team != first_team_wins_ties:
				return true
			if b["unit"].team == first_team_wins_ties and a["unit"].team != first_team_wins_ties:
				return false
		# Seeded fallback
		return a["_tiebreak"] > b["_tiebreak"]
	)
	return entries


func clear() -> void:
	_plans.clear()


func size() -> int:
	return _plans.size()
