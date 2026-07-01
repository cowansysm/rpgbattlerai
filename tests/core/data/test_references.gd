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
	var vagabond := ClassData.new()
	vagabond.id = "vagabond"
	vagabond.tier = 0
	vagabond.granted_abilities = [] as Array[String]
	vagabond.equipment_access = [] as Array[String]
	vagabond.prerequisites = {}
	vagabond.jp_costs = {}
	vagabond.required_classes = []
	var fighter := ClassData.new()
	fighter.id = "fighter"
	fighter.tier = 1
	fighter.granted_abilities = [] as Array[String]
	fighter.equipment_access = [] as Array[String]
	fighter.prerequisites = {"classes": [["vagabond", 3]]}
	fighter.jp_costs = {}
	fighter.required_classes = []
	var knight := ClassData.new()
	knight.id = "knight"
	knight.tier = 2
	knight.granted_abilities = [] as Array[String]
	knight.equipment_access = [] as Array[String]
	knight.prerequisites = {"classes": [["fighter", 3]]}
	knight.jp_costs = {}
	knight.required_classes = [["fighter", 3]]
	var registries := {
		"races": EntityRegistry.new(),
		"classes": _make_registry_with([vagabond, fighter, knight]),
		"abilities": EntityRegistry.new(),
		"items": EntityRegistry.new(),
		"characters": EntityRegistry.new(),
		"maps": EntityRegistry.new(),
	}
	var errors := Validator.validate_references(registries)
	assert_eq(errors.size(), 0, "valid required_class ref should pass")


# --- A9: Job tree validation ---

func _make_class(id: String, tier: int, prereqs: Dictionary = {}) -> ClassData:
	var cls := ClassData.new()
	cls.id = id
	cls.tier = tier
	cls.granted_abilities = [] as Array[String]
	cls.equipment_access = [] as Array[String]
	cls.prerequisites = prereqs
	cls.jp_costs = {}
	cls.required_classes = []
	return cls


func test_valid_tree_passes() -> void:
	var vagabond := _make_class("vagabond", 0)
	var soldier := _make_class("soldier", 1, {"classes": [["vagabond", 3]]})
	var knight := _make_class("knight", 2, {"classes": [["soldier", 3]]})
	var templar := _make_class("templar", 3, {"classes": [["knight", 5]]})
	var reg := _make_registry_with([vagabond, soldier, knight, templar])
	var errors := Validator.validate_job_tree(reg)
	assert_eq(errors.size(), 0, "valid tree should pass: %s" % str(errors))


func test_cycle_detected() -> void:
	var vagabond := _make_class("vagabond", 0)
	var a := _make_class("a", 1, {"classes": [["b", 3]]})
	var b := _make_class("b", 1, {"classes": [["a", 3]]})
	var reg := _make_registry_with([vagabond, a, b])
	var errors := Validator.validate_job_tree(reg)
	var has_cycle := false
	for err in errors:
		if err.find("cycle") >= 0:
			has_cycle = true
			break
	assert_true(has_cycle, "should detect cycle: %s" % str(errors))


func test_orphan_detected() -> void:
	var vagabond := _make_class("vagabond", 0)
	var soldier := _make_class("soldier", 1, {"classes": [["vagabond", 3]]})
	# orphan requires a non-existent parent, making it unreachable
	var orphan := _make_class("orphan", 2, {"classes": [["nonexistent", 3]]})
	var reg := _make_registry_with([vagabond, soldier, orphan])
	var errors := Validator.validate_job_tree(reg)
	var has_orphan := false
	for err in errors:
		if err.find("orphan") >= 0 or err.find("not reachable") >= 0:
			has_orphan = true
			break
	assert_true(has_orphan, "should detect orphan class: %s" % str(errors))


func test_multiple_roots_allowed() -> void:
	var vag1 := _make_class("vagabond", 0)
	var vag2 := _make_class("vagabond2", 0)
	var reg := _make_registry_with([vag1, vag2])
	var errors := Validator.validate_job_tree(reg)
	assert_eq(errors.size(), 0, "multiple roots should be allowed in n-tier model: %s" % str(errors))


