class_name ShopService
extends RefCounted
## Transactional buy/sell operations on a BattleBand.
## Spec reference: alpha-phaseA6-spec.md §5


## Buys an item for the band. Returns "" on success, error string on failure.
static func buy(band: BattleBand, item_id: String, item_provider: Callable) -> String:
	var item: ItemData = item_provider.call(item_id)
	if item == null:
		return "Unknown item '%s'" % item_id
	var cost: int = Pricing.buy_price(item)
	if band.gold < cost:
		return "Not enough gold (need %d, have %d)" % [cost, band.gold]
	band.gold -= cost
	if item.slot.is_empty():
		# Consumable — stack in consumables
		band.add_consumable(item_id)
	else:
		band.add_to_inventory(item_id)
	return ""


## Sells an item from the band's inventory. Returns "" on success, error string on failure.
static func sell(band: BattleBand, item_id: String, item_provider: Callable) -> String:
	var item: ItemData = item_provider.call(item_id)
	if item == null:
		return "Unknown item '%s'" % item_id
	var sell_val: int = Pricing.sell_value(item)
	if item.slot.is_empty():
		# Consumable
		if not band.has_consumable(item_id):
			return "Band does not have consumable '%s'" % item_id
		band.remove_consumable(item_id, 1)
	else:
		if not band.remove_from_inventory(item_id):
			return "Band does not have item '%s'" % item_id
	band.gold += sell_val
	return ""


## Returns a deduplicated, sorted list of item IDs from the given pool IDs.
static func available_items(pool_ids: Array, pool_provider: Callable) -> Array[String]:
	var seen: Dictionary = {}
	var out: Array[String] = []
	for pid in pool_ids:
		var pool: Array = pool_provider.call(str(pid))
		for item_id in pool:
			var sid: String = str(item_id)
			if not seen.has(sid):
				seen[sid] = true
				out.append(sid)
	out.sort()
	return out
