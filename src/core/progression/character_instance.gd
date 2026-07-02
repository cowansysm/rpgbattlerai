class_name CharacterInstance
extends RefCounted
## Persistent, mutable character instance generated from a template.
## Holds all per-character progression state: class_levels, XP, JP, learned abilities,
## active class, equipment, and accumulated growth.
## Spec reference: alpha-phaseA4-spec.md §4

var instance_id: String = ""
var template_id: String = ""
var name: String = ""
var race: String = ""
var class_levels: Dictionary = {}
var xp: int = 0
var active_class: String = "vagabond"
var unlocked_classes: Array[String] = ["vagabond"]
var jp: Dictionary = {}
var learned_abilities: Array[String] = []
var ability_loadout: Array[String] = []
var equipment: Dictionary = {}
var growth_accumulated: Dictionary = {}
var downs_this_run: int = 0

## A18: equipped passive slots (one per category)
var reaction_slot: String = ""
var support_slot: String = ""
var movement_slot: String = ""


## Sum of all class levels (minimum 1).
func character_level() -> int:
	var total: int = 0
	for lv in class_levels.values():
		total += int(lv)
	return maxi(1, total)


## Level in the currently active class.
func active_class_level() -> int:
	return int(class_levels.get(active_class, 0))


## Increments active class level by 1, applies growth. Returns true on success.
func increment_active_class_level(class_provider: Callable, level_max: int = 10) -> bool:
	var current: int = active_class_level()
	if current >= level_max:
		return false
	class_levels[active_class] = current + 1
	_apply_growth(class_provider)
	return true


static func generate(template: CharacterData, name_gen: Callable,
		bonus_classes: Array[String] = []) -> CharacterInstance:
	var ci := CharacterInstance.new()
	ci.instance_id = _generate_id()
	ci.template_id = template.id
	ci.race = template.race
	ci.name = name_gen.call(template.race)
	# Use template's first class as starting class (vagabond for players, monster class for monsters)
	var starting_class: String = template.classes[0] if not template.classes.is_empty() else "vagabond"
	ci.unlocked_classes = [starting_class]
	for cls_id in bonus_classes:
		if not ci.unlocked_classes.has(cls_id):
			ci.unlocked_classes.append(cls_id)
	ci.active_class = starting_class
	ci.class_levels = {starting_class: 1}
	ci.xp = 0
	return ci


## Adds JP to the specified class.
func gain_jp(class_id: String, amount: int) -> void:
	jp[class_id] = int(jp.get(class_id, 0)) + amount


## Attempts to learn an ability by spending JP. Returns true on success.
func learn_ability(ability_id: String, class_id: String, class_provider: Callable) -> bool:
	if not unlocked_classes.has(class_id):
		return false
	var cls: ClassData = class_provider.call(class_id)
	if cls == null:
		return false
	var cost: int = int(cls.jp_costs.get(ability_id, -1))
	if cost < 0:
		return false
	if int(jp.get(class_id, 0)) < cost:
		return false
	jp[class_id] = int(jp.get(class_id, 0)) - cost
	if not learned_abilities.has(ability_id):
		learned_abilities.append(ability_id)
	return true


## Returns whether the given class can be unlocked based on prerequisites.
func can_unlock(class_id: String, class_provider: Callable) -> bool:
	if unlocked_classes.has(class_id):
		return false
	var cls: ClassData = class_provider.call(class_id)
	if cls == null:
		return false
	var pre: Dictionary = cls.prerequisites
	if pre.is_empty():
		return true
	if character_level() < int(pre.get("level", 0)):
		return false
	for pair in pre.get("classes", []):
		var req_class: String = str(pair[0])
		var req_level: int = int(pair[1]) if pair.size() > 1 else 1
		if int(class_levels.get(req_class, 0)) < req_level:
			return false
	return true


## Attempts to unlock a class. Returns true on success.
func unlock_class(class_id: String, class_provider: Callable) -> bool:
	if not can_unlock(class_id, class_provider):
		return false
	unlocked_classes.append(class_id)
	return true


## Sets the active class. Must be unlocked. Returns true on success.
func set_active_class(class_id: String) -> bool:
	if not unlocked_classes.has(class_id):
		return false
	active_class = class_id
	return true


## A18: Equips a learned passive ability into its matching slot by passive_kind.
## Requires the ability to be learned and have the matching passive_kind.
## Returns true on success, false on rejection.
func equip_passive(ability_id: String, ability_provider: Callable) -> bool:
	if not learned_abilities.has(ability_id):
		return false
	if not ability_provider.is_valid():
		return false
	var ab: AbilityData = ability_provider.call(ability_id)
	if ab == null:
		return false
	match ab.passive_kind:
		"reaction":
			reaction_slot = ability_id
			return true
		"support":
			support_slot = ability_id
			return true
		"movement":
			movement_slot = ability_id
			return true
	return false


## A18: Clears the passive slot for the given kind ("reaction"|"support"|"movement").
func unequip_passive(kind: String) -> void:
	match kind:
		"reaction":
			reaction_slot = ""
		"support":
			support_slot = ""
		"movement":
			movement_slot = ""


