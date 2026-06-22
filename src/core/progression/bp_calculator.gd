class_name BpCalculator
extends RefCounted
## Computes a BP (battle power) value for a CharacterInstance.
## Centralizes the heuristic so fielding rules and encounter scaling use the same metric.
## Spec reference: alpha-phaseA5-spec.md §7.4

const LEVEL_FACTOR: int = 3
const LOADOUT_FACTOR: int = 2


static func compute(ci: CharacterInstance, item_provider: Callable) -> int:
	var bp: int = ci.level * LEVEL_FACTOR
	# Equipment contribution
	for slot in ci.equipment.keys():
		var item: ItemData = item_provider.call(str(ci.equipment[slot]))
		if item != null:
			bp += item.bp_value
	# Ability loadout contribution
	bp += ci.ability_loadout.size() * LOADOUT_FACTOR
	return bp
