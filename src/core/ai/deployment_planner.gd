class_name DeploymentPlanner
extends RefCounted
## AI deployment heuristic: scores legal tiles for placement based on
## role (front/back), cover, elevation, hazard avoidance, and anti-clustering.
## Pure (reads MatchState for terrain/positions). Used by DeploymentController
## for AI teams and the headless/auto_complete path.
## Spec reference: alpha-phaseA12-spec.md §6


## Scores each legal tile and returns the best for the given unit.
## enemy_zone: the opposing team's zone tiles (for centroid computation).
## weights: Dictionary of tuning weights (frontline, cover, elevation, hazard, spacing).
static func choose(
	state: MatchState, team: String, unit: BattleUnit,
	legal: Array[Vector2i], enemy_zone: Array[Vector2i],
	weights: Dictionary
) -> Vector2i:
	assert(not legal.is_empty(), "DeploymentPlanner.choose called with no legal tiles")

	var enemy_centroid := _zone_centroid(enemy_zone)
	var melee := _is_frontline(unit)

	var w_front: float = float(weights.get("frontline", 6.0))
	var w_cover: float = float(weights.get("cover", 4.0))
	var w_elev: float = float(weights.get("elevation", 2.0))
	var w_hazard: float = float(weights.get("hazard", 8.0))
	var w_spacing: float = float(weights.get("spacing", 2.0))

	var best: Vector2i = legal[0]
	var best_score: float = -INF

	for t: Vector2i in legal:
		var s: float = 0.0

		# Frontline/backline: melee prefer closer to enemy, ranged prefer farther
		var d: float = float(Hex.distance(t, enemy_centroid))
		if melee:
			s -= d * w_front * 0.1
		else:
			s += d * w_front * 0.1

		# Cover
		s += float(state.graph.effective_cover(t)) * w_cover

		# Elevation
		s += float(state.graph.elevation(t)) * w_elev

		# Hazard avoidance
		var hazard: float = float(state.graph.damage_per_turn(t)) + float(state.graph.damage_on_enter(t))
		if hazard > 0.0:
			s -= w_hazard

		# Anti-clustering: penalize tiles adjacent to already-placed allies
		s -= float(_adjacent_allies(state, team, t)) * w_spacing

		if s > best_score:
			best_score = s
			best = t

	return best


## Returns true if the unit should deploy in the frontline (melee/tank).
static func _is_frontline(unit: BattleUnit) -> bool:
	var rng_val: int = unit.stats.effective("rng")
	if rng_val >= 2:
		return false
	var atk: int = unit.stats.effective("atk")
	var mag: int = unit.stats.effective("mag")
	return atk >= mag


## Computes the centroid of zone tiles (stable reference independent of placement).
static func _zone_centroid(zone: Array[Vector2i]) -> Vector2i:
	if zone.is_empty():
		return Vector2i(0, 0)
	var sum_q: int = 0
	var sum_r: int = 0
	for t: Vector2i in zone:
		sum_q += t.x
		sum_r += t.y
	return Vector2i(roundi(float(sum_q) / float(zone.size())), roundi(float(sum_r) / float(zone.size())))


## Counts already-placed allies adjacent to the given tile.
static func _adjacent_allies(state: MatchState, team: String, tile: Vector2i) -> int:
	var count: int = 0
	for n: Vector2i in Hex.neighbors(tile):
		var occupant: BattleUnit = state.unit_at(n)
		if occupant and occupant.team == team:
			count += 1
	return count


static func _other(team: String) -> String:
	return "playerA" if team == "playerB" else "playerB"
