extends GutTest
## Tests for the CSV content pipeline: EntitySchema, CsvExporter, CsvImporter.
## Core invariant: json→csv→json round-trip produces semantically equal data.


# ---------------------------------------------------------------------------
# EntitySchema tests
# ---------------------------------------------------------------------------

func test_schema_covers_all_entity_types() -> void:
	for entity in EntitySchema.ENTITIES:
		var cols := EntitySchema.columns_for(entity)
		assert_gt(cols.size(), 0, "%s should have columns" % entity)


func test_schema_unknown_entity_returns_empty() -> void:
	var cols := EntitySchema.columns_for("nonexistent")
	assert_eq(cols.size(), 0)


func test_schema_abilities_has_id_column() -> void:
	var cols := EntitySchema.columns_for("abilities")
	assert_eq(cols[0]["name"], "id")
	assert_eq(cols[0]["mode"], EntitySchema.Mode.SCALAR)


func test_schema_classes_has_stat_columns() -> void:
	var cols := EntitySchema.columns_for("classes")
	var col_names: Array[String] = []
	for c in cols:
		col_names.append(c["name"])
	for key in StatKey.all_strings():
		assert_true(("stats." + key) in col_names, "classes should have stats.%s" % key)


func test_schema_terrain_is_keyed_dict() -> void:
	assert_true(EntitySchema.is_keyed_dict("terrain"))
	assert_false(EntitySchema.is_keyed_dict("abilities"))


# ---------------------------------------------------------------------------
# CsvExporter.flatten tests
# ---------------------------------------------------------------------------

func test_flatten_scalar_fields() -> void:
	var obj := {"id": "test_1", "name": "Test", "type": "spell", "ap": 1, "wp": 2, "range": 3, "source": "class"}
	var cols := EntitySchema.columns_for("abilities")
	var row := CsvExporter.flatten(obj, cols)
	assert_eq(row[0], "test_1")
	assert_eq(row[1], "Test")
	assert_eq(row[2], "spell")
	assert_eq(row[3], "1")


func test_flatten_dotted_nested() -> void:
	var obj := {"id": "x", "type": "spell", "effect": {"effect_type": "damage", "value": 10, "element": "fire"}}
	var cols := EntitySchema.columns_for("abilities")
	var row := CsvExporter.flatten(obj, cols)
	# Find effect.effect_type column
	var et_idx := -1
	for i in range(cols.size()):
		if cols[i]["name"] == "effect.effect_type":
			et_idx = i
			break
	assert_ne(et_idx, -1)
	assert_eq(row[et_idx], "damage")


func test_flatten_absent_keys_produce_blank() -> void:
	var obj := {"id": "minimal", "type": "skill"}
	var cols := EntitySchema.columns_for("abilities")
	var row := CsvExporter.flatten(obj, cols)
	# area.shape should be blank
	var shape_idx := -1
	for i in range(cols.size()):
		if cols[i]["name"] == "area.shape":
			shape_idx = i
			break
	assert_eq(row[shape_idx], "")


func test_flatten_json_cell() -> void:
	var obj := {"id": "cls", "stats": {}, "equipment_access": ["sword", "shield"], "granted_abilities": [], "required_classes": [], "derived_bonuses": {}}
	var cols := EntitySchema.columns_for("classes")
	var row := CsvExporter.flatten(obj, cols)
	# Find equipment_access column
	var ea_idx := -1
	for i in range(cols.size()):
		if cols[i]["name"] == "equipment_access":
			ea_idx = i
			break
	assert_ne(ea_idx, -1)
	var parsed: Variant = JSON.parse_string(row[ea_idx])
	assert_eq(parsed, ["sword", "shield"])


func test_flatten_bool_field() -> void:
	var obj := {"id": "grass", "move_cost": 1, "impassable": false, "blocks_los": true, "cover": 0, "los_height": 0}
	var cols := EntitySchema.columns_for("terrain")
	var row := CsvExporter.flatten(obj, cols)
	# Find impassable column
	var imp_idx := -1
	var blos_idx := -1
	for i in range(cols.size()):
		if cols[i]["name"] == "impassable":
			imp_idx = i
		if cols[i]["name"] == "blocks_los":
			blos_idx = i
	assert_eq(row[imp_idx], "false")
	assert_eq(row[blos_idx], "true")


