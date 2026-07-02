extends GutTest
## Tests for Phase A16: Elemental Affinities & Critical Hits.
## Covers each affinity tier, multi-source stacking, crit apply/flag,
## absorb→heal, neutral-default regression, and AoE-per-tile verification.

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

func _make_unit(id: String, hp: int = 20, atk: int = 5, def_val: int = 2,
		mag: int = 0, res: int = 0) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = []
	c.abilities = []
	var sb := StatBlock.new()
	sb.set_base("spd", 3)
	sb.set_base("hp", hp)
	sb.set_base("atk", atk)
	sb.set_base("def", def_val)
	sb.set_base("rng", 1)
	sb.set_base("mag", mag)
	sb.set_base("res", res)
	return BattleUnit.from_character(c, sb)


# =====================================================================
# Affinity model unit tests
# =====================================================================

func test_tier_to_weight_mappings() -> void:
	assert_eq(Affinity.tier_to_weight("weak"), 1)
	assert_eq(Affinity.tier_to_weight("neutral"), 0)
	assert_eq(Affinity.tier_to_weight("resist"), -1)
	assert_eq(Affinity.tier_to_weight("immune"), -2)
	assert_eq(Affinity.tier_to_weight("absorb"), -3)
	assert_eq(Affinity.tier_to_weight("unknown"), 0, "unknown tier → 0")


func test_weight_to_tier_clamping() -> void:
	assert_eq(Affinity.weight_to_tier(1), Affinity.Tier.WEAK)
	assert_eq(Affinity.weight_to_tier(0), Affinity.Tier.NEUTRAL)
	assert_eq(Affinity.weight_to_tier(-1), Affinity.Tier.RESIST)
	assert_eq(Affinity.weight_to_tier(-2), Affinity.Tier.IMMUNE)
	assert_eq(Affinity.weight_to_tier(-3), Affinity.Tier.ABSORB)
	# Clamp extremes
	assert_eq(Affinity.weight_to_tier(5), Affinity.Tier.WEAK, "high weight clamped to WEAK")
	assert_eq(Affinity.weight_to_tier(-10), Affinity.Tier.ABSORB, "low weight clamped to ABSORB")


func test_tier_to_name() -> void:
	assert_eq(Affinity.tier_to_name(Affinity.Tier.WEAK), "weak")
	assert_eq(Affinity.tier_to_name(Affinity.Tier.NEUTRAL), "neutral")
	assert_eq(Affinity.tier_to_name(Affinity.Tier.RESIST), "resist")
	assert_eq(Affinity.tier_to_name(Affinity.Tier.IMMUNE), "immune")
	assert_eq(Affinity.tier_to_name(Affinity.Tier.ABSORB), "absorb")


func test_multiplier_values() -> void:
	assert_eq(Affinity.multiplier(Affinity.Tier.WEAK), 1.5)
	assert_eq(Affinity.multiplier(Affinity.Tier.NEUTRAL), 1.0)
	assert_eq(Affinity.multiplier(Affinity.Tier.RESIST), 0.5)
	assert_eq(Affinity.multiplier(Affinity.Tier.IMMUNE), 0.0)
	assert_eq(Affinity.multiplier(Affinity.Tier.ABSORB), 1.0)


func test_merge_sources_empty() -> void:
	var merged := Affinity.merge_sources([])
	assert_eq(merged.size(), 0)


func test_merge_sources_single() -> void:
	var merged := Affinity.merge_sources([{"fire": "weak", "ice": "resist"}])
	assert_eq(merged["fire"], 1)
	assert_eq(merged["ice"], -1)


func test_merge_sources_stacking() -> void:
	# Race: fire weak (+1), class: fire resist (-1) → net 0 (NEUTRAL)
	var merged := Affinity.merge_sources([
		{"fire": "weak"},
		{"fire": "resist"},
	])
	assert_eq(merged["fire"], 0, "weak + resist = neutral (0)")


func test_merge_sources_multiple_elements() -> void:
	var merged := Affinity.merge_sources([
		{"fire": "weak", "ice": "resist"},
		{"fire": "resist", "lightning": "immune"},
	])
	assert_eq(merged["fire"], 0, "weak + resist = neutral")
	assert_eq(merged["ice"], -1, "resist only")
	assert_eq(merged["lightning"], -2, "immune only")


