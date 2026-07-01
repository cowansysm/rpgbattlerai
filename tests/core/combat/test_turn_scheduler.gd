extends GutTest
## Tests for TurnScheduler: CT accrual, ordering, haste/slow, seeded determinism.


# --- Stub terrain provider ---

static func _stub_terrain(id: String) -> TerrainProps:
	var p := TerrainProps.new()
	p.id = id
	p.move_cost = 1
	return p


# --- Helpers ---

func _make_unit(id: String, team: String, spd: int = 3) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = []
	c.abilities = []
	c.race = "human"
	var sb := StatBlock.new()
	sb.set_base("spd", spd)
	sb.set_base("hp", 10)
	sb.set_base("def", 1)
	sb.set_base("atk", 2)
	sb.set_base("rng", 1)
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	return u


# --- Tests ---

func test_fast_unit_activates_first() -> void:
	var fast := _make_unit("fast", "playerA", 7)
	var slow := _make_unit("slow", "playerB", 3)
	var sched := TurnScheduler.new()
	sched.setup([fast, slow], 42)

	# Tick until someone activates
	var activated: BattleUnit = null
	for _i in range(200):
		activated = sched.tick()
		if activated:
			break

	assert_not_null(activated, "A unit should activate")
	assert_eq(activated.character.id, "fast", "Faster unit should activate first")


func test_ct_accrual_proportional_to_spd() -> void:
	var fast := _make_unit("fast", "playerA", 10)
	var slow := _make_unit("slow", "playerB", 5)
	var sched := TurnScheduler.new()
	sched.setup([fast, slow], 42)

	# After one tick, fast should have more CT
	sched.tick()
	var ct_fast: float = sched.get_ct(fast)
	var ct_slow: float = sched.get_ct(slow)
	assert_gt(ct_fast, ct_slow, "Fast unit should accrue more CT per tick")
	assert_almost_eq(ct_fast / ct_slow, 2.0, 0.01, "CT ratio should match SPD ratio")


func test_action_surcharge_delays_next_turn() -> void:
	var unit := _make_unit("warrior", "playerA", 10)
	var sched := TurnScheduler.new()
	sched.setup([unit], 42)

	# Tick until activation
	var ticks_1 := 0
	for _i in range(200):
		var u := sched.tick()
		ticks_1 += 1
		if u:
			sched.on_acted(u, false)  # Full action surcharge
			break

	# Tick until second activation
	var ticks_2 := 0
	for _i in range(200):
		var u := sched.tick()
		ticks_2 += 1
		if u:
			break

	assert_gt(ticks_2, ticks_1, "Action surcharge should delay next activation")


func test_wait_surcharge_less_than_action() -> void:
	var unit_a := _make_unit("actor", "playerA", 10)
	var unit_b := _make_unit("waiter", "playerB", 10)
	var sched := TurnScheduler.new()
	sched.setup([unit_a, unit_b], 42)

	# Activate both — actor gets full-action surcharge, waiter gets wait surcharge
	var acted_count := 0
	for _i in range(200):
		var u := sched.tick()
		if u:
			if u.character.id == "actor":
				sched.on_acted(u, false)  # full action surcharge (20)
			else:
				sched.on_acted(u, true)  # wait surcharge (0)
			acted_count += 1
		if acted_count >= 2:
			break

	assert_eq(acted_count, 2, "Both units should have activated")
	# The waiter should have higher CT (less surcharge applied)
	var ct_actor: float = sched.get_ct(unit_a)
	var ct_waiter: float = sched.get_ct(unit_b)
	# Wait surcharge is 0, action surcharge is 20 — waiter should be ahead
	assert_gt(ct_waiter, ct_actor, "Wait should apply less surcharge than full action")


func test_haste_speeds_up_accrual() -> void:
	var normal := _make_unit("normal", "playerA", 5)
	var hasted := _make_unit("hasted", "playerB", 5)
	hasted.status_effects = [{"id": "haste", "duration": 3, "source": "test"}]
	var sched := TurnScheduler.new()
	sched.setup([normal, hasted], 42)

	# One tick
	sched.tick()
	var ct_normal: float = sched.get_ct(normal)
	var ct_hasted: float = sched.get_ct(hasted)
	assert_gt(ct_hasted, ct_normal, "Hasted unit should accrue CT faster")


