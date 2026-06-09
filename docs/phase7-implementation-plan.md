# Phase 7 — Implementation Plan

**Source spec:** `phase7-spec.md`
**Builds on:** `phase0` (hex math), `phase1` (data layer, `BattleUnit`, `StatBlock`), `phase2` (map rendering), `phase3` (movement, range, LoS), `phase4` (activation loop, deployment, `MatchSetup`, `RoundManager`), `phase5` (combat resolution, `CombatResolver`), `phase6` (8 characters, 6 maps, validated content)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages, order-flexible within groups; cross-group dependencies noted.
**Date:** 2026-06-09

---

## How to use this plan

Five **work groups** (A--E). Within a group, tasks can be done in any order unless noted. Across groups: **A** (PartyDraft logic) is the foundation; **B** (MatchBuilder orchestration) needs A; **C** (GameData extension) is independent; **D** (UI scene) needs A + B + C; **E** (tests) trails the logic and UI.

Phase 7 is split evenly between **headless logic** (A, B — pure GDScript classes with no Node/scene dependency) and **UI** (D — Godot Control scene). The logic layer is built and tested first; the UI consumes it.

> **Carry-over:** consumes `MatchSetup`, `Deployment`, `RoundManager`, `MatchState`, `TurnActions`, `CombatResolver`, `AbilityResolver` from Phases 4--5; `BattleUnit`, `CharacterData`, `StatBlock`, `MapData`, `GameData`, `Constants` from Phases 0--1; `MapBuilder`, `OverlayController` from Phase 2; 8 characters, 6 maps from Phase 6.

---

## Group A — PartyDraft (Core Logic)

*Foundation. No dependencies beyond Phase 1 data types and Constants autoload.*

### A1. `PartyDraft` class — draft state and validation

- Holds the selected character IDs for one player's draft.
- Tracks total BP, party size, and draft state.
- Validates additions against tier config (BP cap, max count, no self-duplicates).
- Reports whether the draft is valid (meets min count and BP ≤ cap).
- **Done:** can add/remove characters, enforce all validation rules, confirm a draft.

```gdscript
# src/core/combat/party_draft.gd
class_name PartyDraft
extends RefCounted

## Manages the draft state for a single player.
## Validates character additions against tier BP cap, size bounds,
## and duplicate rules. Fully headless — no UI dependency.

enum State { EMPTY, DRAFTING, VALID, CONFIRMED }

var _tier_config: Dictionary         # {bp_cap: int, min: int, max: int}
var _character_provider: Callable    # (String) -> CharacterData
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
```

---

## Group B — MatchBuilder (Orchestration)

*Depends on A. Orchestrates tier config, map selection, and match construction.*

### B1. `GameData.all_maps()` accessor

- Add `all_maps() -> Array` to `GameData`, delegating to `_pipeline.maps.all()`.
- Required for map filtering by tier in MatchBuilder.
- **Done:** `GameData.all_maps()` returns all loaded MapData entries.

```gdscript
# Addition to src/autoload/game_data.gd

func all_maps() -> Array:
    return _pipeline.maps.all()
```

### B2. `MatchBuilder` class — match construction

- Loads tier config from Constants.
- Filters maps by tier.
- Selects a random map.
- Creates BattleUnit arrays from confirmed draft IDs.
- Calls MatchSetup, wires providers, runs Deployment, starts round 1.
- Returns a ready-to-play MatchState or error list.
- **Done:** full match construction from two confirmed drafts.

