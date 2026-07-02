class_name DeploymentController
extends RefCounted
## Drives the interactive deployment phase. Manages per-team queues of
## undeployed units, legal-tile computation within each zone, one-at-a-time
## alternating placement, and completion -> ROUND_START.
## Replaces Deployment.auto_deploy with interactive + AI paths.
## Spec reference: alpha-phaseA12-spec.md §3

var _state: MatchState
var _queue: Dictionary = {}			# team -> Array[BattleUnit] (undeployed, in party order)
var _zone: Dictionary = {}			# team -> Array[Vector2i] (parsed zone tiles)
var _turn_team: String = ""
var first_team: String = ""


## Initializes deployment: parses zones, builds per-team queues, validates
## zone sizes, and sets state.phase = DEPLOYMENT.
## ai_teams: which teams are AI-controlled (used to resolve deploy order).
## Returns errors (empty = ready to place).
func begin(state: MatchState, zones: Dictionary, ai_teams: Array) -> Array[String]:
	_state = state
	state.phase = MatchState.Phase.DEPLOYMENT
	var errors: Array[String] = []

	for team in ["playerA", "playerB"]:
		_zone[team] = _parse_zone(zones.get(team, []))
		var party: Array = state.parties.get(team, [])
		_queue[team] = party.duplicate()

		if _queue[team].size() > _zone[team].size():
			errors.append(
				"Team '%s': %d units > %d zone tiles" % [
					team, _queue[team].size(), _zone[team].size()])

		# Validate zone tiles are on-map
		for tile in _zone[team]:
			if not state.graph.has_tile(tile):
				errors.append(
					"Zone tile %s not on map for team '%s'" % [str(tile), team])

	if not errors.is_empty():
		return errors

	first_team = _resolve_first(ai_teams)
	_turn_team = first_team
	return []


## Returns the legal (zone + on-map + unoccupied) tiles for the given team.
func legal_tiles(team: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for t: Vector2i in _zone.get(team, []):
		if _state.graph.has_tile(t) and not _state.is_occupied(t):
			out.append(t)
	return out


## Returns the team that should place next, or "" if deployment is complete.
func current_team() -> String:
	if is_complete():
		return ""
	return _turn_team


## Returns the zone tiles for the given team.
func zone_tiles(team: String) -> Array[Vector2i]:
	return _zone.get(team, [] as Array[Vector2i])


## Returns the next unit to be placed for the given team, or null.
func next_unit(team: String) -> BattleUnit:
	var q: Array = _queue.get(team, [])
	if q.is_empty():
		return null
	return q[0]


## Places the next queued unit for `team` at `tile`.
## Returns errors (empty = success). On success, occupancy is set,
## terrain modifiers applied, and the turn advances.
func place_next(team: String, tile: Vector2i) -> Array[String]:
	if team != _turn_team:
		return ["Not %s's turn" % team]
	var q: Array = _queue.get(team, [])
	if q.is_empty():
		return ["%s has no units to place" % team]
	if not tile in legal_tiles(team):
		return ["Illegal tile %s for team '%s'" % [str(tile), team]]

	var unit: BattleUnit = q.pop_front()
	unit.position = tile
	_state.occupancy[tile] = unit
	TurnActions.apply_terrain_modifiers_on_deploy(unit, _state.graph)
	# A19: set initial facing toward the enemy zone centroid
	var enemy_team: String = _other_team(team)
	var enemy_zone: Array[Vector2i] = zone_tiles(enemy_team)
	if not enemy_zone.is_empty():
		unit.set_facing(Hex.direction_toward(tile, _zone_centroid(enemy_zone)))
	_advance_turn()
	return []


## Returns true when both teams have placed all their units.
func is_complete() -> bool:
	return _queue.get("playerA", []).is_empty() and _queue.get("playerB", []).is_empty()


## Finishes deployment: asserts completion and advances to ROUND_START.
func finish() -> void:
	assert(is_complete(), "Cannot finish deployment: units remain unplaced")
	RoundManager.start_round(_state)


## Headless/AI-vs-AI path: deploys all units via the planner callable and finishes.
## planner signature: func(state, team, unit, legal_tiles, enemy_zone) -> Vector2i
func auto_complete(planner: Callable) -> void:
	while not is_complete():
		var team := current_team()
		var unit := next_unit(team)
		var legal := legal_tiles(team)
		if legal.is_empty():
			Log.error("DeploymentController",
				"auto_complete: no legal tiles for team '%s'" % team)
			break
		var enemy := _other_team(team)
		var enemy_z := zone_tiles(enemy)
		var tile: Vector2i = planner.call(_state, team, unit, legal, enemy_z)
		var errs := place_next(team, tile)
		if not errs.is_empty():
			Log.error("DeploymentController", "auto_complete error: %s" % str(errs))
			break
	if is_complete():
		finish()


# --- Private ---

func _advance_turn() -> void:
	var other := _other_team(_turn_team)
	if not _queue.get(other, []).is_empty():
		_turn_team = other
	elif not _queue.get(_turn_team, []).is_empty():
		pass  # Stay on current team (other is empty)
	# else both empty — is_complete() will be true


func _resolve_first(ai_teams: Array) -> String:
	var deploy_first: String = str(Constants.get_value("DEPLOY_FIRST", "ai"))
	if deploy_first == "ai":
		# AI team goes first; if both or neither are AI, playerB goes first
		if "playerB" in ai_teams and "playerA" not in ai_teams:
			return "playerB"
		elif "playerA" in ai_teams and "playerB" not in ai_teams:
			return "playerA"
		else:
			return "playerB"
	elif deploy_first == "player":
		if "playerA" not in ai_teams:
			return "playerA"
		elif "playerB" not in ai_teams:
			return "playerB"
		else:
			return "playerA"
	return "playerB"


static func _other_team(team: String) -> String:
	return "playerA" if team == "playerB" else "playerB"


static func _parse_zone(zone_strs: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for s in zone_strs:
		var parts := str(s).split(",")
		if parts.size() >= 2:
			out.append(Vector2i(int(parts[0]), int(parts[1])))
	return out


## A19: Returns the approximate centroid of a zone as a Vector2i (truncated average).
static func _zone_centroid(zone: Array[Vector2i]) -> Vector2i:
	if zone.is_empty():
		return Vector2i.ZERO
	var sum := Vector2i.ZERO
	for t: Vector2i in zone:
		sum += t
	return Vector2i(sum.x / zone.size(), sum.y / zone.size())
