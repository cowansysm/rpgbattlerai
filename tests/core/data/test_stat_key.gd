extends GutTest
## Tests for StatKey enum and string conversion helpers.

func test_roundtrip_all_keys() -> void:
	for k in StatKey.KEYS:
		var s := StatKey.to_string_key(k)
		var back := StatKey.from_string(s)
		assert_eq(back, k, "roundtrip for key %s" % s)


func test_all_strings_count() -> void:
	assert_eq(StatKey.all_strings().size(), StatKey.KEYS.size(),
		"all_strings returns same count as KEYS")


func test_is_valid_key_accepts_known() -> void:
	for s in StatKey.all_strings():
		assert_true(StatKey.is_valid_key(s), "'%s' should be valid" % s)


func test_is_valid_key_rejects_unknown() -> void:
	assert_false(StatKey.is_valid_key("magic_power"))
	assert_false(StatKey.is_valid_key(""))
	assert_false(StatKey.is_valid_key("SPD"))


func test_specific_keys_exist() -> void:
	var expected: Array[String] = ["spd", "atk", "rng", "def", "hp"]
	for s in expected:
		assert_true(StatKey.is_valid_key(s), "'%s' must be a valid stat key" % s)