# =====================================================================
# BattleUnit.effective_affinity tests
# =====================================================================

func test_effective_affinity_empty_element() -> void:
	var unit := _make_unit("a")
	assert_eq(unit.effective_affinity(""), Affinity.Tier.NEUTRAL)


func test_effective_affinity_no_affinities() -> void:
	var unit := _make_unit("a")
	assert_eq(unit.effective_affinity("fire"), Affinity.Tier.NEUTRAL)


func test_effective_affinity_with_sources() -> void:
	var unit := _make_unit("a")
	unit.apply_affinity_sources([{"fire": "weak"}, {"ice": "resist"}])
	assert_eq(unit.effective_affinity("fire"), Affinity.Tier.WEAK)
	assert_eq(unit.effective_affinity("ice"), Affinity.Tier.RESIST)
	assert_eq(unit.effective_affinity("lightning"), Affinity.Tier.NEUTRAL)


func test_effective_affinity_with_extra_weight() -> void:
	var unit := _make_unit("a")
	unit.apply_affinity_sources([{"fire": "neutral"}])
	# Extra weight -1 from terrain → RESIST
	assert_eq(unit.effective_affinity("fire", -1), Affinity.Tier.RESIST)


func test_effective_affinity_stacking_to_immune() -> void:
	var unit := _make_unit("a")
	# Two resist sources: -1 + -1 = -2 → IMMUNE
	unit.apply_affinity_sources([{"fire": "resist"}, {"fire": "resist"}])
	assert_eq(unit.effective_affinity("fire"), Affinity.Tier.IMMUNE)


# =====================================================================
# resolve_damage — affinity tier tests (element-aware)
# =====================================================================

func test_resolve_damage_weak_amplifies() -> void:
	var attacker := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 40, 3, 2, 0, 0)  # DEF=2
	target.apply_affinity_sources([{"fire": "weak"}])
	# Skill: base = 3 + 4 + 0 - 2 = 5, scaled = round(5 * 1.5) = 8
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, 1, 1.0, "fire")
	assert_eq(result["damage"], 8, "weak ×1.5 applied")
	assert_eq(result["affinity"], "weak")
	assert_eq(result["element"], "fire")


func test_resolve_damage_neutral_unchanged() -> void:
	var attacker := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 40, 3, 2, 0, 0)
	# No affinities set → NEUTRAL
	# Skill: base = 3 + 4 + 0 - 2 = 5, scaled = round(5 * 1.0) = 5
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, 1, 1.0, "fire")
	assert_eq(result["damage"], 5, "neutral ×1.0 = no change")
	assert_eq(result["affinity"], "neutral")


func test_resolve_damage_resist_halves() -> void:
	var attacker := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 40, 3, 2, 0, 0)
	target.apply_affinity_sources([{"fire": "resist"}])
	# Skill: base = 3 + 4 + 0 - 2 = 5, scaled = round(5 * 0.5) = 2 → max(1,2) = 2 wait, round(2.5) = 2
	# Actually round(2.5) in GDScript rounds to 2 (banker's rounding) or 3? Let's check: round(2.5) = 2 in GDScript.
	# No, round(2.5) = 3 in GDScript (rounds half up to even? Actually in Godot round() rounds half away from zero)
	# round(2.5) = 3 in GDScript
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, 1, 1.0, "fire")
	assert_eq(result["damage"], 3, "resist ×0.5 applied (round(5 * 0.5) = round(2.5) = 3)")
	assert_eq(result["affinity"], "resist")


func test_resolve_damage_immune_nullifies() -> void:
	var attacker := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 20, 3, 2, 0, 0)
	target.apply_affinity_sources([{"fire": "immune"}])
	var hp_before: int = target.current_hp
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, 1, 1.0, "fire")
	assert_eq(result["damage"], 0, "immune nullifies damage")
	assert_eq(target.current_hp, hp_before, "HP unchanged")
	assert_eq(result["affinity"], "immune")
	assert_false(result["is_downed"])


