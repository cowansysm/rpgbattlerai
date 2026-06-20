class_name RaceData
extends Resource
## Authored race/ancestry data.
## Spec reference: rpg-specs.md §4.1

@export var id: String = ""
@export var display_name: String = ""
@export var stat_modifiers: Dictionary = {}
@export var flavor: String = ""
@export var base_stats: Dictionary = {}
