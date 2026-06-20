class_name InstanceStatResolver
extends RefCounted
## Computes the base StatBlock for a CharacterInstance.
## base(key) = race.base_stats[key] + active_class.stat_modifiers[key] + growth_accumulated[key]
## Spec reference: alpha-phaseA4-spec.md §7.1

static func resolve(ci: RefCounted, race_provider: Callable, class_provider: Callable) -> StatBlock:
	var sb := StatBlock.new()
	var race_data: RaceData = race_provider.call(ci.race)
	var cls: ClassData = class_provider.call(ci.active_class)
	for k in StatKey.all_strings():
		var v: int = 0
		if race_data != null:
			v += int(race_data.base_stats.get(k, 0))
		if cls != null:
			v += int(cls.stat_modifiers.get(k, 0))
		v += int(ci.growth_accumulated.get(k, 0))
		sb.set_base(k, v)
	return sb
