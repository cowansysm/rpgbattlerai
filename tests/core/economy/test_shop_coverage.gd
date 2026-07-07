extends GutTest
## Phase 4 — economy wiring: every item is reachable via a shop pool (and thus
## buyable and, for run pools, lootable), and every pool ref resolves.
const SharedPipeline = preload("res://tests/helpers/shared_pipeline.gd")


func test_every_item_is_in_a_shop_pool() -> void:
	var p := SharedPipeline.get_pipeline()
	var pooled: Dictionary = {}
	for pool_id in p.shop_pools:
		for item_id in p.shop_pools[pool_id]:
			pooled[item_id] = true
	var unwired: Array = []
	for it in p.items.all():
		if not pooled.has(it.id):
			unwired.append(it.id)
	assert_eq(unwired, [] as Array,
		"every item should be reachable via a shop pool (buyable/lootable); unwired: %s" % str(unwired))


func test_shop_pool_refs_resolve() -> void:
	var p := SharedPipeline.get_pipeline()
	for pool_id in p.shop_pools:
		for item_id in p.shop_pools[pool_id]:
			assert_true(p.items.has(item_id),
				"shop pool '%s' references unknown item '%s'" % [pool_id, item_id])


func test_loot_table_pools_exist() -> void:
	var p := SharedPipeline.get_pipeline()
	for table_id in p.loot_tables:
		var table: Dictionary = p.loot_tables[table_id]
		for drop in table.get("drops", []):
			if drop.get("kind", "") == "equipment":
				var pool_id: String = str(drop.get("pool", ""))
				assert_true(p.shop_pools.has(pool_id),
					"loot table '%s' references unknown pool '%s'" % [table_id, pool_id])
