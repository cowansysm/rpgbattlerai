class_name Profile
extends RefCounted
## Account-level persistent profile for meta-progression.
## Tracks completed runs, unlocked templates/classes, and meta unlock keys.
## Persisted in SaveManager.profile; to_dict/from_dict for serialization.
## Spec reference: alpha-phaseA10-spec.md §3


var profile_id: String = "default"
var unlocked_templates: Array[String] = []
var unlocked_classes: Array[String] = []
var completed_runs: int = 0
var meta_unlocks: Array[String] = []


func has_template(id: String) -> bool:
	return unlocked_templates.has(id)


func has_class(id: String) -> bool:
	return unlocked_classes.has(id)


func has_unlock(key: String) -> bool:
	return meta_unlocks.has(key)


func grant_template(id: String) -> void:
	if not unlocked_templates.has(id):
		unlocked_templates.append(id)


func grant_class(id: String) -> void:
	if not unlocked_classes.has(id):
		unlocked_classes.append(id)


func grant_unlock(key: String) -> void:
	if not meta_unlocks.has(key):
		meta_unlocks.append(key)


func to_dict() -> Dictionary:
	return {
		"profile_id": profile_id,
		"unlocked_templates": unlocked_templates.duplicate(),
		"unlocked_classes": unlocked_classes.duplicate(),
		"completed_runs": completed_runs,
		"meta_unlocks": meta_unlocks.duplicate(),
	}


static func from_dict(d: Dictionary) -> Profile:
	var p := Profile.new()
	p.profile_id = str(d.get("profile_id", "default"))
	p.unlocked_templates = _to_str_array(d.get("unlocked_templates", []))
	p.unlocked_classes = _to_str_array(d.get("unlocked_classes", []))
	p.completed_runs = int(d.get("completed_runs", 0))
	p.meta_unlocks = _to_str_array(d.get("meta_unlocks", []))
	return p


static func _to_str_array(arr: Variant) -> Array[String]:
	var out: Array[String] = []
	if arr is Array:
		for item in arr:
			out.append(str(item))
	return out
