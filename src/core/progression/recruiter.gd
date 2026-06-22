class_name Recruiter
extends RefCounted
## Generates new CharacterInstances for band recruitment.
## Spec reference: alpha-phaseA5-spec.md §6


## Recruits a new instance from a template into a band.
## Returns {instance: CharacterInstance, error: String}.
## On failure, instance is null and error describes the reason.
static func recruit(band: BattleBand, template: CharacterData,
		name_gen: Callable, cost: int = -1, cap: int = -1) -> Dictionary:
	if cost < 0:
		cost = Constants.get_value("RECRUIT_COST", 50)
	if band.gold < cost:
		return {"instance": null, "error": "Not enough gold (need %d, have %d)" % [cost, band.gold]}
	if band.is_roster_full(cap):
		return {"instance": null, "error": "Roster is full"}
	var ci: CharacterInstance = CharacterInstance.generate(template, name_gen)
	band.gold -= cost
	band.add_instance(ci, cap)
	return {"instance": ci, "error": ""}


## Brings a recruit up to a target level by granting XP.
## Useful for scaling new recruits to match a band's power level.
static func scale_to_level(ci: CharacterInstance, target_level: int,
		class_provider: Callable) -> void:
	if target_level <= ci.level:
		return
	# Grant enough XP to reach target level
	var xp_needed: int = CharacterInstance.xp_for_level(target_level) - ci.xp + 1
	if xp_needed > 0:
		ci.gain_xp(xp_needed, class_provider)


## Returns the average level of a band's roster, or 1 if empty.
static func average_band_level(band: BattleBand) -> int:
	if band.roster.is_empty():
		return 1
	var total: int = 0
	for ci in band.roster:
		total += ci.level
	return maxi(1, total / band.roster.size())
