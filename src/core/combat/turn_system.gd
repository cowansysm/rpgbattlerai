class_name TurnSystem
extends RefCounted
## Abstract interface for turn-activation models.
## Implementations: SpeedRoundTurnSystem (A15), ChargeTimeTurnSystem (A20).
## RefCounted — no scene-tree dependency. Fully testable headless.
## Spec reference: alpha-phaseA15-spec.md §2.1


## Called once at the start of each round. Sets up round state
## (queue, plans, etc.) specific to this system.
func begin_round(_state: MatchState) -> void:
	pass


## Returns true when the current round's work is complete
## and the match should advance to the next round (or end).
func is_round_complete(_state: MatchState) -> bool:
	return true


## Advance the turn system by one step. What "one step" means
## depends on the implementation: one activation (alternating),
## one resolution tick (speed-round), one CT tick (charge-time).
func advance(_state: MatchState) -> void:
	pass


## Whether this system uses telegraphing (AI intents disclosed).
## SpeedRound returns true; AlternatingActivation/ChargeTime return false.
func wants_telegraph() -> bool:
	return false
