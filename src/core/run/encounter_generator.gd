class_name EncounterGenerator
extends RefCounted
## Generates battle encounters for run nodes: selects a map and composes
## an enemy band scaled to a target BP for the current depth.
## All randomness flows from the injected RNG for determinism.


## Returns {map: MapData, enemy_instances: Array[CharacterInstance]}.
## providers keys: all_maps, all_characters, class_provider, name_gen, run_config
static func generate(depth: int, rng: RandomNumberGenerator,
		providers: Dictionary, is_boss: bool = false) -> Dictionary:
	var cfg: Dictionary = providers.get("run_config", {}) as Dictionary
	var map_data: Variant = _pick_map(depth, rng, providers, cfg)
	var enemy_instances: Array[CharacterInstance] = _compose_enemy_band(
		depth, rng, providers, cfg, is_boss)
	return {"map": map_data, "enemy_instances": enemy_instances}


static func _pick_map(depth: int, rng: RandomNumberGenerator,
		providers: Dictionary, cfg: Dictionary) -> Variant:
	var all_maps_fn: Variant = providers.get("all_maps", null)
	if all_maps_fn == null or not all_maps_fn is Callable:
		return null
	var all_maps: Array = (all_maps_fn as Callable).call()
	var tier: String = _tier_for_depth(depth, cfg)
	var candidates: Array = []
	for m in all_maps:
		if m is MapData and (m as MapData).tier == tier:
			candidates.append(m)
	# Fallback: use all maps if no tier match
	if candidates.is_empty():
		candidates = all_maps.duplicate()
	if candidates.is_empty():
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _tier_for_depth(depth: int, cfg: Dictionary) -> String:
	var tier_map: Dictionary = cfg.get("depth_tier_map", {}) as Dictionary
	var best_tier: String = "skirmish"
	var best_threshold: int = -1
	for key in tier_map.keys():
		var threshold: int = int(key)
		if threshold <= depth and threshold > best_threshold:
			best_threshold = threshold
			best_tier = str(tier_map[key])
	return best_tier


static func _compose_enemy_band(depth: int, rng: RandomNumberGenerator,
		providers: Dictionary, cfg: Dictionary, is_boss: bool) -> Array[CharacterInstance]:
	var target_bp: int = _target_bp(depth, cfg, is_boss)
	var count_range: Array = cfg.get("enemy_count_range", [2, 4]) as Array
	var min_count: int = int(count_range[0]) if count_range.size() >= 1 else 2
	var max_count: int = int(count_range[1]) if count_range.size() >= 2 else 4
	var enemy_count: int = rng.randi_range(min_count, max_count)

	var all_templates_fn: Variant = providers.get("all_characters", null)
	if all_templates_fn == null or not all_templates_fn is Callable:
		return []
	var all_templates: Array = (all_templates_fn as Callable).call()
	if all_templates.is_empty():
		return []

	var name_gen: Callable = providers.get("name_gen", func(_r: String) -> String: return "Enemy") as Callable
	var class_prov: Callable = providers.get("class_provider", Callable()) as Callable

	var instances: Array[CharacterInstance] = []
	for i in range(enemy_count):
		var template: CharacterData = all_templates[
			rng.randi_range(0, all_templates.size() - 1)] as CharacterData
		var ci: CharacterInstance = CharacterInstance.generate(template, name_gen)
		instances.append(ci)

	# Scale instances to approach target BP
	var bp_per_unit: int = maxi(1, target_bp / maxi(1, enemy_count))
	var target_level: int = maxi(1, bp_per_unit / BpCalculator.LEVEL_FACTOR)
	for ci in instances:
		if class_prov.is_valid():
			Recruiter.scale_to_level(ci, target_level, class_prov)

	return instances


static func _target_bp(depth: int, cfg: Dictionary, is_boss: bool) -> int:
	var curve: Array = cfg.get("depth_bp_curve", [30]) as Array
	var idx: int = clampi(depth, 0, curve.size() - 1)
	var base_bp: int = int(curve[idx])
	if is_boss:
		base_bp = int(round(base_bp * float(cfg.get("boss_bp_multiplier", 1.5))))
	return base_bp
