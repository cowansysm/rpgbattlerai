class_name DevOverridesStore
extends Node
## Runtime override store for dev-mode testing.
## Provides key-value overrides that game systems can check.
## Falls through to Constants.get_value() when no override is set.
## Gated by Dev.enabled — all writes are no-ops when disabled.

## Known override keys (for documentation — not enforced):
## DEV_INFINITE_GOLD  (bool)  — ShopService/Recruiter skip gold check
## DEV_FREE_RECRUIT   (bool)  — Recruiter cost = 0
## DEV_ROSTER_CAP     (int)   — Override ROSTER_CAP constant
## DEV_INFINITE_AP    (bool)  — Units never lose AP in combat
## DEV_INFINITE_WP    (bool)  — Units never lose WP in combat
## DEV_INVINCIBLE     (bool)  — Player units take 0 damage
## DEV_ONE_HIT_KILL   (bool)  — Player attacks always down target

var _overrides: Dictionary = {}
var _enabled: bool = false


func _ready() -> void:
	_enabled = Dev.enabled
	if not _enabled:
		set_process(false)


func set_override(key: String, value: Variant) -> void:
	if not _enabled:
		return
	_overrides[key] = value
	Log.info("DevOverrides", "Set %s = %s" % [key, str(value)])


func clear_override(key: String) -> void:
	_overrides.erase(key)


func clear_all() -> void:
	_overrides.clear()
	Log.info("DevOverrides", "All overrides cleared")


## Returns the override value if set, otherwise falls through to Constants.
func get_override(key: String, default_value: Variant = null) -> Variant:
	if _overrides.has(key):
		return _overrides[key]
	return Constants.get_value(key, default_value)


## Returns the override value if set, or the provided default (no Constants fallback).
func get_flag(key: String, default_value: Variant = false) -> Variant:
	return _overrides.get(key, default_value)


func has_override(key: String) -> bool:
	return _overrides.has(key)


func is_active() -> bool:
	return _enabled


func all_overrides() -> Dictionary:
	return _overrides.duplicate()
