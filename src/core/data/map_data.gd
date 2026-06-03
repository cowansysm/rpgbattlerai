class_name MapData
extends Resource
## Authored map data.
## Spec reference: rpg-specs.md §9.5
## Tiles stored as Array[TileRecord] (not raw dicts).
## Note: tiles is a plain var (not @export) because Array[TileRecord] is not
## inspector-exportable. The loader populates it programmatically.

@export var id: String = ""
@export var tier: String = ""
var tiles: Array[TileRecord] = []
@export var deployment_zones: Dictionary = {}
