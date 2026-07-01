class_name Recruiter
extends RefCounted
## Generates new CharacterInstances for band recruitment.
## Spec reference: alpha-phaseA5-spec.md §6


## Recruits a new instance from a template into a band.
## Returns {instance: CharacterInstance, error: String}.
## On failure, instance is null and error describes the reason.
static func recruit(band: BattleBand, template: CharacterData,
		name_gen: Callable, cost: int = -1, cap: int = -1,
		bonus_classes: Array[String] = []) -> Dictionary:
	if cost < 0:
		cost = Constants.get_value("RECRUIT_COST", 50)
	if Dev.enabled and DevOverrides.get_flag("DEV_FREE_RECRUIT", false):
		cost = 0
	if band.gold < cost:
		return {"instance": null, "error": "Not enough gold (need %d, have %d)" % [cost, band.gold]}
	if band.is_roster_full(cap):
		return {"instance": null, "error": "Roster is full"}
	var ci: CharacterInstance = CharacterInstance.generate(template, name_gen, bonus_classes)
	band.gold -= cost
	band.add_instance(ci, cap)
	return {"instance": ci, "error": ""}


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
