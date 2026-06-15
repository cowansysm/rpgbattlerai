class_name StatBlock
extends RefCounted
## Stores base stat values plus a modifier stack for runtime changes.
## Effective values are computed on demand: base + sum(modifiers).
## Derived stat: move recomputes from effective SPD.

var _base: Dictionary = {}                   ## StatKey string -> int
var _modifiers: Array[StatModifier] = []


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


func has_modifier_from_source(source: String) -> bool:
	for m in _modifiers:
		if m.source == source:
			return true
	return false


func effective_move() -> int:
	return effective("spd")


func duplicate() -> StatBlock:
	var sb := StatBlock.new()
	sb._base = _base.duplicate()
	for m in _modifiers:
		sb._modifiers.append(StatModifier.new(m.key, m.value, m.source))
	return sb