# ---------------------------------------------------------------------------
# CsvImporter.unflatten tests
# ---------------------------------------------------------------------------

func test_unflatten_scalar_fields() -> void:
	var cols := EntitySchema.columns_for("abilities")
	var header := PackedStringArray()
	for c in cols:
		header.append(c["name"])
	var row := PackedStringArray(["test_1", "Test", "spell", "1", "2", "3", "", "", "", "", "", "", "", "", "", "class"])
	var obj := CsvImporter.unflatten(header, row, cols)
	assert_eq(obj["id"], "test_1")
	assert_eq(obj["name"], "Test")
	assert_eq(obj["ap"], 1)
	assert_eq(obj["source"], "class")


func test_unflatten_blank_cells_omitted() -> void:
	var cols := EntitySchema.columns_for("abilities")
	var header := PackedStringArray()
	for c in cols:
		header.append(c["name"])
	var row := PackedStringArray(["test_1", "Test", "spell", "1", "", "3", "", "", "", "", "", "", "", "", "", ""])
	var obj := CsvImporter.unflatten(header, row, cols)
	assert_false(obj.has("wp"), "blank wp should be omitted")
	assert_false(obj.has("area"), "blank area fields should not create nested dict")
	assert_false(obj.has("source"), "blank source should be omitted")


func test_unflatten_dotted_nested() -> void:
	var cols := EntitySchema.columns_for("abilities")
	var header := PackedStringArray()
	for c in cols:
		header.append(c["name"])
	# Build row: id, name, type, ap, wp, range, mag_scaling, area.shape, area.radius,
	#            effect.effect_type, effect.value, effect.element, effect.status_id, effect.duration, effect.stat, source
	var row := PackedStringArray(["x", "X", "spell", "1", "3", "3", "", "burst", "1", "damage", "10", "fire", "", "", "", "class"])
	var obj := CsvImporter.unflatten(header, row, cols)
	assert_true(obj.has("area"))
	assert_eq(obj["area"]["shape"], "burst")
	assert_eq(obj["area"]["radius"], 1)
	assert_eq(obj["effect"]["effect_type"], "damage")
	assert_eq(obj["effect"]["value"], 10)
	assert_eq(obj["effect"]["element"], "fire")


func test_unflatten_json_cell() -> void:
	var cols := EntitySchema.columns_for("classes")
	var header := PackedStringArray()
	for c in cols:
		header.append(c["name"])
	# Build row with JSON cells
	var row := PackedStringArray()
	row.resize(header.size())
	for i in range(row.size()):
		row[i] = ""
	# Set id, name
	row[0] = "test_cls"
	row[1] = "Test Class"
	# Find equipment_access column and fill it
	for i in range(header.size()):
		if header[i] == "equipment_access":
			row[i] = '["sword","bow"]'
		if header[i] == "granted_abilities":
			row[i] = '["fire_1"]'
		if header[i] == "required_classes":
			row[i] = "[]"
		if header[i] == "derived_bonuses":
			row[i] = "{}"
	var obj := CsvImporter.unflatten(header, row, cols)
	assert_eq(obj["equipment_access"], ["sword", "bow"])
	assert_eq(obj["granted_abilities"], ["fire_1"])


func test_unflatten_bool_field() -> void:
	var cols := EntitySchema.columns_for("terrain")
	var header := PackedStringArray()
	for c in cols:
		header.append(c["name"])
	var row := PackedStringArray()
	row.resize(header.size())
	for i in range(row.size()):
		row[i] = ""
	row[0] = "test_terrain"
	for i in range(header.size()):
		if header[i] == "move_cost":
			row[i] = "1"
		if header[i] == "impassable":
			row[i] = "true"
		if header[i] == "blocks_los":
			row[i] = "false"
	var obj := CsvImporter.unflatten(header, row, cols)
	assert_eq(obj["impassable"], true)
	assert_eq(obj["blocks_los"], false)


# ---------------------------------------------------------------------------
# Round-trip tests: json→csv→json semantic equality
# ---------------------------------------------------------------------------

