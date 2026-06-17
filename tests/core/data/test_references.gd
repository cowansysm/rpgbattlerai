extends GutTest
## Tests for referential integrity validation.
## G3: unit tests with hand-built registries.
## G7: integration tests with fixture directories.

# --- Unit tests (hand-built registries) ---

func _make_registry_with(entries: Array) -> EntityRegistry:
	var reg := EntityRegistry.new()
	for entry in entries:
		reg._entries[entry.id] = entry
	return reg


func test_dangling_class_ref_detected() -> void:
	var c := CharacterData.new()
	c.id = "hero"
	c.race = "human"
	c.classes = ["ghost_class"] as Array[String]
	c.equipment = [] as Array[String]
	c.abilities = [] as Array[String]
	var human := RaceData.new()
	human.id = "human"
	var registries := {
		"races": _make_registry_with([human]),
		"classes": EntityRegistry.new(),
		"abilities": EntityRegistry.new(),
		"items": EntityRegistry.new(),
		"characters": _make_registry_with([c]),
		"maps": EntityRegistry.new(),
	}
	var errors := Validator.validate_references(registries)
	assert_true(errors.size() > 0, "should detect dangling class ref")
	assert_true(errors[0].find("unknown class") >= 0, "error should name the dangling class ref")


func test_clean_set_passes() -> void:
	var human := RaceData.new()
	human.id = "human"
	var fighter := ClassData.new()
	fighter.id = "fighter"
	fighter.granted_abilities = [] as Array[String]
	fighter.equipment_access = ["sword"] as Array[String]
	var sword := ItemData.new()
	sword.id = "sword"
	sword.granted_abilities = [] as Array[String]
	var c := CharacterData.new()
	c.id = "hero"
	c.race = "human"
	c.classes = ["fighter"] as Array[String]
	c.equipment = ["sword"] as Array[String]
	c.abilities = [] as Array[String]
	var registries := {
		"races": _make_registry_with([human]),
		"classes": _make_registry_with([fighter]),
		"abilities": EntityRegistry.new(),
		"items": _make_registry_with([sword]),
		"characters": _make_registry_with([c]),
		"maps": EntityRegistry.new(),
	}
	var errors := Validator.validate_references(registries)
	assert_eq(errors.size(), 0, "clean set should have no ref errors")


func test_dangling_required_class_ref_detected() -> void:
	var knight := ClassData.new()
	knight.id = "knight"
	knight.granted_abilities = [] as Array[String]
	knight.equipment_access = [] as Array[String]
	knight.required_classes = [["ghost_class", 2]]
	var registries := {
		"races": EntityRegistry.new(),
		"classes": _make_registry_with([knight]),
		"abilities": EntityRegistry.new(),
		"items": EntityRegistry.new(),
		"characters": EntityRegistry.new(),
		"maps": EntityRegistry.new(),
	}
	var errors := Validator.validate_references(registries)
	assert_true(errors.size() > 0, "should detect dangling required_class ref")
	assert_true(errors[0].find("unknown class") >= 0)


func test_valid_required_class_ref_passes() -> void:
	var fighter := ClassData.new()
	fighter.id = "fighter"
	fighter.granted_abilities = [] as Array[String]
	fighter.equipment_access = [] as Array[String]
	var knight := ClassData.new()
	knight.id = "knight"
	knight.granted_abilities = [] as Array[String]
	knight.equipment_access = [] as Array[String]
	knight.required_classes = [["fighter", 2]]
	var registries := {
		"races": EntityRegistry.new(),
		"classes": _make_registry_with([fighter, knight]),
		"abilities": EntityRegistry.new(),
		"items": EntityRegistry.new(),
		"characters": EntityRegistry.new(),
		"maps": EntityRegistry.new(),
	}
	var errors := Validator.validate_references(registries)
	assert_eq(errors.size(), 0, "valid required_class ref should pass")


# --- Integration tests (fixture directories) ---

func test_fixture_valid_set_passes_referential() -> void:
	var pipeline := DataPipeline.new()
	var load_errors := pipeline._load_all("res://tests/fixtures/valid_set")
	assert_eq(load_errors.size(), 0, "valid fixture should load cleanly")
	var ref_errors := pipeline._validate_references()
	assert_eq(ref_errors.size(), 0, "valid fixture set has no dangling refs")


func test_fixture_dangling_ref_caught() -> void:
	var pipeline := DataPipeline.new()
	var load_errors := pipeline._load_all("res://tests/fixtures/dangling_ref")
	assert_eq(load_errors.size(), 0, "dangling_ref fixture should load structurally")
	var ref_errors := pipeline._validate_references()
	assert_true(ref_errors.size() > 0, "dangling ref should be caught")
	assert_true(ref_errors[0].find("unknown class") >= 0, "error should name the dangling class ref")
