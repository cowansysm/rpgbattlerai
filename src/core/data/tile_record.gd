class_name TileRecord
extends RefCounted
## Typed container for a single map tile's data.
## Replaces raw dictionaries in MapData.tiles.
## Fields: q, r (axial coords), elevation (int), terrain (String).

var q: int
var r: int
var elevation: int
var terrain: String


func _init(tq: int = 0, tr: int = 0, te: int = 0, tt: String = "grass") -> void:
	q = tq
	r = tr
	elevation = te
	terrain = tt


func coord() -> Vector2i:
	return Vector2i(q, r)
