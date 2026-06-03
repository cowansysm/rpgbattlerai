class_name StatModifier
extends RefCounted
## A single additive modifier entry for the stat modifier stack.
## Used by StatBlock to track runtime stat changes (equipment, buffs, elevation, etc.).

var key: String       ## A valid StatKey string (e.g., "spd")
var value: int        ## Additive modifier amount
var source: String    ## Origin tag (e.g., "equipment", "buff", "elevation")


func _init(k: String = "", v: int = 0, s: String = "") -> void:
	key = k
	value = v
	source = s
