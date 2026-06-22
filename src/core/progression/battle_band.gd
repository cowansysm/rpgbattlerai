class_name BattleBand
extends RefCounted
## Persistent roster container: characters, shared inventory, and gold.
## Spec reference: alpha-phaseA5-spec.md §3

var band_id: String = ""
var name: String = "New Band"
var roster: Array[CharacterInstance] = []
var inventory: Dictionary = {"equipment": [], "consumables": []}
var gold: int = 0


static func create(band_name: String) -> BattleBand:
	var band := BattleBand.new()
	band.band_id = _generate_id()
	band.name = band_name
	band.roster = []
	band.inventory = {"equipment": [], "consumables": []}
	band.gold = 0
	return band


func roster_size() -> int:
	return roster.size()


func is_roster_full(cap: int = -1) -> bool:
	if cap < 0:
		cap = Constants.get_value("ROSTER_CAP", 12)
	return roster.size() >= cap


func add_instance(ci: CharacterInstance, cap: int = -1) -> bool:
	if is_roster_full(cap):
		return false
	roster.append(ci)
	return true


## Removes an instance by id. Unequips all gear back to inventory first.
## Returns the removed instance or null if not found.
func remove_instance(instance_id: String) -> CharacterInstance:
	for i in range(roster.size()):
		if roster[i].instance_id == instance_id:
			var ci: CharacterInstance = roster[i]
			# Return all equipped gear to inventory
			for slot in ci.equipment.keys():
				var item_id: String = str(ci.equipment[slot])
				add_to_inventory(item_id)
			ci.equipment.clear()
			roster.remove_at(i)
			return ci
	return null


func get_instance(instance_id: String) -> CharacterInstance:
	for ci in roster:
		if ci.instance_id == instance_id:
			return ci
	return null


func add_to_inventory(item_id: String) -> void:
	(inventory["equipment"] as Array).append(item_id)


func remove_from_inventory(item_id: String) -> bool:
	var equip_list: Array = inventory["equipment"] as Array
	var idx: int = equip_list.find(item_id)
	if idx < 0:
		return false
	equip_list.remove_at(idx)
	return true


## Assigns equipment from band inventory to an instance's slot.
## Returns the displaced item (if any) to inventory. Returns true on success.
func assign_equipment(ci: CharacterInstance, slot: String, item_id: String,
		class_provider: Callable, item_provider: Callable) -> bool:
	if not remove_from_inventory(item_id):
		return false
	# Return currently equipped item to inventory
	if ci.equipment.has(slot):
		add_to_inventory(str(ci.equipment[slot]))
	if not ci.equip(slot, item_id, class_provider, item_provider):
		# Equip failed (class restriction, etc.) — return item to inventory
		add_to_inventory(item_id)
		return false
	return true


## Adds a consumable to inventory, stacking by id.
func add_consumable(item_id: String, qty: int = 1) -> void:
	var consumables: Array = inventory["consumables"] as Array
	for entry in consumables:
		if entry is Dictionary and str(entry["id"]) == item_id:
			entry["qty"] = int(entry["qty"]) + qty
			return
	consumables.append({"id": item_id, "qty": qty})


## Removes a consumable from inventory. Returns false if not held or insufficient qty.
func remove_consumable(item_id: String, qty: int = 1) -> bool:
	var consumables: Array = inventory["consumables"] as Array
	for i in range(consumables.size()):
		var entry: Variant = consumables[i]
		if entry is Dictionary and str(entry["id"]) == item_id:
			var current: int = int(entry["qty"])
			if current < qty:
				return false
			if current == qty:
				consumables.remove_at(i)
			else:
				entry["qty"] = current - qty
			return true
	return false


func has_consumable(item_id: String) -> bool:
	return consumable_qty(item_id) > 0


func consumable_qty(item_id: String) -> int:
	var consumables: Array = inventory["consumables"] as Array
	for entry in consumables:
		if entry is Dictionary and str(entry["id"]) == item_id:
			return int(entry["qty"])
	return 0


func unassign_equipment(ci: CharacterInstance, slot: String) -> void:
	if ci.equipment.has(slot):
		add_to_inventory(str(ci.equipment[slot]))
		ci.unequip(slot)


func to_dict() -> Dictionary:
	var roster_dicts: Array = []
	for ci in roster:
		roster_dicts.append(ci.to_dict())
	return {
		"band_id": band_id,
		"name": name,
		"roster": roster_dicts,
		"inventory": inventory.duplicate(true),
		"gold": gold,
	}


static func from_dict(d: Dictionary) -> BattleBand:
	var band := BattleBand.new()
	band.band_id = str(d.get("band_id", ""))
	band.name = str(d.get("name", "New Band"))
	band.gold = int(d.get("gold", 0))
	# Restore roster
	var roster_arr: Array = d.get("roster", []) as Array
	for entry in roster_arr:
		if entry is Dictionary:
			band.roster.append(CharacterInstance.from_dict(entry))
	# Restore inventory
	var inv: Variant = d.get("inventory", null)
	if inv is Dictionary:
		band.inventory = {
			"equipment": _to_variant_array(inv.get("equipment", [])),
			"consumables": _to_variant_array(inv.get("consumables", [])),
		}
	else:
		band.inventory = {"equipment": [], "consumables": []}
	return band


static func _to_variant_array(v: Variant) -> Array:
	if v is Array:
		return (v as Array).duplicate()
	return []


static func _generate_id() -> String:
	var t: int = Time.get_ticks_usec()
	var r: int = randi()
	return "band_%x_%x" % [t, r]
