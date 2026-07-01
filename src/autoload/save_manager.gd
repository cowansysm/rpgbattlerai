extends Node
## Versioned JSON persistence under user://saves/.
## Manages band lifecycle and provides save/load for the full game state.
## Spec reference: alpha-phaseA5-spec.md §4

const SAVE_PATH: String = "user://saves/save.json"
const CURRENT_SAVE_VERSION: int = 2

var bands: Array[BattleBand] = []
var profile: Profile = Profile.new()  ## Account-level meta-progression (A10)
var active_run: Variant = null        ## Reserved for A8 roguelike run

var _save_path: String = SAVE_PATH


func set_save_path(path: String) -> void:
	_save_path = path


func has_save() -> bool:
	return FileAccess.file_exists(_save_path)


func load_game() -> void:
	bands.clear()
	profile = Profile.new()
	active_run = null
	if not has_save():
		return
	var text: String = FileAccess.get_file_as_string(_save_path)
	if text.is_empty():
		Log.warn("SaveManager", "Save file is empty: %s" % _save_path)
		return
	var json := JSON.new()
	var parse_err: int = json.parse(text)
	if parse_err != OK:
		Log.warn("SaveManager", "Save file is not valid JSON: %s" % _save_path)
		return
	var raw: Variant = json.data
	if not raw is Dictionary:
		Log.warn("SaveManager", "Save file root is not a dictionary: %s" % _save_path)
		return
	var doc: Dictionary = _migrate(raw as Dictionary)
	var raw_profile: Variant = doc.get("profile", {})
	if raw_profile is Dictionary:
		profile = Profile.from_dict(raw_profile as Dictionary)
	else:
		profile = Profile.new()
	var raw_run: Variant = doc.get("active_run", null)
	if raw_run is Dictionary and not (raw_run as Dictionary).is_empty():
		active_run = RunState.from_dict(raw_run as Dictionary)
	else:
		active_run = null
	var band_arr: Variant = doc.get("bands", [])
	if band_arr is Array:
		for entry in (band_arr as Array):
			if entry is Dictionary:
				bands.append(BattleBand.from_dict(entry))
	Log.info("SaveManager", "Loaded %d band(s) from %s" % [bands.size(), _save_path])


func save_game() -> void:
	var dir_path: String = _save_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)
	var doc: Dictionary = {
		"save_version": CURRENT_SAVE_VERSION,
		"profile": profile.to_dict(),
		"active_run": _serialize_active_run(),
		"bands": _serialize_bands(),
	}
	var tmp: String = _save_path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		Log.error("SaveManager", "Failed to open temp file for save: %s" % tmp)
		return
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()
	var err: int = DirAccess.rename_absolute(tmp, _save_path)
	if err != OK:
		Log.error("SaveManager", "Failed to rename temp save to final: %s" % _save_path)
		return
	Log.info("SaveManager", "Saved %d band(s) to %s" % [bands.size(), _save_path])


func create_band(band_name: String, name_gen: Callable = Callable()) -> BattleBand:
	var band := BattleBand.create(band_name)
	band.gold = int(Constants.get_value("STARTING_GOLD",
		Constants.get_value("RECRUIT_STARTING_GOLD", 500)))
	# A11: Seed one Human Vagabond L1 as the starter character
	var starting_class: String = str(Constants.get_value("STARTING_CLASS", "vagabond"))
	var starter_template: CharacterData = null
	if GameData != null:
		starter_template = GameData.get_character("human_fighter")
	if starter_template != null:
		var gen: Callable = name_gen if name_gen.is_valid() else func(_r: String) -> String: return "Starter"
		var ci: CharacterInstance = CharacterInstance.generate(starter_template, gen)
		band.add_instance(ci)
	bands.append(band)
	return band


func delete_band(band_id: String) -> bool:
	for i in range(bands.size()):
		if bands[i].band_id == band_id:
			bands.remove_at(i)
			return true
	return false


func get_band(band_id: String) -> BattleBand:
	for band in bands:
		if band.band_id == band_id:
			return band
	return null


func _serialize_bands() -> Array:
	var out: Array = []
	for band in bands:
		out.append(band.to_dict())
	return out


func _migrate(doc: Dictionary) -> Dictionary:
	var version: int = int(doc.get("save_version", 0))
	if version < 1:
		# Pre-versioned or corrupted — return minimal valid structure
		Log.warn("SaveManager", "Unknown save version %d; treating as empty" % version)
		return {"save_version": CURRENT_SAVE_VERSION, "profile": {}, "bands": [], "active_run": null}
	if version < 2:
		doc = _migrate_v1_to_v2(doc)
	return doc


func _migrate_v1_to_v2(doc: Dictionary) -> Dictionary:
	if not doc.has("active_run"):
		doc["active_run"] = null
	doc["save_version"] = 2
	return doc


func _serialize_active_run() -> Variant:
	if active_run == null:
		return null
	if active_run is RunState:
		return (active_run as RunState).to_dict()
	if active_run is Dictionary:
		return active_run
	return null
