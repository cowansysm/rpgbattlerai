class_name Deployment
extends RefCounted
## Legacy shim: auto_deploy now delegates to DeploymentController + a simple
## positional planner. Kept for backward compatibility with tests and the
## Phase4Demo fallback. New code should use DeploymentController directly.
## Spec reference: phase4-spec.md §6, alpha-phaseA12-spec.md §10


## Positional auto-deploy: places units in zone tile order via DeploymentController.
## This is the headless/test path — new interactive code should use
## DeploymentController.begin() + place_next() or auto_complete() instead.
static func auto_deploy(state: MatchState, zones: Dictionary) -> Array[String]:
	var controller := DeploymentController.new()
	var errors := controller.begin(state, zones, [])
	if not errors.is_empty():
		return errors

	# Simple positional planner: pick zone tiles in order (first legal tile)
	var positional_planner := func(
		s: MatchState, team: String, _unit: BattleUnit,
		legal: Array[Vector2i], _enemy_zone: Array[Vector2i],
	) -> Vector2i:
		return legal[0]

	controller.auto_complete(positional_planner)
	if not controller.is_complete():
		return ["Deployment failed: not all units could be placed (overlapping/blocked zones?)"] as Array[String]
	return []
