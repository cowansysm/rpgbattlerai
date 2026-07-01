class_name Validator
extends RefCounted
## Structural and referential validation for content data.
## Accepts both condensed and legacy field names.
## Returns error arrays (empty == valid). Fail-loud philosophy.

const TERRAINS := [
	"grass", "road", "brush", "trees", "rocks",
	"shallow_water", "deep_water", "cliff",
	"rubble", "barricade",
	"lava", "spikes", "bog", "sand",
	"ice", "cursed_ground", "blessed_ground",
]
const SLOTS := ["weapon", "armor", "shield", "accessory", "consumable"]
const ABILITY_TYPES := ["spell", "skill", "item", "passive"]
const EFFECT_TYPES := ["damage", "heal", "status", "buff", "revive"]
const ARCHETYPES := ["", "physical_attack", "physical_defense", "magical_attack", "magical_defense", "support", "control"]


# --- Shared helpers ---

static func validate_stat_keys(d: Dictionary, entity_id: String, field_name: String) -> Array[String]:
	var e: Array[String] = []
	for k in d.keys():
		if not StatKey.is_valid_key(str(k)):
			e.append("%s '%s' has unknown stat key '%s' in %s" % ["entity", entity_id, k, field_name])
	return e


## A16: Validate an affinities dict {element: tier_name}.
## Element keys must be in Affinity.ELEMENTS, tier values in Affinity.TIER_NAMES.
static func validate_affinities(d: Dictionary, entity_id: String, entity_type: String) -> Array[String]:
	var e: Array[String] = []
	for elem in d.keys():
		if not Affinity.ELEMENTS.has(str(elem)):
			e.append("%s '%s' affinities has unknown element '%s'" % [entity_type, entity_id, elem])
		var tier_name: String = str(d[elem])
		if not Affinity.TIER_NAMES.has(tier_name):
			e.append("%s '%s' affinities element '%s' has unknown tier '%s'" % [entity_type, entity_id, elem, tier_name])
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
	# A4: Validate base_stats keys
	if d.has("base_stats") and typeof(d["base_stats"]) == TYPE_DICTIONARY:
		e.append_array(validate_stat_keys(d["base_stats"], str(d.get("id", "?")), "base_stats"))
	# A16: Validate affinities
	if d.has("affinities") and typeof(d["affinities"]) == TYPE_DICTIONARY:
		e.append_array(validate_affinities(d["affinities"], str(d.get("id", "?")), "race"))
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
	# A4: Validate archetype enum
	if d.has("archetype") and not ARCHETYPES.has(str(d["archetype"])):
		e.append("class '%s' has unknown archetype '%s'" % [d.get("id", "?"), d["archetype"]])
	# A11: Validate tier is a non-negative integer
	if d.has("tier"):
		if typeof(d["tier"]) != TYPE_INT and typeof(d["tier"]) != TYPE_FLOAT:
			e.append("class '%s' tier must be an integer" % d.get("id", "?"))
		elif int(d["tier"]) < 0:
			e.append("class '%s' tier must be >= 0" % d.get("id", "?"))
	# A4: Validate growth keys are valid stat keys
	if d.has("growth") and typeof(d["growth"]) == TYPE_DICTIONARY:
		e.append_array(validate_stat_keys(d["growth"], str(d.get("id", "?")), "growth"))
	# A4: Validate jp_costs values are non-negative
	if d.has("jp_costs") and typeof(d["jp_costs"]) == TYPE_DICTIONARY:
		for ab_id in d["jp_costs"].keys():
			var cost: Variant = d["jp_costs"][ab_id]
			if (typeof(cost) != TYPE_INT and typeof(cost) != TYPE_FLOAT) or int(cost) < 0:
				e.append("class '%s' jp_costs['%s'] must be a non-negative integer" % [d.get("id", "?"), ab_id])
	# A4: Validate prerequisites structure
	if d.has("prerequisites") and typeof(d["prerequisites"]) == TYPE_DICTIONARY:
		e.append_array(_validate_prerequisites_structure(d))
	# A16: Validate affinities
	if d.has("affinities") and typeof(d["affinities"]) == TYPE_DICTIONARY:
		e.append_array(validate_affinities(d["affinities"], str(d.get("id", "?")), "class"))
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


