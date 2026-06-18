class_name DataFactory
extends RefCounted
## Per-type factory methods that convert raw JSON dictionaries into typed Resources.
## Accepts both condensed field names (name, stats, ap, wp, bp, power, range)
## and legacy field names (display_name, stat_modifiers, ap_cost, etc.).
## Each method assumes the dict has already been structurally validated.

static func make_race(d: Dictionary) -> RaceData:
	var r := RaceData.new()
	r.id = str(d["id"])
	r.display_name = str(d.get("name", d.get("display_name", d["id"])))
	r.stat_modifiers = d.get("stats", d.get("stat_modifiers", {}))
	r.flavor = str(d.get("flavor", ""))
	return r


static func make_class(d: Dictionary) -> ClassData:
	var c := ClassData.new()
	c.id = str(d["id"])
	c.display_name = str(d.get("name", d.get("display_name", d["id"])))
	c.abbr = str(d.get("abbr", ""))
	c.stat_modifiers = d.get("stats", d.get("stat_modifiers", {}))
	c.derived_bonuses = d.get("derived_bonuses", {})
	c.equipment_access = _to_str_array(d.get("equipment_access", []))
	c.granted_abilities = _to_str_array(d.get("granted_abilities", []))
	c.level_max = int(d.get("level_max", 1))
	c.required_classes = _parse_required_classes(d.get("required_classes", []))
	return c


static func make_ability(d: Dictionary) -> AbilityData:
	var a := AbilityData.new()
	a.id = str(d["id"])
	a.display_name = str(d.get("name", d.get("display_name", d["id"])))
	a.type = str(d.get("type", ""))
	a.ap_cost = int(d.get("ap", d.get("ap_cost", 1)))
	a.wp_cost = int(d.get("wp", d.get("wp_cost", 0)))
	a.ability_range = int(d.get("range", 0))
	a.area = d.get("area", {})
	a.effect = d.get("effect", {})
	a.effect_type = str(d.get("effect", {}).get("effect_type", ""))
	a.mag_scaling = float(d.get("mag_scaling", 1.0))
	a.source = str(d.get("source", "class"))
	return a


static func make_item(d: Dictionary) -> ItemData:
	var i := ItemData.new()
	i.id = str(d["id"])
	i.display_name = str(d.get("name", d.get("display_name", d["id"])))
	i.slot = str(d.get("slot", ""))
	i.bp_value = int(d.get("bp", d.get("bp_value", 0)))
	i.passive = d.get("passive", {})
	i.granted_abilities = _to_str_array(d.get("granted_abilities", []))
	i.weapon_power = int(d.get("power", d.get("weapon_power", 0)))
	i.weapon_range = int(d.get("range", d.get("weapon_range", 0)))
	return i


static func make_character(d: Dictionary) -> CharacterData:
	var c := CharacterData.new()
	c.id = str(d["id"])
	c.display_name = str(d.get("name", d.get("display_name", d["id"])))
	c.race = str(d["race"])
	c.classes = _to_str_array(d.get("classes", []))
	c.level = int(d.get("level", 1))
	c.bp = int(d.get("bp", 0))
	c.base_stats = d.get("stats", d.get("base_stats", {}))
	c.equipment = _to_str_array(d.get("equipment", []))
	c.abilities = _to_str_array(d.get("abilities", []))
	return c


static func make_map(d: Dictionary) -> MapData:
	var m := MapData.new()
	m.id = str(d["id"])
	m.tier = str(d.get("tier", "standard"))
	m.deployment_zones = d.get("deployment_zones", {})
	var tiles: Array[TileRecord] = []
	for t in d.get("tiles", []):
		if typeof(t) == TYPE_ARRAY:
			# Alpha A0 condensed format: [q, r, elevation, terrain, (tags)]
			var tags_c: Array[String] = _to_str_array(t[4]) if t.size() > 4 else _to_str_array([])
			tiles.append(TileRecord.new(int(t[0]), int(t[1]), int(t[2]), str(t[3]), tags_c))
		else:
			# MVP verbose dict format
			var tile_tags: Array[String] = _to_str_array(t.get("tags", []))
			tiles.append(TileRecord.new(
				int(t["q"]), int(t["r"]),
				int(t.get("elevation", 0)), str(t.get("terrain", "grass")),
				tile_tags))
	m.tiles = tiles
	return m


static func _to_str_array(v: Variant) -> Array[String]:
	var out: Array[String] = []
	for e in v:
		out.append(str(e))
	return out


static func _parse_required_classes(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry in raw:
		if typeof(entry) == TYPE_ARRAY and entry.size() == 2:
			out.append([str(entry[0]), int(entry[1])])
	return out
