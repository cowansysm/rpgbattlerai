extends GutTest
## Tests for PartyDraft validation logic.
## Spec reference: phase7-spec.md §4


# --- Stub character provider ---

var _stub_characters: Dictionary = {}


func before_each() -> void:
	_stub_characters = {
		"cheap_a": _make_char("cheap_a", 10),
		"cheap_b": _make_char("cheap_b", 15),
		"mid_c": _make_char("mid_c", 30),
		"expensive_d": _make_char("expensive_d", 50),
		"expensive_e": _make_char("expensive_e", 60),
		"filler_f": _make_char("filler_f", 5),
		"filler_g": _make_char("filler_g", 5),
		"filler_h": _make_char("filler_h", 5),
	}


func _stub_provider(id: String) -> CharacterData:
	return _stub_characters.get(id, null)


func _make_char(id: String, bp: int) -> CharacterData:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.bp = bp
	c.base_stats = {}
	c.classes = []
	c.equipment = []
	c.abilities = []
	return c


func _make_draft(bp_cap: int = 100, min_chars: int = 3, max_chars: int = 5) -> PartyDraft:
	var config := {"bp_cap": bp_cap, "min": min_chars, "max": max_chars}
	return PartyDraft.new(config, _stub_provider)


# --- Add character tests ---

func test_add_character_succeeds() -> void:
	var draft := _make_draft()
	var err := draft.add_character("cheap_a")
	assert_eq(err, "")
	assert_eq(draft.party_size(), 1)
	assert_eq(draft.total_bp(), 10)


func test_add_multiple_characters() -> void:
	var draft := _make_draft()
	draft.add_character("cheap_a")
	draft.add_character("cheap_b")
	assert_eq(draft.party_size(), 2)
	assert_eq(draft.total_bp(), 25)


func test_add_character_exceeding_bp_cap_fails() -> void:
	var draft := _make_draft(50)
	draft.add_character("mid_c")		# 30 BP
	var err := draft.add_character("expensive_d")	# 30 + 50 = 80 > 50
	assert_ne(err, "")
	assert_eq(draft.party_size(), 1)
	assert_eq(draft.total_bp(), 30)


func test_add_duplicate_character_fails() -> void:
	var draft := _make_draft()
	draft.add_character("cheap_a")
	var err := draft.add_character("cheap_a")
	assert_ne(err, "")
	assert_eq(draft.party_size(), 1)


func test_add_at_max_size_fails() -> void:
	var draft := _make_draft(200, 1, 3)
	draft.add_character("cheap_a")
	draft.add_character("cheap_b")
	draft.add_character("filler_f")
	var err := draft.add_character("filler_g")
	assert_ne(err, "")
	assert_eq(draft.party_size(), 3)


func test_add_nonexistent_character_fails() -> void:
	var draft := _make_draft()
	var err := draft.add_character("nonexistent")
	assert_ne(err, "")
	assert_eq(draft.party_size(), 0)


# --- Remove character tests ---

func test_remove_character_updates_state() -> void:
	var draft := _make_draft()
	draft.add_character("cheap_a")
	draft.add_character("cheap_b")
	var err := draft.remove_character("cheap_a")
	assert_eq(err, "")
	assert_eq(draft.party_size(), 1)
	assert_eq(draft.total_bp(), 15)


func test_remove_nonexistent_character_fails() -> void:
	var draft := _make_draft()
	var err := draft.remove_character("cheap_a")
	assert_ne(err, "")


# --- Validation tests ---

func test_is_valid_when_meets_requirements() -> void:
	var draft := _make_draft(100, 3, 5)
	draft.add_character("cheap_a")		# 10
	draft.add_character("cheap_b")		# 15
	assert_false(draft.is_valid())		# only 2, need 3
	draft.add_character("mid_c")		# 30, total 55, 3 chars
	assert_true(draft.is_valid())


func test_is_valid_false_when_below_min() -> void:
	var draft := _make_draft(100, 3, 5)
	draft.add_character("cheap_a")
	assert_false(draft.is_valid())


func test_can_add_reflects_rules() -> void:
	var draft := _make_draft(50, 1, 3)
	assert_true(draft.can_add("cheap_a"))		# 10 <= 50, not in party
	draft.add_character("cheap_a")
	assert_false(draft.can_add("cheap_a"))		# already in party
	assert_true(draft.can_add("cheap_b"))		# 10+15 = 25 <= 50
	assert_false(draft.can_add("expensive_d"))	# 10+50 = 60 > 50
	assert_false(draft.can_add("nonexistent"))	# not found


func test_can_add_false_at_max_size() -> void:
	var draft := _make_draft(200, 1, 2)
	draft.add_character("cheap_a")
	draft.add_character("cheap_b")
	assert_false(draft.can_add("filler_f"))


func test_can_add_false_after_confirm() -> void:
	var draft := _make_draft(200, 1, 5)
	draft.add_character("cheap_a")
	draft.confirm()
	assert_false(draft.can_add("cheap_b"))


# --- BP tracking tests ---

