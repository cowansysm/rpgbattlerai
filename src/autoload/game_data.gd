extends Node
## Thin facade delegating to DataPipeline. Registered as autoload "GameData".
## Orchestrates boot, exposes typed lazy accessors. Read-only post-load.

var _pipeline := DataPipeline.new()


func _ready() -> void:
	var errors := _pipeline.run()
	if not errors.is_empty():
		for err in errors:
			push_error("GameData: %s" % err)
		Log.error("GameData", "Data pipeline failed with %d error(s)" % errors.size())
		return
	Log.info("GameData", "Loaded %d race(s), %d class(es), %d ability(ies), %d item(s), %d character(s), %d map(s), %d terrain(s)" % [
		_pipeline.races.size(), _pipeline.classes.size(),
		_pipeline.abilities.size(), _pipeline.items.size(),
		_pipeline.characters.size(), _pipeline.maps.size(),
		_pipeline.terrains.size()])


# --- Public accessors (delegate to pipeline) ---

func get_race(id: String) -> RaceData:
	return _pipeline.get_race(id)

func get_job_class(id: String) -> ClassData:
	return _pipeline.get_job_class(id)

func get_ability(id: String) -> AbilityData:
	return _pipeline.get_ability(id)

func get_item(id: String) -> ItemData:
	return _pipeline.get_item(id)

func get_character(id: String) -> CharacterData:
	return _pipeline.get_character(id)

func get_map(id: String) -> MapData:
	return _pipeline.get_map(id)

func get_terrain(id: String) -> TerrainProps:
	return _pipeline.get_terrain(id)

func get_final_stats(id: String) -> StatBlock:
	return _pipeline.get_final_stats(id)

func all_characters() -> Array:
	return _pipeline.characters.all()

func all_maps() -> Array:
	return _pipeline.maps.all()
