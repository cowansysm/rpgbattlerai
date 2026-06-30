class_name MatchState
extends RefCounted
## Authoritative match state container. Holds parties, round tracking,
## activation queue, occupancy, and action logs.
## All state transitions are explicit methods — no scene-tree dependency.
## Spec reference: phase4-spec.md §3

enum Phase {
	SETUP, DEPLOYMENT, ROUND_START, AWAITING_ACTIVATION, UNIT_TURN, MATCH_OVER,
	AI_PLANNING, PLAYER_PLANNING, RESOLUTION,
}

var phase: int = Phase.SETUP
var round_number: int = 0
var parties: Dictionary = {}			# "playerA" -> Array[BattleUnit], "playerB" -> Array[BattleUnit]
var initiative: String = ""				# Team with first activation this round
var activation_queue: Array = []		# Ordered list of team strings (interleaved)
var current_index: int = 0
var current_unit: BattleUnit = null
var turn_log: Array = []				# Action records for the current turn
var match_log: Array = []				# All action records across all rounds
var graph: HexGraph = null
var occupancy: Dictionary = {}			# Vector2i -> BattleUnit
var ability_provider: Callable = Callable()	# (BattleUnit, String) -> AbilityData or null
var item_provider: Callable = Callable()	# (String) -> ItemData or null
var buff_durations: Array = []				# [{source_tag, unit, remaining}, ...]
var ai_teams: Array = []					# Team strings controlled by AI (e.g. ["playerB"])
var turn_system: TurnSystem = null			# Active turn system (null = legacy alternating)


func living_units(team: String) -> Array:
	return parties.get(team, []).filter(
		func(u: BattleUnit) -> bool: return u.current_hp > 0 and not u.is_downed)


func unactivated_units(team: String) -> Array:
	return living_units(team).filter(
		func(u: BattleUnit) -> bool: return not u.is_activated)


func activatable_units(team: String) -> Array:
	## Returns units eligible for activation: living + downed (not permanently dead).
	return parties.get(team, []).filter(
		func(u: BattleUnit) -> bool:
			return (u.current_hp > 0 or u.is_downed) and not u.is_activated)


func all_living_units() -> Array:
	var out: Array = []
	for team in parties.keys():
		out.append_array(living_units(team))
	return out


func downed_units(team: String) -> Array:
	return parties.get(team, []).filter(
		func(u: BattleUnit) -> bool: return u.is_downed)


func all_downed_units() -> Array:
	var out: Array = []
	for team in parties.keys():
		out.append_array(downed_units(team))
	return out


func unit_at(pos: Vector2i) -> BattleUnit:
	return occupancy.get(pos, null)


func is_occupied(pos: Vector2i) -> bool:
	return occupancy.has(pos)


func other_team(team: String) -> String:
	return "playerB" if team == "playerA" else "playerA"


func check_winner() -> String:
	## Returns the winning team string, or "" if no winner yet.
	## A team loses when it has no living units AND no downed units.
	for team in parties.keys():
		var has_viable := false
		for unit: BattleUnit in parties[team]:
			if unit.current_hp > 0 or unit.is_downed:
				has_viable = true
				break
		if not has_viable:
			return other_team(team)
	return ""
