class_name Pricing
extends RefCounted
## Computes buy and sell prices for items.
## Authored price is used when >= 0; otherwise derived from bp_value.
## Spec reference: alpha-phaseA6-spec.md §3


## Returns the buy price for an item.
## Uses authored price if >= 0, otherwise derives from bp_value * PRICE_PER_BP.
static func buy_price(item: ItemData) -> int:
	if item.price >= 0:
		return item.price
	return item.bp_value * int(Constants.get_value("PRICE_PER_BP", 5))


## Returns the sell value for an item (fraction of buy price).
static func sell_value(item: ItemData) -> int:
	return int(round(buy_price(item) * float(Constants.get_value("SELL_RATIO", 0.5))))