```gdscript
# src/core/combat/match_builder.gd
class_name MatchBuilder
extends RefCounted

## Orchestrates match construction from two confirmed PartyDrafts.
## Handles tier config, map selection, BattleUnit creation, and
## wiring of MatchSetup/Deployment/RoundManager.

var _character_provider: Callable   # (String) -> CharacterData
var _stats_provider: Callable       # (String) -> StatBlock
var _map_provider: Callable         # (String) -> MapData
var _all_maps_provider: Callable    # () -> Array of MapData
var _terrain_provider: Callable     # (String) -> TerrainProps
var _ability_getter: Callable       # (String) -> AbilityData
var _class_getter: Callable         # (String) -> ClassData
var _item_getter: Callable          # (String) -> ItemData


func _init(
    character_provider: Callable,
    stats_provider: Callable,
    map_provider: Callable,
    all_maps_provider: Callable,
    terrain_provider: Callable,
    ability_getter: Callable,
    class_getter: Callable,
    item_getter: Callable,
) -> void:
    _character_provider = character_provider
    _stats_provider = stats_provider
    _map_provider = map_provider
    _all_maps_provider = all_maps_provider
    _terrain_provider = terrain_provider
    _ability_getter = ability_getter
    _class_getter = class_getter
    _item_getter = item_getter


## Returns tier config dict {bp_cap, min, max} or empty dict if invalid.
func get_tier_config(tier_id: String) -> Dictionary:
    var tiers: Dictionary = Constants.get_value("tiers")
    if not tiers or not tiers.has(tier_id):
        return {}
    return tiers[tier_id]


## Returns available tier IDs.
func get_tier_ids() -> Array[String]:
    var tiers: Dictionary = Constants.get_value("tiers")
    if not tiers:
        return []
    var ids: Array[String] = []
    for key in tiers.keys():
        ids.append(str(key))
    return ids


## Returns all maps matching the given tier.
func get_maps_for_tier(tier_id: String) -> Array:
    var all: Array = _all_maps_provider.call()
    var result: Array = []
    for m in all:
        if m is MapData and m.tier == tier_id:
            result.append(m)
    return result


## Selects a random map from the given tier. Returns null if none available.
func select_random_map(tier_id: String) -> MapData:
    var maps := get_maps_for_tier(tier_id)
    if maps.is_empty():
        return null
    return maps[randi() % maps.size()]


## Creates a PartyDraft for the given tier.
func create_draft(tier_id: String) -> PartyDraft:
    var config := get_tier_config(tier_id)
    return PartyDraft.new(config, _character_provider)


## Builds a complete MatchState from two confirmed drafts and a selected map.
## Returns {state: MatchState, errors: Array[String]}.
func build_match(
    draft_a: PartyDraft,
    draft_b: PartyDraft,
    map_data: MapData,
) -> Dictionary:
    var errors: Array[String] = []

    # Validate drafts are confirmed
    if draft_a.state() != PartyDraft.State.CONFIRMED:
        errors.append("Player A draft is not confirmed")
    if draft_b.state() != PartyDraft.State.CONFIRMED:
        errors.append("Player B draft is not confirmed")
    if not errors.is_empty():
        return {"state": null, "errors": errors}

    # Create BattleUnit arrays
    var party_a: Array[BattleUnit] = _create_party(draft_a.confirmed_ids(), errors)
    var party_b: Array[BattleUnit] = _create_party(draft_b.confirmed_ids(), errors)
    if not errors.is_empty():
        return {"state": null, "errors": errors}

    # Build MatchState via MatchSetup
    var state := MatchSetup.create(party_a, party_b, map_data, _terrain_provider)

    # Wire providers
    var resolver := AbilityResolver.new(_ability_getter, _class_getter, _item_getter)
    state.ability_provider = resolver.resolve
    state.item_provider = _item_getter

    # Deploy
    var deploy_errors := Deployment.auto_deploy(state, map_data.deployment_zones)
    if not deploy_errors.is_empty():
        return {"state": null, "errors": deploy_errors}

    # Start round 1
    RoundManager.start_round(state)

    return {"state": state, "errors": []}


func _create_party(ids: Array[String], errors: Array[String]) -> Array[BattleUnit]:
    var party: Array[BattleUnit] = []
    for id in ids:
        var c: CharacterData = _character_provider.call(id)
        if not c:
            errors.append("Character '%s' not found" % id)
            continue
        var fs: StatBlock = _stats_provider.call(id)
        if not fs:
            errors.append("Final stats for '%s' not found" % id)
            continue
        party.append(BattleUnit.from_character(c, fs))
    return party
```

