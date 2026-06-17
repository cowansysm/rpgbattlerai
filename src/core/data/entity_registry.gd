class_name EntityRegistry
extends RefCounted
## Per-domain registry that stores loaded Resources keyed by id.
## Supports loading from a consolidated array-of-objects file or a directory.

var _entries: Dictionary = {}


## Loads from a single consolidated JSON file (array-of-objects format).
## Returns Array[String] of validation/load errors (empty == success).
func load_validated_file(file_path: String, validator: Callable, factory: Callable) -> Array[String]:
	var result := JsonLoader.load_and_validate_file(file_path, validator, factory)
	_entries = result["entries"]
	var errors: Array[String] = []
	errors.assign(result["errors"])
	return errors


## Legacy: loads JSON files from a directory, validates each raw dict, then converts via factory.
## Returns Array[String] of validation/load errors (empty == success).
func load_validated(dir_path: String, validator: Callable, factory: Callable) -> Array[String]:
	var result := JsonLoader.load_and_validate_dir(dir_path, validator, factory)
	_entries = result["entries"]
	var errors: Array[String] = []
	errors.assign(result["errors"])
	return errors


func get_entry(id: String) -> Resource:
	return _entries.get(id)


func has(id: String) -> bool:
	return _entries.has(id)


func all() -> Array:
	return _entries.values()


func size() -> int:
	return _entries.size()


func ids() -> Array:
	return _entries.keys()