func test_resolve_damage_absorb_heals() -> void:
	var attacker := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 30, 3, 2, 0, 0)
	target.current_hp = 15  # Missing 15 HP
	target.apply_affinity_sources([{"fire": "absorb"}])
	# Skill: base = 3 + 4 + 0 - 2 = 5, scaled = round(5 * 1.0) = 5 → heal 5
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, 1, 1.0, "fire")
	assert_eq(result["damage"], 0, "absorb deals no damage")
	assert_eq(result["healing"], 5, "absorb heals for scaled amount")
	assert_eq(target.current_hp, 20, "HP increased by healing")
	assert_eq(result["affinity"], "absorb")
	assert_false(result["is_downed"])


func test_resolve_damage_absorb_caps_at_max_hp() -> void:
	var attacker := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 20, 3, 2, 0, 0)
	target.current_hp = 18  # Only 2 missing
	target.apply_affinity_sources([{"fire": "absorb"}])
	# Skill: base = 3 + 4 + 0 - 2 = 5, but only 2 HP missing
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, 1, 1.0, "fire")
	assert_eq(result["healing"], 2, "absorb capped at missing HP")
	assert_eq(target.current_hp, 20, "HP at max")


# =====================================================================
# resolve_damage — critical hit tests
# =====================================================================

func test_resolve_damage_crit_applies_multiplier() -> void:
	CombatResolver.crit_roller = func() -> float: return 0.0  # always crits
	var attacker := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 40, 3, 2, 0, 0)
	# Skill: base = 3 + 4 + 0 - 2 = 5, scaled = 5, crit = round(5 * 1.5) = 8
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, 1, 1.0)
	assert_eq(result["damage"], 8, "crit ×1.5 applied")
	assert_true(result["is_crit"], "is_crit flag set")


func test_resolve_damage_no_crit_flag_when_no_crit() -> void:
	var attacker := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 40, 3, 2, 0, 0)
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, 1, 1.0)
	assert_false(result["is_crit"], "is_crit false when no crit")


func test_resolve_damage_crit_plus_weak() -> void:
	CombatResolver.crit_roller = func() -> float: return 0.0  # always crits
	var attacker := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 40, 3, 2, 0, 0)
	target.apply_affinity_sources([{"fire": "weak"}])
	# Skill: base = 5, weak scaled = round(5 * 1.5) = 8, crit = round(8 * 1.5) = 12
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, 1, 1.0, "fire")
	assert_eq(result["damage"], 12, "weak + crit stacked")
	assert_true(result["is_crit"])
	assert_eq(result["affinity"], "weak")


func test_resolve_damage_crit_on_immune_still_zero() -> void:
	CombatResolver.crit_roller = func() -> float: return 0.0  # always crits
	var attacker := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 20, 3, 2, 0, 0)
	target.apply_affinity_sources([{"fire": "immune"}])
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, 1, 1.0, "fire")
	assert_eq(result["damage"], 0, "immune × crit still 0")
	assert_true(result["is_crit"])


# =====================================================================
# Neutral-default backward compatibility regression
# =====================================================================

func test_neutral_default_regression_skill() -> void:
	## No element, no affinities, no crit → exact same numbers as before A16.
	var attacker := _make_unit("a", 20, 2, 1, 0, 0)
	var target := _make_unit("b", 16, 2, 3, 0, 0)
	# Skill: damage = max(1, 3 + 4 + 0 - 3) = 4
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, 1, 1.0)
	assert_eq(result["damage"], 4, "neutral default reproduces pre-A16 damage")
	assert_eq(result["affinity"], "neutral")
	assert_false(result["is_crit"])
	assert_eq(result["element"], "")


func test_neutral_default_regression_spell() -> void:
	var attacker := _make_unit("a", 20, 0, 0, 4, 0)  # MAG=4
	var target := _make_unit("b", 20, 2, 5, 0, 2)  # RES=2
	# Spell: base = 3 + 4 + round(1.0 * 4) + 0 - 2 = 9, scaled = round(9 * 1.0) = 9
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "spell", 0, 0, 1, 1.0)
	assert_eq(result["damage"], 9, "spell neutral default unchanged")


