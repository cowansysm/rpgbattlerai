class_name BattleUnit
extends RefCounted
## Runtime wrapper separating immutable authored data from mutable per-battle state.
## Authored Resources (CharacterData, etc.) are never mutated post-load.
## All per-battle mutable state lives here.
## Spec reference: rpg-specs.md §9.6, phase1-spec.md §5.1

var character: CharacterData        ## Immutable authored data (read-only reference)
var stats: StatBlock                ## Own copy for runtime modifiers; initialized from load-time derivation
var position: Vector2i = Vector2i.ZERO
var current_hp: int = 0
var ap_remaining: int = 2
var is_activated: bool = false
var team: String = ""


static func from_character(c: CharacterData, final_stats: StatBlock) -> BattleUnit:
	var u := BattleUnit.new()
	u.character = c
	u.stats = final_stats.duplicate()
	u.current_hp = u.stats.effective(StatKey.to_string_key(StatKey.Key.HP))
	return u
