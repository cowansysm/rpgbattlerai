extends Node
## Simple data holder for passing match state between scenes.
## Populated by DraftScene, band management, or RunScene; consumed by map_scene.
## Registered as autoload "MatchData".

var match_state: MatchState = null
var map_id: String = ""

## Band-battle fields (A5)
var active_band: BattleBand = null
var fielded_ids: Array[String] = []
var is_instance_battle: bool = false

## Deployment controller (A12) — passed to BattleController for interactive deployment
## Typed as Variant to avoid parse-time dependency on DeploymentController from autoload.
var deployment_controller: Variant = null

## Turn-system mode (A15): "run" = speed-round, "skirmish" = charge-time (A20)
var mode: String = "run"

## Skirmish fields (A20)
var opponent_type: String = "ai"     ## "ai" or "hot_seat"
var skirmish_squad_size: int = 3     ## Number of units per side

## Run-battle fields (A8)
var active_run: Variant = null       ## RunState or null
var run_node_id: String = ""         ## Node being resolved
var battle_result: Variant = null    ## Dictionary from BattleController on match over


func has_match() -> bool:
	return match_state != null


func has_band_battle() -> bool:
	return active_band != null and not fielded_ids.is_empty()


## Clears only match-specific state; preserves band/run context for battle return.
func clear_match() -> void:
	match_state = null
	deployment_controller = null
	map_id = ""


## Clears all state.
func clear() -> void:
	clear_match()
	active_band = null
	fielded_ids = []
	is_instance_battle = false
	deployment_controller = null
	mode = "run"
	opponent_type = "ai"
	skirmish_squad_size = 3
	active_run = null
	run_node_id = ""
	battle_result = null
