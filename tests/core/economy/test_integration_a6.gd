extends GutTest
const SharedPipeline = preload("res://tests/helpers/shared_pipeline.gd")
## Integration test for Phase A6 economy: full pipeline exercises Pricing,
## ShopService, LootRoller, and BattleBand consumable helpers together.


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
			item.bp_value = 2
			item.price = 50
		elif id == "potion":
			item.display_name = "Potion"
			item.slot = ""
			item.bp_value = 0
			item.price = 10
		elif id == "staff":
			item.display_name = "Staff"
			item.slot = "weapon"
			item.bp_value = 1
			item.price = 20
		else:
			return null
		return item


func test_full_economy_loop() -> void:
	# Create band with starting gold → buy items → sell items → verify final state
	var band := BattleBand.create("Economy Test")
	band.gold = 200

	# Buy equipment
	var err := ShopService.buy(band, "sword", _item_prov)
	assert_eq(err, "", "buy sword succeeds")
	assert_eq(band.gold, 150)

	# Buy consumable
	err = ShopService.buy(band, "potion", _item_prov)
	assert_eq(err, "", "buy potion succeeds")
	assert_eq(band.gold, 140)
	assert_eq(band.consumable_qty("potion"), 1)

	# Buy more potions (stacking)
	ShopService.buy(band, "potion", _item_prov)
	ShopService.buy(band, "potion", _item_prov)
	assert_eq(band.consumable_qty("potion"), 3)
	assert_eq(band.gold, 120)

	# Sell equipment (50 * 0.5 = 25)
	err = ShopService.sell(band, "sword", _item_prov)
	assert_eq(err, "", "sell sword succeeds")
	assert_eq(band.gold, 145)

	# Sell one potion (10 * 0.5 = 5)
	err = ShopService.sell(band, "potion", _item_prov)
	assert_eq(err, "", "sell potion succeeds")
	assert_eq(band.consumable_qty("potion"), 2)
	assert_eq(band.gold, 150)


func test_loot_then_sell_flow() -> void:
	# Roll loot → grant rewards → sell loot
	var band := BattleBand.create("Loot Test")
	band.gold = 0

	var pool_prov := func(id: String) -> Array:
		if id == "test_pool":
			return ["sword", "staff"]
		return []

	var table := {
		"gold": {"min": 20, "max": 20},
		"drops": [
			{"weight": 1, "kind": "equipment", "pool": "test_pool"},
			{"weight": 1, "kind": "consumable", "id": "potion", "qty": 2},
		],
		"rolls": 2,
	}

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var rolled := LootRoller.roll(table, 0, rng, pool_prov)

	# Verify structure
	assert_true(rolled.has("gold"))
	assert_true(rolled.has("equipment"))
	assert_true(rolled.has("consumables"))
	assert_true(rolled["gold"] > 0)

	# Grant to band
	LootRoller.grant_rewards(band, rolled)
	assert_true(band.gold > 0, "band received gold from loot")

	# Band should have some items or consumables now
	var equip_list: Array = band.inventory["equipment"] as Array
	var has_items: bool = not equip_list.is_empty() or band.has_consumable("potion")
	assert_true(has_items, "band received items from loot")

	# Sell everything
	var gold_before: int = band.gold
	for eid in equip_list.duplicate():
		ShopService.sell(band, str(eid), _item_prov)
	while band.has_consumable("potion"):
		ShopService.sell(band, "potion", _item_prov)

	assert_true(band.gold >= gold_before, "selling loot increases gold")
	var final_equip: Array = band.inventory["equipment"] as Array
	assert_eq(final_equip.size(), 0, "all equipment sold")
	assert_eq(band.consumable_qty("potion"), 0, "all potions sold")


func test_economy_with_serialization() -> void:
	# Buy items → serialize → deserialize → verify state persists
	var band := BattleBand.create("Serial Test")
	band.gold = 100
	ShopService.buy(band, "staff", _item_prov)
	ShopService.buy(band, "potion", _item_prov)
	ShopService.buy(band, "potion", _item_prov)

	# Serialize
	var d := band.to_dict()
	var restored := BattleBand.from_dict(d)

	assert_eq(restored.gold, band.gold)
	var orig_equip: Array = band.inventory["equipment"] as Array
	var rest_equip: Array = restored.inventory["equipment"] as Array
	assert_eq(rest_equip.size(), orig_equip.size())
	assert_eq(restored.consumable_qty("potion"), band.consumable_qty("potion"))

	# Sell from restored band should work
	var err := ShopService.sell(restored, "staff", _item_prov)
	assert_eq(err, "")
	assert_eq(restored.gold, band.gold + 10)  # staff sell = 20 * 0.5 = 10


func test_depth_scaled_loot_gold_increases() -> void:
	var pool_prov := func(_id: String) -> Array: return ["sword"]
	var table := {
		"gold": {"min": 100, "max": 100},
		"drops": [{"weight": 1, "kind": "nothing"}],
		"rolls": 1,
	}
	var rng0 := RandomNumberGenerator.new()
	rng0.seed = 99
	var rolled0 := LootRoller.roll(table, 0, rng0, pool_prov)

	var rng5 := RandomNumberGenerator.new()
	rng5.seed = 99
	var rolled5 := LootRoller.roll(table, 5, rng5, pool_prov)

	# depth 0: 100 * (1.0 + 0.1*0) = 100
	# depth 5: 100 * (1.0 + 0.1*5) = 150
	assert_eq(rolled0["gold"], 100)
	assert_eq(rolled5["gold"], 150)


func test_buy_sell_net_loss() -> void:
	# Buying and immediately selling always results in a net gold loss
	var band := BattleBand.create("NetLoss")
	band.gold = 1000
	var starting: int = band.gold

	ShopService.buy(band, "sword", _item_prov)
	ShopService.buy(band, "shield", _item_prov)
	ShopService.buy(band, "potion", _item_prov)
	ShopService.sell(band, "sword", _item_prov)
	ShopService.sell(band, "shield", _item_prov)
	ShopService.sell(band, "potion", _item_prov)

	# Net: bought for 50+50+10=110, sold for 25+25+5=55
	assert_eq(band.gold, starting - 55)


func test_data_pipeline_validates_economy_cleanly() -> void:
	# Full pipeline load should pass with no economy validation errors
	var pipeline := SharedPipeline.get_pipeline()
	var errors := SharedPipeline.load_errors()
	assert_eq(errors.size(), 0, "full pipeline validates cleanly: %s" % str(errors))
	# Verify loot tables and shop pools loaded
	assert_true(not pipeline.loot_tables.is_empty(), "loot tables loaded")
	assert_true(not pipeline.shop_pools.is_empty(), "shop pools loaded")
	# Verify accessors work
	var std := pipeline.get_loot_table("standard_battle")
	assert_true(not std.is_empty(), "standard_battle table accessible")
	var base := pipeline.get_shop_pool("base_shop")
	assert_true(not base.is_empty(), "base_shop pool accessible")
