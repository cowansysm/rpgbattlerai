class_name AbilityData
extends Resource
## Authored ability/spell data.
## Spec reference: rpg-specs.md §9.3
## Note: field is "ability_range" not "range" to avoid shadowing GDScript builtin.
## JSON key "range" maps to this field in the factory.

@export var id: String = ""
@export var display_name: String = ""
@export var type: String = ""
@export var ap_cost: int = 1
@export var ability_range: int = 0
@export var area: Dictionary = {}
@export var effect: Dictionary = {}
@export var effect_type: String = ""
@export var source: String = ""
