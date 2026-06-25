class_name DevCheatService
extends RefCounted
## Pure-logic cheat operations for dev-mode testing.
## All methods are static — no scene-tree dependency.
## Gated at the call site by Dev.enabled.


# ============================================================
# CHARACTER INSTANCE CHEATS
# ============================================================

## Sets the character to a target level by manipulating XP directly.
## Applies growth for levels gained (upleveling) but does NOT undo growth (downleveling).
static func set_level(ci: CharacterInstance, target_level: int,
		class_provider: Callable, max_level: int = 50, curve_base: int = 10) -> void:
	target_level = clampi(target_level, 1, max_level)
	if target_level > ci.level:
		# Grant enough XP to reach the target level
		var xp_needed: int = CharacterInstance.xp_for_level(target_level, curve_base) - ci.xp + 1
		if xp_needed > 0:
			ci.gain_xp(xp_needed, class_provider, max_level, curve_base)
	elif target_level < ci.level:
		# Downlevel: directly set level and XP (no growth undo)
		ci.level = target_level
		ci.xp = CharacterInstance.xp_for_level(target_level, curve_base)


## Adds XP via the standard gain_xp path. Returns levels gained.
static func add_xp(ci: CharacterInstance, amount: int,
		class_provider: Callable, max_level: int = 50, curve_base: int = 10) -> int:
	return ci.gain_xp(amount, class_provider, max_level, curve_base)


## Directly sets JP for a specific class.
static func set_jp(ci: CharacterInstance, class_id: String, amount: int) -> void:
	ci.jp[class_id] = maxi(0, amount)


## Adds JP to a specific class without requiring a battle.
static func add_jp(ci: CharacterInstance, class_id: String, amount: int) -> void:
	ci.gain_jp(class_id, amount)


## Sets JP to the given amount for all unlocked classes.
static func grant_all_jp(ci: CharacterInstance, amount: int) -> void:
	for class_id in ci.unlocked_classes:
		ci.jp[class_id] = maxi(0, amount)


## Unlocks a class without checking prerequisites. Idempotent.
static func force_unlock_class(ci: CharacterInstance, class_id: String) -> void:
	if not ci.unlocked_classes.has(class_id):
		ci.unlocked_classes.append(class_id)


## Unlocks all classes known to the data layer.
static func force_unlock_all_classes(ci: CharacterInstance, class_provider: Callable,
		all_class_ids: Array[String] = []) -> void:
	if all_class_ids.is_empty():
		# Fallback: use GameData if no explicit list
		for cid in GameData.all_classes():
			force_unlock_class(ci, cid)
	else:
		for cid in all_class_ids:
			force_unlock_class(ci, cid)


## Learns an ability without spending JP or checking class ownership.
static func force_learn_ability(ci: CharacterInstance, ability_id: String) -> void:
	if not ci.learned_abilities.has(ability_id):
		ci.learned_abilities.append(ability_id)


## Learns all abilities from all unlocked classes (reads jp_costs keys).
static func force_learn_all_abilities(ci: CharacterInstance, class_provider: Callable) -> void:
	for class_id in ci.unlocked_classes:
		var cls: ClassData = class_provider.call(class_id)
		if cls == null:
			continue
		for ability_id in cls.jp_costs.keys():
			force_learn_ability(ci, str(ability_id))


## Equips an item to a slot bypassing class access restrictions.
static func force_equip(ci: CharacterInstance, slot: String, item_id: String) -> void:
	ci.equipment[slot] = item_id


## Resets the down counter for the current run.
static func reset_downs(ci: CharacterInstance) -> void:
	ci.downs_this_run = 0


# ============================================================
# BAND CHEATS
# ============================================================

## Sets band gold to an exact amount.
static func set_gold(band: BattleBand, amount: int) -> void:
	band.gold = maxi(0, amount)


## Adds gold to a band (can be negative to subtract).
static func add_gold(band: BattleBand, amount: int) -> void:
	band.gold = maxi(0, band.gold + amount)


## Adds a single equipment item to band inventory.
static func add_item_to_inventory(band: BattleBand, item_id: String) -> void:
	band.add_to_inventory(item_id)


## Adds one of every equipment item to the band inventory.
static func add_all_items(band: BattleBand) -> void:
	for item_id in GameData.all_items():
		var item: ItemData = GameData.get_item(item_id)
		if item != null and not item.slot.is_empty():
			band.add_to_inventory(item_id)


