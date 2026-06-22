class_name LootRoller
extends RefCounted
## Rolls loot from authored tables with depth scaling and injectable RNG.
## Spec reference: alpha-phaseA6-spec.md §4


## Rolls a loot result from a table at the given depth.
## Returns {gold: int, equipment: Array, consumables: Array[{id, qty}]}.
static func roll(table: Dictionary, depth: int, rng: RandomNumberGenerator,
		shop_pool_provider: Callable) -> Dictionary:
	var result := {"gold": 0, "equipment": [], "consumables": []}
	if table.is_empty():
		return result
	var scale: float = 1.0 + float(Constants.get_value("LOOT_DEPTH_SCALE", 0.1)) * depth
	# Roll gold
	var gold_range: Variant = table.get("gold", {})
	if gold_range is Dictionary:
		var gd: Dictionary = gold_range as Dictionary
		var gmin: int = int(gd.get("min", 0))
		var gmax: int = int(gd.get("max", 0))
		if gmax >= gmin and gmax > 0:
			var base_gold: int = rng.randi_range(gmin, gmax)
			result["gold"] = int(round(base_gold * scale))
	# Roll drops
	var drops: Variant = table.get("drops", [])
	var rolls: int = int(table.get("rolls", 1))
	if drops is Array and not (drops as Array).is_empty():
		for _i in range(rolls):
			var pick: Dictionary = _weighted_pick(drops as Array, rng)
			var kind: String = str(pick.get("kind", "nothing"))
			match kind:
				"equipment":
					var pool: Array = shop_pool_provider.call(str(pick.get("pool", "")))
					if not pool.is_empty():
						(result["equipment"] as Array).append(_pick_from_pool(pool, rng))
				"consumable":
					var cid: String = str(pick.get("id", ""))
					var qty: int = int(pick.get("qty", 1))
					if not cid.is_empty():
						(result["consumables"] as Array).append({"id": cid, "qty": qty})
	return result


## Applies rolled rewards to a band.
static func grant_rewards(band: BattleBand, rolled: Dictionary) -> void:
	band.gold += int(rolled.get("gold", 0))
	for item_id in rolled.get("equipment", []):
		band.add_to_inventory(str(item_id))
	for consumable in rolled.get("consumables", []):
		if consumable is Dictionary:
			band.add_consumable(str(consumable["id"]), int(consumable.get("qty", 1)))


## Weighted random pick from an array of {weight: int, ...} entries.
static func _weighted_pick(entries: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total: int = 0
	for entry in entries:
		if entry is Dictionary:
			total += int((entry as Dictionary).get("weight", 1))
	if total <= 0:
		return {}
	var roll: int = rng.randi_range(0, total - 1)
	var accum: int = 0
	for entry in entries:
		if entry is Dictionary:
			accum += int((entry as Dictionary).get("weight", 1))
			if roll < accum:
				return entry as Dictionary
	return entries.back() as Dictionary if not entries.is_empty() else {}


## Picks a random item from a pool array.
static func _pick_from_pool(pool: Array, rng: RandomNumberGenerator) -> String:
	if pool.is_empty():
		return ""
	return str(pool[rng.randi_range(0, pool.size() - 1)])