func test_remaining_bp_tracks_budget() -> void:
	var draft := _make_draft(100, 1, 5)
	assert_eq(draft.remaining_bp(), 100)
	draft.add_character("mid_c")		# 30
	assert_eq(draft.remaining_bp(), 70)
	draft.remove_character("mid_c")
	assert_eq(draft.remaining_bp(), 100)


func test_bp_cap_returns_tier_cap() -> void:
	var draft := _make_draft(150, 4, 8)
	assert_eq(draft.bp_cap(), 150)


func test_min_max_characters() -> void:
	var draft := _make_draft(100, 3, 5)
	assert_eq(draft.min_characters(), 3)
	assert_eq(draft.max_characters(), 5)


# --- Confirm tests ---

func test_confirm_when_valid_succeeds() -> void:
	var draft := _make_draft(100, 3, 5)
	draft.add_character("cheap_a")
	draft.add_character("cheap_b")
	draft.add_character("filler_f")
	var err := draft.confirm()
	assert_eq(err, "")
	assert_eq(draft.state(), PartyDraft.State.CONFIRMED)


func test_confirm_when_below_min_fails() -> void:
	var draft := _make_draft(100, 3, 5)
	draft.add_character("cheap_a")
	var err := draft.confirm()
	assert_ne(err, "")
	assert_ne(draft.state(), PartyDraft.State.CONFIRMED)


func test_skirmish_min_2_party_confirms_successfully() -> void:
	# Boundary: a 2-character party is valid when tier min = 2 (skirmish)
	var draft := _make_draft(100, 2, 5)
	draft.add_character("cheap_a")
	draft.add_character("cheap_b")
	var err := draft.confirm()
	assert_eq(err, "")
	assert_eq(draft.state(), PartyDraft.State.CONFIRMED)


func test_skirmish_min_2_single_character_rejected() -> void:
	# Boundary: a 1-character party is invalid when tier min = 2
	var draft := _make_draft(100, 2, 5)
	draft.add_character("cheap_a")
	var err := draft.confirm()
	assert_ne(err, "")
	assert_true(err.contains("at least 2"))
	assert_ne(draft.state(), PartyDraft.State.CONFIRMED)


func test_skirmish_min_2_empty_party_rejected() -> void:
	# Boundary: a 0-character party is invalid when tier min = 2
	var draft := _make_draft(100, 2, 5)
	var err := draft.confirm()
	assert_ne(err, "")
	assert_ne(draft.state(), PartyDraft.State.CONFIRMED)


func test_confirm_twice_fails() -> void:
	var draft := _make_draft(100, 1, 5)
	draft.add_character("cheap_a")
	draft.confirm()
	var err := draft.confirm()
	assert_ne(err, "")


func test_add_after_confirm_fails() -> void:
	var draft := _make_draft(100, 3, 5)
	draft.add_character("cheap_a")
	draft.add_character("cheap_b")
	draft.add_character("filler_f")
	draft.confirm()
	var err := draft.add_character("filler_g")
	assert_ne(err, "")
	assert_eq(draft.party_size(), 3)


func test_remove_after_confirm_fails() -> void:
	var draft := _make_draft(100, 3, 5)
	draft.add_character("cheap_a")
	draft.add_character("cheap_b")
	draft.add_character("filler_f")
	draft.confirm()
	var err := draft.remove_character("cheap_a")
	assert_ne(err, "")
	assert_eq(draft.party_size(), 3)


func test_confirmed_ids_empty_before_confirm() -> void:
	var draft := _make_draft(100, 1, 5)
	draft.add_character("cheap_a")
	assert_true(draft.confirmed_ids().is_empty())


func test_confirmed_ids_returns_selected_after_confirm() -> void:
	var draft := _make_draft(100, 1, 5)
	draft.add_character("cheap_a")
	draft.add_character("cheap_b")
	draft.confirm()
	var ids := draft.confirmed_ids()
	assert_eq(ids.size(), 2)
	assert_true("cheap_a" in ids)
	assert_true("cheap_b" in ids)


# --- State transition tests ---

func test_state_transitions() -> void:
	var draft := _make_draft(100, 2, 4)
	assert_eq(draft.state(), PartyDraft.State.EMPTY)
	draft.add_character("cheap_a")
	assert_eq(draft.state(), PartyDraft.State.DRAFTING)		# 1 < min 2
	draft.add_character("cheap_b")
	assert_eq(draft.state(), PartyDraft.State.VALID)		# 2 >= min 2
	draft.remove_character("cheap_b")
	assert_eq(draft.state(), PartyDraft.State.DRAFTING)		# back to 1
	draft.add_character("cheap_b")
	draft.confirm()
	assert_eq(draft.state(), PartyDraft.State.CONFIRMED)


func test_selected_ids_returns_copy() -> void:
	var draft := _make_draft()
	draft.add_character("cheap_a")
	var ids := draft.selected_ids()
	ids.append("tampered")
	assert_eq(draft.party_size(), 1, "modifying returned array should not affect draft")
