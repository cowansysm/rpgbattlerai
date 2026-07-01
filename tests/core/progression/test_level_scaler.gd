extends GutTest
## Tests for LevelScaler: one-shot stat projection by level.


func test_l1_returns_base_stats() -> void:
	var base := {"hp": 30, "atk": 5, "def": 5}
	var growth := {"hp": 1.5, "atk": 0.5, "def": 0.3}
	var result := LevelScaler.scale(base, growth, 1)
	assert_eq(int(result["hp"]), 30, "L1 HP = base")
	assert_eq(int(result["atk"]), 5, "L1 ATK = base")
	assert_eq(int(result["def"]), 5, "L1 DEF = base")


func test_scale_up_applies_growth() -> void:
	var base := {"hp": 30, "atk": 5}
	var growth := {"hp": 2.0, "atk": 1.0}
	var result := LevelScaler.scale(base, growth, 5)
	# L5: base + round(growth * 4)
	assert_eq(int(result["hp"]), 38, "HP = 30 + round(2.0 * 4) = 38")
	assert_eq(int(result["atk"]), 9, "ATK = 5 + round(1.0 * 4) = 9")


func test_missing_growth_key_defaults_zero() -> void:
	var base := {"hp": 30, "atk": 5, "mag": 3}
	var growth := {"hp": 1.0}  # No atk or mag growth
	var result := LevelScaler.scale(base, growth, 5)
	assert_eq(int(result["hp"]), 34, "HP = 30 + round(1.0 * 4)")
	assert_eq(int(result["atk"]), 5, "ATK unchanged (no growth)")
	assert_eq(int(result["mag"]), 3, "MAG unchanged (no growth)")


func test_missing_base_key_defaults_zero() -> void:
	var base := {"hp": 30}
	var growth := {"hp": 1.0, "atk": 0.5}
	var result := LevelScaler.scale(base, growth, 5)
	assert_eq(int(result["hp"]), 34)
	assert_eq(int(result["atk"]), 2, "ATK = 0 + round(0.5 * 4) = 2")


func test_rounding() -> void:
	var base := {"atk": 10}
	var growth := {"atk": 0.3}
	var result := LevelScaler.scale(base, growth, 4)
	# L4: 10 + round(0.3 * 3) = 10 + round(0.9) = 10 + 1 = 11
	assert_eq(int(result["atk"]), 11, "0.3 * 3 = 0.9 rounds to 1")


func test_all_stat_keys_present() -> void:
	var base := {"hp": 30}
	var growth := {}
	var result := LevelScaler.scale(base, growth, 1)
	for k in StatKey.all_strings():
		assert_true(result.has(k), "result should have key '%s'" % k)
