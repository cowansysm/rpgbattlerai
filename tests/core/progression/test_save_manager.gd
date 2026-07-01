extends GutTest
## Tests for SaveManager: save/load round-trip, band lifecycle, error recovery.

var _test_path: String = "user://saves/_test_save.json"


func before_each() -> void:
	SaveManager.bands = []
	SaveManager.profile = Profile.new()
	SaveManager.active_run = null
	SaveManager.set_save_path(_test_path)
	# Clean up any leftover test file
	if FileAccess.file_exists(_test_path):
		DirAccess.remove_absolute(_test_path)
	var tmp: String = _test_path + ".tmp"
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)


func after_each() -> void:
	if FileAccess.file_exists(_test_path):
		DirAccess.remove_absolute(_test_path)
	var tmp: String = _test_path + ".tmp"
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	SaveManager.set_save_path(SaveManager.SAVE_PATH)


func _make_instance(id: String) -> CharacterInstance:
	var ci := CharacterInstance.new()
	ci.instance_id = id
	ci.template_id = "human_fighter"
	ci.name = "Hero " + id
	ci.race = "human"
	ci.class_levels = {"vagabond": 3}
	ci.active_class = "vagabond"
	ci.unlocked_classes = ["vagabond"] as Array[String]
	ci.jp = {"vagabond": 15}
	ci.equipment = {"weapon": "sword"}
	return ci


func test_first_run_no_file_loads_empty() -> void:
	SaveManager.load_game()
	assert_eq(SaveManager.bands.size(), 0)
	assert_eq(SaveManager.profile.completed_runs, 0)
	assert_null(SaveManager.active_run)


func test_save_and_load_round_trip() -> void:
	var band := BattleBand.create("Test Band")
	band.gold = 150
	band.add_to_inventory("shield")
	band.add_instance(_make_instance("ci_save_1"), 12)
	band.add_instance(_make_instance("ci_save_2"), 12)
	SaveManager.bands = [band]
	SaveManager.save_game()
	# Clear in-memory
	SaveManager.bands = []
	# Reload
	SaveManager.load_game()
	assert_eq(SaveManager.bands.size(), 1)
	var loaded: BattleBand = SaveManager.bands[0]
	assert_eq(loaded.name, "Test Band")
	assert_eq(loaded.gold, 150)
	assert_eq(loaded.roster_size(), 2)
	assert_eq(loaded.roster[0].instance_id, "ci_save_1")
	assert_eq(loaded.roster[0].name, "Hero ci_save_1")
	assert_eq(loaded.roster[0].jp, {"vagabond": 15})
	assert_eq(loaded.roster[1].instance_id, "ci_save_2")
	var equip: Array = loaded.inventory["equipment"]
	assert_eq(equip.size(), 1)
	assert_true(equip.has("shield"))


func test_multiple_bands_round_trip() -> void:
	var a := BattleBand.create("Alpha")
	a.gold = 100
	a.add_instance(_make_instance("ci_a"), 12)
	var b := BattleBand.create("Bravo")
	b.gold = 200
	SaveManager.bands = [a, b]
	SaveManager.save_game()
	SaveManager.bands = []
	SaveManager.load_game()
	assert_eq(SaveManager.bands.size(), 2)
	assert_eq(SaveManager.bands[0].name, "Alpha")
	assert_eq(SaveManager.bands[0].gold, 100)
	assert_eq(SaveManager.bands[0].roster_size(), 1)
	assert_eq(SaveManager.bands[1].name, "Bravo")
	assert_eq(SaveManager.bands[1].gold, 200)


func test_create_band() -> void:
	var band := SaveManager.create_band("My Band")
	assert_eq(SaveManager.bands.size(), 1)
	assert_eq(band.name, "My Band")
	assert_false(band.band_id.is_empty())
	assert_eq(band.gold, 500)  # STARTING_GOLD


func test_delete_band() -> void:
	var band := SaveManager.create_band("Doomed")
	var id := band.band_id
	assert_true(SaveManager.delete_band(id))
	assert_eq(SaveManager.bands.size(), 0)


func test_delete_band_nonexistent() -> void:
	assert_false(SaveManager.delete_band("no_such_id"))


func test_get_band() -> void:
	var band := SaveManager.create_band("Find Me")
	var found := SaveManager.get_band(band.band_id)
	assert_not_null(found)
	assert_eq(found.name, "Find Me")
	assert_null(SaveManager.get_band("nonexistent"))


func test_malformed_file_loads_empty() -> void:
	DirAccess.make_dir_recursive_absolute("user://saves")
	var f := FileAccess.open(_test_path, FileAccess.WRITE)
	f.store_string("not valid json {{{")
	f.close()
	SaveManager.load_game()
	assert_eq(SaveManager.bands.size(), 0)


func test_empty_file_loads_empty() -> void:
	DirAccess.make_dir_recursive_absolute("user://saves")
	var f := FileAccess.open(_test_path, FileAccess.WRITE)
	f.store_string("")
	f.close()
	SaveManager.load_game()
	assert_eq(SaveManager.bands.size(), 0)


func test_migration_unknown_version() -> void:
	DirAccess.make_dir_recursive_absolute("user://saves")
	var doc := {"save_version": 0, "bands": []}
	var f := FileAccess.open(_test_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	SaveManager.load_game()
	assert_eq(SaveManager.bands.size(), 0)
