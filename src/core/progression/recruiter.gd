class_name Recruiter
extends RefCounted
## Generates new CharacterInstances for band recruitment.
## Spec reference: alpha-phaseA5-spec.md §6


## Recruits a new instance from a template into a band.
## Returns {instance: CharacterInstance, error: String}.
## On failure, instance is null and error describes the reason.
static func recruit(band: BattleBand, template: CharacterData,
		name_gen: Callable, cost: int = -1, cap: int = -1,
		bonus_classes: Array[String] = [],
		rng: RandomNumberGenerator = null) -> Dictionary:
	if cost < 0:
		cost = Constants.get_value("RECRUIT_COST", 50)
	if Dev.enabled and DevOverrides.get_flag("DEV_FREE_RECRUIT", false):
		cost = 0
	if band.gold < cost:
		return {"instance": null, "error": "Not enough gold (need %d, have %d)" % [cost, band.gold]}
	if band.is_roster_full(cap):
		return {"instance": null, "error": "Roster is full"}
	var ci: CharacterInstance = CharacterInstance.generate(template, name_gen, bonus_classes)
	# Recruits start skill-less (learn-via-JP) but arrive with a small random JP
	# pool in their starting class so the first turn is not dead. Tunable in constants.json.
	ci.gain_jp(ci.active_class, _roll_starting_jp(rng))
	band.gold -= cost
	band.add_instance(ci, cap)
	return {"instance": ci, "error": ""}


## Rolls the random starting-JP grant for a new recruit (inclusive range).
static func _roll_starting_jp(rng: RandomNumberGenerator = null) -> int:
	var lo: int = int(Constants.get_value("RECRUIT_STARTING_JP_MIN", 20))
	var hi: int = int(Constants.get_value("RECRUIT_STARTING_JP_MAX", 50))
	if hi < lo:
		hi = lo
	if rng != null:
		return rng.randi_range(lo, hi)
	return randi_range(lo, hi)


## Brings a recruit up to a target level by directly setting class levels.
## Useful for scaling new recruits to match a band's power level.
static func scale_to_level(ci: CharacterInstance, target_level: int,
		class_provider: Callable) -> void:
	if target_level <= ci.character_level():
		return
	var levels_to_gain: int = target_level - ci.character_level()
	for i in levels_to_gain:
		ci.increment_active_class_level(class_provider)


## Returns the average level of a band's roster, or 1 if empty.
static func average_band_level(band: BattleBand) -> int:
	if band.roster.is_empty():
		return 1
	var total: int = 0
	for ci in band.roster:
		total += ci.character_level()
	return maxi(1, total / band.roster.size())
