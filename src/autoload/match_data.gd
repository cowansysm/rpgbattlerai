extends Node
## Simple data holder for passing match state between scenes.
## Populated by DraftScene or band management, consumed by map_scene.
## Registered as autoload "MatchData".

var match_state: MatchState = null
var map_id: String = ""

## Band-battle fields (A5)
var active_band: BattleBand = null
var fielded_ids: Array[String] = []
var is_instance_battle: bool = false


func has_match() -> bool:
	return match_state != null


func has_band_battle() -> bool:
	return active_band != null and not fielded_ids.is_empty()


func clear() -> void:
	match_state = null
	map_id = ""
	active_band = null
	fielded_ids = []
	is_instance_battle = false