func test_neutral_default_regression_with_defend() -> void:
	var attacker := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 40, 3, 2, 0, 0)
	target.stats.push_modifier(StatModifier.new("def", 2, "defend"))
	# Skill: base = 3 + 4 + 0 - 4 = 3, scaled = 3
	# Defend roll: 3 → 3 - 3 = 0 → max(1, 0) = 1
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, 1, 1.0)
	assert_eq(result["damage"], 1, "defend + floor still produces min 1")
	assert_eq(result["def_roll"], 3)


# =====================================================================
# Multi-source stacking integration
# =====================================================================

func test_multi_source_stacking_weak_plus_resist_equals_neutral() -> void:
	var attacker := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 40, 3, 2, 0, 0)
	# Race: fire weak (+1), equipment: fire resist (-1) → net 0 → NEUTRAL
	target.apply_affinity_sources([{"fire": "weak"}, {"fire": "resist"}])
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, 1, 1.0, "fire")
	assert_eq(result["affinity"], "neutral", "weak + resist = neutral")
	assert_eq(result["damage"], 5, "neutral damage")


func test_multi_source_stacking_double_resist_equals_immune() -> void:
	var attacker := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 20, 3, 2, 0, 0)
	# Two resist sources: -1 + -1 = -2 → IMMUNE
	target.apply_affinity_sources([{"fire": "resist"}, {"fire": "resist"}])
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, 1, 1.0, "fire")
	assert_eq(result["affinity"], "immune")
	assert_eq(result["damage"], 0, "double resist → immune → 0 damage")


func test_multi_source_terrain_affinity_weight() -> void:
	var attacker := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 40, 3, 2, 0, 0)
	# Unit has no affinity, but terrain provides fire weak (+1)
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, 1, 1.0, "fire", 1)
	assert_eq(result["affinity"], "weak", "terrain weight shifts to weak")
	assert_eq(result["damage"], 8, "weak ×1.5")


# =====================================================================
# OutcomeProjection — affinity/crit-aware bounds
# =====================================================================

func test_projection_neutral_with_crit_max() -> void:
	var caster := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 20, 3, 4, 0, 0)
	# Skill: base_atk = 8 + 0 - 4 = 4
	# Min: max(1, 1+4) = 5, Max before crit: max(1, 6+4) = 10, with crit: round(10*1.5) = 15
	var result := OutcomeProjection.project_ability_damage(
		caster, target, 8, "skill", 0, 0, 1.0, "fire")
	assert_eq(result["min"], 5)
	assert_eq(result["max"], 15, "max includes crit multiplier")
	assert_true(result["max"] > result["min"])


func test_projection_weak_scales_range() -> void:
	var caster := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 20, 3, 4, 0, 0)
	target.apply_affinity_sources([{"fire": "weak"}])
	# Skill: base_atk = 8 + 0 - 4 = 4
	# Min: max(1, round((1+4)*1.5)) = max(1, round(7.5)) = max(1, 8) = 8
	# Max before crit: max(1, round((6+4)*1.5)) = max(1, 15) = 15
	# Max with crit: round(15 * 1.5) = 23
	var result := OutcomeProjection.project_ability_damage(
		caster, target, 8, "skill", 0, 0, 1.0, "fire")
	assert_eq(result["min"], 8, "weak-scaled min")
	assert_eq(result["max"], 23, "weak-scaled max with crit")
	assert_eq(result["affinity"], "weak")


func test_projection_immune_zero() -> void:
	var caster := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 20, 3, 4, 0, 0)
	target.apply_affinity_sources([{"fire": "immune"}])
	var result := OutcomeProjection.project_ability_damage(
		caster, target, 8, "skill", 0, 0, 1.0, "fire")
	assert_eq(result["min"], 0)
	assert_eq(result["mid"], 0)
	assert_eq(result["max"], 0)
	assert_eq(result["affinity"], "immune")


func test_projection_absorb_returns_heal() -> void:
	var caster := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 20, 3, 4, 0, 0)
	target.apply_affinity_sources([{"fire": "absorb"}])
	var result := OutcomeProjection.project_ability_damage(
		caster, target, 8, "skill", 0, 0, 1.0, "fire")
	assert_true(result.get("is_heal", false), "absorb projection is heal")
	assert_true(result["min"] >= 0, "absorb heal values non-negative")
	assert_eq(result["affinity"], "absorb")


