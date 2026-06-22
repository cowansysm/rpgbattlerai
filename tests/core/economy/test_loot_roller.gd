extends GutTest
## Tests for LootRoller: determinism, depth scaling, reward grants.


var _table: Dictionary
var _pool_provider: Callable


func before_each() -> void:
	_table = {
		"gold": {"min": 10, "max": 20},
		"drops": [
			{"weight": 5, "kind": "equipment", "pool": "weapons"},
			{"weight": 3, "kind": "consumable", "id": "potion", "qty": 1},
			{"weight": 2, "kind": "nothing"}
		],
		"rolls": 2
	}
	_pool_provider = func(pool_id: String) -> Array:
		if pool_id == "weapons":
			return ["sword", "bow", "daggers"]
		return []


func test_seeded_consistency() -> void:
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 42
	var result1 := LootRoller.roll(_table, 1, rng1, _pool_provider)

	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 42
	var result2 := LootRoller.roll(_table, 1, rng2, _pool_provider)

	assert_eq(result1["gold"], result2["gold"])
	assert_eq(result1["equipment"], result2["equipment"])
	assert_eq(result1["consumables"], result2["consumables"])


func test_depth_scaling_increases_gold() -> void:
	var gold_d0: int = 0
	var gold_d10: int = 0
	# Average over multiple rolls to account for RNG variance
	for i in range(20):
		var rng0 := RandomNumberGenerator.new()
		rng0.seed = i
		var r0 := LootRoller.roll(_table, 0, rng0, _pool_provider)
		gold_d0 += int(r0["gold"])

		var rng10 := RandomNumberGenerator.new()
		rng10.seed = i
		var r10 := LootRoller.roll(_table, 10, rng10, _pool_provider)
		gold_d10 += int(r10["gold"])
	assert_true(gold_d10 > gold_d0, "Depth 10 should yield more gold than depth 0")


func test_grant_rewards_updates_band() -> void:
	var band := BattleBand.create("Test")
	band.gold = 100
	var rolled := {"gold": 25, "equipment": ["sword", "bow"], "consumables": [{"id": "potion", "qty": 2}]}
	LootRoller.grant_rewards(band, rolled)
	assert_eq(band.gold, 125)
	var equip: Array = band.inventory["equipment"] as Array
	assert_true(equip.has("sword"))
	assert_true(equip.has("bow"))
	assert_eq(band.consumable_qty("potion"), 2)


func test_empty_table_returns_zero() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var result := LootRoller.roll({}, 0, rng, _pool_provider)
	assert_eq(result["gold"], 0)
	assert_eq((result["equipment"] as Array).size(), 0)
	assert_eq((result["consumables"] as Array).size(), 0)


func test_grant_rewards_stacks_consumables() -> void:
	var band := BattleBand.create("Test")
	band.add_consumable("potion", 3)
	var rolled := {"gold": 0, "equipment": [], "consumables": [{"id": "potion", "qty": 2}]}
	LootRoller.grant_rewards(band, rolled)
	assert_eq(band.consumable_qty("potion"), 5)