---

## Group C — GameData Extension

*Independent of A and B. Minor accessor additions.*

### C1. Add `all_maps()` to GameData

- Exposes `_pipeline.maps.all()` for MatchBuilder's map-by-tier filtering.
- One-line addition to the autoload.
- **Done:** `GameData.all_maps()` returns Array of all MapData.

```gdscript
# Addition to src/autoload/game_data.gd (after all_characters)

func all_maps() -> Array:
    return _pipeline.maps.all()
```

> Note: this is the same code as B1 — listed separately to clarify it's a GameData change, not a MatchBuilder change. Implement once.

---

## Group D — UI Scene

*Depends on A + B + C. Builds the Godot Control scene for the draft flow.*

### D1. Scene file: `scenes/draft/draft_scene.tscn`

- Root node: `DraftScene` (Control, full-rect anchored).
- Three child panels: `TierSelectPanel`, `DraftPanel`, `MatchStartPanel`.
- Only one panel visible at a time (managed by `DraftScene.gd`).
- Use Godot's built-in Control theme. No custom styling.
- **Done:** scene file with node tree matching the spec §6.1 layout.

### D2. `DraftScene.gd` — scene controller

- Manages the flow state machine: `TIER_SELECT → DRAFT_PLAYER_A → DRAFT_PLAYER_B → MATCH_READY → BATTLE`.
- Creates `MatchBuilder` on `_ready()` with GameData providers.
- On tier button click: stores tier, creates Player A's `PartyDraft`, transitions to draft panel.
- On character card click: calls `draft.add_character()`, updates UI.
- On confirm click: calls `draft.confirm()`, transitions to next state.
- On start battle click: calls `match_builder.build_match()`, transitions to combat.
- **Done:** full flow from tier select to match start.

