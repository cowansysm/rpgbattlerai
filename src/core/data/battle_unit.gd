class_name BattleUnit
extends RefCounted
## Runtime wrapper separating immutable authored data from mutable per-battle state.
## Authored Resources (CharacterData, etc.) are never mutated post-load.
## All per-battle mutable state lives here.
## Spec reference: rpg-specs.md §9.6, phase1-spec.md §5.1

var character: CharacterData        ## Immutable authored data (read-only reference)
var stats: StatBlock                ## Own copy for runtime modifiers; initialized from load-time derivation
var position: Vector2i = Vector2i.ZERO
var current_hp: int = 0
var current_wp: int = 0
var base_ap: int = 2					## Starting AP per activation (default 2)
var ap_remaining: int = 2
var is_activated: bool = false
var has_moved: bool = false				## Whether unit has moved this activation
var team: String = ""
var status_effects: Array = []			## [{id: String, duration: int, source: String}, ...]
var is_downed: bool = false				## True when HP <= 0 but not yet permanently removed
var downed_round: int = -1				## Round number when unit was downed (-1 = never)
var affinities: Dictionary = {}			## {element: int_weight} — cumulative from static sources (race+class+equipment)


func is_alive() -> bool:
	return current_hp > 0 and not is_downed


static func from_character(c: CharacterData, final_stats: StatBlock) -> BattleUnit:
	var u := BattleUnit.new()
	u.character = c
	u.stats = final_stats.duplicate()
	u.current_hp = u.stats.effective(StatKey.to_string_key(StatKey.Key.HP))
	u.current_wp = u.stats.effective(StatKey.to_string_key(StatKey.Key.WP))
	return u


static func from_instance(ci: RefCounted, race_provider: Callable, class_provider: Callable) -> BattleUnit:
	var resolver := preload("res://src/core/progression/instance_stat_resolver.gd")
	var sb: StatBlock = resolver.resolve(ci, race_provider, class_provider)
	return BattleUnit.from_character(ci.to_character_data(sb), sb)


func has_status(status_id: String) -> bool:
	for s in status_effects:
		if s["id"] == status_id:
			return true
	return false


func remove_status(status_id: String) -> void:
	status_effects = status_effects.filter(
		func(s: Dictionary) -> bool: return s["id"] != status_id)


## Return the effective affinity tier for an element, including an optional
## extra weight from external sources (e.g., terrain).
func effective_affinity(element: String, extra_weight: int = 0) -> int:
	if element.is_empty():
		return Affinity.Tier.NEUTRAL
	var weight: int = int(affinities.get(element, 0)) + extra_weight
	return Affinity.weight_to_tier(weight)


## Populate affinities from authored source dicts.
## Each source is {element: tier_name_string}.
func apply_affinity_sources(sources: Array) -> void:
	affinities = Affinity.merge_sources(sources)
