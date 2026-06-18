class_name TerrainRegistry
extends RefCounted
## Loads terrain properties from a single keyed-dict JSON file.
## Different from EntityRegistry (which loads a directory of individual files).

var _entries: Dictionary = {}


## Loads terrain properties from a single JSON file (keyed dict format).
## Returns Array[String] of errors (empty == success).
func load_from(path: String) -> Array[String]:
	var errors: Array[String] = []
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("terrain file not found or empty: '%s'" % path)
		return errors
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		errors.append("terrain file '%s' is not a JSON object" % path)
		return errors
	for id in data.keys():
		var d: Variant = data[id]
		if typeof(d) != TYPE_DICTIONARY:
			errors.append("terrain '%s' entry is not a JSON object" % id)
			continue
		var p := TerrainProps.new()
		p.id = str(id)
		p.move_cost = int(d.get("move_cost", 1))
		p.impassable = bool(d.get("impassable", false))
		p.blocks_los = bool(d.get("blocks_los", false))
		p.cover = int(d.get("cover", 0))
		p.los_height = int(d.get("los_height", 0))
		# Alpha A0 effect fields (optional, neutral defaults)
		p.damage_on_enter = int(d.get("damage_on_enter", 0))
		p.damage_per_turn = int(d.get("damage_per_turn", 0))
		p.status_on_enter = d.get("status_on_enter", {})
		p.occupant_modifiers = d.get("occupant_modifiers", [])
		p.is_water = bool(d.get("is_water", false))
		p.terrain_tags = _to_str_array(d.get("tags", []))
		_entries[str(id)] = p
	return errors


func get_entry(id: String) -> TerrainProps:
	return _entries.get(id, _entries.get("grass"))


func has(id: String) -> bool:
	return _entries.has(id)


func size() -> int:
	return _entries.size()


func ids() -> Array:
	return _entries.keys()


static func _to_str_array(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(raw) == TYPE_ARRAY:
		for v in raw:
			out.append(str(v))
	return out