func test_abilities_round_trip() -> void:
	assert_true(_round_trips("abilities", "res://data/abilities.json"),
		"abilities round-trip failed")


func test_classes_round_trip() -> void:
	assert_true(_round_trips("classes", "res://data/classes.json"),
		"classes round-trip failed")


func test_items_round_trip() -> void:
	assert_true(_round_trips("items", "res://data/items.json"),
		"items round-trip failed")


func test_characters_round_trip() -> void:
	assert_true(_round_trips("characters", "res://data/characters.json"),
		"characters round-trip failed")


func test_races_round_trip() -> void:
	assert_true(_round_trips("races", "res://data/races.json"),
		"races round-trip failed")


func test_terrain_round_trip() -> void:
	assert_true(_round_trips("terrain", "res://data/terrain.json"),
		"terrain round-trip failed")


# ---------------------------------------------------------------------------
# Validation / rejection tests
# ---------------------------------------------------------------------------

func test_import_rejects_ability_missing_id() -> void:
	var cols := EntitySchema.columns_for("abilities")
	var row := {"type": "spell", "name": "Bad"}
	var errors := CsvImporter.validate_rows("abilities", [row])
	assert_gt(errors.size(), 0, "should reject ability without id")


func test_import_rejects_ability_bad_type() -> void:
	var row := {"id": "bad", "type": "banana"}
	var errors := CsvImporter.validate_rows("abilities", [row])
	assert_gt(errors.size(), 0, "should reject ability with unknown type")


func test_import_rejects_item_missing_slot() -> void:
	var row := {"id": "bad_item", "name": "Bad"}
	var errors := CsvImporter.validate_rows("items", [row])
	assert_gt(errors.size(), 0, "should reject item without slot")


func test_import_rejects_character_missing_stats() -> void:
	var row := {"id": "bad_char", "race": "human", "classes": ["fighter"], "level": 1, "bp": 10}
	var errors := CsvImporter.validate_rows("characters", [row])
	assert_gt(errors.size(), 0, "should reject character without stats")


func test_import_rejects_character_zero_hp() -> void:
	var row := {"id": "bad_char", "race": "human", "classes": ["fighter"], "level": 1, "bp": 10,
		"stats": {"hp": 0, "spd": 10}}
	var errors := CsvImporter.validate_rows("characters", [row])
	assert_gt(errors.size(), 0, "should reject character with hp=0")


func test_import_accepts_valid_race() -> void:
	var row := {"id": "test_race", "name": "Test", "stats": {"spd": 1}}
	var errors := CsvImporter.validate_rows("races", [row])
	assert_eq(errors.size(), 0, "valid race should pass: %s" % str(errors))


func test_import_rejects_terrain_bad_status_on_enter() -> void:
	var row := {"id": "bad_terrain", "move_cost": 1, "status_on_enter": {"status_id": "slowed"}}
	var errors := CsvImporter.validate_rows("terrain", [row])
	assert_gt(errors.size(), 0, "should reject terrain with status_on_enter missing duration")


func test_validate_rows_accumulates_all_errors() -> void:
	var rows: Array[Dictionary] = [
		{"type": "spell"},  # missing id
		{"id": "ok", "type": "banana"},  # bad type
	]
	var errors := CsvImporter.validate_rows("abilities", rows)
	assert_true(errors.size() >= 2, "should accumulate errors from multiple rows")


# ---------------------------------------------------------------------------
# File I/O round-trip test (export → import → compare)
# ---------------------------------------------------------------------------

func test_abilities_file_round_trip() -> void:
	_file_round_trip("abilities")


func test_classes_file_round_trip() -> void:
	_file_round_trip("classes")


func test_items_file_round_trip() -> void:
	_file_round_trip("items")


func test_characters_file_round_trip() -> void:
	_file_round_trip("characters")


func test_races_file_round_trip() -> void:
	_file_round_trip("races")


func test_terrain_file_round_trip() -> void:
	_file_round_trip("terrain")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## In-memory round-trip: load original → flatten → unflatten → compare.
