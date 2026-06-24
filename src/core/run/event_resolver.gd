class_name EventResolver
extends RefCounted
## Resolves event, boon, and hazard node outcomes from data/events.json.
## Applies effects to the band's instances. Intentionally simple per spec.


## Resolves a random event/boon/hazard of the given kind.
## Returns {event: Dictionary, effects_applied: Array[String]}.
static func resolve(kind: String, rng: RandomNumberGenerator,
		band: BattleBand, events_data: Dictionary) -> Dictionary:
	var pool: Array = events_data.get(_pool_key(kind), []) as Array
	if pool.is_empty():
		return {"event": {}, "effects_applied": []}
	var event: Dictionary = pool[rng.randi_range(0, pool.size() - 1)] as Dictionary
	var effects: Array = _get_effects(event)
	var applied: Array[String] = _apply_effects(effects, band, rng)
	return {"event": event, "effects_applied": applied}


## Resolves a specific choice for an event with choices.
## choice_index selects which choice's effects to apply.
static func resolve_choice(event: Dictionary, choice_index: int,
		band: BattleBand, rng: RandomNumberGenerator) -> Array[String]:
	var choices: Array = event.get("choices", []) as Array
	if choice_index < 0 or choice_index >= choices.size():
		return []
	var effects: Array = (choices[choice_index] as Dictionary).get("effects", []) as Array
	return _apply_effects(effects, band, rng)


static func _pool_key(kind: String) -> String:
	match kind:
		"event": return "events"
		"boon": return "boons"
		"hazard": return "hazards"
		_: return kind


static func _get_effects(event: Dictionary) -> Array:
	if event.has("effects"):
		return event["effects"] as Array
	# For events with choices, return the first choice's effects as default
	if event.has("choices"):
		var choices: Array = event["choices"] as Array
		if not choices.is_empty():
			return (choices[0] as Dictionary).get("effects", []) as Array
	return []


static func _apply_effects(effects: Array, band: BattleBand,
		rng: RandomNumberGenerator) -> Array[String]:
	var applied: Array[String] = []
	for effect in effects:
		if not effect is Dictionary:
			continue
		var e: Dictionary = effect as Dictionary
		var etype: String = str(e.get("type", ""))
		match etype:
			"gold":
				var val: int = int(e.get("value", 0))
				band.gold = maxi(0, band.gold + val)
				if val >= 0:
					applied.append("Gained %d gold" % val)
				else:
					applied.append("Lost %d gold" % absi(val))
			"item":
				var item_id: String = str(e.get("item_id", ""))
				var qty: int = int(e.get("qty", 1))
				if not item_id.is_empty():
					band.add_consumable(item_id, qty)
					applied.append("Received %d x %s" % [qty, item_id])
			"heal_all":
				var healed: int = 0
				for ci in band.roster:
					if ci.downs_this_run > 0:
						ci.downs_this_run = maxi(0, ci.downs_this_run - 1)
						healed += 1
				if healed > 0:
					applied.append("Reduced downs for %d character(s)" % healed)
				else:
					applied.append("Band is already healthy")
			"damage_all":
				for ci in band.roster:
					ci.downs_this_run += 1
				applied.append("All characters injured (+1 down each)")
			"damage_random":
				if not band.roster.is_empty():
					var idx: int = rng.randi_range(0, band.roster.size() - 1)
					band.roster[idx].downs_this_run += 1
					applied.append("%s was injured (+1 down)" % band.roster[idx].name)
			"xp":
				var val: int = int(e.get("value", 0))
				for ci in band.roster:
					ci.xp += val
				applied.append("Gained %d XP each" % val)
	return applied
