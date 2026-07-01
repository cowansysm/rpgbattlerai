class_name Affinity
extends RefCounted
## Elemental affinity model: tiers, multiplier lookup, and stacking.
## Affinities are authored per source (race/class/equipment/terrain) as
## {element: tier_name} dicts. Tier weights are summed across sources and
## clamped to a band to produce one effective tier per element at hit time.
## Spec reference: alpha-phaseA16-spec.md §2


## Tier enum — ordered by weight for clamping.
enum Tier { ABSORB = -3, IMMUNE = -2, RESIST = -1, NEUTRAL = 0, WEAK = 1 }

## Canonical tier names for serialization/validation.
const TIER_NAMES: Array[String] = ["absorb", "immune", "resist", "neutral", "weak"]

## Known element tags (validated in Validator).
const ELEMENTS: Array[String] = [
	"fire", "ice", "lightning", "dark", "holy", "earth", "wind", "water",
]

## Weight assigned to each authored tier name for additive stacking.
const _TIER_WEIGHT: Dictionary = {
	"weak": 1,
	"neutral": 0,
	"resist": -1,
	"immune": -2,
	"absorb": -3,
}


## Convert a tier name string to its stacking weight.
## Unknown names return 0 (NEUTRAL).
static func tier_to_weight(tier_name: String) -> int:
	return int(_TIER_WEIGHT.get(tier_name.to_lower(), 0))


## Clamp a summed weight to the valid tier range and return the Tier enum.
static func weight_to_tier(weight: int) -> int:
	return clampi(weight, Tier.ABSORB, Tier.WEAK)


## Look up the damage multiplier for a tier from constants.
## Falls back to sensible defaults if constants are missing.
static func multiplier(tier: int) -> float:
	var table: Dictionary = Constants.get_value("AFFINITY_MULT", {})
	match tier:
		Tier.WEAK:
			return float(table.get("weak", 1.5))
		Tier.NEUTRAL:
			return float(table.get("neutral", 1.0))
		Tier.RESIST:
			return float(table.get("resist", 0.5))
		Tier.IMMUNE:
			return float(table.get("immune", 0.0))
		Tier.ABSORB:
			return float(table.get("absorb", 1.0))
	return 1.0


## Convert a Tier enum to its canonical string name.
static func tier_to_name(tier: int) -> String:
	match tier:
		Tier.WEAK:    return "weak"
		Tier.NEUTRAL: return "neutral"
		Tier.RESIST:  return "resist"
		Tier.IMMUNE:  return "immune"
		Tier.ABSORB:  return "absorb"
	return "neutral"


## Merge multiple affinity source dicts into a single {element: weight} dict.
## Each source is {element_string: tier_name_string}.
## Returns {element_string: int_weight_sum}.
static func merge_sources(sources: Array) -> Dictionary:
	var merged: Dictionary = {}
	for source: Dictionary in sources:
		for elem: String in source.keys():
			var w: int = tier_to_weight(str(source[elem]))
			if not merged.has(elem):
				merged[elem] = 0
			merged[elem] += w
	return merged