func _round_trips(entity: String, json_path: String) -> bool:
	var original := _load_array(entity, json_path)
	var cols := EntitySchema.columns_for(entity)
	var header := PackedStringArray()
	for c in cols:
		header.append(c["name"])

	for obj in original:
		var row := CsvExporter.flatten(obj, cols)
		var back := CsvImporter.unflatten(header, row, cols)
		if not _semantic_eq(obj, back):
			gut.p("Round-trip mismatch for %s:" % obj.get("id", "?"))
			gut.p("  original: %s" % str(obj))
			gut.p("  back:     %s" % str(back))
			return false
	return true


## File round-trip: export to CSV, import back, compare with original.
func _file_round_trip(entity: String) -> void:
	var json_path := "res://data/" + entity + ".json"
	var csv_path := "user://test_csv_" + entity + ".csv"
	var json_out := "user://test_json_" + entity + ".json"

	# Export
	var export_errors := CsvExporter.export_entity(entity, json_path, csv_path)
	assert_eq(export_errors.size(), 0, "export errors: %s" % str(export_errors))

	# Import to a temp JSON
	var import_errors := CsvImporter.import_entity(entity, csv_path, json_out)
	assert_eq(import_errors.size(), 0, "import errors: %s" % str(import_errors))

	# Compare original with re-imported
	var original := _load_array(entity, json_path)
	var reimported := _load_array(entity, json_out)
	assert_eq(original.size(), reimported.size(), "row count mismatch for %s" % entity)

	# Keyed-dict entities (terrain) may have keys reordered by JSON.stringify;
	# sort both arrays by id so comparison is order-independent.
	if EntitySchema.is_keyed_dict(entity):
		original.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))
		reimported.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))

	for i in range(original.size()):
		assert_true(_semantic_eq(original[i], reimported[i]),
			"%s[%d] round-trip mismatch: original=%s reimported=%s" % [
				entity, i, str(original[i]), str(reimported[i])])

	# Cleanup
	DirAccess.remove_absolute(csv_path)
	DirAccess.remove_absolute(json_out)


## Load a JSON file as an array of dicts (handles terrain keyed dict).
func _load_array(entity: String, json_path: String) -> Array[Dictionary]:
	var f := FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		return []
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		return []

	if EntitySchema.is_keyed_dict(entity):
		var arr: Array[Dictionary] = []
		var dict: Dictionary = parsed
		for key in dict.keys():
			var entry: Dictionary = dict[key].duplicate()
			entry["id"] = key
			arr.append(entry)
		return arr

	var result: Array[Dictionary] = []
	for item in parsed:
		if typeof(item) == TYPE_DICTIONARY:
			result.append(item)
	return result


## Semantic equality: order-independent dict/array comparison.
## Absent keys and empty sub-dicts from dotted-path reconstruction are equivalent.
func _semantic_eq(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		# int/float coercion
		if (typeof(a) in [TYPE_INT, TYPE_FLOAT]) and (typeof(b) in [TYPE_INT, TYPE_FLOAT]):
			return is_equal_approx(float(a), float(b))
		return false

	if typeof(a) == TYPE_DICTIONARY:
		var da: Dictionary = a
		var db: Dictionary = b
		# Check all keys in a
		for k in da.keys():
			if not db.has(k):
				# Absent in b — check if a's value is trivially empty
				if _is_trivially_empty(da[k]):
					continue
				return false
			if not _semantic_eq(da[k], db[k]):
				return false
		# Check keys in b that aren't in a
		for k in db.keys():
			if not da.has(k):
				if _is_trivially_empty(db[k]):
					continue
				return false
		return true

	if typeof(a) == TYPE_ARRAY:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return false
		for i in range(aa.size()):
			if not _semantic_eq(aa[i], ab[i]):
				return false
		return true

	return a == b


## An empty dict, empty array, or empty string is trivially empty.
## Empty strings are treated as trivially empty because the CSV pipeline
## cannot distinguish between an absent key and an empty string value.
func _is_trivially_empty(v: Variant) -> bool:
	if typeof(v) == TYPE_DICTIONARY:
		return (v as Dictionary).is_empty()
	if typeof(v) == TYPE_ARRAY:
		return (v as Array).is_empty()
	if typeof(v) == TYPE_STRING:
		return (v as String).is_empty()
	return false
