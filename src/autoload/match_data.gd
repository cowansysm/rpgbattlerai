extends Node
## Simple data holder for passing match state between scenes.
## Populated by DraftScene, consumed by map_scene. Registered as autoload "MatchData".

var match_state: MatchState = null
var map_id: String = ""


func has_match() -> bool:
	return match_state != null


func clear() -> void:
	match_state = null
	map_id = ""
