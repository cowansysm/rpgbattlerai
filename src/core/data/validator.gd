class_name Validator
extends RefCounted
## Structural and referential validation for content data.
## Returns error arrays (empty == valid). Fail-loud philosophy.

const TERRAINS := ["grass", "road", "brush", "trees", "rocks", "shallow_water", "deep_water", "cliff"]
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
	for key in ["id", "display_name"]:
		if not d.has(key):
			e.append("race missing required field '%s'" % key)
	if d.has("stat_modifiers") and typeof(d["stat_modifiers"]) == TYPE_DICTIONARY:
		e.append_array(validate_stat_keys(d["stat_modifiers"], str(d.get("id", "?")), "stat_modifiers"))
	return e


static func validate_class(d: Dictionary) -> Array[String]:
	var e: Array[String] = []
	if not d.has("id"):
		e.append("class missing required field 'id'")
	if d.has("stat_modifiers") and typeof(d["stat_modifiers"]) == TYPE_DICTIONARY:
		e.append_array(validate_stat_keys(d["stat_modifiers"], str(d.get("id", "?")), "stat_modifiers"))
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
	if d.has("ap_cost") and int(d["ap_cost"]) < 0:
		e.append("ability '%s' has negative ap_cost" % d.get("id", "?"))
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
	for key in ["id", "slot"]:
		if not d.has(key):
			e.append("item missing required field '%s'" % key)
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
	if not d.has("base_stats"):
		e.append("character missing required field 'base_stats'")
	elif typeof(d["base_stats"]) != TYPE_DICTIONARY:
		e.append("character '%s': base_stats must be a Dictionary" % d.get("id", "?"))
	else:
		var stats_dict: Dictionary = d["base_stats"]
		e.append_array(validate_stat_keys(stats_dict, str(d.get("id", "?")), "base_stats"))
		if not stats_dict.has("hp"):
			e.append("character '%s': base_stats missing 'hp'" % d.get("id", "?"))
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
			if typeof(t) != TYPE_DICTIONARY:
				e.append("map '%s' tile %d is not a Dictionary" % [d.get("id", "?"), idx])
				continue
			if not t.has("q") or not t.has("r"):
				e.append("map '%s' tile %d missing 'q' or 'r'" % [d.get("id", "?"), idx])
				continue
			if t.has("terrain") and not TERRAINS.has(str(t["terrain"])):
				e.append("map '%s' tile (%d,%d) has unknown terrain '%s'" % [
					d.get("id", "?"), int(t["q"]), int(t["r"]), t["terrain"]])
			tile_coords["%d,%d" % [int(t["q"]), int(t["r"])]] = true
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
	# Item references
	for it in registries["items"].all():
		for ab in it.granted_abilities:
			if not registries["abilities"].has(ab):
				e.append("item '%s' references unknown ability '%s'" % [it.id, ab])
	# Map tile terrain references — verify every terrain used by maps exists
	# in the terrain registry (if present). Structural validation via
	# const TERRAINS catches typos early; this cross-checks against loaded data.
	if registries.has("terrains"):
		for m in registries["maps"].all():
			for t in m.tiles:
				if not registries["terrains"].has(t.terrain):
					e.append("map '%s' tile (%d,%d) uses terrain '%s' not in terrain registry" % [
						m.id, t.q, t.r, t.terrain])
	return e
