class_name NameGenerator
extends RefCounted
## Generates character names from per-race name tables.
## Tables are JSON files in data/names/<race>.json with {given: [...], surname: [...]}.

var _tables: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func load_tables(base_path: String = "res://data/names") -> void:
	var dir := DirAccess.open(base_path)
	if dir == null:
		push_warning("NameGenerator: cannot open '%s'" % base_path)
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var race_id: String = file_name.get_basename()
			var full_path: String = base_path.path_join(file_name)
			var text := FileAccess.get_file_as_string(full_path)
			if not text.is_empty():
				var parsed: Variant = JSON.parse_string(text)
				if typeof(parsed) == TYPE_DICTIONARY:
					_tables[race_id] = parsed
		file_name = dir.get_next()
	dir.list_dir_end()


func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func generate_name(race: String) -> String:
	var table: Dictionary = _tables.get(race, {})
	var given_list: Array = table.get("given", [])
	var surname_list: Array = table.get("surname", [])
	if given_list.is_empty():
		return "Unknown"
	var given: String = str(given_list[_rng.randi() % given_list.size()])
	if surname_list.is_empty():
		return given
	var surname: String = str(surname_list[_rng.randi() % surname_list.size()])
	return "%s %s" % [given, surname]
