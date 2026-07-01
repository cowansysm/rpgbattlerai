extends GutTest
## Tests for Phase A3 magical resolution: spell damage scales with MAG,
## reduced by RES, attack die and defend die preserved, heal scaling.

var _default_roller: Callable
var _default_crit_roller: Callable


func before_each() -> void:
	_default_roller = CombatResolver.dice_roller
	_default_crit_roller = CombatResolver.crit_roller
	CombatResolver.dice_roller = func() -> int: return 3
	CombatResolver.crit_roller = func() -> float: return 1.0  # never crits


func after_each() -> void:
	CombatResolver.dice_roller = _default_roller
	CombatResolver.crit_roller = _default_crit_roller


# --- Helpers ---

func _make_unit(overrides: Dictionary) -> BattleUnit:
	var c := CharacterData.new()
	c.id = "test"
	c.display_name = "test"
	c.classes = []
	c.equipment = []
	c.abilities = []
	var sb := StatBlock.new()
	sb.set_base("spd", int(overrides.get("spd", 3)))
	sb.set_base("hp", int(overrides.get("hp", 50)))
	sb.set_base("atk", int(overrides.get("atk", 0)))
	sb.set_base("def", int(overrides.get("def", 0)))
	sb.set_base("rng", int(overrides.get("rng", 0)))
	sb.set_base("mag", int(overrides.get("mag", 0)))
	sb.set_base("res", int(overrides.get("res", 0)))
	return BattleUnit.from_character(c, sb)


# --- Spell damage with MAG/RES ---

func test_spell_scales_with_mag_and_res() -> void:
	var caster := _make_unit({"mag": 6})
	var target := _make_unit({"res": 2, "hp": 50})
	var r := CombatResolver.resolve_damage(
		caster, target, 4, "spell", 0, 0, 0, 1.0)
	# 3(roll) + 4(value) + 6(mag) + 0(elev) - 2(res) = 11
	assert_eq(r["damage"], 11)
	assert_eq(target.current_hp, 39)


func test_spell_with_zero_mag() -> void:
	var caster := _make_unit({"mag": 0})
	var target := _make_unit({"res": 0, "hp": 50})
	var r := CombatResolver.resolve_damage(
		caster, target, 4, "spell", 0, 0, 0, 1.0)
	# 3(roll) + 4(value) + 0(mag) + 0(elev) - 0(res) = 7
	assert_eq(r["damage"], 7)


func test_spell_high_res_floors_at_one() -> void:
	var caster := _make_unit({"mag": 2})
	var target := _make_unit({"res": 20, "hp": 50})
	var r := CombatResolver.resolve_damage(
		caster, target, 4, "spell", 0, 0, 0, 1.0)
	# max(1, 3 + 4 + 2 + 0 - 20) = max(1, -11) = 1
	assert_eq(r["damage"], 1)


func test_spell_with_elevation_bonus() -> void:
	var caster := _make_unit({"mag": 6})
	var target := _make_unit({"res": 2, "hp": 50})
	var r := CombatResolver.resolve_damage(
		caster, target, 4, "spell", 3, 0, 1, 1.0)
	# 3(roll) + 4(value) + 6(mag) + 1(elev) - 2(res) = 12
	assert_eq(r["damage"], 12)


func test_spell_no_elevation_bonus_when_lower() -> void:
	var caster := _make_unit({"mag": 6})
	var target := _make_unit({"res": 2, "hp": 50})
	var r := CombatResolver.resolve_damage(
		caster, target, 4, "spell", 0, 3, 1, 1.0)
	# 3(roll) + 4(value) + 6(mag) + 0(no elev) - 2(res) = 11
	assert_eq(r["damage"], 11)


func test_spell_mag_scaling_factor() -> void:
	var caster := _make_unit({"mag": 10})
	var target := _make_unit({"res": 0, "hp": 50})
	# mag_scaling = 0.5: bonus = round(0.5 * 10) = 5
	var r := CombatResolver.resolve_damage(
		caster, target, 4, "spell", 0, 0, 0, 0.5)
	# 3(roll) + 4(value) + 5(mag×0.5) + 0(elev) - 0(res) = 12
	assert_eq(r["damage"], 12)


func test_spell_zero_mag_scaling() -> void:
	var caster := _make_unit({"mag": 10})
	var target := _make_unit({"res": 0, "hp": 50})
	var r := CombatResolver.resolve_damage(
		caster, target, 4, "spell", 0, 0, 0, 0.0)
	# 3(roll) + 4(value) + 0(mag×0) + 0(elev) - 0(res) = 7
	assert_eq(r["damage"], 7)


func test_higher_mag_deals_more_damage() -> void:
	var target := _make_unit({"res": 2, "hp": 50})
	var low_caster := _make_unit({"mag": 2})
	var high_caster := _make_unit({"mag": 8})
	var r_low := CombatResolver.resolve_damage(
		low_caster, target, 4, "spell", 0, 0, 0, 1.0)
	target.current_hp = 50  # reset
	var r_high := CombatResolver.resolve_damage(
		high_caster, target, 4, "spell", 0, 0, 0, 1.0)
	assert_gt(r_high["damage"], r_low["damage"])


