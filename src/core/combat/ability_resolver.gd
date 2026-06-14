class_name AbilityResolver
extends RefCounted
## Resolves whether a BattleUnit has access to a given ability.
## Checks character abilities, class-granted, and equipment-granted.
## Designed as an injectable provider for MatchState.ability_provider.

var _ability_getter: Callable		# (String) -> AbilityData
var _class_getter: Callable			# (String) -> ClassData
var _item_getter: Callable			# (String) -> ItemData


func _init(
	ability_getter: Callable,
	class_getter: Callable,
	item_getter: Callable
) -> void:
	_ability_getter = ability_getter
	_class_getter = class_getter
	_item_getter = item_getter


func resolve(unit: BattleUnit, ability_id: String) -> AbilityData:
	## Returns the AbilityData if the unit has access, or null.
	# Direct character abilities
	if ability_id in unit.character.abilities:
		return _ability_getter.call(ability_id)

	# Class-granted abilities
	for cls_id in unit.character.classes:
		var cls: ClassData = _class_getter.call(cls_id)
		if cls and ability_id in cls.granted_abilities:
			return _ability_getter.call(ability_id)

	# Equipment-granted abilities
	for eq_id in unit.character.equipment:
		var item: ItemData = _item_getter.call(eq_id)
		if item and ability_id in item.granted_abilities:
			return _ability_getter.call(ability_id)

	return null


func all_abilities(unit: BattleUnit) -> Array:
	## Returns all abilities the unit has access to (deduplicated).
	## Sources: character abilities, class-granted, equipment-granted.
	var seen: Dictionary = {}
	var result: Array = []

	# Direct character abilities
	for ability_id in unit.character.abilities:
		if not seen.has(ability_id):
			var a: AbilityData = _ability_getter.call(ability_id)
			if a:
				result.append(a)
				seen[ability_id] = true

	# Class-granted abilities
	for cls_id in unit.character.classes:
		var cls: ClassData = _class_getter.call(cls_id)
		if cls:
			for ability_id in cls.granted_abilities:
				if not seen.has(ability_id):
					var a: AbilityData = _ability_getter.call(ability_id)
					if a:
						result.append(a)
						seen[ability_id] = true

	# Equipment-granted abilities
	for eq_id in unit.character.equipment:
		var item: ItemData = _item_getter.call(eq_id)
		if item:
			for ability_id in item.granted_abilities:
				if not seen.has(ability_id):
					var a: AbilityData = _ability_getter.call(ability_id)
					if a:
						result.append(a)
						seen[ability_id] = true

	return result
