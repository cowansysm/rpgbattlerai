class_name Validator
extends RefCounted
## Structural and referential validation for content data.
## Accepts both condensed and legacy field names.
## Returns error arrays (empty == valid). Fail-loud philosophy.

const TERRAINS := [
	"grass", "road", "brush", "trees", "rocks",
	"shallow_water", "deep_water", "cliff",
	"rubble", "barricade",
	"lava", "spikes", "bog",
]
const SLOTS := ["weapon", "armor", "shield", "accessory"]
const ABILITY_TYPES := ["spell", "skill", "item", "passive"]
const EFFECT_TYPES := ["damage", "heal", "status", "buff", "revive"]


# --- Shared helpers ---

static func validate_stat_keys(d: Dictionary, entity_id: String, field_name: String) -> Array[String]:
	var e: Array[String] = []
	for k in d.keys():
		if not StatKey.is_valid_key(str(k)):
			e.append("%s '%s' has unknown stat key '%s' in %s" % ["entity", entity_id, k, field_name])
	return e


# --- Per-type structural validators ---

static func validate_race(d: Dictionary) -> Array[String]:
	var e: Array[String] = []
	if not d.has("id"):
		e.append("race missing required field 'id'")
	# Accept "name" or "display_name"
	if not d.has("name") and not d.has("display_name"):
		e.append("race '%s' missing name" % d.get("id", "?"))
	# Accept "stats" or "stat_modifiers"
	var stats_dict: Variant = d.get("stats", d.get("stat_modifiers", null))
	if stats_dict != null and typeof(stats_dict) == TYPE_DICTIONARY:
		e.append_array(validate_stat_keys(stats_dict, str(d.get("id", "?")), "stats"))
	return e


static func validate_class(d: Dictionary) -> Array[String]:
	var e: Array[String] = []
	if not d.has("id"):
		e.append("class missing required field 'id'")
	# Accept "stats" or "stat_modifiers"
	var stats_dict: Variant = d.get("stats", d.get("stat_modifiers", null))
	if stats_dict != null and typeof(stats_dict) == TYPE_DICTIONARY:
		e.append_array(validate_stat_keys(stats_dict, str(d.get("id", "?")), "stats"))
	# Validate level_max (optional, defaults to 1, must be >= 1)
	if d.has("level_max"):
		if typeof(d["level_max"]) != TYPE_INT and typeof(d["level_max"]) != TYPE_FLOAT:
			e.append("class '%s' field 'level_max' must be an integer" % d.get("id", "?"))
		elif int(d["level_max"]) < 1:
			e.append("class '%s' field 'level_max' must be >= 1" % d.get("id", "?"))
	# Validate required_classes structure (optional, defaults to [])
	if d.has("required_classes"):
		e.append_array(_validate_required_classes_structure(d))
	return e


static func _validate_required_classes_structure(d: Dictionary) -> Array[String]:
	var e: Array[String] = []
	var cls_id: String = str(d.get("id", "?"))
	var rc: Variant = d["required_classes"]
	if typeof(rc) != TYPE_ARRAY:
		e.append("class '%s' field 'required_classes' must be an array" % cls_id)
		return e
	for idx in range(rc.size()):
		var pair: Variant = rc[idx]
		if typeof(pair) != TYPE_ARRAY:
			e.append("class '%s' required_classes[%d] must be a [class_id, level] pair" % [cls_id, idx])
			continue
		if pair.size() != 2:
			e.append("class '%s' required_classes[%d] must have exactly 2 elements" % [cls_id, idx])
			continue
		if typeof(pair[0]) != TYPE_STRING:
			e.append("class '%s' required_classes[%d][0] must be a string (class_id)" % [cls_id, idx])
		if typeof(pair[1]) != TYPE_INT and typeof(pair[1]) != TYPE_FLOAT:
			e.append("class '%s' required_classes[%d][1] must be an integer (level)" % [cls_id, idx])
		elif int(pair[1]) < 1:
			e.append("class '%s' required_classes[%d][1] level must be >= 1" % [cls_id, idx])
	return e