static func _validate_prerequisites_structure(d: Dictionary) -> Array[String]:
	var e: Array[String] = []
	var cls_id: String = str(d.get("id", "?"))
	var pre: Dictionary = d["prerequisites"]
	if pre.has("level"):
		if typeof(pre["level"]) != TYPE_INT and typeof(pre["level"]) != TYPE_FLOAT:
			e.append("class '%s' prerequisites.level must be an integer" % cls_id)
		elif int(pre["level"]) < 0:
			e.append("class '%s' prerequisites.level must be >= 0" % cls_id)
	if pre.has("classes"):
		if typeof(pre["classes"]) != TYPE_ARRAY:
			e.append("class '%s' prerequisites.classes must be an array" % cls_id)
		else:
			for idx in range(pre["classes"].size()):
				var pair: Variant = pre["classes"][idx]
				if typeof(pair) != TYPE_ARRAY or pair.size() != 2:
					e.append("class '%s' prerequisites.classes[%d] must be a [class_id, threshold] pair" % [cls_id, idx])
					continue
				if typeof(pair[0]) != TYPE_STRING:
					e.append("class '%s' prerequisites.classes[%d][0] must be a string" % [cls_id, idx])
				if typeof(pair[1]) != TYPE_INT and typeof(pair[1]) != TYPE_FLOAT:
					e.append("class '%s' prerequisites.classes[%d][1] must be an integer" % [cls_id, idx])
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
	# A16: Validate element if present on any effect type
	if effect.has("element") and not Affinity.ELEMENTS.has(str(effect["element"])):
		e.append("ability '%s' effect has unknown element '%s'" % [ability_id, effect["element"]])
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
	# slot is optional (empty or absent = consumable); if present and non-empty, must be valid
	if d.has("slot") and str(d["slot"]) != "" and not SLOTS.has(str(d["slot"])):
		e.append("item '%s' has unknown slot '%s'" % [d.get("id", "?"), d["slot"]])
	# price must be int >= -1 when present
	if d.has("price"):
		var p: Variant = d["price"]
		if typeof(p) != TYPE_INT and typeof(p) != TYPE_FLOAT:
			e.append("item '%s' price must be numeric" % d.get("id", "?"))
		elif int(p) < -1:
			e.append("item '%s' price must be >= -1" % d.get("id", "?"))
	# passive dict: free-form keys allowed, but values must be numeric
	if d.has("passive") and typeof(d["passive"]) == TYPE_DICTIONARY:
		for pk in d["passive"].keys():
			var pv: Variant = d["passive"][pk]
			if typeof(pv) != TYPE_INT and typeof(pv) != TYPE_FLOAT:
				e.append("item '%s' passive key '%s' has non-numeric value" % [d.get("id", "?"), pk])
	# A16: Validate affinities
	if d.has("affinities") and typeof(d["affinities"]) == TYPE_DICTIONARY:
		e.append_array(validate_affinities(d["affinities"], str(d.get("id", "?")), "item"))
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


## Validates map structure. When known_terrains is provided (non-empty),
## terrain IDs are checked against that list instead of the hardcoded TERRAINS const.
static func validate_map(d: Dictionary, known_terrains: Array[String] = []) -> Array[String]:
	var e: Array[String] = []
	var terrain_list: Array = known_terrains if not known_terrains.is_empty() else TERRAINS
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
			if not terrain_str.is_empty() and not terrain_list.has(terrain_str):
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
		# A4: Validate prerequisites.classes references
		for pair in cls.prerequisites.get("classes", []):
			if typeof(pair) == TYPE_ARRAY and pair.size() == 2:
				if not registries["classes"].has(str(pair[0])):
					e.append("class '%s' prerequisite references unknown class '%s'" % [cls.id, pair[0]])
		# A4: Validate jp_costs ability references
		for ab_id in cls.jp_costs.keys():
			if not registries["abilities"].has(str(ab_id)):
				e.append("class '%s' jp_costs references unknown ability '%s'" % [cls.id, ab_id])
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
	# A11: Encounter references
	if registries.has("encounters"):
		e.append_array(validate_encounter_references(
			registries["encounters"], registries["characters"], registries["maps"]))
	# A9: Job tree structural validation
	if registries.has("classes"):
		e.append_array(validate_job_tree(registries["classes"]))
	return e


# --- Job tree validation (A11: n-tier model) ---

