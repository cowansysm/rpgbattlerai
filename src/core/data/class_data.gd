class_name ClassData
extends Resource
## Authored class/job data.
## Spec reference: rpg-specs.md §9.2

@export var id: String = ""
@export var display_name: String = ""
@export var abbr: String = ""
@export var stat_modifiers: Dictionary = {}
@export var derived_bonuses: Dictionary = {}
@export var equipment_access: Array[String] = []
@export var granted_abilities: Array[String] = []
@export var level_max: int = 1
@export var required_classes: Array = []
@export var archetype: String = ""
@export var branch: String = ""
@export var tier: int = 0
@export var growth: Dictionary = {}
@export var jp_costs: Dictionary = {}
@export var prerequisites: Dictionary = {}
