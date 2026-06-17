class_name JsonLoader
extends RefCounted
## Loads entity data from JSON files. Supports both consolidated (single file,
## array-of-objects) and legacy (directory of individual files) formats.
## Engine-light, fully testable.


## Consolidated loader: reads a single JSON file containing an array of entities.
## Each entry must include an "id" field.
## Returns {"entries": {id: Resource}, "errors": Array[String]}.
## validator signature: func(d: Dictionary) -> Array[String]
## factory signature: func(d: Dictionary) -> Resource
static func load_and_validate_file(file_path: String, validator: Callable, factory: Callable) -> Dictionary:
	var entries := {}
	var errors: Array[String] = []
	var text := FileAccess.get_file_as_string(file_path)
	if text.is_empty():
		errors.append("file not found or empty: '%s'" % file_path)
		return {"entries": entries, "errors": errors}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		errors.append("'%s' is not a JSON array" % file_path)
		return {"entries": entries, "errors": errors}
	for i in range(parsed.size()):
		var d: Variant = parsed[i]
		if typeof(d) != TYPE_DICTIONARY:
			errors.append("entry %d in '%s' is not a JSON object" % [i, file_path])
			continue
		if not d.has("id"):
			errors.append("entry %d in '%s' is missing required field 'id'" % [i, file_path])
			continue
		d["id"] = str(d["id"])
		var validation_errors: Array[String] = validator.call(d)
		if not validation_errors.is_empty():
			errors.append_array(validation_errors)
			continue
		var res: Resource = factory.call(d)
		if res != null and res.get("id") != null and res.id != "":
			entries[res.id] = res
	return {"entries": entries, "errors": errors}


## Legacy directory loader (no validation). Kept for backward compatibility.
## factory signature: func(d: Dictionary) -> Resource or null
static func load_dir(dir_path: String, factory: Callable) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var path := dir_path.path_join(file_name)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var res: Resource = factory.call(parsed)
		if res != null and res.get("id") != null and res.id != "":
			out[res.id] = res
	return out


## Legacy validated directory loader.
## Returns {"entries": {id: Resource}, "errors": Array[String]}.
## validator signature: func(d: Dictionary) -> Array[String]
## factory signature: func(d: Dictionary) -> Resource
static func load_and_validate_dir(dir_path: String, validator: Callable, factory: Callable) -> Dictionary:
	var entries := {}
	var errors: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return {"entries": entries, "errors": errors}
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var path := dir_path.path_join(file_name)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			errors.append("empty or unreadable file '%s'" % path)
			continue
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			errors.append("'%s' is not a JSON object" % path)
			continue
		var validation_errors: Array[String] = validator.call(parsed)
		if not validation_errors.is_empty():
			errors.append_array(validation_errors)
			continue
		var res: Resource = factory.call(parsed)
		if res != null and res.get("id") != null and res.id != "":
			entries[res.id] = res
	return {"entries": entries, "errors": errors}
