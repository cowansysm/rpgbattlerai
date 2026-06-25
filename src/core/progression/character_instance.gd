class_name CharacterInstance
extends RefCounted
## Persistent, mutable character instance generated from a template.
## Holds all per-character progression state: level, XP, JP, learned abilities,
## active class, equipment, and accumulated growth.
## Spec reference: alpha-phaseA4-spec.md §4

var instance_id: String = ""
var template_id: String = ""
var name: String = ""
var race: String = ""
var level: int = 1
var xp: int = 0
var active_class: String = "vagabond"
var unlocked_classes: Array[String] = ["vagabond"]
var jp: Dictionary = {}
var learned_abilities: Array[String] = []
var ability_loadout: Array[String] = []
var equipment: Dictionary = {}
var growth_accumulated: Dictionary = {}
var downs_this_run: int = 0


static func generate(template: CharacterData, name_gen: Callable,
		bonus_classes: Array[String] = []) -> CharacterInstance:
	var ci := CharacterInstance.new()
	ci.instance_id = _generate_id()
	ci.template_id = template.id
	ci.race = template.race
	ci.name = name_gen.call(template.race)
	ci.unlocked_classes = ["vagabond"]
	for cls_id in bonus_classes:
		if not ci.unlocked_classes.has(cls_id):
			ci.unlocked_classes.append(cls_id)
	ci.active_class = "vagabond"
	ci.level = 1
	ci.xp = 0
	return ci


## Returns the XP threshold to reach the given level.
static func xp_for_level(lv: int, curve_base: int = 10) -> int:
	return curve_base * lv * lv


## Returns XP needed for next level-up from current state.
func xp_for_next_level(curve_base: int = 10) -> int:
	return xp_for_level(level + 1, curve_base)


## Adds XP, levels up when thresholds are crossed, accumulates growth.
## Returns the number of levels gained.
func gain_xp(amount: int, class_provider: Callable, max_level: int = 50, curve_base: int = 10) -> int:
	xp += amount
	var levels_gained: int = 0
	while level < max_level and xp >= xp_for_level(level + 1, curve_base):
		level += 1
		levels_gained += 1
		_apply_growth(class_provider)
	return levels_gained


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
	if level < int(pre.get("level", 0)):
		return false
	for pair in pre.get("classes", []):
		if not unlocked_classes.has(str(pair[0])):
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
func to_character_data(stat_block: StatBlock) -> CharacterData:
	var c := CharacterData.new()
	c.id = instance_id
	c.display_name = name
	c.race = race
	c.classes = [active_class]
	c.level = level
	c.bp = 0
	c.equipment = _equipment_array()
	c.abilities = ability_loadout.duplicate()
	c.base_stats = {}
	for k in StatKey.all_strings():
		c.base_stats[k] = stat_block.base(k)
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
		"level": level,
		"xp": xp,
		"active_class": active_class,
		"unlocked_classes": unlocked_classes.duplicate(),
		"jp": jp.duplicate(),
		"learned_abilities": learned_abilities.duplicate(),
		"ability_loadout": ability_loadout.duplicate(),
		"equipment": equipment.duplicate(),
		"growth_accumulated": growth_accumulated.duplicate(),
		"downs_this_run": downs_this_run,
	}


## Reconstructs a CharacterInstance from a saved Dictionary.
## Uses defaults for any missing keys (forward-compatible).
static func from_dict(d: Dictionary) -> CharacterInstance:
	var ci := CharacterInstance.new()
	ci.instance_id = str(d.get("instance_id", ""))
	ci.template_id = str(d.get("template_id", ""))
	ci.name = str(d.get("name", ""))
	ci.race = str(d.get("race", ""))
	ci.level = int(d.get("level", 1))
	ci.xp = int(d.get("xp", 0))
	ci.active_class = str(d.get("active_class", "vagabond"))
	ci.unlocked_classes = _to_str_array(d.get("unlocked_classes", ["vagabond"]))
	ci.jp = _to_int_dict(d.get("jp", {}))
	ci.learned_abilities = _to_str_array(d.get("learned_abilities", []))
	ci.ability_loadout = _to_str_array(d.get("ability_loadout", []))
	ci.equipment = _to_str_dict(d.get("equipment", {}))
	ci.growth_accumulated = _to_int_dict(d.get("growth_accumulated", {}))
	ci.downs_this_run = int(d.get("downs_this_run", 0))
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
