class_name TurnScheduler
extends RefCounted
## CT bookkeeping: per-unit charge-time accrual, threshold detection,
## timeline forecasting, and deterministic seeded tie-breaking.
## Pure data — no scene-tree dependency.
## Spec reference: alpha-phaseA20-spec.md §2, §3

var _ct: Dictionary = {}          # character_id -> float (current CT)
var _units: Array = []            # Array[BattleUnit] — all participating units
var _threshold: int = 100
var _action_surcharge: int = 20
var _wait_surcharge: int = 0
var _haste_mult: float = 1.5
var _slow_mult: float = 0.5
var _tie_rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(units: Array, seed_val: int) -> void:
	_units = units.duplicate()
	_tie_rng.seed = seed_val
	_threshold = int(Constants.get_value("CT_THRESHOLD", 100))
	_action_surcharge = int(Constants.get_value("CT_ACTION_SURCHARGE", 20))
	_wait_surcharge = int(Constants.get_value("CT_WAIT_SURCHARGE", 0))
	_haste_mult = float(Constants.get_value("CT_HASTE_MULTIPLIER", 1.5))
	_slow_mult = float(Constants.get_value("CT_SLOW_MULTIPLIER", 0.5))
	# Initialize all CT to 0
	_ct.clear()
	for u: BattleUnit in _units:
		_ct[u.character.id] = 0.0


## Tick all living units' CT by their effective SPD (with status modifiers).
## Returns the unit that crossed the threshold first (highest CT above threshold,
## with deterministic seeded tie-break), or null if nobody is ready.
func tick() -> BattleUnit:
	# Accrue CT for all living, non-downed units
	for u: BattleUnit in _units:
		if u.current_hp <= 0 and not u.is_downed:
			continue  # permanently removed
		if u.is_downed:
			continue  # downed units don't accrue CT
		var spd: int = u.stats.effective("spd")
		var accrual: float = float(spd) * _status_multiplier(u)
		_ct[u.character.id] = _ct.get(u.character.id, 0.0) + accrual

	return _pick_ready_unit()


## Returns the unit with the highest CT above threshold, or null.
## Breaks ties deterministically with seeded RNG.
func _pick_ready_unit() -> BattleUnit:
	var ready: Array = []
	for u: BattleUnit in _units:
		if u.current_hp <= 0 and not u.is_downed:
			continue
		if u.is_downed:
			continue
		var ct_val: float = _ct.get(u.character.id, 0.0)
		if ct_val >= float(_threshold):
			ready.append(u)

	if ready.is_empty():
		return null

	if ready.size() == 1:
		return ready[0]

	# Tie-break: highest CT first, then seeded random
	ready.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool:
		var ct_a: float = _ct.get(a.character.id, 0.0)
		var ct_b: float = _ct.get(b.character.id, 0.0)
		if ct_a != ct_b:
			return ct_a > ct_b
		# Deterministic tie-break: hash character ID with seed
		var hash_a: int = (a.character.id.hash() * 31 + _tie_rng.seed) % 1000000
		var hash_b: int = (b.character.id.hash() * 31 + _tie_rng.seed) % 1000000
		return hash_a > hash_b)

	return ready[0]


## Reset CT after a unit acts. Full action applies action_surcharge;
## Wait applies wait_surcharge (typically 0, meaning faster re-activation after waiting).
func on_acted(unit: BattleUnit, did_wait: bool) -> void:
	var surcharge: int = _wait_surcharge if did_wait else _action_surcharge
	_ct[unit.character.id] = _ct.get(unit.character.id, 0.0) - float(_threshold) - float(surcharge)
	# Clamp to 0 minimum — negative CT is allowed as a delay penalty
	# but don't allow it to go below -threshold (extreme edge)


## Forecast the next N activations without mutating state.
## Returns Array[{unit: BattleUnit, ticks_away: int}].
func forecast(count: int) -> Array:
	# Snapshot current CT values
	var ct_snap: Dictionary = _ct.duplicate()
	var result: Array = []

	for _i in range(count * 200):  # safety bound
		if result.size() >= count:
			break

		# Find if anyone is currently ready
		var best: BattleUnit = null
		var best_ct: float = -999999.0
		for u: BattleUnit in _units:
			if u.current_hp <= 0 and not u.is_downed:
				continue
			if u.is_downed:
				continue
			var cv: float = ct_snap.get(u.character.id, 0.0)
			if cv >= float(_threshold):
				if cv > best_ct or (cv == best_ct and best != null and _tie_break_wins(u, best)):
					best = u
					best_ct = cv

		if best:
			result.append({"unit": best, "ticks_away": 0})
			ct_snap[best.character.id] = best_ct - float(_threshold) - float(_action_surcharge)
			if result.size() >= count:
				break
			continue

		# Tick forward
		for u: BattleUnit in _units:
			if u.current_hp <= 0 and not u.is_downed:
				continue
			if u.is_downed:
				continue
			var spd: int = u.stats.effective("spd")
			var accrual: float = float(spd) * _status_multiplier(u)
			ct_snap[u.character.id] = ct_snap.get(u.character.id, 0.0) + accrual

	return result


func _tie_break_wins(a: BattleUnit, b: BattleUnit) -> bool:
	var hash_a: int = (a.character.id.hash() * 31 + _tie_rng.seed) % 1000000
	var hash_b: int = (b.character.id.hash() * 31 + _tie_rng.seed) % 1000000
	return hash_a > hash_b


func _status_multiplier(u: BattleUnit) -> float:
	var mult: float = 1.0
	if u.has_status("haste"):
		mult *= _haste_mult
	if u.has_status("slowed"):
		mult *= _slow_mult
	return mult


## Get current CT for a unit (for HUD display).
func get_ct(unit: BattleUnit) -> float:
	return _ct.get(unit.character.id, 0.0)


## Get threshold value.
func get_threshold() -> int:
	return _threshold


## Remove a unit from tracking (permanent removal).
func remove_unit(unit: BattleUnit) -> void:
	_ct.erase(unit.character.id)


## Check if any living units remain.
func has_living_units() -> bool:
	for u: BattleUnit in _units:
		if u.current_hp > 0 and not u.is_downed:
			return true
	return false
