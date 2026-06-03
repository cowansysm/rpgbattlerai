extends Node
## Loads constants.json and exposes tunable values. Registered as autoload "Constants".

var _values: Dictionary = {}


func _ready() -> void:
	var text := FileAccess.get_file_as_string("res://data/constants.json")
	if text.is_empty():
		push_error("Constants: failed to load data/constants.json")
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		_values = parsed
	else:
		push_error("Constants: data/constants.json is not a JSON object")


func get_value(key: String, default_value: Variant = null) -> Variant:
	return _values.get(key, default_value)
