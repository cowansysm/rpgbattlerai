class_name BandPartyBuilder
extends RefCounted
## Converts a fielded selection of CharacterInstances into BattleUnits.
## Spec reference: alpha-phaseA5-spec.md §7


## Builds an Array[BattleUnit] from a list of CharacterInstances.
static func build_party(fielded: Array[CharacterInstance],
		race_provider: Callable, class_provider: Callable) -> Array[BattleUnit]:
	var party: Array[BattleUnit] = []
	for ci in fielded:
		party.append(BattleUnit.from_instance(ci, race_provider, class_provider))
	return party


## Generates a throwaway opponent band from character templates.
static func generate_opponent_instances(templates: Array,
		name_gen: Callable, count: int = 3) -> Array[CharacterInstance]:
	var instances: Array[CharacterInstance] = []
	for i in range(mini(count, templates.size())):
		var t: CharacterData = templates[i] as CharacterData
		if t != null:
			instances.append(CharacterInstance.generate(t, name_gen))
	return instances