```gdscript
# src/ui/draft_scene.gd
class_name DraftScene
extends Control

## Controls the party draft UI flow. Manages two PartyDraft instances
## (one per player) and a MatchBuilder for match construction.

enum FlowState { TIER_SELECT, DRAFT_PLAYER_A, DRAFT_PLAYER_B, MATCH_READY, BATTLE }

var _flow_state: int = FlowState.TIER_SELECT
var _match_builder: MatchBuilder
var _tier_id: String = ""
var _draft_a: PartyDraft
var _draft_b: PartyDraft
var _current_draft: PartyDraft
var _selected_map: MapData

# Node references (assigned in _ready via get_node or @onready)
@onready var _tier_panel: Control = $TierSelectPanel
@onready var _draft_panel: Control = $DraftPanel
@onready var _match_panel: Control = $MatchStartPanel
@onready var _player_label: Label = $DraftPanel/PlayerLabel
@onready var _bp_label: Label = $DraftPanel/InfoBar/BPLabel
@onready var _count_label: Label = $DraftPanel/InfoBar/CountLabel
@onready var _tier_label: Label = $DraftPanel/InfoBar/TierLabel
@onready var _roster_grid: Container = $DraftPanel/RosterGrid
@onready var _selected_list: Container = $DraftPanel/SelectedList
@onready var _confirm_btn: Button = $DraftPanel/ConfirmButton
@onready var _map_label: Label = $MatchStartPanel/MapLabel
@onready var _start_btn: Button = $MatchStartPanel/StartBattleButton


func _ready() -> void:
    _match_builder = MatchBuilder.new(
        GameData.get_character,
        GameData.get_final_stats,
        GameData.get_map,
        GameData.all_maps,
        GameData.get_terrain,
        GameData.get_ability,
        GameData.get_job_class,
        GameData.get_item,
    )
    _show_tier_select()


# --- Flow state transitions ---

func _show_tier_select() -> void:
    _flow_state = FlowState.TIER_SELECT
    _tier_panel.visible = true
    _draft_panel.visible = false
    _match_panel.visible = false


func _show_draft(player_label: String, draft: PartyDraft) -> void:
    _current_draft = draft
    _tier_panel.visible = false
    _draft_panel.visible = true
    _match_panel.visible = false
    _player_label.text = "%s — Draft Your Party" % player_label
    _tier_label.text = _tier_id.capitalize()
    _update_roster_grid()
    _update_selected_list()
    _update_info_bar()
    _confirm_btn.disabled = true


func _show_match_ready() -> void:
    _flow_state = FlowState.MATCH_READY
    _tier_panel.visible = false
    _draft_panel.visible = false
    _match_panel.visible = true
    _selected_map = _match_builder.select_random_map(_tier_id)
    if _selected_map:
        _map_label.text = "Map: %s" % _selected_map.id.replace("_", " ").capitalize()
    else:
        _map_label.text = "Error: No maps for tier"
        _start_btn.disabled = true


# --- Tier selection ---

func _on_tier_selected(tier_id: String) -> void:
    _tier_id = tier_id
    _draft_a = _match_builder.create_draft(tier_id)
    _flow_state = FlowState.DRAFT_PLAYER_A
    _show_draft("Player A", _draft_a)


# --- Character selection ---

func _on_character_clicked(character_id: String) -> void:
    if not _current_draft:
        return
    if character_id in _current_draft.selected_ids():
        _current_draft.remove_character(character_id)
    else:
        var err := _current_draft.add_character(character_id)
        if not err.is_empty():
            Log.info("DraftScene", err)
            return
    _update_roster_grid()
    _update_selected_list()
    _update_info_bar()


func _on_confirm_pressed() -> void:
    if not _current_draft:
        return
    var err := _current_draft.confirm()
    if not err.is_empty():
        Log.info("DraftScene", err)
        return

    if _flow_state == FlowState.DRAFT_PLAYER_A:
        _draft_b = _match_builder.create_draft(_tier_id)
        _flow_state = FlowState.DRAFT_PLAYER_B
        _show_draft("Player B", _draft_b)
    elif _flow_state == FlowState.DRAFT_PLAYER_B:
        _show_match_ready()


# --- Match start ---

func _on_start_battle_pressed() -> void:
    if not _selected_map or not _draft_a or not _draft_b:
        return
    var result := _match_builder.build_match(_draft_a, _draft_b, _selected_map)
    if not result["errors"].is_empty():
        for e in result["errors"]:
            Log.error("DraftScene", e)
        return
    var state: MatchState = result["state"]
    _start_battle(state)


func _start_battle(_state: MatchState) -> void:
    # Transition to the combat scene with the constructed MatchState.
    # Implementation depends on the project's scene management pattern.
    # Options:
    #   1. Store state in an autoload, change scene.
    #   2. Emit a signal that the parent scene handles.
    #   3. Directly instantiate the combat scene as a child.
    # For MVP: use an autoload or signal approach.
    Log.info("DraftScene", "Match ready — transitioning to battle")


# --- UI update helpers ---

func _update_roster_grid() -> void:
    # Rebuild character cards. Each card is a Button showing
    # name, class, BP. Disabled if can_add() is false.
    for child in _roster_grid.get_children():
        child.queue_free()

    var characters := GameData.all_characters()
    for c in characters:
        if not c is CharacterData:
            continue
        var char_data: CharacterData = c
        var btn := Button.new()
        btn.text = "%s\n%s · %d BP" % [
            char_data.display_name,
            char_data.classes[0].capitalize() if not char_data.classes.is_empty() else "",
            char_data.bp]

        var is_selected: bool = char_data.id in _current_draft.selected_ids()
        var can_add: bool = _current_draft.can_add(char_data.id)
        btn.disabled = not can_add and not is_selected

        # Visual feedback for selected characters
        if is_selected:
            btn.modulate = Color(0.5, 1.0, 0.5)  # Green tint for selected

        var char_id := char_data.id
        btn.pressed.connect(_on_character_clicked.bind(char_id))
        _roster_grid.add_child(btn)


func _update_selected_list() -> void:
    for child in _selected_list.get_children():
        child.queue_free()

    for id in _current_draft.selected_ids():
        var c: CharacterData = GameData.get_character(id)
        if not c:
            continue
        var hbox := HBoxContainer.new()
        var label := Label.new()
        label.text = "%s (%d BP)" % [c.display_name, c.bp]
        var remove_btn := Button.new()
        remove_btn.text = "X"
        remove_btn.pressed.connect(_on_character_clicked.bind(id))
        hbox.add_child(label)
        hbox.add_child(remove_btn)
        _selected_list.add_child(hbox)


func _update_info_bar() -> void:
    _bp_label.text = "BP: %d / %d" % [_current_draft.total_bp(), _current_draft.bp_cap()]
    _count_label.text = "Characters: %d / %d–%d" % [
        _current_draft.party_size(),
        _current_draft.min_characters(),
        _current_draft.max_characters()]
    _confirm_btn.disabled = not _current_draft.is_valid()
```

