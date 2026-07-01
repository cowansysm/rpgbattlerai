class_name LevelScaler
extends RefCounted
## One-shot stat projection: scales a base stat block to a target level
## using per-level growth rates from a class definition.
##
## Formula: scaled[k] = base_stats[k] + round(growth[k] * (level - 1))
##
## Used for monster/NPC stat projection at encounter time.
## Player instances use InstanceStatResolver instead, which tracks accumulated
## growth across class switches (different semantic — see instance_stat_resolver.gd).
## Spec reference: alpha-phaseA11-spec.md §3.2


## Projects base stats to a target level via class growth.
## Returns a plain Dictionary of stat key (String) -> value (int).
static func scale(base_stats: Dictionary, growth: Dictionary, level: int) -> Dictionary:
	var out: Dictionary = {}
	var n: int = maxi(0, level - 1)
	for k in StatKey.all_strings():
		var base: int = int(base_stats.get(k, 0))
		var g: float = float(growth.get(k, 0.0))
		out[k] = base + int(round(g * n))
	return out
