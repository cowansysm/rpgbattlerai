class_name Deployment
extends RefCounted
## Auto-deploys units into deployment zones. Parses zone coordinate strings,
## validates placement, and populates occupancy.
## Spec reference: phase4-spec.md §6

static func auto_deploy(state: MatchState, zones: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	state.phase = MatchState.Phase.DEPLOYMENT

	for team in ["playerA", "playerB"]:
		var units: Array = state.parties.get(team, [])
		var zone_strs: Array = zones.get(team, [])
		var zone_tiles: Array[Vector2i] = _parse_zone(zone_strs)

		if units.size() > zone_tiles.size():
			errors.append(
				"Team '%s' has %d units but only %d zone tiles" % [
					team, units.size(), zone_tiles.size()])
			continue

		for i in range(units.size()):
			var tile: Vector2i = zone_tiles[i]
			if not state.graph.has_tile(tile):
				errors.append(
					"Zone tile %s not on map for team '%s'" % [str(tile), team])
				continue
			if state.is_occupied(tile):
				errors.append(
					"Zone tile %s already occupied for team '%s'" % [str(tile), team])
				continue
			units[i].position = tile
			state.occupancy[tile] = units[i]

	if errors.is_empty():
		state.phase = MatchState.Phase.ROUND_START
	return errors


static func _parse_zone(zone_strs: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for s in zone_strs:
		var parts := str(s).split(",")
		if parts.size() >= 2:
			out.append(Vector2i(int(parts[0]), int(parts[1])))
	return out
