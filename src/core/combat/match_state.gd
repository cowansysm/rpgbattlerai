class_name MatchState
extends RefCounted
## Authoritative match state container. Holds parties, round tracking,
## activation queue, occupancy, and action logs.
## All state transitions are explicit methods — no scene-tree dependency.
## Spec reference: phase4-spec.md §3

enum Phase { SETUP, DEPLOYMENT, ROUND_START, AWAITING_ACTIVATION, UNIT_TURN, MATCH_OVER }

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


func living_units(team: String) -> Array:
	return parties.get(team, []).filter(
		func(u: BattleUnit) -> bool: return u.current_hp > 0)


func unactivated_units(team: String) -> Array:
	return living_units(team).filter(
		func(u: BattleUnit) -> bool: return not u.is_activated)


func all_living_units() -> Array:
	var out: Array = []
	for team in parties.keys():
		out.append_array(living_units(team))
	return out


func unit_at(pos: Vector2i) -> BattleUnit:
	return occupancy.get(pos, null)


func is_occupied(pos: Vector2i) -> bool:
	return occupancy.has(pos)


func other_team(team: String) -> String:
	return "playerB" if team == "playerA" else "playerA"
