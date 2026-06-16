class_name DataFactory
extends RefCounted
## Per-type factory methods that convert raw JSON dictionaries into typed Resources.
## Each method assumes the dict has already been structurally validated.

static func make_race(d: Dictionary) -> RaceData:
	var r := RaceData.new()
	r.id = str(d["id"])
	r.display_name = str(d.get("display_name", d["id"]))
	r.stat_modifiers = d.get("stat_modifiers", {})
	r.flavor = str(d.get("flavor", ""))
	return r


static func make_class(d: Dictionary) -> ClassData:
	var c := ClassData.new()
	c.id = str(d["id"])
	c.display_name = str(d.get("display_name", d["id"]))
	c.abbr = str(d.get("abbr", ""))
	c.stat_modifiers = d.get("stat_modifiers", {})
	c.derived_bonuses = d.get("derived_bonuses", {})
	c.equipment_access = _to_str_array(d.get("equipment_access", []))
	c.granted_abilities = _to_str_array(d.get("granted_abilities", []))
	return c


static func make_ability(d: Dictionary) -> AbilityData:
	var a := AbilityData.new()
	a.id = str(d["id"])
	a.display_name = str(d.get("display_name", d["id"]))
	a.type = str(d.get("type", ""))
	a.ap_cost = int(d.get("ap_cost", 1))
	a.wp_cost = int(d.get("wp_cost", 0))
	a.ability_range = int(d.get("range", 0))
	a.area = d.get("area", {})
	a.effect = d.get("effect", {})
	a.effect_type = str(d.get("effect", {}).get("effect_type", ""))
	a.source = str(d.get("source", "class"))
	return a


static func make_item(d: Dictionary) -> ItemData:
	var i := ItemData.new()
	i.id = str(d["id"])
	i.display_name = str(d.get("display_name", d["id"]))
	i.slot = str(d.get("slot", ""))
	i.bp_value = int(d.get("bp_value", 0))
	i.passive = d.get("passive", {})
	i.granted_abilities = _to_str_array(d.get("granted_abilities", []))
	i.weapon_power = int(d.get("weapon_power", 0))
	i.weapon_range = int(d.get("weapon_range", 0))
	return i


static func make_character(d: Dictionary) -> CharacterData:
	var c := CharacterData.new()
	c.id = str(d["id"])
	c.display_name = str(d.get("display_name", d["id"]))
	c.race = str(d["race"])
	c.classes = _to_str_array(d.get("classes", []))
	c.level = int(d.get("level", 1))
	c.bp = int(d.get("bp", 0))
	c.base_stats = d.get("base_stats", {})
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
		tiles.append(TileRecord.new(
			int(t["q"]), int(t["r"]),
			int(t.get("elevation", 0)), str(t.get("terrain", "grass"))))
	m.tiles = tiles
	return m


static func _to_str_array(v: Variant) -> Array[String]:
	var out: Array[String] = []
	for e in v:
		out.append(str(e))
	return out
