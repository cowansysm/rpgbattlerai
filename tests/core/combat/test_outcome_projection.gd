extends GutTest
## Tests for OutcomeProjection: min/mid/max damage and healing projection.


func _make_unit(id: String, team: String, atk: int = 5, def: int = 2,
		hp: int = 20, mag: int = 0, res: int = 0) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = []
	c.abilities = []
	var sb := StatBlock.new()
	sb.set_base("atk", atk)
	sb.set_base("def", def)
	sb.set_base("hp", hp)
	sb.set_base("mag", mag)
	sb.set_base("res", res)
	sb.set_base("spd", 3)
	sb.set_base("rng", 1)
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	return u


# --- Attack projection ---

func test_project_attack_min_less_than_max() -> void:
	var attacker := _make_unit("a", "playerA", 5, 2)
	var target := _make_unit("b", "playerB", 3, 3)
	var result := OutcomeProjection.project_attack(attacker, target, 2, 0, 0, 0, false)
	assert_lt(result["min"], result["max"], "min should be less than max")
	assert_true(result["min"] >= 1, "min damage should be at least 1")


func test_project_attack_mid_is_average() -> void:
	var attacker := _make_unit("a", "playerA", 5, 2)
	var target := _make_unit("b", "playerB", 3, 3)
	var result := OutcomeProjection.project_attack(attacker, target, 2, 0, 0, 0, false)
	assert_eq(result["mid"], (result["min"] + result["max"]) / 2)


func test_project_attack_with_elevation() -> void:
	var attacker := _make_unit("a", "playerA", 5, 2)
	var target := _make_unit("b", "playerB", 3, 3)
	var no_elev := OutcomeProjection.project_attack(attacker, target, 2, 0, 0, 0, false)
	var with_elev := OutcomeProjection.project_attack(attacker, target, 2, 3, 0, 0, false)
	assert_true(with_elev["max"] >= no_elev["max"],
		"Higher elevation should increase or maintain max damage")


func test_project_attack_with_defend() -> void:
	var attacker := _make_unit("a", "playerA", 5, 2)
	var target := _make_unit("b", "playerB", 3, 3)
	var no_defend := OutcomeProjection.project_attack(attacker, target, 2, 0, 0, 0, false)
	# Add defend modifier
	target.stats.push_modifier(StatModifier.new("def", 3, "defend"))
	var with_defend := OutcomeProjection.project_attack(attacker, target, 2, 0, 0, 0, false)
	assert_true(with_defend["min"] <= no_defend["min"],
		"Defend should reduce or maintain min damage")
	assert_true(with_defend["min"] >= 1, "Min damage should still be at least 1")


func test_project_attack_matches_resolver_at_fixed_roll() -> void:
	var attacker := _make_unit("a", "playerA", 5, 2, 20)
	var target := _make_unit("b", "playerB", 3, 3, 20)
	var projection := OutcomeProjection.project_attack(attacker, target, 2, 0, 0, 0, false)

	# Run resolver with die fixed to 1
	var saved_roller: Callable = CombatResolver.dice_roller
	CombatResolver.dice_roller = func() -> int: return 1
	var target_clone := _make_unit("b_clone", "playerB", 3, 3, 20)
	var result := CombatResolver.resolve_attack(
		attacker, target_clone, 2, 0, 0, 0, false)
	CombatResolver.dice_roller = saved_roller

	assert_eq(projection["min"], result["damage"],
		"Projection min should match resolver with die=1")


func test_project_attack_no_mutation() -> void:
	var attacker := _make_unit("a", "playerA", 5, 2, 20)
	var target := _make_unit("b", "playerB", 3, 3, 15)
	var hp_before: int = target.current_hp
	OutcomeProjection.project_attack(attacker, target, 2, 0, 0, 0, false)
	assert_eq(target.current_hp, hp_before, "Projection should not mutate target HP")


# --- Ability damage projection ---

func test_project_ability_damage_skill() -> void:
	var caster := _make_unit("a", "playerA", 5, 2, 20)
	var target := _make_unit("b", "playerB", 3, 4, 20)
	var result := OutcomeProjection.project_ability_damage(caster, target, 8, "skill", 0, 0)
	assert_lt(result["min"], result["max"])
	assert_true(result["min"] >= 1)


func test_project_ability_damage_spell_uses_mag() -> void:
	var caster := _make_unit("a", "playerA", 5, 2, 20, 6, 0)
	var target := _make_unit("b", "playerB", 3, 4, 20, 0, 2)
	var result := OutcomeProjection.project_ability_damage(
		caster, target, 5, "spell", 0, 0, 1.0)
	# Spell damage = roll + value + round(mag_scaling * MAG) + e_bonus - RES
	# Min (roll=1): 1 + 5 + 6 + 0 - 2 = 10
	# Max (roll=6): 6 + 5 + 6 + 0 - 2 = 15
	assert_eq(result["min"], 10)
	assert_eq(result["max"], 15)


func test_project_ability_damage_with_defend() -> void:
	var caster := _make_unit("a", "playerA", 5, 2, 20)
	var target := _make_unit("b", "playerB", 3, 4, 20)
	var no_defend := OutcomeProjection.project_ability_damage(caster, target, 8, "skill", 0, 0)
	target.stats.push_modifier(StatModifier.new("def", 3, "defend"))
	var with_defend := OutcomeProjection.project_ability_damage(caster, target, 8, "skill", 0, 0)
	assert_true(with_defend["min"] <= no_defend["min"])


# --- Heal projection ---

func test_project_heal_deterministic() -> void:
	var target := _make_unit("b", "playerB", 3, 3, 20)
	target.current_hp = 12
	var result := OutcomeProjection.project_heal(target, 5)
	assert_eq(result["min"], 5)
	assert_eq(result["mid"], 5)
	assert_eq(result["max"], 5)


func test_project_heal_capped_at_missing_hp() -> void:
	var target := _make_unit("b", "playerB", 3, 3, 20)
	target.current_hp = 18  # Only 2 missing
	var result := OutcomeProjection.project_heal(target, 10)
	assert_eq(result["min"], 2, "Heal should be capped at missing HP")


func test_project_heal_with_mag_scaling() -> void:
	var caster := _make_unit("a", "playerA", 3, 2, 20, 4, 0)
	var target := _make_unit("b", "playerA", 3, 3, 20)
	target.current_hp = 5
	var result := OutcomeProjection.project_heal(target, 5, caster, 1.0)
	# Heal = min(5 + round(1.0 * 4), 15) = 9
	assert_eq(result["min"], 9)