## Validates the class job tree is structurally sound:
## - At least one root class (no prerequisites.classes) exists
## - Acyclic prerequisite graph
## - All classes reachable from some root via prerequisite chains
## - Tier consistency: prerequisites must have strictly smaller tier;
##   authored tier must match the transitive prerequisite closure size
static func validate_job_tree(classes_reg: EntityRegistry) -> Array[String]:
	var e: Array[String] = []
	if classes_reg.size() == 0:
		return e

	# 1. Find roots: classes with no prerequisite classes
	#    (includes vagabond + all monster classes)
	var roots: Array[String] = []
	for cls in classes_reg.all():
		var prereq_classes: Array = cls.prerequisites.get("classes", [])
		if prereq_classes.is_empty():
			roots.append(cls.id)
	if roots.is_empty():
		e.append("job tree has no root classes (no class with empty prerequisites.classes)")
		return e

	# 2. Build children_of graph (parent_id → [child_ids])
	var children_of: Dictionary = {}
	for cls in classes_reg.all():
		var prereq_classes: Array = cls.prerequisites.get("classes", [])
		for pair in prereq_classes:
			if typeof(pair) == TYPE_ARRAY and pair.size() == 2:
				var parent_id: String = str(pair[0])
				if not children_of.has(parent_id):
					children_of[parent_id] = []
				children_of[parent_id].append(cls.id)

	# 3. Cycle detection via DFS on prerequisite graph
	var visited: Dictionary = {}
	var in_stack: Dictionary = {}
	for cls in classes_reg.all():
		if not visited.has(cls.id):
			e.append_array(_dfs_cycle_check(cls.id, classes_reg, visited, in_stack))

	# 4. Reachability: BFS from all roots
	var reachable: Dictionary = {}
	var queue: Array[String] = []
	for root_id in roots:
		queue.append(root_id)
		reachable[root_id] = true
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for child_id in children_of.get(current, []):
			if not reachable.has(child_id):
				reachable[child_id] = true
				queue.append(child_id)
	for cls in classes_reg.all():
		if not reachable.has(cls.id):
			e.append("class '%s' is not reachable from any root class (orphan)" % cls.id)

	# 5. Tier consistency (n-tier rules)
	for cls in classes_reg.all():
		var prereq_classes: Array = cls.prerequisites.get("classes", [])
		if prereq_classes.is_empty():
			# Root classes must have tier 0
			if cls.tier != 0:
				e.append("root class '%s' must have tier 0, has %d" % [cls.id, cls.tier])
		else:
			# Every prerequisite class must have a strictly smaller tier
			for pair in prereq_classes:
				if typeof(pair) == TYPE_ARRAY and pair.size() == 2:
					var req_cls: ClassData = classes_reg.get_entry(str(pair[0]))
					if req_cls and req_cls.tier >= cls.tier:
						e.append("class '%s' (tier %d) has prerequisite '%s' (tier %d) which is not strictly lower" % [
							cls.id, cls.tier, req_cls.id, req_cls.tier])
		# Verify authored tier matches computed closure size
		var closure_size: int = _compute_closure_size(cls.id, classes_reg)
		if closure_size != cls.tier:
			e.append("class '%s' authored tier %d does not match computed closure size %d" % [
				cls.id, cls.tier, closure_size])
	return e


## Computes the transitive prerequisite closure size for a class.
## The closure is the set of all ancestor classes reachable via prerequisites.
static func _compute_closure_size(cls_id: String, classes_reg: EntityRegistry) -> int:
	var closure: Dictionary = {}
	var stack: Array = [cls_id]
	while not stack.is_empty():
		var current: String = str(stack.pop_back())
		var cls: ClassData = classes_reg.get_entry(current)
		if cls == null:
			continue
		for pair in cls.prerequisites.get("classes", []):
			if typeof(pair) == TYPE_ARRAY and pair.size() == 2:
				var parent_id: String = str(pair[0])
				if not closure.has(parent_id):
					closure[parent_id] = true
					stack.append(parent_id)
	return closure.size()


## DFS cycle detection on the prerequisite graph.
static func _dfs_cycle_check(cls_id: String, classes_reg: EntityRegistry,
		visited: Dictionary, in_stack: Dictionary) -> Array[String]:
	var e: Array[String] = []
	visited[cls_id] = true
	in_stack[cls_id] = true
	var cls: ClassData = classes_reg.get_entry(cls_id)
	if cls:
		var prereq_classes: Array = cls.prerequisites.get("classes", [])
		for pair in prereq_classes:
			if typeof(pair) == TYPE_ARRAY and pair.size() == 2:
				var parent_id: String = str(pair[0])
				if in_stack.has(parent_id):
					e.append("job tree cycle detected: '%s' → '%s'" % [cls_id, parent_id])
				elif not visited.has(parent_id) and classes_reg.has(parent_id):
					e.append_array(_dfs_cycle_check(parent_id, classes_reg, visited, in_stack))
	in_stack.erase(cls_id)
	return e


