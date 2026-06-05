extends GutTest
## Tests for CombatResolver: physical damage, spell/skill damage, healing,
## buffs, status effects, weapon power lookup.


# --- Helpers ---

func _make_unit(id: String, spd: int = 3, hp: int = 10,
		atk: int = 2, def_val: int = 1, rng: int = 1) -> BattleUnit:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = []
	c.abilities = []
	var sb := StatBlock.new()
	sb.set_base("spd", spd)
	sb.set_base("hp", hp)
	sb.set_base("atk", atk)
	sb.set_base("def", def_val)
	sb.set_base("rng", rng)
	return BattleUnit.from_character(c, sb)


# --- Physical Attack Tests ---

func test_physical_damage_basic() -> void:
	var attacker := _make_unit("a", 3, 10, 2, 1)  # ATK=2
	var target := _make_unit("b", 3, 10, 2, 1)    # DEF=1
	var result := CombatResolver.resolve_attack(
		attacker, target, 3,  # weapon_power=3
		0, 0, 0, false, 1, 1)  # flat ground, melee
	# damage = max(1, 2 + 3 + 0 - 1 - 0) = 4
	assert_eq(result["damage"], 4)
	assert_eq(target.current_hp, 6)
	assert_false(result["is_downed"])


func test_physical_damage_no_weapon() -> void:
	var attacker := _make_unit("a", 3, 10, 2, 1)
	var target := _make_unit("b", 3, 10, 2, 1)
	var result := CombatResolver.resolve_attack(
		attacker, target, 0, 0, 0, 0, false, 1, 1)
	# damage = max(1, 2 + 0 + 0 - 1 - 0) = 1
	assert_eq(result["damage"], 1)


func test_minimum_damage_is_one() -> void:
	var attacker := _make_unit("a", 3, 10, 1, 1)  # ATK=1
	var target := _make_unit("b", 3, 10, 2, 10)   # DEF=10
	var result := CombatResolver.resolve_attack(
		attacker, target, 0, 0, 0, 0, false, 1, 1)
	assert_eq(result["damage"], 1)
	assert_eq(target.current_hp, 9)


func test_elevation_bonus_applied() -> void:
	var attacker := _make_unit("a", 3, 10, 2, 1)
	var target := _make_unit("b", 3, 10, 2, 1)
	var result := CombatResolver.resolve_attack(
		attacker, target, 3,
		3, 0, 0, false, 1, 1)  # attacker elev 3, target elev 0
	# damage = max(1, 2 + 3 + 1 - 1 - 0) = 5
	assert_eq(result["damage"], 5)


func test_no_elevation_bonus_when_lower() -> void:
	var attacker := _make_unit("a", 3, 10, 2, 1)
	var target := _make_unit("b", 3, 10, 2, 1)
	var result := CombatResolver.resolve_attack(
		attacker, target, 3,
		0, 3, 0, false, 1, 1)  # attacker elev 0, target elev 3
	# damage = max(1, 2 + 3 + 0 - 1 - 0) = 4  (no bonus)
	assert_eq(result["damage"], 4)


func test_cover_reduces_ranged_damage() -> void:
	var attacker := _make_unit("a", 3, 10, 2, 1)
	var target := _make_unit("b", 3, 10, 2, 1)
	var result := CombatResolver.resolve_attack(
		attacker, target, 3,
		0, 0, 1, true, 1, 1)  # cover=1, ranged
	# damage = max(1, 2 + 3 + 0 - 1 - 1) = 3
	assert_eq(result["damage"], 3)


func test_cover_ignored_for_melee() -> void:
	var attacker := _make_unit("a", 3, 10, 2, 1)
	var target := _make_unit("b", 3, 10, 2, 1)
	var result := CombatResolver.resolve_attack(
		attacker, target, 3,
		0, 0, 1, false, 1, 1)  # cover=1, but melee
	# damage = max(1, 2 + 3 + 0 - 1 - 0) = 4
	assert_eq(result["damage"], 4)


func test_downing_at_zero_hp() -> void:
	var attacker := _make_unit("a", 3, 10, 5, 1)  # ATK=5
	var target := _make_unit("b", 3, 3, 2, 0)     # HP=3, DEF=0
	var result := CombatResolver.resolve_attack(
		attacker, target, 3, 0, 0, 0, false, 1, 1)
	# damage = max(1, 5 + 3 + 0 - 0 - 0) = 8, HP=3-8 = clamped to 0
	assert_true(result["is_downed"])
	assert_eq(target.current_hp, 0)
	assert_eq(result["target_hp_after"], 0)


