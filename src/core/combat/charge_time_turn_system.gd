class_name ChargeTimeTurnSystem
extends TurnSystem
## Continuous charge-time turn system for skirmish mode.
## Units accrue CT from SPD each tick; act on threshold crossing;
## CT resets with surcharge on acting (full action > Wait).
## No telegraph — opponents' intents are hidden.
## Spec reference: alpha-phaseA20-spec.md §2, §4

var _scheduler: TurnScheduler = null
var _seed: int = 0
var _round_complete: bool = false
var _pending_unit: BattleUnit = null  # unit that just crossed threshold

## The unit whose CT triggered this activation. Read by BattleController.
var activated_unit: BattleUnit = null

## Whether the last activation was a wait (for surcharge calculation).
var _last_was_wait: bool = false


func setup(units: Array, seed_val: int) -> void:
	_seed = seed_val
	_scheduler = TurnScheduler.new()
	_scheduler.setup(units, seed_val)


func begin_round(state: MatchState) -> void:
	RoundManager.do_round_start_bookkeeping(state)
	_round_complete = false
	activated_unit = null
	_pending_unit = null
	state.phase = MatchState.Phase.AWAITING_ACTIVATION


func is_round_complete(_state: MatchState) -> bool:
	return _round_complete


## Tick the CT clock. If a unit crosses threshold, set activated_unit
## and transition state to UNIT_TURN. Returns without doing anything
## if a unit is already active (controller must finish that activation first).
func advance(state: MatchState) -> void:
	if state.current_unit != null:
		return  # still resolving an activation

	if activated_unit != null:
		return  # controller hasn't consumed the activation yet

	var unit: BattleUnit = _scheduler.tick()
	if unit:
		activated_unit = unit
		_pending_unit = unit


func wants_telegraph() -> bool:
	return false


## Called by BattleController after it finishes an activation.
## Applies CT reset/surcharge and checks for round/match end.
func on_activation_complete(state: MatchState, did_wait: bool) -> void:
	if _pending_unit:
		_scheduler.on_acted(_pending_unit, did_wait)
		_pending_unit.is_activated = false  # CT units can act multiple times per "round"
		_pending_unit = null
	activated_unit = null
	_last_was_wait = did_wait

	# Flush turn log
	state.match_log.append_array(state.turn_log)
	state.turn_log = []
	state.current_unit = null

	# Check if match is over
	var winner := state.check_winner()
	if not winner.is_empty():
		state.phase = MatchState.Phase.MATCH_OVER
		_round_complete = true
		return

	# Check if round should end (all units have had a chance to act).
	# In CT mode, a "round" is a full cycle — we end it after every unit
	# has crossed threshold at least once. For simplicity, use a tick count
	# based approach: end round after N activations equal to living unit count.
	# This triggers status/buff duration bookkeeping.
	_check_round_boundary(state)

	state.phase = MatchState.Phase.AWAITING_ACTIVATION


## Forecast upcoming activations for HUD timeline.
func get_timeline(count: int) -> Array:
	if not _scheduler:
		return []
	return _scheduler.forecast(count)


## Get the scheduler for direct access (tests, etc).
func get_scheduler() -> TurnScheduler:
	return _scheduler


## Remove a permanently removed unit from tracking.
func remove_unit(unit: BattleUnit) -> void:
	if _scheduler:
		_scheduler.remove_unit(unit)


## Track activations per round for round-boundary detection.
var _activations_this_round: int = 0
var _living_at_round_start: int = 0


func _check_round_boundary(state: MatchState) -> void:
	_activations_this_round += 1
	if _living_at_round_start <= 0:
		_living_at_round_start = state.all_living_units().size()

	# End round when total activations >= living units at round start
	if _activations_this_round >= _living_at_round_start:
		_round_complete = true
		_activations_this_round = 0
		_living_at_round_start = 0
