class_name MatchBuilder
extends RefCounted
## Orchestrates match construction from two confirmed PartyDrafts.
## Handles tier config, map selection, BattleUnit creation, and
## wiring of MatchSetup/DeploymentController.
## Returns {state, controller, errors} — caller drives deployment.
## Spec reference: phase7-spec.md §5, alpha-phaseA12-spec.md §8

var _character_provider: Callable		# (String) -> CharacterData
var _stats_provider: Callable			# (String) -> StatBlock
var _all_maps_provider: Callable		# () -> Array of MapData
var _terrain_provider: Callable			# (String) -> TerrainProps
var _ability_getter: Callable			# (String) -> AbilityData
var _class_getter: Callable				# (String) -> ClassData
var _item_getter: Callable				# (String) -> ItemData


func _init(
	character_provider: Callable,
	stats_provider: Callable,
	all_maps_provider: Callable,
	terrain_provider: Callable,
	ability_getter: Callable,
	class_getter: Callable,
	item_getter: Callable,
) -> void:
	_character_provider = character_provider
	_stats_provider = stats_provider
	_all_maps_provider = all_maps_provider
	_terrain_provider = terrain_provider
	_ability_getter = ability_getter
	_class_getter = class_getter
	_item_getter = item_getter


## Returns tier config dict {bp_cap, min, max} or empty dict if invalid.
func get_tier_config(tier_id: String) -> Dictionary:
	var tiers: Dictionary = Constants.get_value("tiers")
	if not tiers or not tiers.has(tier_id):
		return {}
	return tiers[tier_id]


## Returns available tier IDs.
func get_tier_ids() -> Array[String]:
	var tiers: Dictionary = Constants.get_value("tiers")
	if not tiers:
		return []
	var ids: Array[String] = []
	for key in tiers.keys():
		ids.append(str(key))
	return ids


## Returns all maps matching the given tier.
func get_maps_for_tier(tier_id: String) -> Array:
	var all: Array = _all_maps_provider.call()
	var result: Array = []
	for m in all:
		if m is MapData and m.tier == tier_id:
			result.append(m)
	return result


## Selects a random map from the given tier. Returns null if none available.
func select_random_map(tier_id: String) -> MapData:
	var maps := get_maps_for_tier(tier_id)
	if maps.is_empty():
		return null
	return maps[randi() % maps.size()]


## Creates a PartyDraft for the given tier.
func create_draft(tier_id: String) -> PartyDraft:
	var config := get_tier_config(tier_id)
	return PartyDraft.new(config, _character_provider)


## Builds a MatchState from two confirmed drafts and a selected map.
## Returns {state: MatchState, controller: DeploymentController, errors: Array[String]}.
## The state is left in DEPLOYMENT — caller drives placement via the controller.
func build_match(
	draft_a: PartyDraft,
	draft_b: PartyDraft,
	map_data: MapData,
	ai_teams: Array = [],
) -> Dictionary:
	var errors: Array[String] = []

	# Validate drafts are confirmed
	if draft_a.state() != PartyDraft.State.CONFIRMED:
		errors.append("Player A draft is not confirmed")
	if draft_b.state() != PartyDraft.State.CONFIRMED:
		errors.append("Player B draft is not confirmed")
	if not errors.is_empty():
		return {"state": null, "controller": null, "errors": errors}

	# Create BattleUnit arrays
	var party_a: Array[BattleUnit] = _create_party(draft_a.confirmed_ids(), errors)
	var party_b: Array[BattleUnit] = _create_party(draft_b.confirmed_ids(), errors)
	if not errors.is_empty():
		return {"state": null, "controller": null, "errors": errors}

	# Build MatchState via MatchSetup
	var state := MatchSetup.create(party_a, party_b, map_data, _terrain_provider)

	# Wire providers
	var resolver := AbilityResolver.new(_ability_getter, _class_getter, _item_getter)
	state.ability_provider = resolver.resolve
	state.item_provider = _item_getter
	state.ai_teams = ai_teams

	# Create deployment controller (leaves state in DEPLOYMENT)
	var controller := DeploymentController.new()
	var deploy_errors := controller.begin(state, map_data.deployment_zones, ai_teams)
	if not deploy_errors.is_empty():
		return {"state": null, "controller": null, "errors": deploy_errors}

	return {"state": state, "controller": controller, "errors": []}


## Builds a MatchState from two pre-built BattleUnit arrays and a map.
## Used by the band-to-battle path (A5) where parties come from CharacterInstances.
## Returns {state: MatchState, controller: DeploymentController, errors: Array[String]}.
## The state is left in DEPLOYMENT — caller drives placement via the controller.
func build_match_from_parties(
	party_a: Array[BattleUnit],
	party_b: Array[BattleUnit],
	map_data: MapData,
	ai_teams: Array = [],
) -> Dictionary:
	var errors: Array[String] = []
	if party_a.is_empty():
		errors.append("Party A is empty")
	if party_b.is_empty():
		errors.append("Party B is empty")
	if not errors.is_empty():
		return {"state": null, "controller": null, "errors": errors}

	var state := MatchSetup.create(party_a, party_b, map_data, _terrain_provider)

	var resolver := AbilityResolver.new(_ability_getter, _class_getter, _item_getter)
	state.ability_provider = resolver.resolve
	state.item_provider = _item_getter
	state.ai_teams = ai_teams

	var controller := DeploymentController.new()
	var deploy_errors := controller.begin(state, map_data.deployment_zones, ai_teams)
	if not deploy_errors.is_empty():
		return {"state": null, "controller": null, "errors": deploy_errors}

	return {"state": state, "controller": controller, "errors": []}


func _create_party(ids: Array[String], errors: Array[String]) -> Array[BattleUnit]:
	var party: Array[BattleUnit] = []
	for id in ids:
		var c: CharacterData = _character_provider.call(id)
		if not c:
			errors.append("Character '%s' not found" % id)
			continue
		var fs: StatBlock = _stats_provider.call(id)
		if not fs:
			errors.append("Final stats for '%s' not found" % id)
			continue
		# A18: pass ability getter so support/movement passives are applied at build time
		party.append(BattleUnit.from_character(c, fs, _ability_getter))
	return party