func test_hp_does_not_go_negative() -> void:
	var attacker := _make_unit("a", 3, 10, 10, 1)
	var target := _make_unit("b", 3, 5, 2, 0)
	CombatResolver.resolve_attack(
		attacker, target, 5, 0, 0, 0, false, 1, 1)
	assert_eq(target.current_hp, 0)


# --- Spell/Skill Damage Tests ---

func test_spell_damage_ignores_def() -> void:
	var attacker := _make_unit("a", 3, 10, 0, 0)
	var target := _make_unit("b", 3, 12, 2, 5)  # DEF=5
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "spell", 0, 0, 1)
	# spell: damage = 4 + 0 = 4 (DEF ignored)
	assert_eq(result["damage"], 4)
	assert_eq(target.current_hp, 8)


func test_spell_damage_with_elevation() -> void:
	var attacker := _make_unit("a", 3, 10, 0, 0)
	var target := _make_unit("b", 3, 12, 2, 5)
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "spell", 3, 0, 1)
	# spell: damage = 4 + 1 = 5
	assert_eq(result["damage"], 5)


func test_skill_damage_reduced_by_def() -> void:
	var attacker := _make_unit("a", 3, 10, 2, 1)
	var target := _make_unit("b", 3, 16, 2, 3)  # DEF=3
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, 1)
	# skill: damage = max(1, 4 + 0 - 3) = 1
	assert_eq(result["damage"], 1)


func test_skill_damage_with_elevation() -> void:
	var attacker := _make_unit("a", 3, 10, 2, 1)
	var target := _make_unit("b", 3, 16, 2, 3)
	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 3, 0, 1)
	# skill: damage = max(1, 4 + 1 - 3) = 2
	assert_eq(result["damage"], 2)


func test_skill_minimum_damage_is_one() -> void:
	var attacker := _make_unit("a", 3, 10, 1, 1)
	var target := _make_unit("b", 3, 16, 2, 10)  # DEF=10
	var result := CombatResolver.resolve_damage(
		attacker, target, 2, "skill", 0, 0, 1)
	assert_eq(result["damage"], 1)


func test_damage_downs_target() -> void:
	var attacker := _make_unit("a", 3, 10, 0, 0)
	var target := _make_unit("b", 3, 3, 2, 0)  # HP=3
	var result := CombatResolver.resolve_damage(
		attacker, target, 7, "spell", 0, 0, 1)
	assert_true(result["is_downed"])
	assert_eq(target.current_hp, 0)


# --- Healing Tests ---

func test_heal_restores_hp() -> void:
	var target := _make_unit("b", 3, 10, 2, 1)
	target.current_hp = 5
	var result := CombatResolver.resolve_heal(target, 4)
	assert_eq(result["healing"], 4)
	assert_eq(target.current_hp, 9)


func test_heal_clamped_to_max() -> void:
	var target := _make_unit("b", 3, 10, 2, 1)
	target.current_hp = 8
	var result := CombatResolver.resolve_heal(target, 5)
	# max_hp=10, can only heal 2
	assert_eq(result["healing"], 2)
	assert_eq(target.current_hp, 10)


func test_heal_at_full_hp() -> void:
	var target := _make_unit("b", 3, 10, 2, 1)
	# current_hp starts at max (10)
	var result := CombatResolver.resolve_heal(target, 5)
	assert_eq(result["healing"], 0)
	assert_eq(target.current_hp, 10)


# --- Buff Tests ---

func test_buff_pushes_modifier() -> void:
	var target := _make_unit("b", 3, 10, 2, 1)
	var base_def: int = target.stats.effective("def")
	var result := CombatResolver.resolve_buff(target, "def", 2, "shield_1")
	assert_eq(target.stats.effective("def"), base_def + 2)
	assert_eq(result["buff_stat"], "def")
	assert_eq(result["buff_value"], 2)
	assert_eq(result["source_tag"], "buff:shield_1")


func test_buff_source_tag_format() -> void:
	var target := _make_unit("b", 3, 10, 2, 1)
	var result := CombatResolver.resolve_buff(target, "atk", 3, "rage")
	assert_eq(result["source_tag"], "buff:rage")


func test_buff_stacks_from_different_sources() -> void:
	var target := _make_unit("b", 3, 10, 2, 1)
	var base_atk: int = target.stats.effective("atk")
	CombatResolver.resolve_buff(target, "atk", 2, "inspire")
	CombatResolver.resolve_buff(target, "atk", 3, "rage")
	assert_eq(target.stats.effective("atk"), base_atk + 5)


func test_buff_removable_by_source_tag() -> void:
	var target := _make_unit("b", 3, 10, 2, 1)
	var base_def: int = target.stats.effective("def")
	CombatResolver.resolve_buff(target, "def", 2, "shield_1")
	assert_eq(target.stats.effective("def"), base_def + 2)
	target.stats.remove_modifiers_by_source("buff:shield_1")
	assert_eq(target.stats.effective("def"), base_def)