### D3. Wire tier buttons

- Each of the three tier buttons calls `_on_tier_selected()` with the tier ID.
- Buttons display tier name, BP cap, and character count bounds.
- Can be wired in `_ready()` or via the scene editor.
- **Done:** clicking a tier button starts the Player A draft.

```gdscript
# In _ready(), after MatchBuilder creation:

# Wire tier buttons (assumes buttons exist in scene tree)
for tier_id in _match_builder.get_tier_ids():
    var config := _match_builder.get_tier_config(tier_id)
    var btn := Button.new()
    btn.text = "%s\n%d BP · %d–%d characters" % [
        tier_id.capitalize(),
        int(config["bp_cap"]),
        int(config["min"]),
        int(config["max"])]
    btn.pressed.connect(_on_tier_selected.bind(tier_id))
    $TierSelectPanel/TierButtons.add_child(btn)
```

### D4. Match start panel

- Shows the randomly selected map name.
- Shows both party summaries (character names and total BP).
- Start Battle button calls `_on_start_battle_pressed()`.
- **Done:** match ready screen displays before battle starts.

### D5. Scene transition to combat

- After `build_match()` returns a valid MatchState, the DraftScene must transition to the combat scene.
- **Approach**: store the MatchState in a new `MatchData` autoload (simple data holder) and change scene to the map scene. The map scene reads from the autoload instead of hardcoding parties.
- Alternative: emit a signal. The simplest working approach should be chosen during implementation.
- **Done:** DraftScene hands off a fully initialized MatchState to the combat scene.

---

## Group E — Testing & Verification

*Depends on A + B. Tests are headless (no UI scene dependency).*

### E1. PartyDraft validation tests (GUT)

- Test: add character within BP cap — succeeds.
- Test: add character exceeding BP cap — returns error.
- Test: add duplicate character — returns error.
- Test: add character at max party size — returns error.
- Test: remove character — BP decreases, size decreases.
- Test: `is_valid()` true when min ≤ size ≤ max and BP ≤ cap.
- Test: `is_valid()` false when below min count.
- Test: confirm when valid — state becomes CONFIRMED.
- Test: confirm when invalid — returns error.
- Test: add/remove after confirm — returns error.
- Test: `can_add()` reflects all validation rules.
- Test: `remaining_bp()` correctly tracks available budget.
- **Done:** green, headless.

