extends GutTest
## Tests for Pricing: buy price derivation and sell value calculation.


func _make_item(id: String, bp: int, price: int = -1) -> ItemData:
	var item := ItemData.new()
	item.id = id
	item.bp_value = bp
	item.price = price
	return item


func test_authored_price_used_when_non_negative() -> void:
	var item := _make_item("sword", 2, 50)
	assert_eq(Pricing.buy_price(item), 50)


func test_derived_price_from_bp_value() -> void:
	var item := _make_item("dagger", 3, -1)
	# 3 * PRICE_PER_BP(5) = 15
	assert_eq(Pricing.buy_price(item), 15)


func test_zero_price_is_valid() -> void:
	var item := _make_item("free_item", 5, 0)
	assert_eq(Pricing.buy_price(item), 0)


func test_sell_value_is_fraction_of_buy() -> void:
	var item := _make_item("sword", 2, 50)
	# 50 * SELL_RATIO(0.5) = 25
	assert_eq(Pricing.sell_value(item), 25)


func test_sell_value_rounds() -> void:
	var item := _make_item("odd", 2, 33)
	# 33 * 0.5 = 16.5 → rounds to 17
	assert_eq(Pricing.sell_value(item), 17)


func test_derived_price_sell_value() -> void:
	var item := _make_item("staff", 4, -1)
	# buy = 4 * 5 = 20, sell = 20 * 0.5 = 10
	assert_eq(Pricing.buy_price(item), 20)
	assert_eq(Pricing.sell_value(item), 10)
