class_name DataPipeline
extends RefCounted
## Owns the six entity registries and orchestrates the full boot pipeline:
## load → structural validate → referential validate → derive.
## Extracted from GameData so the entire pipeline is testable without the scene tree.

var races := EntityRegistry.new()
var classes := EntityRegistry.new()
var abilities := EntityRegistry.new()
var items := EntityRegistry.new()
var characters := EntityRegistry.new()
var maps := EntityRegistry.new()
var terrains := TerrainRegistry.new()


## Runs the full pipeline. Returns Array[String] of errors (empty == success).
func run(base_path: String = "res://data") -> Array[String]:
	var errors := _load_all(base_path)
	if not errors.is_empty():
		return errors
	errors.append_array(_validate_references())
	if not errors.is_empty():
		return errors
	_derive_all()
	return errors


## Loads all entity types with structural validation. Returns accumulated errors.
## Uses consolidated single-file format (array-of-objects JSON).
## Maps still load from a directory since each map file is large.
func _load_all(base_path: String) -> Array[String]:
	var errors: Array[String] = []
	errors.append_array(races.load_validated_file(
		base_path.path_join("races.json"), Validator.validate_race, DataFactory.make_race))
	errors.append_array(classes.load_validated_file(
		base_path.path_join("classes.json"), Validator.validate_class, DataFactory.make_class))
	errors.append_array(abilities.load_validated_file(
		base_path.path_join("abilities.json"), Validator.validate_ability, DataFactory.make_ability))
	errors.append_array(items.load_validated_file(
		base_path.path_join("items.json"), Validator.validate_item, DataFactory.make_item))
	errors.append_array(characters.load_validated_file(
		base_path.path_join("characters.json"), Validator.validate_character, DataFactory.make_character))
	errors.append_array(maps.load_validated(
		base_path.path_join("maps"), Validator.validate_map, DataFactory.make_map))
	errors.append_array(terrains.load_from(base_path.path_join("terrain.json")))
	return errors


## Cross-entity referential integrity check.
func _validate_references() -> Array[String]:
	return Validator.validate_references({
		"races": races, "classes": classes, "abilities": abilities,
		"items": items, "characters": characters, "maps": maps,
		"terrains": terrains,
	})


## Computes final stat blocks for all characters.
func _derive_all() -> void:
	for c in characters.all():
		var race: RaceData = races.get_entry(c.race)
		var cls_list: Array = []
		for cid in c.classes:
			cls_list.append(classes.get_entry(cid))
		c.final_stats = StatResolver.resolve(c, race, cls_list)


# --- Convenience accessors (delegate to registries) ---

func get_race(id: String) -> RaceData:
	return races.get_entry(id)

func get_job_class(id: String) -> ClassData:
	return classes.get_entry(id)

func get_ability(id: String) -> AbilityData:
	return abilities.get_entry(id)

func get_item(id: String) -> ItemData:
	return items.get_entry(id)

func get_character(id: String) -> CharacterData:
	return characters.get_entry(id)

func get_map(id: String) -> MapData:
	return maps.get_entry(id)

func get_terrain(id: String) -> TerrainProps:
	return terrains.get_entry(id)

func get_final_stats(id: String) -> StatBlock:
	var c := get_character(id)
	return c.final_stats if c else null
