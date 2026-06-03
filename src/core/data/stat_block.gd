class_name StatBlock
extends RefCounted
## Stores base stat values plus a modifier stack for runtime changes.
## Effective values are computed on demand: base + sum(modifiers).
## Derived stats (move, jump_climb) recompute from effective values.

var _base: Dictionary = {}                   ## StatKey string -> int
var _modifiers: Array[StatModifier] = []
var _jump_climb_bonus: int = 0               ## Class-derived (e.g., Rogue)


func set_base(key: String, value: int) -> void:
	_base[key] = value


func base(key: String) -> int:
	return int(_base.get(key, 0))


func effective(key: String) -> int:
	var v: int = base(key)
	for m in _modifiers:
		if m.key == key:
			v += m.value
	return v


func push_modifier(m: StatModifier) -> void:
	_modifiers.append(m)


func remove_modifiers_by_source(source: String) -> void:
	_modifiers = _modifiers.filter(func(m: StatModifier) -> bool: return m.source != source)


func set_jump_climb_bonus(bonus: int) -> void:
	_jump_climb_bonus = bonus


func effective_move() -> int:
	return effective("spd")


func effective_jump_climb() -> int:
	return int(floor(effective("spd") / 2.0)) + 1 + _jump_climb_bonus


func duplicate() -> StatBlock:
	var sb := StatBlock.new()
	sb._base = _base.duplicate()
	sb._jump_climb_bonus = _jump_climb_bonus
	for m in _modifiers:
		sb._modifiers.append(StatModifier.new(m.key, m.value, m.source))
	return sb
