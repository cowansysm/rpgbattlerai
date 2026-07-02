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

## A18: per-battle passive flags (mutable, set at unit construction from passive data)
var reaction_locked: bool = false		## Prevents counter-of-counter chains
var wp_cost_mult: float = 1.0			## WP cost multiplier (Half WP sets to 0.5)
var ignores_hazards: bool = false		## Skip hazard damage_on_enter and damage_per_turn


func is_alive() -> bool:
	return current_hp > 0 and not is_downed


## A18: Returns the ability ID equipped in the named passive slot ("reaction"|"support"|"movement").
func equipped_passive(kind: String) -> String:
	match kind:
		"reaction":
			return character.reaction_passive
		"support":
			return character.support_passive
		"movement":
			return character.movement_passive
	return ""


static func from_character(c: CharacterData, final_stats: StatBlock,
		ability_provider: Callable = Callable()) -> BattleUnit:
	var u := BattleUnit.new()
	u.character = c
	u.stats = final_stats.duplicate()
	u.current_hp = u.stats.effective(StatKey.to_string_key(StatKey.Key.HP))
	u.current_wp = u.stats.effective(StatKey.to_string_key(StatKey.Key.WP))
	# A18: apply support and movement passives if an ability provider is available
	if ability_provider.is_valid():
		_apply_passive_modifiers(u, ability_provider)
	return u


static func from_instance(ci: RefCounted, race_provider: Callable,
		class_provider: Callable, ability_provider: Callable = Callable()) -> BattleUnit:
	var resolver := preload("res://src/core/progression/instance_stat_resolver.gd")
	var sb: StatBlock = resolver.resolve(ci, race_provider, class_provider)
	return BattleUnit.from_character(ci.to_character_data(sb), sb, ability_provider)


## A18: Internal — applies support and movement passive modifiers at construction time.
static func _apply_passive_modifiers(u: BattleUnit, ability_provider: Callable) -> void:
	for kind in ["support", "movement"]:
		var ab_id: String = u.equipped_passive(kind)
		if ab_id.is_empty():
			continue
		var ab: AbilityData = ability_provider.call(ab_id)
		if ab == null or ab.passive_kind != kind:
			continue
		var mod: Dictionary = ab.modifier
		var mod_kind: String = str(mod.get("kind", ""))
		match mod_kind:
			"stat":
				var stat: String = str(mod.get("stat", ""))
				var value: int = int(mod.get("value", 0))
				if not stat.is_empty() and value != 0:
					var source: String = "passive:%s" % kind
					u.stats.push_modifier(StatModifier.new(stat, value, source))
			"wp_mult":
				u.wp_cost_mult = float(mod.get("value", 1.0))
			"hazard_immune":
				u.ignores_hazards = true


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
