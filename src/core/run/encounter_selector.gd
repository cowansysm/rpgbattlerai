class_name EncounterSelector
extends RefCounted
## Selects an authored encounter eligible for the current band level,
## then instantiates and scales the enemy CharacterInstances.
## All randomness flows from the injected RNG for determinism.


## Selects an encounter and builds enemy instances.
## Returns {encounter: EncounterData, enemies: Array[CharacterInstance], map_id: String}.
## Returns empty dict when no eligible encounter exists.
## providers keys: character_provider (id -> CharacterData), class_provider (id -> ClassData),
##                 name_gen (race -> String)
static func select(band_level: int, rng: RandomNumberGenerator,
		encounters: Array, providers: Dictionary) -> Dictionary:
	var eligible: Array = []
	for enc in encounters:
		if enc is EncounterData and (enc as EncounterData).min_band_level <= band_level:
			eligible.append(enc)
	if eligible.is_empty():
		return {}

	var chosen: EncounterData = _weighted_pick(eligible, rng)
	var target_level: int = clampi(band_level + chosen.level_offset, 1, 10)

	var char_prov: Callable = providers.get("character_provider", Callable()) as Callable
	var class_prov: Callable = providers.get("class_provider", Callable()) as Callable
	var name_gen: Callable = providers.get("name_gen",
		func(_r: String) -> String: return "Enemy") as Callable

	var enemies: Array[CharacterInstance] = []
	for entry in chosen.enemies:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var char_id: String = str(entry.get("character", ""))
		var count: int = int(entry.get("count", 1))
		var template: CharacterData = char_prov.call(char_id) if char_prov.is_valid() else null
		if template == null:
			continue
		for i in count:
			var ci: CharacterInstance = CharacterInstance.generate(template, name_gen)
			if class_prov.is_valid():
				Recruiter.scale_to_level(ci, target_level, class_prov)
			enemies.append(ci)

	return {"encounter": chosen, "enemies": enemies, "map_id": chosen.map_id}


static func _weighted_pick(eligible: Array, rng: RandomNumberGenerator) -> EncounterData:
	var total_weight: float = 0.0
	for enc in eligible:
		total_weight += (enc as EncounterData).weight
	if total_weight <= 0.0:
		return eligible[rng.randi_range(0, eligible.size() - 1)] as EncounterData
	var roll: float = rng.randf() * total_weight
	var accum: float = 0.0
	for enc in eligible:
		accum += (enc as EncounterData).weight
		if roll <= accum:
			return enc as EncounterData
	return eligible[eligible.size() - 1] as EncounterData
