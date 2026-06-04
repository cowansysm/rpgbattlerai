class_name MatchSetup
extends RefCounted
## Creates and initializes a MatchState from two party arrays, a MapData,
## and a terrain provider. Determines first activation by highest SPD.
## Spec reference: phase4-spec.md §4.2

static func create(
	party_a: Array[BattleUnit],
	party_b: Array[BattleUnit],
	map_data: MapData,
	terrain_provider: Callable
) -> MatchState:
	var state := MatchState.new()
	state.parties = { "playerA": party_a, "playerB": party_b }

	for u in party_a:
		u.team = "playerA"
	for u in party_b:
		u.team = "playerB"

	state.graph = HexGraph.new()
	state.graph.build(map_data, terrain_provider)

	state.initiative = _determine_initiative(party_a, party_b)
	return state


static func _determine_initiative(a: Array, b: Array) -> String:
	var max_a := 0
	for u: BattleUnit in a:
		max_a = maxi(max_a, u.stats.effective_move())
	var max_b := 0
	for u: BattleUnit in b:
		max_b = maxi(max_b, u.stats.effective_move())
	if max_a > max_b:
		return "playerA"
	if max_b > max_a:
		return "playerB"
	return "playerA" if randi() % 2 == 0 else "playerB"
