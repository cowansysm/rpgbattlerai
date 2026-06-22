extends GutTest
## Tests for ShopService: buy/sell operations on BattleBand.


var _item_prov: Callable


func before_each() -> void:
	_item_prov = func(id: String) -> ItemData:
		var item := ItemData.new()
		item.id = id
		if id == "sword":
			item.display_name = "Sword"
			item.slot = "weapon"
			item.bp_value = 2
			item.price = 50
		elif id == "shield":
			item.display_name = "Shield"
			item.slot = "shield"
			item.bp_value = 1
			item.price = 30
		elif id == "potion":
			item.display_name = "Potion"
			item.slot = ""  # Consumable (no slot)
			item.bp_value = 0
			item.price = 10
		else:
			return null
		return item


func test_buy_deducts_gold_adds_item() -> void:
	var band := BattleBand.create("Test")
	band.gold = 200
	var err := ShopService.buy(band, "sword", _item_prov)
	assert_eq(err, "")
	assert_eq(band.gold, 150)
	var equip: Array = band.inventory["equipment"] as Array
	assert_true(equip.has("sword"))


func test_buy_rejects_insufficient_gold() -> void:
	var band := BattleBand.create("Test")
	band.gold = 10
	var err := ShopService.buy(band, "sword", _item_prov)
	assert_true(err.begins_with("Not enough gold"))
	assert_eq(band.gold, 10)  # Unchanged
	var equip: Array = band.inventory["equipment"] as Array
	assert_eq(equip.size(), 0)


func test_sell_adds_gold_removes_item() -> void:
	var band := BattleBand.create("Test")
	band.gold = 100
	band.add_to_inventory("sword")
	var err := ShopService.sell(band, "sword", _item_prov)
	assert_eq(err, "")
	assert_eq(band.gold, 125)  # 100 + sell_value(50 * 0.5 = 25)
	var equip: Array = band.inventory["equipment"] as Array
	assert_false(equip.has("sword"))


func test_sell_rejects_unheld_item() -> void:
	var band := BattleBand.create("Test")
	band.gold = 100
	var err := ShopService.sell(band, "sword", _item_prov)
	assert_true(err.find("does not have") >= 0)
	assert_eq(band.gold, 100)  # Unchanged


func test_buy_then_sell_nets_loss() -> void:
	var band := BattleBand.create("Test")
	band.gold = 200
	ShopService.buy(band, "sword", _item_prov)
	ShopService.sell(band, "sword", _item_prov)
	# 200 - 50 + 25 = 175 (net loss of 25)
	assert_eq(band.gold, 175)


func test_gold_never_negative() -> void:
	var band := BattleBand.create("Test")
	band.gold = 50
	ShopService.buy(band, "sword", _item_prov)  # Exactly 50
	assert_eq(band.gold, 0)
	var err := ShopService.buy(band, "shield", _item_prov)  # Should fail
	assert_true(not err.is_empty())
	assert_eq(band.gold, 0)  # Still 0, not negative


func test_buy_unknown_item_errors() -> void:
	var band := BattleBand.create("Test")
	band.gold = 200
	var err := ShopService.buy(band, "nonexistent", _item_prov)
	assert_true(err.find("Unknown item") >= 0)


func test_buy_consumable_stacks() -> void:
	var band := BattleBand.create("Test")
	band.gold = 200
	ShopService.buy(band, "potion", _item_prov)
	ShopService.buy(band, "potion", _item_prov)
	assert_eq(band.consumable_qty("potion"), 2)
	assert_eq(band.gold, 180)  # 200 - 10 - 10


func test_sell_consumable() -> void:
	var band := BattleBand.create("Test")
	band.gold = 100
	band.add_consumable("potion", 3)
	var err := ShopService.sell(band, "potion", _item_prov)
	assert_eq(err, "")
	assert_eq(band.consumable_qty("potion"), 2)
	assert_eq(band.gold, 105)  # 100 + sell_value(10 * 0.5 = 5)
