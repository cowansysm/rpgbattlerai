class_name Leveling
extends RefCounted
## XP threshold computation and level-up service.
## Replaces the removed CharacterInstance.gain_xp() with a stateless service.
## character_level = sum of class levels (defined by CharacterInstance).
## One XP curve keyed by total character level; levels the active class.
## Spec reference: alpha-phaseA11-spec.md §3.5


## XP threshold for the next level, keyed by total character level.
## Formula: XP_CURVE_BASE * character_level * (character_level + 1)
static func next_threshold(char_level: int) -> int:
	var base: int = int(Constants.get_value("XP_CURVE_BASE", 10))
	return base * char_level * (char_level + 1)


## Grants XP to a CharacterInstance. Levels up the active class on threshold
## crossings (respecting per-class cap). Discards overflow XP when the active
## class is at max level. Returns the number of levels gained.
static func grant_xp(ci: CharacterInstance, amount: int,
		class_provider: Callable, max_level: int = 10) -> int:
	ci.xp += amount
	var levels_gained: int = 0
	while ci.active_class_level() < max_level:
		var threshold: int = next_threshold(ci.character_level())
		if ci.xp < threshold:
			break
		ci.xp -= threshold
		if ci.increment_active_class_level(class_provider, max_level):
			levels_gained += 1
		else:
			break
	# Overflow XP discarded when active class at cap
	if ci.active_class_level() >= max_level:
		ci.xp = 0
	return levels_gained
