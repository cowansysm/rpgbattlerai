class_name CsvExporter
extends RefCounted
## Exports consolidated JSON content files to CSV using the EntitySchema.
## Each entity type produces one CSV with a header row and one row per entity.

const JSON_DIR := "res://data/"
const CSV_DIR := "res://data/csv/"


## Flatten a single entity dict into a CSV row per the column schema.
## Absent keys → blank cell. JSON-mode fields → JSON text.
static func flatten(obj: Dictionary, cols: Array[Dictionary]) -> PackedStringArray:
	var row := PackedStringArray()
	for col in cols:
		var v: Variant = _dig(obj, col["path"])
		if v == null:
			row.append("")
		elif col["mode"] == EntitySchema.Mode.JSON:
			row.append(JSON.stringify(v))
		elif col["type"] == "bool":
			row.append("true" if v else "false")
		else:
			row.append(str(v))
	return row


## Export one entity type from JSON to CSV.
## Returns an empty array on success, or an array of error strings.
static func export_entity(entity: String, json_path: String = "", csv_path: String = "") -> Array[String]:
	var jp := json_path if json_path != "" else JSON_DIR + entity + ".json"
	var cp := csv_path if csv_path != "" else CSV_DIR + entity + ".csv"

	var cols := EntitySchema.columns_for(entity)
	if cols.is_empty():
		return ["Unknown entity type: " + entity]

	var arr := _load_as_array(entity, jp)
	if arr.is_empty() and entity != "terrain":
		# terrain could be empty legitimately, but for others this is suspicious
		return ["Failed to load or empty file: " + jp]

	# Ensure the output directory exists
	var dir := DirAccess.open("res://")
	if dir and not dir.dir_exists("data/csv"):
		dir.make_dir_recursive("data/csv")

	var f := FileAccess.open(cp, FileAccess.WRITE)
	if f == null:
		return ["Cannot open for writing: " + cp + " (error: " + str(FileAccess.get_open_error()) + ")"]

	# Header
	var header := PackedStringArray()
	for c in cols:
		header.append(c["name"])
	f.store_csv_line(header)

	# Rows
	for obj in arr:
		f.store_csv_line(flatten(obj, cols))

	f.close()
	return []


## Export all entity types. Returns accumulated errors.
static func export_all() -> Array[String]:
	var errors: Array[String] = []
	for entity in EntitySchema.ENTITIES:
		errors.append_array(export_entity(entity))
	return errors


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Dig into a nested dict by a dotted path (e.g. "effect.value").
## Returns null if any segment is missing.
static func _dig(obj: Dictionary, path: String) -> Variant:
	var cur: Variant = obj
	for part in path.split("."):
		if typeof(cur) != TYPE_DICTIONARY or not cur.has(part):
			return null
		cur = cur[part]
	return cur


## Load a JSON file as an array of entity dicts.
## Terrain (keyed dict) is converted to an array with the key injected as "id".
static func _load_as_array(entity: String, json_path: String) -> Array[Dictionary]:
	var f := FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		return []
	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		return []

	if EntitySchema.is_keyed_dict(entity):
		# Keyed dict → array with id injected
		var arr: Array[Dictionary] = []
		var dict: Dictionary = parsed
		for key in dict.keys():
			var entry: Dictionary = dict[key].duplicate()
			entry["id"] = key
			arr.append(entry)
		return arr

	# Already an array
	var result: Array[Dictionary] = []
	for item in parsed:
		if typeof(item) == TYPE_DICTIONARY:
			result.append(item)
	return result
