class_name MatchSetup
extends RefCounted
## Creates and initializes a MatchState from two party arrays, a MapData,
## and a terrain provider. Determines first activation by total team SPD.
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
	var sum_a := 0
	for u: BattleUnit in a:
		sum_a += u.stats.effective_move()
	var sum_b := 0
	for u: BattleUnit in b:
		sum_b += u.stats.effective_move()
	if sum_a > sum_b:
		return "playerA"
	if sum_b > sum_a:
		return "playerB"
	return "playerA" if randi() % 2 == 0 else "playerB"
