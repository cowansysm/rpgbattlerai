extends GutTest
## A18: Tests for support passives — Magic Up raises spell damage; Half WP halves cost.

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

func _make_support_ability(id: String, mod_kind: String, stat: String = "",
		value: float = 0.0) -> AbilityData:
	var ab := AbilityData.new()
	ab.id = id
	ab.type = "passive"
	ab.passive_kind = "support"
	ab.trigger = {}
	var mod: Dictionary = {"kind": mod_kind}
	if not stat.is_empty():
		mod["stat"] = stat
	if value != 0.0:
		mod["value"] = value
	ab.modifier = mod
	return ab


func _ability_provider(ab_id: String) -> AbilityData:
	match ab_id:
		"magic_up":
			return _make_support_ability("magic_up", "stat", "mag", 2.0)
		"attack_up":
			return _make_support_ability("attack_up", "stat", "atk", 2.0)
		"half_wp":
			return _make_support_ability("half_wp", "wp_mult", "", 0.5)
	return null


func _make_cd(id: String, support: String = "") -> CharacterData:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.classes = []
	c.equipment = []
	c.abilities = []
	c.reaction_passive = ""
	c.support_passive = support
	c.movement_passive = ""
	return c


func _make_sb(mag: int = 0, atk: int = 0, def_val: int = 0, hp: int = 20,
		wp: int = 10, rng: int = 0, spd: int = 3) -> StatBlock:
	var sb := StatBlock.new()
	sb.set_base("mag", mag)
	sb.set_base("atk", atk)
	sb.set_base("def", def_val)
	sb.set_base("hp", hp)
	sb.set_base("wp", wp)
	sb.set_base("rng", rng)
	sb.set_base("spd", spd)
	sb.set_base("jump", 1)
	return sb


# --- Magic Up support passive ---

func test_magic_up_increases_effective_mag() -> void:
	var c := _make_cd("mage", "magic_up")
	var sb := _make_sb(4)  # base MAG = 4
	var unit := BattleUnit.from_character(c, sb, _ability_provider)

	# Magic Up adds +2 MAG at construction time
	assert_eq(unit.stats.effective("mag"), 6)


func test_magic_up_raises_spell_damage() -> void:
	## Spell damage = atk_roll + effect_value + mag_bonus - res
	## With die=3, effect_value=5, mag=4 (no magic_up): base = 3+5+4-0 = 12
	## With die=3, effect_value=5, mag=6 (magic_up +2):   base = 3+5+6-0 = 14
	var caster_no_passive_cd := _make_cd("caster_base")
	var caster_passive_cd := _make_cd("caster_boost", "magic_up")
	var target_cd := _make_cd("target")

	var sb_caster := _make_sb(4, 0, 0, 20, 10)
	var sb_target := _make_sb(0, 0, 0, 50, 0)

	var caster_base := BattleUnit.from_character(caster_no_passive_cd, sb_caster)
	var caster_boost := BattleUnit.from_character(caster_passive_cd, sb_caster, _ability_provider)
	var target_base := BattleUnit.from_character(target_cd, sb_target)
	var target_boost := BattleUnit.from_character(target_cd, sb_target)

	var result_base := CombatResolver.resolve_damage(
		caster_base, target_base, 5, "spell", 0, 0, -1, 1.0)
	var result_boost := CombatResolver.resolve_damage(
		caster_boost, target_boost, 5, "spell", 0, 0, -1, 1.0)

	assert_true(result_boost["damage"] > result_base["damage"],
		"Magic Up should increase spell damage")
	assert_eq(result_boost["damage"] - result_base["damage"], 2)


# --- Half WP support passive ---

func test_half_wp_sets_wp_cost_mult() -> void:
	var c := _make_cd("caster", "half_wp")
	var sb := _make_sb(0, 0, 0, 20, 10)
	var unit := BattleUnit.from_character(c, sb, _ability_provider)

	assert_eq(unit.wp_cost_mult, 0.5)