## Structural validation for an encounter definition.
static func validate_encounter(d: Dictionary) -> Array[String]:
	var e: Array[String] = []
	if not d.has("id"):
		e.append("encounter missing required field 'id'")
	if not d.has("enemies") or typeof(d["enemies"]) != TYPE_ARRAY:
		e.append("encounter '%s' missing or invalid 'enemies' array" % d.get("id", "?"))
	else:
		if d["enemies"].is_empty():
			e.append("encounter '%s' has empty enemies list" % d.get("id", "?"))
		for idx in range(d["enemies"].size()):
			var entry: Variant = d["enemies"][idx]
			if typeof(entry) != TYPE_DICTIONARY:
				e.append("encounter '%s' enemies[%d] must be a dict" % [d.get("id", "?"), idx])
				continue
			if not entry.has("character"):
				e.append("encounter '%s' enemies[%d] missing 'character'" % [d.get("id", "?"), idx])
			if not entry.has("count") or int(entry.get("count", 0)) < 1:
				e.append("encounter '%s' enemies[%d] count must be >= 1" % [d.get("id", "?"), idx])
	if d.has("min_band_level") and int(d.get("min_band_level", 1)) < 1:
		e.append("encounter '%s' min_band_level must be >= 1" % d.get("id", "?"))
	if d.has("weight") and float(d.get("weight", 1.0)) < 0.0:
		e.append("encounter '%s' weight must be >= 0" % d.get("id", "?"))
	return e


## Referential validation for encounters: enemy characters and map IDs must exist.
static func validate_encounter_references(encounters_reg: EntityRegistry,
		characters_reg: EntityRegistry, maps_reg: EntityRegistry) -> Array[String]:
	var e: Array[String] = []
	for enc in encounters_reg.all():
		for entry in enc.enemies:
			if typeof(entry) == TYPE_DICTIONARY:
				var char_id: String = str(entry.get("character", ""))
				if not char_id.is_empty() and not characters_reg.has(char_id):
					e.append("encounter '%s' references unknown character '%s'" % [enc.id, char_id])
		if not enc.map_id.is_empty() and not maps_reg.has(enc.map_id):
			e.append("encounter '%s' references unknown map '%s'" % [enc.id, enc.map_id])
	return e


## Validates shop pool item references against the items registry.
static func validate_shop_pools(pools: Dictionary, items_reg: EntityRegistry) -> Array[String]:
	var e: Array[String] = []
	for pool_id in pools.keys():
		var pool: Variant = pools[pool_id]
		if not pool is Array:
			e.append("shop pool '%s' must be an Array" % pool_id)
			continue
		for item_id in (pool as Array):
			if not items_reg.has(str(item_id)):
				e.append("shop pool '%s' references unknown item '%s'" % [pool_id, item_id])
	return e


## Validates loot table structure and references.
static func validate_loot_tables(tables: Dictionary, pools: Dictionary,
		items_reg: EntityRegistry) -> Array[String]:
	var e: Array[String] = []
	var valid_kinds: Array = ["equipment", "consumable", "nothing"]
	for table_id in tables.keys():
		var table: Variant = tables[table_id]
		if not table is Dictionary:
			e.append("loot table '%s' must be a Dictionary" % table_id)
			continue
		var td: Dictionary = table as Dictionary
		# Validate gold range
		var gold: Variant = td.get("gold", {})
		if gold is Dictionary:
			var gd: Dictionary = gold as Dictionary
			var gmin: int = int(gd.get("min", 0))
			var gmax: int = int(gd.get("max", 0))
			if gmin < 0:
				e.append("loot table '%s' gold.min must be >= 0" % table_id)
			if gmax < gmin:
				e.append("loot table '%s' gold.max must be >= gold.min" % table_id)
		# Validate rolls
		var rolls: int = int(td.get("rolls", 1))
		if rolls < 1:
			e.append("loot table '%s' rolls must be >= 1" % table_id)
		# Validate drops
		var drops: Variant = td.get("drops", [])
		if not drops is Array:
			e.append("loot table '%s' drops must be an Array" % table_id)
			continue
		for drop in (drops as Array):
			if not drop is Dictionary:
				continue
			var dd: Dictionary = drop as Dictionary
			var kind: String = str(dd.get("kind", ""))
			if not valid_kinds.has(kind):
				e.append("loot table '%s' drop has unknown kind '%s'" % [table_id, kind])
			if kind == "equipment":
				var pool_id: String = str(dd.get("pool", ""))
				if not pools.has(pool_id):
					e.append("loot table '%s' drop references unknown pool '%s'" % [table_id, pool_id])
			if kind == "consumable":
				if not dd.has("id"):
					e.append("loot table '%s' consumable drop missing 'id'" % table_id)
				elif not items_reg.has(str(dd["id"])):
					e.append("loot table '%s' consumable drop references unknown item '%s'" % [table_id, dd["id"]])
	return e
