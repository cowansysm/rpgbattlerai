class_name RoundManager
extends RefCounted
## Manages the alternating activation round loop.
## Starts rounds, builds interleaved activation queues, advances through
## activations, and flips initiative at round end.
## Spec reference: phase4-spec.md §3.3, §4

static func start_round(state: MatchState) -> void:
	state.round_number += 1

	# Reset all living units for the new round
	for team in state.parties.keys():
		for u: BattleUnit in state.living_units(team):
			u.is_activated = false
			u.ap_remaining = 2
			u.stats.remove_modifiers_by_source("defend")

	state.activation_queue = _build_queue(state)
	state.current_index = 0
	state.current_unit = null
	state.phase = MatchState.Phase.AWAITING_ACTIVATION


static func _build_queue(state: MatchState) -> Array:
	var init_team: String = state.initiative
	var other_team: String = state.other_team(init_team)
	var count_i: int = state.unactivated_units(init_team).size()
	var count_o: int = state.unactivated_units(other_team).size()
	var queue: Array = []
	var i := 0
	var o := 0
	while i < count_i or o < count_o:
		if i < count_i:
			queue.append(init_team)
			i += 1
		if o < count_o:
			queue.append(other_team)
			o += 1
	return queue


static func current_team(state: MatchState) -> String:
	if state.current_index >= state.activation_queue.size():
		return ""
	return str(state.activation_queue[state.current_index])


static func activate_unit(state: MatchState, unit: BattleUnit) -> String:
	## Attempt to activate the given unit. Returns "" on success, or an error string.
	var team := current_team(state)
	if team.is_empty():
		return "No more activations this round"
	if unit.team != team:
		return "It is %s's turn to activate, not %s's" % [team, unit.team]
	if unit.is_activated:
		return "Unit '%s' is already activated this round" % unit.character.id
	if unit.current_hp <= 0:
		return "Unit '%s' is downed" % unit.character.id

	state.current_unit = unit
	state.turn_log = []
	state.phase = MatchState.Phase.UNIT_TURN
	return ""


static func end_activation(state: MatchState) -> void:
	## End the current unit's activation and advance the queue.
	if state.current_unit:
		state.current_unit.is_activated = true
		state.current_unit.ap_remaining = 0
		state.match_log.append_array(state.turn_log)
	state.current_unit = null
	state.current_index += 1

	if state.current_index >= state.activation_queue.size():
		_end_round(state)
	else:
		state.phase = MatchState.Phase.AWAITING_ACTIVATION


static func _end_round(state: MatchState) -> void:
	## Flip initiative and prepare for next round.
	state.initiative = state.other_team(state.initiative)
	state.phase = MatchState.Phase.ROUND_START


static func is_round_over(state: MatchState) -> bool:
	return state.current_index >= state.activation_queue.size()
