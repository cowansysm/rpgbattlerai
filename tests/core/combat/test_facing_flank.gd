extends GutTest
## Tests for A19 facing bonuses in CombatResolver.resolve_attack / resolve_damage.
## All dice are swapped for fixed callables to ensure determinism.
## Key invariant: FRONT arc must not consume any extra crit roll beyond what existed
## in pre-A19 resolve_attack (no roll at all for basic attacks at FRONT).


func _make_unit(id: String, team: String, atk: int = 5, def: int = 2,
		hp: int = 50, mag: int = 0, res: int = 0, wp: int = 10) -> BattleUnit:
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
	sb.set_base("wp", wp)
	var u := BattleUnit.from_character(c, sb)
	u.team = team
	return u


# --- resolve_attack: FRONT == pre-A19 baseline, no extra crit roll ---

func test_resolve_attack_front_baseline() -> void:
	## FRONT attack must produce same damage as pre-A19 formula.
	## Formula: max(1, die + atk + weapon_power + 0 - def) = max(1, 3 + 5 + 0 - 2) = 6
	var attacker := _make_unit("a", "playerA")
	var target := _make_unit("b", "playerB")
	target.current_hp = 50

	var saved_dice: Callable = CombatResolver.dice_roller
	CombatResolver.dice_roller = func() -> int: return 3

	var result := CombatResolver.resolve_attack(
		attacker, target, 0, 0, 0, 0, false,
		-1, -1, {}, Hex.Arc.FRONT)

	CombatResolver.dice_roller = saved_dice

	assert_eq(result["damage"], 6, "FRONT: damage = die(3)+atk(5)+wp(0)+e(0)+f(0)-def(2)=6")
	assert_false(result["is_crit"], "FRONT basic attack should not crit")


func test_resolve_attack_front_consumes_no_extra_crit_roll() -> void:
	## Spy: count how many times crit_roller is called for a FRONT attack.
	var attacker := _make_unit("a", "playerA")
	var target := _make_unit("b", "playerB")
	target.current_hp = 50

	var saved_dice: Callable = CombatResolver.dice_roller
	var saved_crit: Callable = CombatResolver.crit_roller
	var crit_call_count: int = 0

	CombatResolver.dice_roller = func() -> int: return 3
	CombatResolver.crit_roller = func() -> float:
		crit_call_count += 1
		return 0.0  # would always crit if called

	CombatResolver.resolve_attack(
		attacker, target, 0, 0, 0, 0, false,
		-1, -1, {}, Hex.Arc.FRONT)

	CombatResolver.dice_roller = saved_dice
	CombatResolver.crit_roller = saved_crit

	assert_eq(crit_call_count, 0, "FRONT basic attack must consume ZERO crit rolls")


func test_resolve_attack_flank_adds_damage() -> void:
	## FLANK_HIT=1 should add +1 to damage vs FRONT.
	var attacker := _make_unit("a", "playerA")
	var target := _make_unit("b", "playerB")
	target.current_hp = 50

	var saved_dice: Callable = CombatResolver.dice_roller
	var saved_crit: Callable = CombatResolver.crit_roller
	CombatResolver.dice_roller = func() -> int: return 3
	# crit will not fire unless roll < FLANK_CRIT; set roll high so no crit
	CombatResolver.crit_roller = func() -> float: return 0.99

	var front := CombatResolver.resolve_attack(
		attacker, target, 0, 0, 0, 0, false,
		-1, -1, {}, Hex.Arc.FRONT)
	target.current_hp = 50  # reset
	var flank := CombatResolver.resolve_attack(
		attacker, target, 0, 0, 0, 0, false,
		-1, -1, {}, Hex.Arc.FLANK)

	CombatResolver.dice_roller = saved_dice
	CombatResolver.crit_roller = saved_crit

	assert_eq(flank["damage"], front["damage"] + 1, "FLANK should add +1 damage (FLANK_HIT)")


