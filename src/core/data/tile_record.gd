class_name TileRecord
extends RefCounted
## Typed container for a single map tile's data.
## Replaces raw dictionaries in MapData.tiles.
## Fields: q, r (axial coords), elevation (int), terrain (String), tags (Array[String]).

var q: int
var r: int
var elevation: int
var terrain: String
var tags: Array[String] = []


func _init(tq: int = 0, tr: int = 0, te: int = 0, tt: String = "grass", ttags: Array[String] = []) -> void:
	q = tq
	r = tr
	elevation = te
	terrain = tt
	tags = ttags


func coord() -> Vector2i:
	return Vector2i(q, r)