func test_higher_res_takes_less_damage() -> void:
	var caster := _make_unit({"mag": 6})
	var low_res := _make_unit({"res": 0, "hp": 50})
	var high_res := _make_unit({"res": 5, "hp": 50})
	var r_low := CombatResolver.resolve_damage(
		caster, low_res, 4, "spell", 0, 0, 0, 1.0)
	var r_high := CombatResolver.resolve_damage(
		caster, high_res, 4, "spell", 0, 0, 0, 1.0)
	assert_gt(r_low["damage"], r_high["damage"])


# --- Attack die preserved for spells ---

func test_spell_attack_die_contributes() -> void:
	CombatResolver.dice_roller = func() -> int: return 6
	var caster := _make_unit({"mag": 4})
	var target := _make_unit({"res": 0, "hp": 50})
	var r := CombatResolver.resolve_damage(
		caster, target, 4, "spell", 0, 0, 0, 1.0)
	# 6(roll) + 4(value) + 4(mag) + 0(elev) - 0(res) = 14
	assert_eq(r["damage"], 14)
	assert_eq(r["atk_roll"], 6)


# --- Defend die applies to spells ---

func test_defend_die_reduces_spell_damage() -> void:
	var caster := _make_unit({"mag": 6})
	var target := _make_unit({"res": 2, "hp": 50})
	target.stats.push_modifier(StatModifier.new("def", 2, "defend"))
	var r := CombatResolver.resolve_damage(
		caster, target, 4, "spell", 0, 0, 0, 1.0)
	# base = max(1, 3 + 4 + 6 - 2) = 11, def_roll = 3, final = max(1, 11 - 3) = 8
	assert_eq(r["damage"], 8)
	assert_eq(r["def_roll"], 3)


func test_defend_die_on_spell_floors_at_one() -> void:
	CombatResolver.dice_roller = func() -> int: return 6
	var caster := _make_unit({"mag": 0})
	var target := _make_unit({"res": 5, "hp": 50})
	target.stats.push_modifier(StatModifier.new("def", 2, "defend"))
	var r := CombatResolver.resolve_damage(
		caster, target, 2, "spell", 0, 0, 0, 1.0)
	# base = max(1, 6 + 2 + 0 - 5) = 3, def_roll = 6, final = max(1, 3 - 6) = 1
	assert_eq(r["damage"], 1)


# --- Skill damage unchanged (regression) ---

func test_skill_uses_def_not_res() -> void:
	var attacker := _make_unit({"atk": 0, "mag": 10})
	var target := _make_unit({"def": 3, "res": 0, "hp": 50})
	var r := CombatResolver.resolve_damage(
		attacker, target, 5, "skill", 0, 0, 0, 0.0)
	# skill: max(1, 3 + 5 + 0 - 3) = 5 (DEF used, not RES; MAG irrelevant)
	assert_eq(r["damage"], 5)


func test_skill_ignores_mag() -> void:
	var attacker := _make_unit({"mag": 20})
	var target := _make_unit({"def": 2, "hp": 50})
	var r := CombatResolver.resolve_damage(
		attacker, target, 5, "skill", 0, 0, 0, 0.0)
	# skill: max(1, 3 + 5 + 0 - 2) = 6 (MAG not used)
	assert_eq(r["damage"], 6)


# --- Heal scaling ---

func test_heal_with_mag_scaling() -> void:
	var caster := _make_unit({"mag": 6})
	var target := _make_unit({"hp": 50})
	target.current_hp = 20
	var r := CombatResolver.resolve_heal(target, 4, caster, 1.0)
	# healing = min(4 + round(1.0 * 6), 50 - 20) = min(10, 30) = 10
	assert_eq(r["healing"], 10)
	assert_eq(target.current_hp, 30)


func test_heal_flat_no_caster() -> void:
	var target := _make_unit({"hp": 50})
	target.current_hp = 20
	var r := CombatResolver.resolve_heal(target, 4)
	# healing = min(4 + 0, 50 - 20) = 4
	assert_eq(r["healing"], 4)
	assert_eq(target.current_hp, 24)


func test_heal_flat_with_zero_scaling() -> void:
	var caster := _make_unit({"mag": 10})
	var target := _make_unit({"hp": 50})
	target.current_hp = 20
	var r := CombatResolver.resolve_heal(target, 8, caster, 0.0)
	# healing = min(8 + 0, 50 - 20) = 8
	assert_eq(r["healing"], 8)
	assert_eq(target.current_hp, 28)


func test_heal_clamped_to_max_hp() -> void:
	var caster := _make_unit({"mag": 20})
	var target := _make_unit({"hp": 50})
	target.current_hp = 48
	var r := CombatResolver.resolve_heal(target, 4, caster, 1.0)
	# healing = min(4 + 20, 50 - 48) = min(24, 2) = 2
	assert_eq(r["healing"], 2)
	assert_eq(target.current_hp, 50)


func test_spell_downs_target() -> void:
	var caster := _make_unit({"mag": 6})
	var target := _make_unit({"res": 0, "hp": 5})
	var r := CombatResolver.resolve_damage(
		caster, target, 4, "spell", 0, 0, 0, 1.0)
	# 3 + 4 + 6 - 0 = 13, HP 5 → 0
	assert_true(r["is_downed"])
	assert_eq(target.current_hp, 0)