func test_resolve_attack_rear_adds_more_damage() -> void:
	## REAR_HIT=2 should add +2 to damage vs FRONT.
	var attacker := _make_unit("a", "playerA")
	var target := _make_unit("b", "playerB")
	target.current_hp = 50

	var saved_dice: Callable = CombatResolver.dice_roller
	var saved_crit: Callable = CombatResolver.crit_roller
	CombatResolver.dice_roller = func() -> int: return 3
	CombatResolver.crit_roller = func() -> float: return 0.99  # no crit

	var front := CombatResolver.resolve_attack(
		attacker, target, 0, 0, 0, 0, false,
		-1, -1, {}, Hex.Arc.FRONT)
	target.current_hp = 50
	var rear := CombatResolver.resolve_attack(
		attacker, target, 0, 0, 0, 0, false,
		-1, -1, {}, Hex.Arc.REAR)

	CombatResolver.dice_roller = saved_dice
	CombatResolver.crit_roller = saved_crit

	assert_eq(rear["damage"], front["damage"] + 2, "REAR should add +2 damage (REAR_HIT)")


func test_resolve_attack_rear_crit_fires() -> void:
	## REAR crit fires when roll_crit() < REAR_CRIT (0.125).
	var attacker := _make_unit("a", "playerA")
	var target := _make_unit("b", "playerB")
	target.current_hp = 50

	var saved_dice: Callable = CombatResolver.dice_roller
	var saved_crit: Callable = CombatResolver.crit_roller
	CombatResolver.dice_roller = func() -> int: return 3
	CombatResolver.crit_roller = func() -> float: return 0.0  # always crits

	var result := CombatResolver.resolve_attack(
		attacker, target, 0, 0, 0, 0, false,
		-1, -1, {}, Hex.Arc.REAR)

	CombatResolver.dice_roller = saved_dice
	CombatResolver.crit_roller = saved_crit

	assert_true(result["is_crit"], "REAR attack should crit when roll_crit() < REAR_CRIT")


func test_resolve_attack_flank_crit_fires() -> void:
	## FLANK crit fires when roll_crit() < FLANK_CRIT (0.0625).
	var attacker := _make_unit("a", "playerA")
	var target := _make_unit("b", "playerB")
	target.current_hp = 50

	var saved_dice: Callable = CombatResolver.dice_roller
	var saved_crit: Callable = CombatResolver.crit_roller
	CombatResolver.dice_roller = func() -> int: return 3
	CombatResolver.crit_roller = func() -> float: return 0.0  # always crits

	var result := CombatResolver.resolve_attack(
		attacker, target, 0, 0, 0, 0, false,
		-1, -1, {}, Hex.Arc.FLANK)

	CombatResolver.dice_roller = saved_dice
	CombatResolver.crit_roller = saved_crit

	assert_true(result["is_crit"], "FLANK attack should crit when roll_crit() < FLANK_CRIT")


# --- resolve_damage: skill arc cases ---

func test_resolve_damage_skill_front_baseline() -> void:
	## FRONT: damage = max(1, die + value + 0 - def). Base crit_chance = 0.0625; roll=0.99 no crit.
	var attacker := _make_unit("a", "playerA")
	var target := _make_unit("b", "playerB")
	target.current_hp = 50

	var saved_dice: Callable = CombatResolver.dice_roller
	var saved_crit: Callable = CombatResolver.crit_roller
	CombatResolver.dice_roller = func() -> int: return 3
	CombatResolver.crit_roller = func() -> float: return 0.99  # no crit

	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, -1, 0.0, "", 0, {}, Hex.Arc.FRONT)

	CombatResolver.dice_roller = saved_dice
	CombatResolver.crit_roller = saved_crit

	# die(3) + value(4) + f(0) - def(2) = 5
	assert_eq(result["damage"], 5, "FRONT skill: no flank bonus")
	assert_false(result["is_crit"], "no crit with roll 0.99")