static func validate_ability(d: Dictionary) -> Array[String]:
	var e: Array[String] = []
	if not d.has("id"):
		e.append("ability missing required field 'id'")
	if not d.has("type"):
		e.append("ability '%s' missing required field 'type'" % d.get("id", "?"))
	elif not ABILITY_TYPES.has(str(d["type"])):
		e.append("ability '%s' has unknown type '%s'" % [d.get("id", "?"), d["type"]])
	# Passive abilities are exempt from effect validation
	if d.has("type") and str(d["type"]) != "passive":
		if d.has("effect") and typeof(d["effect"]) == TYPE_DICTIONARY and not d["effect"].is_empty():
			e.append_array(validate_ability_effect(d["effect"], str(d.get("id", "?"))))
	# Accept "ap" or "ap_cost"
	var ap_val: Variant = d.get("ap", d.get("ap_cost", null))
	if ap_val != null and int(ap_val) < 0:
		e.append("ability '%s' has negative ap cost" % d.get("id", "?"))
	var wp_val: Variant = d.get("wp", d.get("wp_cost", null))
	if wp_val != null and int(wp_val) < 0:
		e.append("ability '%s' has negative wp cost" % d.get("id", "?"))
	return e


static func validate_ability_effect(effect: Dictionary, ability_id: String) -> Array[String]:
	var e: Array[String] = []
	if not effect.has("effect_type"):
		e.append("ability '%s' effect missing 'effect_type'" % ability_id)
		return e
	var et: String = str(effect["effect_type"])
	if not EFFECT_TYPES.has(et):
		e.append("ability '%s' has unknown effect_type '%s'" % [ability_id, et])
		return e
	match et:
		"damage":
			if not effect.has("value"):
				e.append("ability '%s' damage effect missing 'value'" % ability_id)
		"heal":
			if not effect.has("value"):
				e.append("ability '%s' heal effect missing 'value'" % ability_id)
		"status":
			for k in ["status_id", "duration"]:
				if not effect.has(k):
					e.append("ability '%s' status effect missing '%s'" % [ability_id, k])
		"buff":
			for k in ["stat", "value", "duration"]:
				if not effect.has(k):
					e.append("ability '%s' buff effect missing '%s'" % [ability_id, k])
			if effect.has("stat") and not StatKey.is_valid_key(str(effect["stat"])):
				e.append("ability '%s' buff targets unknown stat '%s'" % [ability_id, effect["stat"]])
		"revive":
			if not effect.has("value"):
				e.append("ability '%s' revive effect missing 'value'" % ability_id)
	return e


static func validate_item(d: Dictionary) -> Array[String]:
	var e: Array[String] = []
	if not d.has("id"):
		e.append("item missing required field 'id'")
	if not d.has("slot"):
		e.append("item '%s' missing required field 'slot'" % d.get("id", "?"))
	if d.has("slot") and not SLOTS.has(str(d["slot"])):
		e.append("item '%s' has unknown slot '%s'" % [d.get("id", "?"), d["slot"]])
	# passive dict: free-form keys allowed, but values must be numeric
	if d.has("passive") and typeof(d["passive"]) == TYPE_DICTIONARY:
		for pk in d["passive"].keys():
			var pv: Variant = d["passive"][pk]
			if typeof(pv) != TYPE_INT and typeof(pv) != TYPE_FLOAT:
				e.append("item '%s' passive key '%s' has non-numeric value" % [d.get("id", "?"), pk])
	return e


static func validate_character(d: Dictionary) -> Array[String]:
	var e: Array[String] = []
	for key in ["id", "race", "classes", "level", "bp"]:
		if not d.has(key):
			e.append("character missing required field '%s'" % key)
	# Accept "stats" or "base_stats"
	var stats_key := "stats" if d.has("stats") else "base_stats"
	if not d.has(stats_key):
		e.append("character '%s' missing stats" % d.get("id", "?"))
	elif typeof(d[stats_key]) != TYPE_DICTIONARY:
		e.append("character '%s': stats must be a Dictionary" % d.get("id", "?"))
	else:
		var stats_dict: Dictionary = d[stats_key]
		e.append_array(validate_stat_keys(stats_dict, str(d.get("id", "?")), stats_key))
		if not stats_dict.has("hp"):
			e.append("character '%s': stats missing 'hp'" % d.get("id", "?"))
		elif stats_dict["hp"] <= 0:
			e.append("character '%s': hp must be positive" % d.get("id", "?"))
	return e


