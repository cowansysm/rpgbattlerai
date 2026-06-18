class_name MapSerializer
extends RefCounted
## Serializes MapData to the condensed minified JSON format (Alpha A0).
## Tiles are positional arrays [q, r, elevation, terrain, (tags)].
## Output is minified (no indentation) for compact map files.

static func to_json(map: MapData) -> String:
	var tiles: Array = []
	for t: TileRecord in map.tiles:
		var rec: Array = [t.q, t.r, t.elevation, t.terrain]
		if not t.tags.is_empty():
			rec.append(t.tags)
		tiles.append(rec)
	var obj := {
		"id": map.id,
		"tier": map.tier,
		"tiles": tiles,
		"deployment_zones": map.deployment_zones,
	}
	return JSON.stringify(obj)
