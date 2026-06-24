class_name DeathModel
extends RefCounted
## Applies the down-limit death model after a battle.
## Tracks downs per instance, removes permadead characters from the band,
## and checks if the run should end in defeat.


## Applies post-battle downs. Returns {dead_ids: Array[String], run_lost: bool}.
static func apply_post_battle(run_state: RunState, band: BattleBand,
		downed_instance_ids: Array[String]) -> Dictionary:
	var dead_ids: Array[String] = []
	for uid in downed_instance_ids:
		var ci: CharacterInstance = band.get_instance(uid)
		if ci == null:
			continue
		ci.downs_this_run += 1
		if ci.downs_this_run > run_state.down_limit:
			band.remove_instance(uid)
			dead_ids.append(uid)
	var run_lost: bool = not can_field_party(band)
	return {"dead_ids": dead_ids, "run_lost": run_lost}


## Checks if a band has at least one living instance that could be fielded.
static func can_field_party(band: BattleBand) -> bool:
	return not band.roster.is_empty()


## Resets all downs_this_run counters for a band's roster. Called at run embark.
static func reset_downs(band: BattleBand) -> void:
	for ci in band.roster:
		ci.downs_this_run = 0


## Extracts instance IDs of downed player units from a completed match.
## Uses BattleUnit.character.id which equals CharacterInstance.instance_id
## (set by CharacterInstance.to_character_data()).
static func extract_downed_ids(match_state: MatchState,
		player_team: String) -> Array[String]:
	var downed: Array[String] = []
	var units: Array = match_state.parties.get(player_team, [])
	for unit in units:
		if unit is BattleUnit and (unit as BattleUnit).is_downed:
			downed.append((unit as BattleUnit).character.id)
	return downed