func test_projection_attack_crit_max() -> void:
	## A19 fix: FRONT (default arc) basic-attack max no longer multiplied by CRIT_MULT.
	## Front attacks cannot crit (crit_bonus=0), so max = raw_max without crit scaling.
	## Pre-A19 the max was incorrectly 15; post-A19 correct value is 10.
	var attacker := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 20, 3, 3, 0, 0)
	var result := OutcomeProjection.project_attack(
		attacker, target, 2, 0, 0, 0, false)
	# Max without crit (FRONT): max(1, 6 + 5 + 2 + 0 - 3 - 0) = 10 (no crit mult for FRONT)
	assert_eq(result["max"], 10, "FRONT attack projection max excludes crit (A19 fix)")


# =====================================================================
# Validator — affinities validation
# =====================================================================

func test_validator_valid_affinities() -> void:
	var e := Validator.validate_affinities(
		{"fire": "weak", "ice": "resist"}, "test", "race")
	assert_eq(e.size(), 0, "valid affinities produce no errors")


func test_validator_unknown_element() -> void:
	var e := Validator.validate_affinities(
		{"plasma": "weak"}, "test", "race")
	assert_eq(e.size(), 1, "unknown element flagged")
	assert_true(e[0].find("plasma") >= 0)


func test_validator_unknown_tier() -> void:
	var e := Validator.validate_affinities(
		{"fire": "invincible"}, "test", "race")
	assert_eq(e.size(), 1, "unknown tier flagged")
	assert_true(e[0].find("invincible") >= 0)


func test_validator_race_affinities() -> void:
	var d := {"id": "test_race", "name": "Test", "affinities": {"fire": "weak"}}
	var e := Validator.validate_race(d)
	assert_eq(e.size(), 0, "race with valid affinities passes")


func test_validator_class_affinities() -> void:
	var d := {"id": "test_class", "affinities": {"ice": "resist"}}
	var e := Validator.validate_class(d)
	assert_eq(e.size(), 0, "class with valid affinities passes")


func test_validator_item_affinities() -> void:
	var d := {"id": "test_item", "affinities": {"lightning": "immune"}}
	var e := Validator.validate_item(d)
	assert_eq(e.size(), 0, "item with valid affinities passes")


func test_validator_ability_element() -> void:
	var d := {
		"id": "test_ability", "type": "spell",
		"effect": {"effect_type": "damage", "value": 5, "element": "fire"}
	}
	var e := Validator.validate_ability(d)
	assert_eq(e.size(), 0, "ability with valid element passes")


func test_validator_ability_unknown_element() -> void:
	var d := {
		"id": "test_ability", "type": "spell",
		"effect": {"effect_type": "damage", "value": 5, "element": "plasma"}
	}
	var e := Validator.validate_ability(d)
	assert_true(e.size() > 0, "ability with unknown element flagged")


# =====================================================================
# DataFactory — affinities loading
# =====================================================================

func test_factory_race_loads_affinities() -> void:
	var d := {"id": "elf", "name": "Elf", "affinities": {"fire": "weak", "ice": "resist"}}
	var r := DataFactory.make_race(d)
	assert_eq(r.affinities["fire"], "weak")
	assert_eq(r.affinities["ice"], "resist")


func test_factory_race_missing_affinities_defaults_empty() -> void:
	var d := {"id": "human", "name": "Human"}
	var r := DataFactory.make_race(d)
	assert_eq(r.affinities.size(), 0)


func test_factory_class_loads_affinities() -> void:
	var d := {"id": "pyro", "affinities": {"fire": "absorb"}}
	var c := DataFactory.make_class(d)
	assert_eq(c.affinities["fire"], "absorb")


func test_factory_item_loads_affinities() -> void:
	var d := {"id": "fire_shield", "name": "Fire Shield", "affinities": {"fire": "resist"}}
	var i := DataFactory.make_item(d)
	assert_eq(i.affinities["fire"], "resist")


# =====================================================================
# resolve_damage — result dict contains enriched fields
# =====================================================================

