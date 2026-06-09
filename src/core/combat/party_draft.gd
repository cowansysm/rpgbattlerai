class_name PartyDraft
extends RefCounted
## Manages the draft state for a single player.
## Validates character additions against tier BP cap, size bounds,
## and duplicate rules. Fully headless — no UI dependency.
## Spec reference: phase7-spec.md §4

enum State { EMPTY, DRAFTING, VALID, CONFIRMED }

var _tier_config: Dictionary			# {bp_cap: int, min: int, max: int}
var _character_provider: Callable		# (String) -> CharacterData
var _selected: Array[String] = []
var _total_bp: int = 0
var _confirmed: bool = false


func _init(tier_config: Dictionary, character_provider: Callable) -> void:
	_tier_config = tier_config
	_character_provider = character_provider


func state() -> State:
	if _confirmed:
		return State.CONFIRMED
	if _selected.is_empty():
		return State.EMPTY
	if is_valid():
		return State.VALID
	return State.DRAFTING


func selected_ids() -> Array[String]:
	return _selected.duplicate()


func party_size() -> int:
	return _selected.size()


func total_bp() -> int:
	return _total_bp


func remaining_bp() -> int:
	return int(_tier_config["bp_cap"]) - _total_bp


func bp_cap() -> int:
	return int(_tier_config["bp_cap"])


func min_characters() -> int:
	return int(_tier_config["min"])


func max_characters() -> int:
	return int(_tier_config["max"])


func is_valid() -> bool:
	return (
		_selected.size() >= int(_tier_config["min"])
		and _selected.size() <= int(_tier_config["max"])
		and _total_bp <= int(_tier_config["bp_cap"])
	)


func can_add(character_id: String) -> bool:
	if _confirmed:
		return false
	if character_id in _selected:
		return false
	if _selected.size() >= int(_tier_config["max"]):
		return false
	var c: CharacterData = _character_provider.call(character_id)
	if not c:
		return false
	return _total_bp + c.bp <= int(_tier_config["bp_cap"])


func add_character(character_id: String) -> String:
	if _confirmed:
		return "Draft is already confirmed"
	if character_id in _selected:
		return "Character '%s' is already in the party" % character_id
	if _selected.size() >= int(_tier_config["max"]):
		return "Party is at maximum size (%d)" % int(_tier_config["max"])
	var c: CharacterData = _character_provider.call(character_id)
	if not c:
		return "Character '%s' not found" % character_id
	if _total_bp + c.bp > int(_tier_config["bp_cap"]):
		return "Adding '%s' (%d BP) would exceed BP cap (%d/%d)" % [
			character_id, c.bp, _total_bp + c.bp, int(_tier_config["bp_cap"])]
	_selected.append(character_id)
	_total_bp += c.bp
	return ""


func remove_character(character_id: String) -> String:
	if _confirmed:
		return "Draft is already confirmed"
	var idx := _selected.find(character_id)
	if idx < 0:
		return "Character '%s' is not in the party" % character_id
	var c: CharacterData = _character_provider.call(character_id)
	if c:
		_total_bp -= c.bp
	_selected.remove_at(idx)
	return ""


func confirm() -> String:
	if _confirmed:
		return "Draft is already confirmed"
	if not is_valid():
		if _selected.size() < int(_tier_config["min"]):
			return "Party needs at least %d characters (has %d)" % [
				int(_tier_config["min"]), _selected.size()]
		if _total_bp > int(_tier_config["bp_cap"]):
			return "Party BP (%d) exceeds cap (%d)" % [
				_total_bp, int(_tier_config["bp_cap"])]
		return "Party is not valid"
	_confirmed = true
	return ""


func confirmed_ids() -> Array[String]:
	if not _confirmed:
		return []
	return _selected.duplicate()
