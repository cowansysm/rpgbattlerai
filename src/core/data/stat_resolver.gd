class_name StatResolver
extends RefCounted
## Combines character base stats + race modifiers + class modifiers into a StatBlock.
## Multiclass stacking: additive (MVP rule).
## Iterates StatKey.all_strings() — no hardcoded key list.

static func resolve(c: CharacterData, race: RaceData, classes_list: Array) -> StatBlock:
	var sb := StatBlock.new()
	for k in StatKey.all_strings():
		var v: int = int(c.base_stats.get(k, 0))
		v += int(race.stat_modifiers.get(k, 0))
		for cls in classes_list:
			v += int(cls.stat_modifiers.get(k, 0))
		sb.set_base(k, v)
	return sb
