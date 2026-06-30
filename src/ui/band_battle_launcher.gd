class_name BandBattleLauncher
extends RefCounted
## Orchestrates the band-to-battle scene transition.
## Builds both parties, constructs the match via MatchBuilder,
## and sets MatchData before changing to map_scene.
## Spec reference: alpha-phaseA5-spec.md §7


## Launches a quick battle from a band's fielded selection vs a generated opponent.
## Returns an error string or "" on success.
static func launch_quick_battle(
	band: BattleBand,
	fielded_ids: Array[String],
	map_data: MapData,
	name_gen: Callable,
	scene_tree: SceneTree,
) -> String:
	# Resolve fielded instances
	var fielded: Array[CharacterInstance] = []
	for fid in fielded_ids:
		var ci := band.get_instance(fid)
		if ci == null:
			return "Fielded instance '%s' not found in band" % fid
		fielded.append(ci)
	if fielded.is_empty():
		return "No characters fielded"

	var race_prov := func(id: String) -> RaceData: return GameData.get_race(id)
	var class_prov := func(id: String) -> ClassData: return GameData.get_job_class(id)

	# Build player party
	var player_party := BandPartyBuilder.build_party(fielded, race_prov, class_prov)

	# Generate opponent from random templates
	var all_templates: Array = GameData.all_characters()
	all_templates.shuffle()
	var opp_count: int = mini(fielded.size(), all_templates.size())
	var opp_instances := BandPartyBuilder.generate_opponent_instances(
		all_templates, name_gen, opp_count)
	var opp_party := BandPartyBuilder.build_party(opp_instances, race_prov, class_prov)

	if opp_party.is_empty():
		return "Failed to generate opponent party"

	# Build the match
	var builder := MatchBuilder.new(
		GameData.get_character,
		GameData.get_final_stats,
		GameData.all_maps,
		GameData.get_terrain,
		GameData.get_ability,
		GameData.get_job_class,
		GameData.get_item,
	)
	var ai_teams: Array = ["playerB"]
	var result: Dictionary = builder.build_match_from_parties(
		player_party, opp_party, map_data, ai_teams)
	if result["state"] == null:
		var errors: Array = result.get("errors", [])
		return "Match build failed: " + ", ".join(errors.map(func(e): return str(e)))

	var state: MatchState = result["state"]

	# Hand off via MatchData
	MatchData.match_state = state
	MatchData.deployment_controller = result["controller"] as DeploymentController
	MatchData.map_id = map_data.id
	MatchData.active_band = band
	MatchData.fielded_ids = fielded_ids
	MatchData.is_instance_battle = true

	scene_tree.change_scene_to_file("res://scenes/map/map_scene.tscn")
	return ""
