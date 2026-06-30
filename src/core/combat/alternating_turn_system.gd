class_name AlternatingTurnSystem
extends TurnSystem
## Wraps the existing RoundManager static methods behind the TurnSystem seam.
## This preserves the MVP alternating-activation behavior exactly.
## Used as the default system when no speed-round or charge-time is selected.


func begin_round(state: MatchState) -> void:
	## Perform round-start bookkeeping and build the alternating queue.
	## Calls the extracted helper directly to avoid re-entering
	## RoundManager.start_round()'s delegation check.
	RoundManager.do_round_start_bookkeeping(state)
	RoundManager._build_and_set_queue(state)


func is_round_complete(state: MatchState) -> bool:
	return RoundManager.is_round_over(state)


func advance(_state: MatchState) -> void:
	# In alternating activation, advancement is handled by the
	# BattleController calling activate_unit/end_activation directly.
	# This method is a no-op for this system.
	pass


func wants_telegraph() -> bool:
	return false
