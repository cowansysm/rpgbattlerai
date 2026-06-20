class_name AIPlan
extends RefCounted
## Ordered list of steps for one AI activation.
## Each step is a Dictionary: {kind, target_pos, ability_id, item_id}.
## Factory helpers produce common plan shapes.

var steps: Array = []


func total_ap_cost() -> int:
	var cost := 0
	for step in steps:
		cost += _step_ap(step)
	return cost


func add_step(step: Dictionary) -> void:
	steps.append(step)


func is_empty() -> bool:
	return steps.is_empty()


# --- Factory helpers ---

static func make_move_attack(tile: Vector2i, target: Vector2i) -> AIPlan:
	var plan := AIPlan.new()
	plan.steps.append({"kind": "move", "target_pos": tile})
	plan.steps.append({"kind": "attack", "target_pos": target})
	return plan


static func make_move_ability(
	tile: Vector2i, ability_id: String, target: Vector2i, ap_cost: int
) -> AIPlan:
	var plan := AIPlan.new()
	plan.steps.append({"kind": "move", "target_pos": tile})
	plan.steps.append({"kind": "ability", "ability_id": ability_id, "target_pos": target, "ap_cost": ap_cost})
	return plan


static func make_move_only(tile: Vector2i) -> AIPlan:
	var plan := AIPlan.new()
	plan.steps.append({"kind": "move", "target_pos": tile})
	return plan


static func make_attack_only(target: Vector2i) -> AIPlan:
	var plan := AIPlan.new()
	plan.steps.append({"kind": "attack", "target_pos": target})
	return plan


static func make_ability_only(
	ability_id: String, target: Vector2i, ap_cost: int
) -> AIPlan:
	var plan := AIPlan.new()
	plan.steps.append({"kind": "ability", "ability_id": ability_id, "target_pos": target, "ap_cost": ap_cost})
	return plan


static func make_defend() -> AIPlan:
	var plan := AIPlan.new()
	plan.steps.append({"kind": "defend"})
	return plan


static func make_wait() -> AIPlan:
	var plan := AIPlan.new()
	plan.steps.append({"kind": "wait"})
	return plan


# --- Internal ---

static func _step_ap(step: Dictionary) -> int:
	match str(step.get("kind", "")):
		"move":
			return 1
		"attack":
			return 1
		"ability":
			return int(step.get("ap_cost", 1))
		"defend":
			return 1
		"use_item":
			return 1
		"wait":
			return 0
	return 0