```gdscript
# tests/core/combat/test_party_draft.gd
extends GutTest

## Tests for PartyDraft validation logic.

# Stub character provider with controlled BP values
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


func test_add_character_succeeds() -> void:
    var draft := _make_draft()
    var err := draft.add_character("cheap_a")
    assert_eq(err, "")
    assert_eq(draft.party_size(), 1)
    assert_eq(draft.total_bp(), 10)

func test_add_character_exceeding_bp_cap_fails() -> void:
    var draft := _make_draft(50)  # 50 BP cap
    draft.add_character("mid_c")  # 30 BP
    var err := draft.add_character("mid_c")  # duplicate — different error
    assert_ne(err, "")
    # Try a new expensive character
    var err2 := draft.add_character("expensive_d")  # 30 + 50 = 80 > 50
    assert_ne(err2, "")

func test_add_duplicate_character_fails() -> void:
    var draft := _make_draft()
    draft.add_character("cheap_a")
    var err := draft.add_character("cheap_a")
    assert_ne(err, "")
    assert_eq(draft.party_size(), 1)

func test_add_at_max_size_fails() -> void:
    var draft := _make_draft(200, 1, 3)  # max 3
    draft.add_character("cheap_a")
    draft.add_character("cheap_b")
    draft.add_character("filler_f")
    var err := draft.add_character("filler_g")
    assert_ne(err, "")
    assert_eq(draft.party_size(), 3)

func test_remove_character_updates_state() -> void:
    var draft := _make_draft()
    draft.add_character("cheap_a")
    draft.add_character("cheap_b")
    var err := draft.remove_character("cheap_a")
    assert_eq(err, "")
    assert_eq(draft.party_size(), 1)
    assert_eq(draft.total_bp(), 15)  # only cheap_b remains

func test_is_valid_when_meets_requirements() -> void:
    var draft := _make_draft(100, 3, 5)
    draft.add_character("cheap_a")   # 10
    draft.add_character("cheap_b")   # 15
    assert_false(draft.is_valid())   # only 2, need 3
    draft.add_character("mid_c")     # 30, total 55, 3 chars
    assert_true(draft.is_valid())

func test_confirm_when_valid_succeeds() -> void:
    var draft := _make_draft(100, 3, 5)
    draft.add_character("cheap_a")
    draft.add_character("cheap_b")
    draft.add_character("filler_f")
    var err := draft.confirm()
    assert_eq(err, "")
    assert_eq(draft.state(), PartyDraft.State.CONFIRMED)

func test_confirm_when_invalid_fails() -> void:
    var draft := _make_draft(100, 3, 5)
    draft.add_character("cheap_a")
    var err := draft.confirm()
    assert_ne(err, "")
    assert_ne(draft.state(), PartyDraft.State.CONFIRMED)

func test_add_after_confirm_fails() -> void:
    var draft := _make_draft(100, 3, 5)
    draft.add_character("cheap_a")
    draft.add_character("cheap_b")
    draft.add_character("filler_f")
    draft.confirm()
    var err := draft.add_character("filler_g")
    assert_ne(err, "")

func test_can_add_reflects_rules() -> void:
    var draft := _make_draft(50, 1, 3)
    assert_true(draft.can_add("cheap_a"))      # 10 ≤ 50, not in party
    draft.add_character("cheap_a")
    assert_false(draft.can_add("cheap_a"))     # already in party
    assert_true(draft.can_add("cheap_b"))      # 10+15 = 25 ≤ 50
    assert_false(draft.can_add("expensive_d")) # 10+50 = 60 > 50
    assert_false(draft.can_add("nonexistent")) # not found

func test_remaining_bp_tracks_budget() -> void:
    var draft := _make_draft(100, 1, 5)
    assert_eq(draft.remaining_bp(), 100)
    draft.add_character("mid_c")  # 30
    assert_eq(draft.remaining_bp(), 70)
    draft.remove_character("mid_c")
    assert_eq(draft.remaining_bp(), 100)

func test_state_transitions() -> void:
    var draft := _make_draft(100, 2, 4)
    assert_eq(draft.state(), PartyDraft.State.EMPTY)
    draft.add_character("cheap_a")
    assert_eq(draft.state(), PartyDraft.State.DRAFTING)  # 1 < min 2
    draft.add_character("cheap_b")
    assert_eq(draft.state(), PartyDraft.State.VALID)     # 2 >= min 2
    draft.remove_character("cheap_b")
    assert_eq(draft.state(), PartyDraft.State.DRAFTING)  # back to 1
    draft.add_character("cheap_b")
    draft.confirm()
    assert_eq(draft.state(), PartyDraft.State.CONFIRMED)
```