## Sets the ability loadout. Must be a subset of learned_abilities and within slot cap.
func set_loadout(abilities: Array[String], max_slots: int = 6) -> bool:
	if abilities.size() > max_slots:
		return false
	for ab in abilities:
		if not learned_abilities.has(ab):
			return false
	ability_loadout = abilities.duplicate()
	return true


## Equips an item to a slot. Validates slot name and class equipment access.
func equip(slot: String, item_id: String, class_provider: Callable, item_provider: Callable) -> bool:
	var item: ItemData = item_provider.call(item_id)
	if item == null:
		return false
	if item.slot != slot:
		return false
	var cls: ClassData = class_provider.call(active_class)
	if cls == null:
		return false
	if not cls.equipment_access.has(item_id):
		return false
	equipment[slot] = item_id
	return true


## Removes equipment from a slot.
func unequip(slot: String) -> void:
	equipment.erase(slot)


## Builds a transient read-only CharacterData snapshot for the combat layer.
## A18: copies passive slots so the combat layer can read them via BattleUnit.
func to_character_data(stat_block: StatBlock) -> CharacterData:
	var c := CharacterData.new()
	c.id = instance_id
	c.display_name = name
	c.race = race
	c.classes = [active_class]
	c.level = character_level()
	c.bp = 0
	c.equipment = _equipment_array()
	c.abilities = ability_loadout.duplicate()
	c.base_stats = {}
	for k in StatKey.all_strings():
		c.base_stats[k] = stat_block.base(k)
	# A18: carry passive slot selections into the combat snapshot
	c.reaction_passive = reaction_slot
	c.support_passive = support_slot
	c.movement_passive = movement_slot
	return c


func _equipment_array() -> Array[String]:
	var out: Array[String] = []
	for slot in equipment.keys():
		out.append(str(equipment[slot]))
	return out


func _apply_growth(class_provider: Callable) -> void:
	var cls: ClassData = class_provider.call(active_class)
	if cls == null:
		return
	for k in cls.growth.keys():
		var rate: float = float(cls.growth[k])
		var current: float = float(growth_accumulated.get(k, 0))
		growth_accumulated[k] = int(floor(current + rate))


## Serializes all instance state to a plain Dictionary for JSON persistence.
func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"template_id": template_id,
		"name": name,
		"race": race,
		"class_levels": class_levels.duplicate(),
		"xp": xp,
		"active_class": active_class,
		"unlocked_classes": unlocked_classes.duplicate(),
		"jp": jp.duplicate(),
		"learned_abilities": learned_abilities.duplicate(),
		"ability_loadout": ability_loadout.duplicate(),
		"equipment": equipment.duplicate(),
		"growth_accumulated": growth_accumulated.duplicate(),
		"downs_this_run": downs_this_run,
		# A18: passive slots
		"reaction_slot": reaction_slot,
		"support_slot": support_slot,
		"movement_slot": movement_slot,
	}


## Reconstructs a CharacterInstance from a saved Dictionary.
## Uses defaults for any missing keys (forward-compatible).
static func from_dict(d: Dictionary) -> CharacterInstance:
	var ci := CharacterInstance.new()
	ci.instance_id = str(d.get("instance_id", ""))
	ci.template_id = str(d.get("template_id", ""))
	ci.name = str(d.get("name", ""))
	ci.race = str(d.get("race", ""))
	ci.active_class = str(d.get("active_class", "vagabond"))
	# Migration: old saves have "level" instead of "class_levels"
	if d.has("class_levels"):
		ci.class_levels = _to_int_dict(d["class_levels"])
	elif d.has("level"):
		ci.class_levels = {ci.active_class: maxi(1, int(d["level"]))}
	else:
		ci.class_levels = {ci.active_class: 1}
	ci.xp = int(d.get("xp", 0))
	ci.unlocked_classes = _to_str_array(d.get("unlocked_classes", ["vagabond"]))
	ci.jp = _to_int_dict(d.get("jp", {}))
	ci.learned_abilities = _to_str_array(d.get("learned_abilities", []))
	ci.ability_loadout = _to_str_array(d.get("ability_loadout", []))
	ci.equipment = _to_str_dict(d.get("equipment", {}))
	ci.growth_accumulated = _to_int_dict(d.get("growth_accumulated", {}))
	ci.downs_this_run = int(d.get("downs_this_run", 0))
	# A18: passive slots — default "" for save migration safety
	ci.reaction_slot = str(d.get("reaction_slot", ""))
	ci.support_slot = str(d.get("support_slot", ""))
	ci.movement_slot = str(d.get("movement_slot", ""))
	return ci


static func _to_str_array(arr: Variant) -> Array[String]:
	var out: Array[String] = []
	if arr is Array:
		for item in arr:
			out.append(str(item))
	return out


static func _to_int_dict(d: Variant) -> Dictionary:
	var out: Dictionary = {}
	if d is Dictionary:
		for key in d.keys():
			out[str(key)] = int(d[key])
	return out


static func _to_str_dict(d: Variant) -> Dictionary:
	var out: Dictionary = {}
	if d is Dictionary:
		for key in d.keys():
			out[str(key)] = str(d[key])
	return out


static func _generate_id() -> String:
	var t: int = Time.get_ticks_usec()
	var r: int = randi()
	return "ci_%x_%x" % [t, r]