## Recruits a character for free, bypassing gold check.
static func free_recruit(band: BattleBand, template: CharacterData,
		name_gen: Callable, cap: int = -1) -> Dictionary:
	return Recruiter.recruit(band, template, name_gen, 0, cap)


# ============================================================
# PROFILE / META-PROGRESSION CHEATS
# ============================================================

## Force-grants a meta unlock key to the profile.
static func grant_profile_unlock(profile: Profile, unlock_key: String) -> void:
	profile.grant_unlock(unlock_key)


## Force-unlocks a template in the profile.
static func grant_profile_template(profile: Profile, template_id: String) -> void:
	profile.grant_template(template_id)


## Force-unlocks a class in the profile.
static func grant_profile_class(profile: Profile, class_id: String) -> void:
	profile.grant_class(class_id)


## Sets completed_runs to an exact count.
static func set_completed_runs(profile: Profile, count: int) -> void:
	profile.completed_runs = maxi(0, count)


## Clears all profile unlocks and resets completed_runs to 0.
static func reset_profile(profile: Profile) -> void:
	profile.unlocked_templates.clear()
	profile.unlocked_classes.clear()
	profile.meta_unlocks.clear()
	profile.completed_runs = 0


# ============================================================
# COMBAT (BATTLEUNIT) CHEATS
# ============================================================

## Sets a unit's HP, clamped to [0, max_hp].
static func set_unit_hp(unit: BattleUnit, hp: int) -> void:
	var max_hp: int = unit.stats.effective("hp")
	unit.current_hp = clampi(hp, 0, max_hp)
	if unit.current_hp <= 0 and not unit.is_downed:
		unit.is_downed = true


## Sets a unit's WP, clamped to [0, max_wp].
static func set_unit_wp(unit: BattleUnit, wp: int) -> void:
	var max_wp: int = unit.stats.effective("wp")
	unit.current_wp = clampi(wp, 0, max_wp)


## Sets a unit's AP directly (no upper clamp — allows dev values).
static func set_unit_ap(unit: BattleUnit, ap: int) -> void:
	unit.ap_remaining = maxi(0, ap)


## Fully heals a unit (HP + WP to max, clears downed state).
static func heal_unit_full(unit: BattleUnit) -> void:
	unit.current_hp = unit.stats.effective("hp")
	unit.current_wp = unit.stats.effective("wp")
	if unit.is_downed:
		unit.is_downed = false
		unit.downed_round = -1


## Restores AP on a unit.
static func restore_ap(unit: BattleUnit, amount: int) -> void:
	unit.ap_remaining += amount


## Kills a unit by setting HP to 0 and marking as downed.
static func kill_unit(unit: BattleUnit, round_number: int = -1) -> void:
	unit.current_hp = 0
	unit.is_downed = true
	unit.downed_round = round_number


## Revives a downed unit with the given HP.
static func revive_unit(unit: BattleUnit, hp: int = -1) -> void:
	if hp < 0:
		hp = unit.stats.effective("hp")
	unit.is_downed = false
	unit.downed_round = -1
	unit.current_hp = clampi(hp, 1, unit.stats.effective("hp"))


## Pushes a stat modifier tagged with "dev_cheat" source.
static func push_dev_modifier(unit: BattleUnit, stat_key: String, value: int) -> void:
	unit.stats.push_modifier(StatModifier.new(stat_key, value, "dev_cheat"))


## Clears all dev-cheat stat modifiers from a unit.
static func clear_dev_modifiers(unit: BattleUnit) -> void:
	unit.stats.remove_modifiers_by_source("dev_cheat")


## Removes all status effects from a unit.
static func clear_all_statuses(unit: BattleUnit) -> void:
	unit.status_effects.clear()
	unit.stats.remove_modifiers_by_source("status")


## Forces a team to win by killing all units on the opposing team.
static func force_win(state: MatchState, winning_team: String) -> void:
	var losing_team: String = state.other_team(winning_team)
	for unit: BattleUnit in state.parties.get(losing_team, []):
		if unit.current_hp > 0 or unit.is_downed:
			unit.current_hp = 0
			unit.is_downed = false  # Permanently dead, not just downed