### E2. MatchBuilder tests (GUT)

- Test: `get_tier_config()` returns correct values from Constants.
- Test: `get_maps_for_tier()` filters to correct tier.
- Test: `select_random_map()` returns a map of the correct tier.
- Test: `build_match()` with unconfirmed drafts returns errors.
- Test: `build_match()` with confirmed drafts returns a valid MatchState with deployed units.
- Test: `build_match()` MatchState has correct party sizes, initiative set, round 1 started.
- **Done:** green, headless.

```gdscript
# tests/core/combat/test_match_builder.gd
extends GutTest

## Tests for MatchBuilder orchestration.
## Uses real GameData (integration test — requires autoload).

var _builder: MatchBuilder

func before_each() -> void:
    _builder = MatchBuilder.new(
        GameData.get_character,
        GameData.get_final_stats,
        GameData.get_map,
        GameData.all_maps,
        GameData.get_terrain,
        GameData.get_ability,
        GameData.get_job_class,
        GameData.get_item,
    )


func test_get_tier_config_returns_valid() -> void:
    var config := _builder.get_tier_config("standard")
    assert_eq(int(config["bp_cap"]), 150)
    assert_eq(int(config["min"]), 4)
    assert_eq(int(config["max"]), 8)


func test_get_tier_config_invalid_returns_empty() -> void:
    var config := _builder.get_tier_config("nonexistent")
    assert_true(config.is_empty())


func test_get_maps_for_tier_filters_correctly() -> void:
    var maps := _builder.get_maps_for_tier("skirmish")
    assert_gte(maps.size(), 1)
    for m in maps:
        assert_eq(m.tier, "skirmish")


func test_select_random_map_returns_correct_tier() -> void:
    var m := _builder.select_random_map("standard")
    assert_not_null(m)
    assert_eq(m.tier, "standard")


func test_build_match_with_unconfirmed_drafts_errors() -> void:
    var draft_a := _builder.create_draft("skirmish")
    var draft_b := _builder.create_draft("skirmish")
    draft_a.add_character("human_fighter")
    # Neither confirmed
    var m := _builder.select_random_map("skirmish")
    var result := _builder.build_match(draft_a, draft_b, m)
    assert_false(result["errors"].is_empty())


func test_build_match_produces_valid_match_state() -> void:
    # Build two valid skirmish parties (3 chars each, BP ≤ 100)
    var draft_a := _builder.create_draft("skirmish")
    draft_a.add_character("human_fighter")    # 18
    draft_a.add_character("human_archer")     # 13
    draft_a.add_character("human_rogue")      # 16, total 47
    draft_a.confirm()

    var draft_b := _builder.create_draft("skirmish")
    draft_b.add_character("human_bard")       # 17
    draft_b.add_character("dwarf_barbarian")  # 20
    draft_b.add_character("elf_red_mage")     # 26, total 63
    draft_b.confirm()

    var m := _builder.select_random_map("skirmish")
    var result := _builder.build_match(draft_a, draft_b, m)

    assert_true(result["errors"].is_empty(),
        "Expected no errors, got: %s" % str(result["errors"]))
    var state: MatchState = result["state"]
    assert_not_null(state)

    # Verify parties
    assert_eq(state.parties["playerA"].size(), 3)
    assert_eq(state.parties["playerB"].size(), 3)

    # Verify deployment (units have positions)
    for u: BattleUnit in state.parties["playerA"]:
        assert_ne(u.position, Vector2i.ZERO,
            "Unit %s should be deployed" % u.character.id)
        assert_eq(u.team, "playerA")

    # Verify round started
    assert_eq(state.phase, MatchState.Phase.AWAITING_ACTIVATION)
    assert_gt(state.round_number, 0)
```