func test_result_dict_has_element() -> void:
	var attacker := _make_unit("a")
	var target := _make_unit("b")
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, 1, 1.0, "ice")
	assert_eq(result["element"], "ice")


func test_result_dict_has_pre_affinity_damage() -> void:
	var attacker := _make_unit("a", 20, 5, 2, 0, 0)
	var target := _make_unit("b", 40, 3, 2, 0, 0)
	target.apply_affinity_sources([{"fire": "weak"}])
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, 1, 1.0, "fire")
	# base = 3 + 4 + 0 - 2 = 5
	assert_eq(result["pre_affinity_damage"], 5, "pre_affinity_damage = raw base")


func test_result_dict_empty_element_default() -> void:
	var attacker := _make_unit("a")
	var target := _make_unit("b")
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, 1, 1.0)
	assert_eq(result["element"], "")
	assert_eq(result["affinity"], "neutral")
	assert_false(result["is_crit"])


# =====================================================================
# AoE-per-tile verification — line/cone abilities resolve on every tile
# =====================================================================

func test_collect_affected_units_line() -> void:
	## Verify _collect_affected_units returns units on all line hexes.
	## This is a verification test (no new AoE code — tests existing A11 logic).
	var state := _make_mini_state()
	# Place units on a line from (1,0) direction 0 (east in flat-top hex)
	var caster := _place_unit(state, "caster", Vector2i(0, 0), "teamA")
	var t1 := _place_unit(state, "t1", Vector2i(1, 0), "teamB")
	var t2 := _place_unit(state, "t2", Vector2i(2, 0), "teamB")
	var area := {"shape": "line", "length": 3}
	var affected := TurnActions._collect_affected_units(
		state, caster.position, Vector2i(1, 0), area)
	# Should collect both t1 at (1,0) and t2 at (2,0)
	var ids: Array[String] = []
	for u in affected:
		ids.append(u.character.id)
	assert_true(ids.has("t1"), "line AoE hits unit at (1,0)")
	assert_true(ids.has("t2"), "line AoE hits unit at (2,0)")


func test_collect_affected_units_cone() -> void:
	## Verify _collect_affected_units returns units in cone tiles.
	var state := _make_mini_state()
	var caster := _place_unit(state, "caster", Vector2i(0, 0), "teamA")
	# Cone direction 0 (east), depth 2: includes (1,0), (2,0), (1,-1), (2,-1), (2,1)
	# Place units at two of these positions
	var t1 := _place_unit(state, "t1", Vector2i(1, 0), "teamB")
	# Cone depth 2 from (1,0) in direction 0 covers: (1,0), (2,1), (3,0)
	var t2 := _place_unit(state, "t2", Vector2i(2, 1), "teamB")
	var area := {"shape": "cone", "depth": 2}
	var affected := TurnActions._collect_affected_units(
		state, caster.position, Vector2i(1, 0), area)
	var ids: Array[String] = []
	for u in affected:
		ids.append(u.character.id)
	assert_true(ids.has("t1"), "cone AoE hits unit at (1,0)")
	assert_true(ids.has("t2"), "cone AoE hits unit at (2,1)")


# --- AoE helper: lightweight MatchState stub ---

func _make_mini_state() -> MatchState:
	var state := MatchState.new()
	# Create a minimal HexGraph with a grid of tiles
	state.graph = HexGraph.new()
	var map := MapData.new()
	map.id = "test_map"
	var tiles: Array[TileRecord] = []
	for q in range(-2, 5):
		for r in range(-2, 5):
			tiles.append(TileRecord.new(q, r, 0, "grass", []))
	map.tiles = tiles
	var terrain_provider := func(id: String) -> TerrainProps:
		var p := TerrainProps.new()
		p.id = id
		p.move_cost = 1
		return p
	state.graph.build(map, terrain_provider)
	return state


func _place_unit(state: MatchState, id: String, pos: Vector2i, team: String) -> BattleUnit:
	var unit := _make_unit(id)
	unit.position = pos
	unit.team = team
	state.occupancy[pos] = unit
	if not state.parties.has(team):
		state.parties[team] = []
	state.parties[team].append(unit)
	return unit
