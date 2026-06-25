class_name MetaUnlockEngine
extends RefCounted
## Evaluates data-driven unlock rules at run end and applies grants to the Profile.
## Rules are loaded from data/meta_unlocks.json.
## Spec reference: alpha-phaseA10-spec.md §3.2


## Evaluates all unlock rules against the run outcome and applies matching grants.
## Always increments completed_runs (on any outcome, not just victory).
## Returns an array of {rule_id: String, grants: Dictionary} for each newly applied rule.
static func evaluate_run_end(profile: Profile, outcome: String,
		run: RunState, table: Dictionary) -> Array[Dictionary]:
	profile.completed_runs += 1
	var earned: Array[Dictionary] = []
	var rules: Array = table.get("rules", []) as Array
	for rule_entry in rules:
		if not rule_entry is Dictionary:
			continue
		var rule: Dictionary = rule_entry as Dictionary
		var rule_id: String = str(rule.get("id", ""))
		if rule_id.is_empty():
			continue
		# Skip rules that have already been fully applied
		if _rule_already_applied(profile, rule):
			continue
		if _trigger_matches(profile, outcome, run, rule):
			var grants: Dictionary = rule.get("grants", {}) as Dictionary
			_apply_grants(profile, grants)
			earned.append({"rule_id": rule_id, "grants": grants})
	return earned


## Resolves which starting boons the player is eligible for based on their profile.
## Returns an array of boon dicts (each has "id", "requires", "effect").
static func resolve_boons(profile: Profile, table: Dictionary) -> Array[Dictionary]:
	var boons: Array[Dictionary] = []
	var boon_defs: Array = table.get("starting_boons", []) as Array
	for entry in boon_defs:
		if not entry is Dictionary:
			continue
		var boon: Dictionary = entry as Dictionary
		var requires: String = str(boon.get("requires", ""))
		if requires.is_empty() or profile.has_unlock(requires):
			boons.append(boon)
	return boons


static func _trigger_matches(profile: Profile, outcome: String,
		run: RunState, rule: Dictionary) -> bool:
	var trigger: String = str(rule.get("trigger", ""))
	match trigger:
		"run_complete":
			# Fires on any run end (victory or defeat)
			return true
		"boss_kill":
			return outcome == "victory"
		"depth_reached":
			var threshold: int = int(rule.get("threshold", 0))
			return run.depth >= threshold
		"runs_completed":
			var threshold: int = int(rule.get("threshold", 0))
			return profile.completed_runs >= threshold
		_:
			Log.warn("MetaUnlockEngine", "Unknown trigger type: %s" % trigger)
			return false


static func _rule_already_applied(profile: Profile, rule: Dictionary) -> bool:
	# A rule is considered applied if all of its grants are already present
	var grants: Dictionary = rule.get("grants", {}) as Dictionary
	var templates: Array = grants.get("templates", []) as Array
	var classes: Array = grants.get("classes", []) as Array
	var unlocks: Array = grants.get("meta_unlocks", []) as Array
	# If the rule grants nothing, skip it (it's a no-op)
	if templates.is_empty() and classes.is_empty() and unlocks.is_empty():
		return true
	for t in templates:
		if not profile.has_template(str(t)):
			return false
	for c in classes:
		if not profile.has_class(str(c)):
			return false
	for u in unlocks:
		if not profile.has_unlock(str(u)):
			return false
	return true


static func _apply_grants(profile: Profile, grants: Dictionary) -> void:
	for t in grants.get("templates", []):
		profile.grant_template(str(t))
	for c in grants.get("classes", []):
		profile.grant_class(str(c))
	for u in grants.get("meta_unlocks", []):
		profile.grant_unlock(str(u))