### E3. Integration test — full draft-to-combat flow

- Test: create MatchBuilder with real GameData, draft two skirmish parties, build match, verify first activation is possible.
- This is a superset of E2 that also exercises RoundManager.
- **Done:** green, headless.

### E4. Manual UI test checklist

- [ ] Launch DraftScene. Three tier buttons visible with correct labels.
- [ ] Click "Standard". Draft panel appears with "Player A" header, 8 character cards, BP counter at "0 / 150".
- [ ] Click character cards. Selected characters appear in the selected list, BP updates, character count updates.
- [ ] Characters already in party show visual feedback (green tint). Characters that can't be added are greyed out.
- [ ] Clicking a selected character in the roster grid removes it from the party.
- [ ] Confirm button is disabled until min characters met. Enabled when party is valid.
- [ ] Click Confirm. Screen transitions to "Player B" draft. Player A's selections are not visible.
- [ ] Player B drafts and confirms. Match start panel appears.
- [ ] Map name displayed. Both party summaries shown.
- [ ] Click Start Battle. Match constructs without errors. Combat scene loads with deployed units.
- [ ] Repeat with Skirmish and Large tiers.
- **Done:** checklist passes.

---

## Dependency Map

```
Phase 1 (CharacterData, StatBlock, BattleUnit, GameData) ──> A (PartyDraft)
Constants (tiers config) ──────────────────────────────────> A
A (PartyDraft) ──> B (MatchBuilder)
Phase 4 (MatchSetup, Deployment, RoundManager) ────────────> B
Phase 5 (AbilityResolver, item_provider) ──────────────────> B
C (GameData.all_maps) ─────────────────────────────────────> B
A + B + C ──> D (UI scene)
A + B ──> E1–E3 (unit tests);  D ──> E4 (manual UI checklist)
```

**Suggested order:** C (tiny, independent) → A (core logic, no dependencies) → B (builds on A + C) → E1–E3 (test logic) → D (UI scene, builds on everything) → E4 (manual UI verification).

---

## Phase 7 Definition of Done

- [ ] `PartyDraft` class with add/remove/validate/confirm, enforcing BP cap, size bounds, no self-duplicates (A).
- [ ] `MatchBuilder` class with tier config lookup, map filtering, random map selection, full match construction (B).
- [ ] `GameData.all_maps()` accessor added (C).
- [ ] UI scene: tier selection with 3 tier buttons (D).
- [ ] UI scene: draft panel with character roster, selected list, BP counter, character count, confirm button (D).
- [ ] UI scene: match start panel with map name, party summaries, start battle button (D).
- [ ] Sequential draft flow: Player A → confirm → Player B → confirm (D).
- [ ] Character cards show name, class, BP; disabled when `can_add()` is false; visual feedback when selected (D).
- [ ] Player A's selections hidden during Player B's draft (D).
- [ ] Random map selection from tier-matching maps (B).
- [ ] Match construction: BattleUnits created, MatchSetup wired, providers set, Deployment run, Round 1 started (B).
- [ ] Scene transition to combat with constructed MatchState (D).
- [ ] GUT tests for PartyDraft: all validation rules, state transitions, edge cases (E).
- [ ] GUT tests for MatchBuilder: tier config, map filtering, match construction (E).
- [ ] Manual UI checklist verified for all 3 tiers (E).
- [ ] Git tag `phase-7-complete`.
