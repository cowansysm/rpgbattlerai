class_name StatKey
extends RefCounted
## Canonical stat-key enum per rpg-specs.md §4.2.1.
## All stat-keyed dictionaries across the project validate against this enum.
## Single point of expansion when future stats are added.

enum Key { SPD, ATK, RNG, DEF, HP }

const KEYS := [Key.SPD, Key.ATK, Key.RNG, Key.DEF, Key.HP]

const _STRINGS: Dictionary = {
	Key.SPD: "spd",
	Key.ATK: "atk",
	Key.RNG: "rng",
	Key.DEF: "def",
	Key.HP: "hp",
}


static func to_string_key(k: int) -> String:
	return _STRINGS[k]


static func from_string(s: String) -> int:
	for k in _STRINGS.keys():
		if _STRINGS[k] == s:
			return k
	push_error("StatKey: unknown key '%s'" % s)
	return Key.SPD


static func all_strings() -> Array[String]:
	var out: Array[String] = []
	for k in KEYS:
		out.append(_STRINGS[k])
	return out


static func is_valid_key(s: String) -> bool:
	return s in _STRINGS.values()
