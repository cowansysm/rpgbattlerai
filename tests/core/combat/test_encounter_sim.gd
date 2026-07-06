extends GutTest
## Phase 3 — Combat/AI validation of the adopted 10-tier content.
## Headless AI-vs-AI simulation of representative encounters (termination, no hard
## errors, AI ability usage), plus passive hygiene and shape/element coverage.
const BattleSim = preload("res://tests/helpers/battle_sim.gd")


func _squad(ids: Array) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for id in ids:
		var u := BattleSim.unit_from_template(id)
		assert_not_null(u, "template '%s' should build a unit (exists + has final stats)" % id)
		if u:
			out.append(u)
	return out


# --- 1. Termination, no hard errors, AI ability usage (low/mid/high bands) ---

func test_sim_matches_resolve_and_use_abilities() -> void:
	var sim := BattleSim.new()
	var matches := [
		{"a": ["bat_swarm", "bat_swarm", "bat_nightstalker"],
		 "b": ["bat_swarm", "bat_nightstalker", "bat_echocaster"], "seed": 1},
		{"a": ["bat_swarm", "bat_nightstalker", "bat_echocaster", "bat_screecher"],
		 "b": ["demon_brute", "demon_hellfire", "demon_corruptor"], "seed": 2},
		{"a": ["demon_brute", "demon_brute", "demon_hellfire", "demon_dreadlord"],
		 "b": ["drake_maw", "drake_skyhunter", "drake_firebreather", "drake_scalelord"], "seed": 3},
	]
	var total_ability_ok := 0
	var executed: Dictionary = {}
	for m in matches:
		var pa := _squad(m["a"])
		var pb := _squad(m["b"])
		var r: Dictionary = sim.run(pa, pb, int(m["seed"]))
		assert_false(bool(r["capped"]),
			"match (seed %d) should resolve within the round cap (rounds=%d)" % [m["seed"], r["rounds"]])
		assert_ne(str(r["winner"]), "", "match (seed %d) should produce a winner" % m["seed"])
		assert_eq((r["errors"] as Array).size(), 0,
			"match (seed %d) should have no hard errors: %s" % [m["seed"], str(r["errors"])])
		assert_eq(int(r["passive_executed"]), 0,
			"no passive ability should ever be executed as an action (seed %d)" % m["seed"])
		total_ability_ok += int(r["ability_ok"])
		for aid in (r["executed_abilities"] as Dictionary):
			executed[aid] = true
	assert_gt(total_ability_ok, 0, "AI should successfully use abilities across the sample")
	# Coverage from real combat: the sample should exercise new elements and AoE shapes.
	var new_elems := ["poison", "arcane", "steam", "alchemical", "aether", "sonic"]
	var saw_new_elem := false
	var saw_aoe := false
	for aid in executed:
		var ab: AbilityData = GameData.get_ability(aid)
		if ab == null:
			continue
		if str(ab.effect.get("element", "")) in new_elems:
			saw_new_elem = true
		if str(ab.area.get("shape", "")) in ["line", "cone", "ring", "burst"]:
			saw_aoe = true
	assert_true(saw_new_elem, "sim should exercise at least one new-element ability")
	assert_true(saw_aoe, "sim should exercise at least one AoE-shape ability")


# --- 2. Ability shape + element coverage (targeted casts, all resolve) ---

func test_ability_shapes_and_elements_resolve() -> void:
	var sim := BattleSim.new()
	# 4 AoE shapes + 6 restored elements — each must cast without error.
	var samples := [
		"cleave", "landslide", "fissure", "ring_of_fire",
		"bio_1", "flare", "steam_dart", "alchemical_dart", "aether_dart", "sonic_dart",
	]
	for aid in samples:
		var ab: AbilityData = GameData.get_ability(aid)
		assert_not_null(ab, "sample ability '%s' should exist" % aid)
		if ab == null:
			continue
		var caster := BattleSim.loadout_unit("caster", [aid])
		var target := BattleSim.unit_from_template("bat_swarm")
		assert_not_null(target, "target template should build")
		var state := sim.duel_state(caster, target)
		var target_pos: Vector2i = caster.position if ab.ability_range == 0 else target.position
		var result := TurnActions.execute_ability(state, aid, target_pos)
		assert_eq(str(result.get("action", "")), "ability",
			"ability '%s' (shape=%s element=%s) should resolve without error: %s"
			% [aid, str(ab.area.get("shape", "")), str(ab.effect.get("element", "")), str(result)])
		assert_true(result.has("outcomes"), "ability '%s' should produce an outcomes record" % aid)


# --- 3. Passive hygiene: passives are never usable as active actions ---

func test_passive_not_usable_as_action() -> void:
	# 'counter' is a reaction passive taught by vagabond; even sitting in a loadout
	# it must not appear as a usable ability nor resolve as an activatable action.
	var resolver := AbilityResolver.new(
		GameData.get_ability, GameData.get_job_class, GameData.get_item)
	var u := BattleSim.loadout_unit("p", ["counter", "basic_strike"])
	var ids: Array = []
	for a in resolver.all_abilities(u):
		ids.append(a.id)
	assert_true("basic_strike" in ids, "active ability should be usable")
	assert_false("counter" in ids, "passive 'counter' must not appear as a usable ability")
	assert_null(resolver.resolve(u, "counter"), "resolve() must reject a passive ability")
	assert_not_null(resolver.resolve(u, "basic_strike"), "resolve() should return an active ability")
