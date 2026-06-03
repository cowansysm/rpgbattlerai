extends GutTest
## Tests for JsonLoader: load_and_validate_dir with real fixture files.

func test_load_valid_fixture_returns_entries() -> void:
	var result := JsonLoader.load_and_validate_dir(
		"res://tests/fixtures/valid_set/characters",
		Validator.validate_character, DataFactory.make_character)
	var entries: Dictionary = result["entries"]
	var errors: Array = result["errors"]
	assert_eq(errors.size(), 0, "valid fixture should have no errors")
	assert_eq(entries.size(), 1, "fixture has one character")
	assert_true(entries.has("test_fighter"), "loaded character has expected id")
	var c: CharacterData = entries["test_fighter"]
	assert_eq(c.race, "test_race")
	assert_eq(c.bp, 10)


func test_load_missing_dir_returns_empty() -> void:
	var result := JsonLoader.load_and_validate_dir(
		"res://tests/fixtures/nonexistent",
		Validator.validate_character, DataFactory.make_character)
	assert_eq(result["entries"].size(), 0)
	assert_eq(result["errors"].size(), 0, "missing dir is not an error")


func test_load_bad_files_reports_errors() -> void:
	var result := JsonLoader.load_and_validate_dir(
		"res://tests/fixtures/bad_files",
		Validator.validate_character, DataFactory.make_character)
	assert_eq(result["entries"].size(), 0, "no valid entries from bad files")
	assert_true(result["errors"].size() > 0, "bad files should produce errors")
	# Engine emits internal errors when parsing malformed JSON; tell GUT that's expected
	assert_engine_error_count(1)
