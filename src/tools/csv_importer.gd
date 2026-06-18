class_name CsvImporter
extends RefCounted
## Imports CSV content files back into consolidated JSON using the EntitySchema.
## Validates every row before writing. Fail-closed: nothing is written on any error.

const JSON_DIR := "res://data/"
const CSV_DIR := "res://data/csv/"


## Unflatten a single CSV row back into a nested entity dict.
## Blank cells are omitted (absent key semantics).
static func unflatten(header: PackedStringArray, row: PackedStringArray, cols: Array[Dictionary]) -> Dictionary:
	var obj: Dictionary = {}
	for col in cols:
		var idx := _find_in_header(header, col["name"])
		if idx < 0 or idx >= row.size():
			continue
		var cell := row[idx].strip_edges()
		if cell == "":
			continue
		var val: Variant = _coerce(cell, col)
		if val == null and col["mode"] == EntitySchema.Mode.JSON:
			continue  # JSON parse failure → treat as absent
		_put(obj, col["path"], val)
	return obj


## Import one entity type from CSV to JSON.
## Validates all rows first. Returns an empty array on success, or error strings.
static func import_entity(entity: String, csv_path: String = "", json_path: String = "") -> Array[String]:
	var cp := csv_path if csv_path != "" else CSV_DIR + entity + ".csv"
	var jp := json_path if json_path != "" else JSON_DIR + entity + ".json"

	var cols := EntitySchema.columns_for(entity)
	if cols.is_empty():
		return ["Unknown entity type: " + entity]

	# Read CSV
	var read_result := _read_csv(cp)
	if read_result["error"] != "":
		return [read_result["error"]]
	var header: PackedStringArray = read_result["header"]
	var rows: Array = read_result["rows"]

	if rows.is_empty():
		return ["CSV has no data rows: " + cp]

	# Unflatten all rows
	var entities: Array[Dictionary] = []
	for row in rows:
		entities.append(unflatten(header, row, cols))

	# Validate all rows
	var errors := validate_rows(entity, entities)
	if not errors.is_empty():
		return errors

	# Write JSON (stable key order)
	return _write_json(entity, entities, jp)


## Import all entity types. Returns accumulated errors. Stops on first entity failure.
static func import_all() -> Array[String]:
	var errors: Array[String] = []
	for entity in EntitySchema.ENTITIES:
		var cp := CSV_DIR + entity + ".csv"
		if not FileAccess.file_exists(cp):
			continue
		var result := import_entity(entity)
		errors.append_array(result)
	return errors


## Validate an array of unflattened entity dicts using the existing Validator.
static func validate_rows(entity: String, rows: Array[Dictionary]) -> Array[String]:
	var errs: Array[String] = []
	for d in rows:
		var entity_id := str(d.get("id", "?"))
		var row_errors: Array[String] = []
		match entity:
			"abilities":
				row_errors = Validator.validate_ability(d)
			"classes":
				row_errors = Validator.validate_class(d)
			"items":
				row_errors = Validator.validate_item(d)
			"characters":
				row_errors = Validator.validate_character(d)
			"races":
				row_errors = Validator.validate_race(d)
			"terrain":
				row_errors = _validate_terrain(d)
		for err in row_errors:
			errs.append("[%s] %s" % [entity_id, err])
	return errs


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Find a column name in the header. Case-sensitive exact match.
static func _find_in_header(header: PackedStringArray, name: String) -> int:
	for i in range(header.size()):
		if header[i].strip_edges() == name:
			return i
	return -1


## Coerce a cell string to the appropriate type per the column schema.
static func _coerce(cell: String, col: Dictionary) -> Variant:
	match col["mode"]:
		EntitySchema.Mode.JSON:
			return JSON.parse_string(cell)
		_:
			match col["type"]:
				"int":
					return int(cell)
				"bool":
					return cell.strip_edges().to_lower() in ["1", "true", "yes"]
				_:
					return cell


## Set a value in a nested dict by dotted path (e.g. "effect.value" → obj.effect.value).
static func _put(obj: Dictionary, path: String, val: Variant) -> void:
	var parts := path.split(".")
	var cur := obj
	for i in range(parts.size() - 1):
		if not cur.has(parts[i]):
			cur[parts[i]] = {}
		cur = cur[parts[i]]
	cur[parts[parts.size() - 1]] = val


