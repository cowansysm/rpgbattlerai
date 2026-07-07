extends GutTest
## Phase 6 — balance harness STABILITY smoke test.
##
## Asserts only stability invariants of the balance-metrics sweeps — NOT balance
## thresholds (win rates, damage bands, rounds distributions are subjective and
## belong in the human-reviewed report, not in CI gates):
##   1. every match terminates within the round cap (no infinite loops),
##   2. no hard runtime errors surface from the AI/combat loop,
##   3. no passive ability is ever executed as an action (A18/Phase-3 hygiene).
##
## Kept fast: small seeded sweeps (a handful of matches each).
const BM = preload("res://tests/helpers/balance_metrics.gd")


func test_monster_sweep_is_stable() -> void:
	var bm := BM.new()
	# Two bands, 2 matches per pair — a quick but representative sweep.
	var s: Dictionary = bm.sweep_monster_vs_monster(9001, [1, 5], 2, 40)
	assert_gt(int(s["matches"]), 0, "sweep should run at least one match")
	assert_eq(int(s["total_errors"]), 0,
		"monster sweep should produce no hard errors: %s" % str(s["error_samples"]))
	assert_eq(int(s["passive_executed"]), 0,
		"no passive ability should ever execute as an action (monster sweep)")
	# Every match resolved within cap OR was cleanly capped (never hung / guard-tripped):
	# a guard trip would have surfaced as an error, already asserted above.
	assert_true(int(s["rounds_max"]) <= 41,
		"no match should exceed the round cap (rounds_max=%d)" % int(s["rounds_max"]))


func test_player_vs_encounter_sweep_is_stable() -> void:
	var bm := BM.new()
	# One low band, small party, 1 match per encounter — fast.
	var out: Dictionary = bm.sweep_player_vs_encounters(9101, [1], 4, 1, 40)
	assert_true(out.has(1), "player sweep should cover band 1")
	var s: Dictionary = out[1]
	assert_gt(int(s["matches"]), 0, "player sweep should run at least one match")
	assert_eq(int(s["total_errors"]), 0,
		"player-vs-encounter sweep should produce no hard errors: %s" % str(s["error_samples"]))
	assert_eq(int(s["passive_executed"]), 0,
		"no passive ability should ever execute as an action (player sweep)")
	assert_true(int(s["rounds_max"]) <= 41,
		"no match should exceed the round cap (rounds_max=%d)" % int(s["rounds_max"]))


func test_progressed_units_build_with_active_loadouts() -> void:
	# Regression guard for the passive-filter fix: a progressed unit's usable
	# loadout must contain only ACTIVE abilities (no type=="passive" / passive_kind).
	var bm := BM.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var built := 0
	for tid in ["human_fighter", "elf_black_mage", "halfling_white_mage", "human_rogue"]:
		var u: BattleUnit = bm.progressed_unit(tid, 5, rng)
		assert_not_null(u, "progressed unit '%s' should build" % tid)
		if u == null:
			continue
		built += 1
		for aid in u.character.abilities:
			var ab: AbilityData = GameData.get_ability(aid)
			if ab == null:
				continue
			assert_true(ab.is_active(),
				"progressed loadout of '%s' must be active-only, found '%s' (type=%s, passive_kind=%s)"
				% [tid, aid, ab.type, ab.passive_kind])
	assert_gt(built, 0, "at least one progressed unit should build")
