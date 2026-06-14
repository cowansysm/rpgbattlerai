extends GutTest
## Tests for StatBlock: base values, effective with modifiers, derived stats, duplicate.

func test_base_and_effective_without_modifiers() -> void:
	var sb := StatBlock.new()
	sb.set_base("atk", 5)
	sb.set_base("hp", 10)
	assert_eq(sb.base("atk"), 5)
	assert_eq(sb.effective("atk"), 5, "effective == base when no modifiers")
	assert_eq(sb.base("spd"), 0, "unset stat returns 0")


func test_push_modifier_affects_effective() -> void:
	var sb := StatBlock.new()
	sb.set_base("def", 2)
	sb.push_modifier(StatModifier.new("def", 3, "equipment"))
	assert_eq(sb.effective("def"), 5)
	assert_eq(sb.base("def"), 2, "base unchanged by modifiers")


func test_remove_modifiers_by_source() -> void:
	var sb := StatBlock.new()
	sb.set_base("def", 2)
	sb.push_modifier(StatModifier.new("def", 3, "equipment"))
	sb.push_modifier(StatModifier.new("def", 1, "buff"))
	assert_eq(sb.effective("def"), 6)
	sb.remove_modifiers_by_source("equipment")
	assert_eq(sb.effective("def"), 3, "only buff modifier remains")


func test_effective_move() -> void:
	var sb := StatBlock.new()
	sb.set_base("spd", 4)
	assert_eq(sb.effective_move(), 4)


func test_effective_jump() -> void:
	var sb := StatBlock.new()
	sb.set_base("jump", 2)
	assert_eq(sb.effective("jump"), 2)


func test_effective_jump_with_modifier() -> void:
	var sb := StatBlock.new()
	sb.set_base("jump", 2)
	sb.push_modifier(StatModifier.new("jump", 1, "class"))
	assert_eq(sb.effective("jump"), 3)


func test_duplicate_is_independent() -> void:
	var sb := StatBlock.new()
	sb.set_base("atk", 5)
	sb.push_modifier(StatModifier.new("atk", 2, "buff"))
	var copy := sb.duplicate()
	copy.push_modifier(StatModifier.new("atk", 1, "extra"))
	assert_eq(sb.effective("atk"), 7, "original unaffected by copy's modifier")
	assert_eq(copy.effective("atk"), 8)