func test_half_wp_halves_ability_wp_cost_in_execute_ability() -> void:
	## Build a state with a caster that has half_wp and a 4-WP ability
	var caster_cd := _make_cd("caster", "half_wp")
	var target_cd := _make_cd("target")
	var sb_caster := _make_sb(0, 3, 0, 20, 10)
	var sb_target := _make_sb(0, 0, 1, 20, 0)

	var caster := BattleUnit.from_character(caster_cd, sb_caster, _ability_provider)
	var target := BattleUnit.from_character(target_cd, sb_target)
	caster.team = "a"
	target.team = "b"
	caster.position = Vector2i(0, 0)
	target.position = Vector2i(1, 0)

	# Ability with wp_cost = 4
	var ab := AbilityData.new()
	ab.id = "test_spell"
	ab.type = "spell"
	ab.passive_kind = ""
	ab.ap_cost = 1
	ab.wp_cost = 4
	ab.ability_range = 2
	ab.mag_scaling = 1.0
	ab.effect = {"effect_type": "damage", "value": 5}
	ab.effect_type = "damage"

	var map := MapData.new()
	map.id = "t"
	map.tiles = [TileRecord.new(0, 0, 0, "grass"), TileRecord.new(1, 0, 0, "grass")]
	map.deployment_zones = {}
	var tp := func(_id: String) -> TerrainProps: return null
	var state := MatchSetup.create([caster], [target], map, tp)
	state.occupancy[Vector2i(0, 0)] = caster
	state.occupancy[Vector2i(1, 0)] = target
	state.current_unit = caster
	caster.ap_remaining = 2

	state.ability_provider = func(_unit: BattleUnit, ab_id: String) -> AbilityData:
		if ab_id == "test_spell":
			return ab
		return null

	# Initial WP = 10, half_wp -> effective cost = floor(4 * 0.5) = 2
	var result := TurnActions.execute_ability(state, "test_spell", Vector2i(1, 0))
	assert_false(result.has("error"), "execute_ability should succeed with half WP")
	# Only 2 WP should have been deducted
	assert_eq(caster.current_wp, 10 - 2)


func test_half_wp_insufficient_still_blocks() -> void:
	## Even with Half WP, if caster has only 1 WP and cost is 4 (halved to 2), still blocked
	var caster_cd := _make_cd("caster", "half_wp")
	var target_cd := _make_cd("target")
	var sb_caster := _make_sb(0, 3, 0, 20, 1)  # wp=1
	var sb_target := _make_sb(0, 0, 1, 20, 0)

	var caster := BattleUnit.from_character(caster_cd, sb_caster, _ability_provider)
	var target := BattleUnit.from_character(target_cd, sb_target)
	caster.team = "a"
	target.team = "b"
	caster.position = Vector2i(0, 0)
	target.position = Vector2i(1, 0)

	var ab := AbilityData.new()
	ab.id = "big_spell"
	ab.type = "spell"
	ab.passive_kind = ""
	ab.ap_cost = 1
	ab.wp_cost = 4  # halved to 2, but caster only has 1
	ab.ability_range = 2
	ab.mag_scaling = 1.0
	ab.effect = {"effect_type": "damage", "value": 5}
	ab.effect_type = "damage"

	var map := MapData.new()
	map.id = "t"
	map.tiles = [TileRecord.new(0, 0, 0, "grass"), TileRecord.new(1, 0, 0, "grass")]
	map.deployment_zones = {}
	var tp := func(_id: String) -> TerrainProps: return null
	var state := MatchSetup.create([caster], [target], map, tp)
	state.occupancy[Vector2i(0, 0)] = caster
	state.occupancy[Vector2i(1, 0)] = target
	state.current_unit = caster
	caster.ap_remaining = 2

	state.ability_provider = func(_unit: BattleUnit, ab_id: String) -> AbilityData:
		if ab_id == "big_spell":
			return ab
		return null

	var result := TurnActions.execute_ability(state, "big_spell", Vector2i(1, 0))
	assert_true(result.has("error"), "Should fail: 1 WP < 2 (halved cost)")
