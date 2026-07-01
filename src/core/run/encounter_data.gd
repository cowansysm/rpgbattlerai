class_name EncounterData
extends Resource
## Authored encounter definition: an opposing band and fight conditions.
## Loaded from data/encounters.json by the DataPipeline.
## Spec reference: alpha-phaseA11-spec.md §4

@export var id: String = ""
@export var name: String = ""
@export var min_band_level: int = 1
@export var enemies: Array = []          ## [{character: String, count: int}]
@export var map_id: String = ""          ## "" = pick from pool
@export var level_offset: int = 0
@export var tags: Array[String] = []
@export var modifiers: Dictionary = {}
@export var weight: float = 1.0