static func validate_map(d: Dictionary) -> Array[String]:
	var e: Array[String] = []
	if not d.has("id"):
		e.append("map missing required field 'id'")
	if not d.has("tiles"):
		e.append("map '%s' missing required field 'tiles'" % d.get("id", "?"))
	elif typeof(d["tiles"]) != TYPE_ARRAY:
		e.append("map '%s': tiles must be an Array" % d.get("id", "?"))
	else:
		var tile_coords := {}
		for idx in range(d["tiles"].size()):
			var t: Variant = d["tiles"][idx]
			var tq: int = 0
			var tr: int = 0
			var terrain_str: String = ""
			if typeof(t) == TYPE_ARRAY:
				# Alpha A0 condensed format: [q, r, elevation, terrain, (tags)]
				if t.size() < 4:
					e.append("map '%s' tile %d condensed array has < 4 elements" % [d.get("id", "?"), idx])
					continue
				tq = int(t[0])
				tr = int(t[1])
				terrain_str = str(t[3])
			elif typeof(t) == TYPE_DICTIONARY:
				if not t.has("q") or not t.has("r"):
					e.append("map '%s' tile %d missing 'q' or 'r'" % [d.get("id", "?"), idx])
					continue
				tq = int(t["q"])
				tr = int(t["r"])
				terrain_str = str(t.get("terrain", ""))
			else:
				e.append("map '%s' tile %d is not an Array or Dictionary" % [d.get("id", "?"), idx])
				continue
			if not terrain_str.is_empty() and not TERRAINS.has(terrain_str):
				e.append("map '%s' tile (%d,%d) has unknown terrain '%s'" % [
					d.get("id", "?"), tq, tr, terrain_str])
			tile_coords["%d,%d" % [tq, tr]] = true
		# Validate deployment zones reference existing tiles
		if d.has("deployment_zones") and typeof(d["deployment_zones"]) == TYPE_DICTIONARY:
			for zone_name in d["deployment_zones"].keys():
				for coord_str in d["deployment_zones"][zone_name]:
					if not tile_coords.has(str(coord_str)):
						e.append("map '%s' deployment zone '%s' references non-existent tile '%s'" % [
							d.get("id", "?"), zone_name, coord_str])
	return e


# --- Referential integrity (cross-entity) ---

## Accepts a Dictionary of EntityRegistry instances keyed by type name.
## Checks that every referenced ID resolves to an existing entry.
static func validate_references(registries: Dictionary) -> Array[String]:
	var e: Array[String] = []
	# Character references
	for c in registries["characters"].all():
		if not registries["races"].has(c.race):
			e.append("character '%s' references unknown race '%s'" % [c.id, c.race])
		for cls in c.classes:
			if not registries["classes"].has(cls):
				e.append("character '%s' references unknown class '%s'" % [c.id, cls])
		for it in c.equipment:
			if not registries["items"].has(it):
				e.append("character '%s' references unknown item '%s'" % [c.id, it])
		for ab in c.abilities:
			if not registries["abilities"].has(ab):
				e.append("character '%s' references unknown ability '%s'" % [c.id, ab])
	# Class references
	for cls in registries["classes"].all():
		for ab in cls.granted_abilities:
			if not registries["abilities"].has(ab):
				e.append("class '%s' references unknown ability '%s'" % [cls.id, ab])
		for it in cls.equipment_access:
			if not registries["items"].has(it):
				e.append("class '%s' references unknown item '%s'" % [cls.id, it])
		for pair in cls.required_classes:
			var req_id: String = pair[0]
			if not registries["classes"].has(req_id):
				e.append("class '%s' requires unknown class '%s'" % [cls.id, req_id])
	# Item references
	for it in registries["items"].all():
		for ab in it.granted_abilities:
			if not registries["abilities"].has(ab):
				e.append("item '%s' references unknown ability '%s'" % [it.id, ab])
	# Map tile terrain references
	if registries.has("terrains"):
		for m in registries["maps"].all():
			for t in m.tiles:
				if not registries["terrains"].has(t.terrain):
					e.append("map '%s' tile (%d,%d) uses terrain '%s' not in terrain registry" % [
						m.id, t.q, t.r, t.terrain])
	return e
