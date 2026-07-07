class_name AbilityData
extends Resource
## Authored ability/spell data.
## Spec reference: rpg-specs.md §9.3
## Note: field is "ability_range" not "range" to avoid shadowing GDScript builtin.
## JSON key "range" maps to this field in the factory.
## A18: passive_kind / trigger / modifier added for reaction, support, movement passives.

@export var id: String = ""
@export var display_name: String = ""
@export var type: String = ""
@export var ap_cost: int = 1
@export var wp_cost: int = 0
@export var ability_range: int = 0
@export var area: Dictionary = {}
@export var effect: Dictionary = {}
@export var effect_type: String = ""
@export var mag_scaling: float = 1.0
@export var source: String = ""

## A18: passive category — "reaction" | "support" | "movement" | "" (active)
@export var passive_kind: String = ""

## A18: trigger descriptor for reaction passives.
## Keys: event (String), melee_only (bool), hp_pct (float).
## Populated only when passive_kind == "reaction".
@export var trigger: Dictionary = {}

## A18: modifier descriptor for support/movement passives.
## Keys: kind (String), stat (String), value (int/float), etc.
## Populated only when passive_kind in ["support", "movement"].
@export var modifier: Dictionary = {}


## True only for abilities usable as an activatable action. Excludes A18 slotted
## passives (passive_kind set) AND legacy passives authored with type == "passive"
## (many carry passive_kind == "" yet are self-buff/innate traits with ap 0 / no
## effect — they would otherwise be enumerated and "used" as no-op actions).
func is_active() -> bool:
	return passive_kind == "" and type != "passive"