func test_tier_mismatch_closure_rejected() -> void:
	var vagabond := _make_class("vagabond", 0)
	var soldier := _make_class("soldier", 1, {"classes": [["vagabond", 3]]})
	# bad_elite claims tier 3 but only has soldier (tier 1) as prereq → closure size is 2
	var bad_elite := _make_class("bad_elite", 3, {"classes": [["soldier", 5]]})
	var reg := _make_registry_with([vagabond, soldier, bad_elite])
	var errors := Validator.validate_job_tree(reg)
	var has_tier_error := false
	for err in errors:
		if err.find("closure size") >= 0:
			has_tier_error = true
			break
	assert_true(has_tier_error, "tier mismatch with closure should fail: %s" % str(errors))


func test_nonzero_tier_with_no_class_prereq_rejected() -> void:
	var vagabond := _make_class("vagabond", 0)
	# Claims tier 2 but has no class prerequisites → closure size 0 != tier 2
	var bad_advanced := _make_class("bad_adv", 2, {"level": 6})
	var reg := _make_registry_with([vagabond, bad_advanced])
	var errors := Validator.validate_job_tree(reg)
	var has_error := false
	for err in errors:
		if err.find("closure size") >= 0:
			has_error = true
			break
	assert_true(has_error, "non-zero tier with no class prereq should fail: %s" % str(errors))


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


# --- A11: Encounter validation ---

func test_valid_encounter_passes() -> void:
	var d := {"id": "test_enc", "enemies": [{"character": "hero", "count": 2}],
		"min_band_level": 1, "weight": 1.0}
	var errors := Validator.validate_encounter(d)
	assert_eq(errors.size(), 0, "valid encounter should pass: %s" % str(errors))


func test_encounter_missing_id() -> void:
	var d := {"enemies": [{"character": "hero", "count": 1}]}
	var errors := Validator.validate_encounter(d)
	assert_true(errors.size() > 0)
	assert_true(errors[0].find("missing") >= 0)


func test_encounter_empty_enemies() -> void:
	var d := {"id": "empty", "enemies": []}
	var errors := Validator.validate_encounter(d)
	assert_true(errors.size() > 0)
	assert_true(errors[0].find("empty") >= 0)


func test_encounter_enemy_missing_character() -> void:
	var d := {"id": "bad", "enemies": [{"count": 2}]}
	var errors := Validator.validate_encounter(d)
	assert_true(errors.size() > 0)


func test_encounter_dangling_character_ref() -> void:
	var enc := EncounterData.new()
	enc.id = "test_enc"
	enc.enemies = [{"character": "nonexistent", "count": 1}]
	enc.map_id = ""
	var enc_reg := _make_registry_with([enc])
	var char_reg := EntityRegistry.new()
	var map_reg := EntityRegistry.new()
	var errors := Validator.validate_encounter_references(enc_reg, char_reg, map_reg)
	assert_true(errors.size() > 0, "dangling char ref should fail")
	assert_true(errors[0].find("nonexistent") >= 0)


func test_encounter_dangling_map_ref() -> void:
	var c := CharacterData.new()
	c.id = "hero"
	var enc := EncounterData.new()
	enc.id = "test_enc"
	enc.enemies = [{"character": "hero", "count": 1}]
	enc.map_id = "missing_map"
	var enc_reg := _make_registry_with([enc])
	var char_reg := _make_registry_with([c])
	var map_reg := EntityRegistry.new()
	var errors := Validator.validate_encounter_references(enc_reg, char_reg, map_reg)
	assert_true(errors.size() > 0, "dangling map ref should fail")
	assert_true(errors[0].find("missing_map") >= 0)


func test_encounter_valid_references_pass() -> void:
	var c := CharacterData.new()
	c.id = "hero"
	var enc := EncounterData.new()
	enc.id = "test_enc"
	enc.enemies = [{"character": "hero", "count": 2}]
	enc.map_id = ""
	var enc_reg := _make_registry_with([enc])
	var char_reg := _make_registry_with([c])
	var map_reg := EntityRegistry.new()
	var errors := Validator.validate_encounter_references(enc_reg, char_reg, map_reg)
	assert_eq(errors.size(), 0, "valid encounter refs should pass")
