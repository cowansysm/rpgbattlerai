class_name ItemData
extends Resource
## Authored item/equipment data.
## Spec reference: rpg-specs.md §9.4

@export var id: String = ""
@export var display_name: String = ""
@export var slot: String = ""
@export var bp_value: int = 0
@export var passive: Dictionary = {}
@export var granted_abilities: Array[String] = []
@export var weapon_power: int = 0
@export var weapon_range: int = 0