## Read a CSV file, returning header and rows.
static func _read_csv(csv_path: String) -> Dictionary:
	var f := FileAccess.open(csv_path, FileAccess.READ)
	if f == null:
		return {"header": PackedStringArray(), "rows": [], "error": "Cannot open: " + csv_path}

	var header := f.get_csv_line()
	if header.is_empty():
		f.close()
		return {"header": PackedStringArray(), "rows": [], "error": "Empty CSV: " + csv_path}

	var rows: Array = []
	while not f.eof_reached():
		var line := f.get_csv_line()
		# Skip blank trailing lines
		if line.size() == 1 and line[0].strip_edges() == "":
			continue
		if line.size() > 0:
			rows.append(line)
	f.close()

	return {"header": header, "rows": rows, "error": ""}


## Write entity dicts to a consolidated JSON file with stable key order.
## Terrain is written as a keyed dict; all others as arrays.
static func _write_json(entity: String, entities: Array[Dictionary], json_path: String) -> Array[String]:
	var cols := EntitySchema.columns_for(entity)
	var ordered: Variant

	if EntitySchema.is_keyed_dict(entity):
		# Terrain: keyed dict, key = id, remove id from inner dict
		ordered = _build_keyed_dict(entities, cols)
	else:
		# Array of objects with stable key order
		ordered = _build_ordered_array(entities, cols)

	var json_text := JSON.stringify(ordered, "  ")
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	if f == null:
		return ["Cannot open for writing: " + json_path]
	f.store_string(json_text)
	f.store_string("\n")
	f.close()
	return []


## Build an array of ordered entity dicts for JSON output.
static func _build_ordered_array(entities: Array[Dictionary], cols: Array[Dictionary]) -> Array:
	var arr: Array = []
	for ent in entities:
		arr.append(_build_ordered_dict(ent, cols))
	return arr


## Build a keyed dict (terrain) for JSON output.
static func _build_keyed_dict(entities: Array[Dictionary], cols: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for ent in entities:
		var entity_id: String = str(ent.get("id", ""))
		var ordered := _build_ordered_dict(ent, cols)
		ordered.erase("id")  # id is the key, not a field
		result[entity_id] = ordered
	return result


## Build a single entity dict with keys ordered per the column schema.
## Preserves nested structure from dotted paths.
static func _build_ordered_dict(ent: Dictionary, cols: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	# First pass: add keys in column order
	for col in cols:
		var val: Variant = _dig(ent, col["path"])
		if val == null:
			continue
		_put(result, col["path"], val)
	# Second pass: include any keys from the original not in the schema
	# (safety net for forward compatibility)
	for key in ent.keys():
		if not result.has(key):
			result[key] = ent[key]
	return result


## Dig into a nested dict by a dotted path.
static func _dig(obj: Dictionary, path: String) -> Variant:
	var cur: Variant = obj
	for part in path.split("."):
		if typeof(cur) != TYPE_DICTIONARY or not cur.has(part):
			return null
		cur = cur[part]
	return cur


## Structural validation for terrain entries (no Validator.validate_terrain exists).
static func _validate_terrain(d: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	if not d.has("id"):
		errs.append("terrain missing required field 'id'")
	if d.has("move_cost"):
		var mc: Variant = d["move_cost"]
		if typeof(mc) != TYPE_INT and typeof(mc) != TYPE_FLOAT:
			errs.append("terrain '%s' move_cost must be numeric" % d.get("id", "?"))
	if d.has("status_on_enter") and typeof(d["status_on_enter"]) == TYPE_DICTIONARY:
		var soe: Dictionary = d["status_on_enter"]
		if not soe.is_empty():
			if not soe.has("status_id"):
				errs.append("terrain '%s' status_on_enter missing 'status_id'" % d.get("id", "?"))
			if not soe.has("duration"):
				errs.append("terrain '%s' status_on_enter missing 'duration'" % d.get("id", "?"))
	if d.has("occupant_modifiers") and typeof(d["occupant_modifiers"]) == TYPE_ARRAY:
		for idx in range(d["occupant_modifiers"].size()):
			var mod: Variant = d["occupant_modifiers"][idx]
			if typeof(mod) != TYPE_DICTIONARY:
				errs.append("terrain '%s' occupant_modifiers[%d] must be a dict" % [d.get("id", "?"), idx])
			elif not mod.has("key") or not mod.has("value"):
				errs.append("terrain '%s' occupant_modifiers[%d] missing 'key' or 'value'" % [d.get("id", "?"), idx])
	return errs
