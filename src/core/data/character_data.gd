class_name CharacterData
extends Resource
## Authored character data loaded from JSON.
## Stats stored as Dictionary validated against StatKey.
## Spec reference: rpg-specs.md §9.1

@export var id: String = ""
@export var display_name: String = ""
@export var race: String = ""
@export var classes: Array[String] = []
@export var level: int = 0
@export var bp: int = 0
@export var base_stats: Dictionary = {}
@export var equipment: Array[String] = []
@export var abilities: Array[String] = []
@export var recommended_path: String = ""

## A18: authored passive slots (set by authored enemies or copied from CharacterInstance).
@export var reaction_passive: String = ""
@export var support_passive: String = ""
@export var movement_passive: String = ""

var final_stats: StatBlock = null