func test_slowed_reduces_accrual() -> void:
	var normal := _make_unit("normal", "playerA", 5)
	var slowed := _make_unit("slowed", "playerB", 5)
	slowed.status_effects = [{"id": "slowed", "duration": 3, "source": "test"}]
	var sched := TurnScheduler.new()
	sched.setup([normal, slowed], 42)

	# One tick
	sched.tick()
	var ct_normal: float = sched.get_ct(normal)
	var ct_slowed: float = sched.get_ct(slowed)
	assert_lt(ct_slowed, ct_normal, "Slowed unit should accrue CT slower")


func test_dead_units_dont_accrue() -> void:
	var alive := _make_unit("alive", "playerA", 5)
	var dead := _make_unit("dead", "playerB", 5)
	dead.current_hp = 0
	var sched := TurnScheduler.new()
	sched.setup([alive, dead], 42)

	sched.tick()
	var ct_dead: float = sched.get_ct(dead)
	assert_almost_eq(ct_dead, 0.0, 0.01, "Dead unit should not accrue CT")


func test_downed_units_dont_accrue() -> void:
	var alive := _make_unit("alive", "playerA", 5)
	var downed := _make_unit("downed", "playerB", 5)
	downed.is_downed = true
	var sched := TurnScheduler.new()
	sched.setup([alive, downed], 42)

	sched.tick()
	var ct_downed: float = sched.get_ct(downed)
	assert_almost_eq(ct_downed, 0.0, 0.01, "Downed unit should not accrue CT")


func test_seeded_determinism() -> void:
	## Same seed should produce same activation order.
	var units_1: Array = [
		_make_unit("alpha", "playerA", 5),
		_make_unit("beta", "playerB", 5),
	]
	var units_2: Array = [
		_make_unit("alpha", "playerA", 5),
		_make_unit("beta", "playerB", 5),
	]
	var sched_1 := TurnScheduler.new()
	sched_1.setup(units_1, 12345)
	var sched_2 := TurnScheduler.new()
	sched_2.setup(units_2, 12345)

	var order_1: Array = []
	var order_2: Array = []
	for _i in range(200):
		var u1 := sched_1.tick()
		var u2 := sched_2.tick()
		if u1:
			order_1.append(u1.character.id)
			sched_1.on_acted(u1, false)
		if u2:
			order_2.append(u2.character.id)
			sched_2.on_acted(u2, false)
		if order_1.size() >= 4:
			break

	assert_eq(order_1, order_2, "Same seed should produce identical activation order")


func test_forecast_returns_upcoming_activations() -> void:
	var fast := _make_unit("fast", "playerA", 7)
	var slow := _make_unit("slow", "playerB", 3)
	var sched := TurnScheduler.new()
	sched.setup([fast, slow], 42)

	var forecast: Array = sched.forecast(3)
	assert_gte(forecast.size(), 1, "Forecast should return at least 1 entry")
	# First activation should be the fast unit
	assert_eq(forecast[0]["unit"].character.id, "fast",
		"Forecast should predict fast unit activates first")


func test_tie_break_deterministic_different_seeds() -> void:
	## With equal SPD, different seeds should still be deterministic per seed.
	var units: Array = [
		_make_unit("alpha", "playerA", 5),
		_make_unit("beta", "playerB", 5),
	]
	var sched := TurnScheduler.new()
	sched.setup(units, 99999)

	var first: BattleUnit = null
	for _i in range(200):
		first = sched.tick()
		if first:
			break

	assert_not_null(first, "Should activate someone")
	# Run again with same seed to verify determinism
	var units2: Array = [
		_make_unit("alpha", "playerA", 5),
		_make_unit("beta", "playerB", 5),
	]
	var sched2 := TurnScheduler.new()
	sched2.setup(units2, 99999)

	var first2: BattleUnit = null
	for _i in range(200):
		first2 = sched2.tick()
		if first2:
			break

	assert_eq(first.character.id, first2.character.id,
		"Same seed should give same tie-break winner")