func test_resolve_damage_skill_rear_bonus() -> void:
	## REAR: damage adds REAR_HIT=2 to base.
	var attacker := _make_unit("a", "playerA")
	var target := _make_unit("b", "playerB")
	target.current_hp = 50

	var saved_dice: Callable = CombatResolver.dice_roller
	var saved_crit: Callable = CombatResolver.crit_roller
	CombatResolver.dice_roller = func() -> int: return 3
	CombatResolver.crit_roller = func() -> float: return 0.99  # no crit

	var front := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, -1, 0.0, "", 0, {}, Hex.Arc.FRONT)
	target.current_hp = 50
	var rear := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, -1, 0.0, "", 0, {}, Hex.Arc.REAR)

	CombatResolver.dice_roller = saved_dice
	CombatResolver.crit_roller = saved_crit

	assert_eq(rear["damage"], front["damage"] + 2, "REAR skill adds +2 damage")


func test_resolve_damage_spell_flank_bonus() -> void:
	## FLANK: damage adds FLANK_HIT=1 to spell base.
	var attacker := _make_unit("a", "playerA", 5, 2, 50, 4, 0)
	var target := _make_unit("b", "playerB", 3, 2, 50, 0, 1)
	target.current_hp = 50

	var saved_dice: Callable = CombatResolver.dice_roller
	var saved_crit: Callable = CombatResolver.crit_roller
	CombatResolver.dice_roller = func() -> int: return 3
	CombatResolver.crit_roller = func() -> float: return 0.99  # no crit

	var front := CombatResolver.resolve_damage(
		attacker, target, 2, "spell", 0, 0, -1, 1.0, "", 0, {}, Hex.Arc.FRONT)
	target.current_hp = 50
	var flank := CombatResolver.resolve_damage(
		attacker, target, 2, "spell", 0, 0, -1, 1.0, "", 0, {}, Hex.Arc.FLANK)

	CombatResolver.dice_roller = saved_dice
	CombatResolver.crit_roller = saved_crit

	# FLANK_HIT=1 bonus applied before affinity scaling (neutral=1.0)
	assert_eq(flank["damage"], front["damage"] + 1, "FLANK spell adds +1 damage")


func test_resolve_damage_rear_crit_additively_stacks() -> void:
	## REAR crit_chance = CRIT_CHANCE(0.0625) + REAR_CRIT(0.125) = 0.1875.
	## If roll = 0.15 -> crit fires (0.15 < 0.1875) but not base-only (0.15 > 0.0625).
	var attacker := _make_unit("a", "playerA")
	var target := _make_unit("b", "playerB")
	target.current_hp = 50

	var saved_dice: Callable = CombatResolver.dice_roller
	var saved_crit: Callable = CombatResolver.crit_roller
	CombatResolver.dice_roller = func() -> int: return 3
	CombatResolver.crit_roller = func() -> float: return 0.15

	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, -1, 0.0, "", 0, {}, Hex.Arc.REAR)

	CombatResolver.dice_roller = saved_dice
	CombatResolver.crit_roller = saved_crit

	assert_true(result["is_crit"],
		"Roll 0.15 < combined crit_chance (0.1875) for REAR should crit")


func test_resolve_damage_front_no_extra_crit_chance() -> void:
	## FRONT: crit_chance == CRIT_CHANCE only. Roll 0.15 -> no crit (0.15 > 0.0625).
	var attacker := _make_unit("a", "playerA")
	var target := _make_unit("b", "playerB")
	target.current_hp = 50

	var saved_dice: Callable = CombatResolver.dice_roller
	var saved_crit: Callable = CombatResolver.crit_roller
	CombatResolver.dice_roller = func() -> int: return 3
	CombatResolver.crit_roller = func() -> float: return 0.15

	var result := CombatResolver.resolve_damage(
		attacker, target, 4, "skill", 0, 0, -1, 0.0, "", 0, {}, Hex.Arc.FRONT)

	CombatResolver.dice_roller = saved_dice
	CombatResolver.crit_roller = saved_crit

	assert_false(result["is_crit"],
		"Roll 0.15 > CRIT_CHANCE (0.0625) for FRONT should NOT crit")
