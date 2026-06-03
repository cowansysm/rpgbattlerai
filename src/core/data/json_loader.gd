class_name JsonLoader
extends RefCounted
## Loads a directory of .json files, maps each onto a Resource via a factory callable.
## Engine-light, fully testable.

## Original Phase 0 loader (no validation). Kept for backward compatibility.
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


## Phase 1 validated loader. Validates raw dicts before factory conversion.
## Returns {"entries": {id: Resource}, "errors": Array[String]}.
## Empty/missing directories return empty results (not errors).
## validator signature: func(d: Dictionary) -> Array[String]
## factory signature: func(d: Dictionary) -> Resource
static func load_and_validate_dir(dir_path: String, validator: Callable, factory: Callable) -> Dictionary:
	var entries := {}
	var errors: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		# Empty/missing dir is not an error — some content dirs may be empty
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
		# Validate raw dict BEFORE conversion to Resource
		var validation_errors: Array[String] = validator.call(parsed)
		if not validation_errors.is_empty():
			errors.append_array(validation_errors)
			continue
		# Only create Resource if validation passed
		var res: Resource = factory.call(parsed)
		if res != null and res.get("id") != null and res.id != "":
			entries[res.id] = res
	return {"entries": entries, "errors": errors}
