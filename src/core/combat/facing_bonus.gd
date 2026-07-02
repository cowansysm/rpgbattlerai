class_name FacingBonus
extends RefCounted
## A19: Static helpers for arc-based combat bonuses.
## Reads tunable constants from the Constants autoload so values can be tweaked
## in data/constants.json without touching code.
## Front arc contributes 0 to everything (backward-compatible default).


## Flat damage bonus for the given arc (added to the hit formula alongside e_bonus).
static func damage_bonus(arc: int) -> int:
	match arc:
		Hex.Arc.FLANK:
			return int(Constants.get_value("FLANK_HIT", 1))
		Hex.Arc.REAR:
			return int(Constants.get_value("REAR_HIT", 2))
	return 0  # FRONT


## Additional crit chance for the given arc (additive with CRIT_CHANCE for resolve_damage).
## Front arc returns 0.0 so no extra roll is consumed (determinism guard).
static func crit_bonus(arc: int) -> float:
	match arc:
		Hex.Arc.FLANK:
			return float(Constants.get_value("FLANK_CRIT", 0.0625))
		Hex.Arc.REAR:
			return float(Constants.get_value("REAR_CRIT", 0.125))
	return 0.0  # FRONT