# --- Status Effect Tests ---

func test_status_applied() -> void:
	var target := _make_unit("b", 3, 10, 2, 1)
	var result := CombatResolver.resolve_status(target, "sleep", 2, "lullaby")
	assert_true(target.has_status("sleep"))
	assert_eq(result["status_id"], "sleep")
	assert_eq(result["status_duration"], 2)
	assert_false(result["refreshed"])


func test_status_refresh() -> void:
	var target := _make_unit("b", 3, 10, 2, 1)
	CombatResolver.resolve_status(target, "blind", 2, "smoke_bomb")
	var result := CombatResolver.resolve_status(target, "blind", 3, "smoke_bomb")
	assert_true(result["refreshed"])
	assert_eq(result["status_duration"], 3)
	# Should still be one entry, not two
	var count := 0
	for s in target.status_effects:
		if s["id"] == "blind":
			count += 1
	assert_eq(count, 1)


func test_has_status_false_when_absent() -> void:
	var target := _make_unit("b", 3, 10, 2, 1)
	assert_false(target.has_status("sleep"))


func test_remove_status() -> void:
	var target := _make_unit("b", 3, 10, 2, 1)
	CombatResolver.resolve_status(target, "sleep", 2, "lullaby")
	assert_true(target.has_status("sleep"))
	target.remove_status("sleep")
	assert_false(target.has_status("sleep"))


# --- Wake on Damage Tests ---

func test_sleep_removed_on_physical_attack() -> void:
	var attacker := _make_unit("a", 3, 10, 3, 1)
	var target := _make_unit("b", 3, 10, 2, 1)
	CombatResolver.resolve_status(target, "sleep", 3, "lullaby")
	assert_true(target.has_status("sleep"))
	CombatResolver.resolve_attack(
		attacker, target, 2, 0, 0, 0, false, 1, 1)
	assert_false(target.has_status("sleep"))


func test_sleep_removed_on_ability_damage() -> void:
	var attacker := _make_unit("a", 3, 10, 0, 0)
	var target := _make_unit("b", 3, 10, 2, 1)
	CombatResolver.resolve_status(target, "sleep", 3, "lullaby")
	CombatResolver.resolve_damage(
		attacker, target, 4, "spell", 0, 0, 1)
	assert_false(target.has_status("sleep"))


# --- Weapon Power Lookup Tests ---

func test_weapon_power_with_provider() -> void:
	var c := CharacterData.new()
	c.id = "test"
	c.display_name = "test"
	c.classes = []
	c.equipment = ["sword", "light_armor"]
	c.abilities = []
	var sb := StatBlock.new()
	sb.set_base("spd", 3)
	sb.set_base("hp", 10)
	sb.set_base("atk", 2)
	sb.set_base("def", 1)
	sb.set_base("rng", 1)
	var unit := BattleUnit.from_character(c, sb)

	var sword := ItemData.new()
	sword.id = "sword"
	sword.slot = "weapon"
	sword.weapon_power = 3

	var armor := ItemData.new()
	armor.id = "light_armor"
	armor.slot = "armor"
	armor.weapon_power = 0

	var items := { "sword": sword, "light_armor": armor }
	var provider := func(id: String) -> ItemData: return items.get(id, null)

	assert_eq(CombatResolver.get_weapon_power(unit, provider), 3)


func test_weapon_power_no_weapon() -> void:
	var c := CharacterData.new()
	c.id = "test"
	c.display_name = "test"
	c.classes = []
	c.equipment = ["light_armor"]
	c.abilities = []
	var sb := StatBlock.new()
	sb.set_base("spd", 3)
	sb.set_base("hp", 10)
	sb.set_base("atk", 0)
	sb.set_base("def", 0)
	sb.set_base("rng", 0)
	var unit := BattleUnit.from_character(c, sb)

	var armor := ItemData.new()
	armor.id = "light_armor"
	armor.slot = "armor"
	var items := { "light_armor": armor }
	var provider := func(id: String) -> ItemData: return items.get(id, null)

	assert_eq(CombatResolver.get_weapon_power(unit, provider), 0)


func test_weapon_power_invalid_provider() -> void:
	var c := CharacterData.new()
	c.id = "test"
	c.display_name = "test"
	c.classes = []
	c.equipment = ["sword"]
	c.abilities = []
	var sb := StatBlock.new()
	sb.set_base("spd", 3)
	sb.set_base("hp", 10)
	sb.set_base("atk", 2)
	sb.set_base("def", 1)
	sb.set_base("rng", 1)
	var unit := BattleUnit.from_character(c, sb)
	assert_eq(CombatResolver.get_weapon_power(unit, Callable()), 0)
