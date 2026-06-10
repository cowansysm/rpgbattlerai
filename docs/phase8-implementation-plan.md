# Phase 8 — Implementation Plan

**Source spec:** `phase8-spec.md`
**Builds on:** `phase2` (3D map, hex tiles, camera, overlays), `phase3` (movement, range, LoS, `OverlayController`), `phase4` (activation loop, `MatchState`, `RoundManager`, `TurnActions`), `phase5` (combat resolution), `phase7` (draft UI, match builder, `MatchData` autoload, scene transition)
**Engine:** Godot 4.6.3 · **Language:** GDScript (typed)
**Structure:** Grouped work packages with dependency order. Cross-group dependencies noted.
**Date:** 2026-06-09

---

## How to use this plan

Seven **work groups** (A–G). Groups A and C are independent foundations that can be done in parallel. Group B depends on A. Group D depends on C. Group E depends on B + D. Group F (tests) trails the logic. Group G is manual verification.

Phase 8 spans three layers: **3D visuals** (A, B — token meshes with NATO-style symbology and sync), **2D HUD** (D — combat UI overlay), and **orchestration** (E — BattleController state machine). A small backend extension (C — AbilityResolver) is needed to populate the ability browser.

> **Carry-over:** consumes `MatchState`, `RoundManager`, `TurnActions`, `CombatResolver`, `AbilityResolver` from Phases 4–5; `BattleUnit`, `CharacterData`, `AbilityData`, `ItemData`, `StatBlock` from Phase 1; `MapBuilder`, `HexTile`, `HexWorld`, `OverlayController`, `OverlayMaterials`, `TileMesh` from Phases 2–3; `MatchData` autoload and `DraftScene` from Phase 7; `GameData` and `Constants` from Phase 0–1.

---

## Group A — PawnFactory & UnitPawn (Foundation)

*No dependencies on other new code. Can be built and tested standalone.*

### A1. `PawnFactory` — token mesh, materials, and symbol textures

Static factory class following the `DecorationFactory` pattern. Creates a cylindrical token mesh, team-colored materials, and NATO-style symbol textures for the top face.

```
# src/map/pawn_factory.gd
class_name PawnFactory
extends RefCounted

# Token body
static func make_token_mesh() -> Mesh
static func team_material(team: String) -> StandardMaterial3D
static func active_material(team: String) -> StandardMaterial3D

# Symbol texture (rendered on token top face)
static func make_symbol_texture(race: String, job_class: String, team: String) -> ImageTexture
static func symbol_material(race: String, job_class: String, team: String) -> StandardMaterial3D

# Internal drawing helpers
static func _draw_race_frame(img: Image, race: String, color: Color) -> void
static func _draw_class_icon(img: Image, job_class: String, color: Color) -> void
```

**Reference patterns:**
- `src/map/decoration_factory.gd` — static mesh factory (make_tree, make_boulder)
- `src/map/overlay_materials.gd` — static material factory (move_tier1, target_valid)

**Token dimensions:**
- Cylinder: radius ≈ 0.3, height ≈ 0.15, radial_segments = 16 (flat disc token)
- Team A: blue (0.2, 0.4, 0.9), Team B: red (0.9, 0.2, 0.2)
- Active variant: emission enabled, energy ≈ 0.8, matching team hue

**Symbol rendering:**
- 128×128 `Image` created via `Image.create()` with `FORMAT_RGBA8`
- Frame shapes drawn with `_draw_race_frame()`: Rectangle (Human), Diamond (Elf), Circle (Halfling), Hexagon (Dwarf)
- Class icons drawn with `_draw_class_icon()`: ✕ Fighter, ↑ Archer, / Rogue, ‡ Barbarian, ⚡ Black Mage, + White Mage, ✳ Red Mage, ∿ Bard
- Frame fill tinted with team color (blue/red), icon and frame outline drawn in white
- Cached by `(race, job_class, team)` key using a static Dictionary — at most 64 entries

**Drawing approach:** Use `Image.set_pixel()` with helper functions for lines, circles, and polygons. Shapes are simple geometric primitives that don't require Godot's CanvasItem drawing API. This avoids the need for SubViewport rendering and keeps the factory purely static/RefCounted.

### A2. `UnitPawn` — 3D token for one deployed character

Node3D that represents a single unit on the map. Has two MeshInstance3D children: a team-colored cylinder body and a PlaneMesh on top with the race/class symbol texture.

```
# src/map/unit_pawn.gd
class_name UnitPawn
extends Node3D

var unit: BattleUnit
var _body: MeshInstance3D          # CylinderMesh token
var _symbol_face: MeshInstance3D   # PlaneMesh on top with symbol texture
var _default_material: StandardMaterial3D
var _active_material: StandardMaterial3D

func setup(battle_unit: BattleUnit, graph: HexGraph) -> void
func place(coord: Vector2i, graph: HexGraph) -> void
func move_to(coord: Vector2i, graph: HexGraph) -> Tween
func set_active(active: bool) -> void
func remove() -> void
```

**Reference patterns:**
- `src/core/hex/hex_world.gd` — `hex_to_world(q, r, elevation)` for coordinate conversion
- `src/map/tile_mesh.gd` — `TILE_HEIGHT` constant for Y offset above tile surface
- `src/map/camera_rig.gd` — tween pattern (`create_tween()`, `EASE_OUT`, `TRANS_CUBIC`, 0.3s)

**Setup flow:**
1. Create cylinder `MeshInstance3D` child → assign team material.
2. Create `PlaneMesh` child (size ≈ 0.5 × 0.5) → position at Y = token_half_height (sitting on top face).
3. Rotate plane -90° on X axis so it faces up.
4. Assign symbol material from `PawnFactory.symbol_material(race, class, team)`.
5. Call `place()` to position at the hex coordinate.

**Placement formula:**
```gdscript
position = HexWorld.hex_to_world(coord.x, coord.y, graph.elevation(coord))
position.y += TileMesh.TILE_HEIGHT * 0.5 + 0.075  # half token height above tile
```

---

## Group B — PawnManager (Sync Layer)

*Depends on: Group A (PawnFactory, UnitPawn).*

### B1. `PawnManager` — manages all unit pawns

Node that maintains a dictionary of `BattleUnit → UnitPawn` mappings. Provides a clean interface for the controller to spawn, move, remove, and highlight pawns.

```
# src/map/pawn_manager.gd
class_name PawnManager
extends Node

var _pawns: Dictionary = {}       # BattleUnit → UnitPawn
var _graph: HexGraph

func setup(state: MatchState, graph: HexGraph) -> void
func spawn_all(state: MatchState) -> void
func move_pawn(unit: BattleUnit, to: Vector2i) -> Tween
func remove_pawn(unit: BattleUnit) -> void
func highlight_active(unit: BattleUnit) -> void
func clear_highlight() -> void
func get_pawn(unit: BattleUnit) -> UnitPawn
```

**Sync model:** Pull-based. The controller calls PawnManager methods explicitly after each TurnActions call. No signals on MatchState — matching the existing Phase4Demo pattern.

**spawn_all flow:**
1. Iterate `state.parties` (both teams).
2. For each living unit, create a `UnitPawn`, call `setup()`, `add_child()`.
3. Store in `_pawns` dictionary.

**move_pawn flow:**
1. Look up UnitPawn in `_pawns`.
2. Call `move_to(to, _graph)` — returns a Tween.
3. Controller awaits tween completion before proceeding.

**remove_pawn flow:**
1. Look up UnitPawn in `_pawns`.
2. Call `remove()` (queue_free).
3. Erase from `_pawns`.

---

## Group C — AbilityResolver Extension

*No dependencies on other new code. Can be done in parallel with Group A.*

### C1. `all_abilities()` method on `AbilityResolver`

Add a new method to the existing `AbilityResolver` class that returns all abilities a unit has access to. Reuses the same three-source resolution logic as `resolve()`.

```
# MODIFY: src/core/combat/ability_resolver.gd

func all_abilities(unit: BattleUnit) -> Array:
    # 1. Direct character abilities
    # 2. Class-granted abilities (for each class)
    # 3. Equipment-granted abilities (for each item)
    # Deduplicate by ability ID
    # Return Array of AbilityData
```

**Reference:** Existing `resolve(unit, ability_id)` method at line 22 of `ability_resolver.gd` — same three-source check, but `all_abilities` collects all rather than checking one specific ID.

---

## Group D — BattleHUD (UI Overlay)

*Depends on: Group C (to populate ability lists via `AbilityResolver.all_abilities()`).*

### D1. `BattleHUD` — full combat HUD

A `CanvasLayer` + `Control` built programmatically in `_ready()`, following the `DraftScene._build_ui()` pattern. The HUD is a passive display — the controller calls update methods on it.

```
# src/ui/battle_hud.gd
class_name BattleHUD
extends CanvasLayer

# Signals emitted to the controller when player clicks action buttons
signal action_selected(action_type: int)
signal ability_selected(ability_id: String)
signal item_selected(item_id: String)
signal cancel_requested()

# Update methods called by controller
func show_unit_info(unit: BattleUnit) -> void
func hide_unit_info() -> void
func show_action_panel(unit: BattleUnit, abilities: Array, items: Array) -> void
func hide_action_panel() -> void
func set_targeting_mode(active: bool) -> void
func update_roster(state: MatchState) -> void
func update_turn_order(state: MatchState) -> void
func update_round_info(round_number: int, team: String) -> void
func append_log(text: String) -> void
func disable_actions_below_ap(ap: int) -> void
```

**Reference pattern:** `src/ui/draft_scene.gd` — builds all UI in `_build_ui()` called from `_ready()`.

**Layout construction order:**
1. CanvasLayer (layer 1, above 3D)
2. Root Control (full rect, mouse filter IGNORE on transparent areas)
3. Top bar (MarginContainer + HBoxContainer)
4. Left sidebar (MarginContainer + VBoxContainer, fixed width ~200px)
5. Right sidebar (MarginContainer + ScrollContainer, fixed width ~250px)
6. Bottom bar (MarginContainer + HBoxContainer)

**Mouse handling:** Panels use `MOUSE_FILTER_STOP` so clicks on buttons are consumed. The transparent center area uses `MOUSE_FILTER_IGNORE` so clicks pass through to the TilePicker/3D map below.

### D2. Ability & item browser sub-panels

Part of BattleHUD. Expandable lists that appear when the player clicks "Abilities ▼" or "Items ▼".

- Abilities: `VBoxContainer` of `Button` nodes, one per ability. Disabled if AP < cost.
- Items: `VBoxContainer` of `Button` nodes, one per usable item. Disabled if AP < 1.
- Each button emits the appropriate signal (`ability_selected` or `item_selected`).
- Sub-panels toggle visibility on click.

### D3. Combat log panel

Part of BattleHUD. `ScrollContainer` + `VBoxContainer` of `Label` nodes.

- `append_log(text)` creates a new Label, adds it to the VBoxContainer, auto-scrolls.
- Maximum 100 entries; older entries removed via `queue_free()`.
- Log formatting is the controller's responsibility (converts TurnActions result dicts to strings).

### D4. Team roster sidebar

Part of BattleHUD. Two sections (Team A, Team B) with per-unit rows.

- Each row: name label + mini ProgressBar (HP) + activation indicator label.
- Updated via `update_roster(state)` which iterates `state.parties`.
- Downed units dimmed (`modulate.a = 0.4`).
- Active unit row highlighted.

---

## Group E — BattleController (Orchestrator)

*Depends on: Groups B + D (PawnManager + BattleHUD).*

### E1. `BattleController` — state machine combat controller

Replaces Phase4Demo as the combat controller. Manages the game flow, wires HUD signals to TurnActions, and syncs PawnManager.

```
# src/map/battle_controller.gd
class_name BattleController
extends Node

enum ControlState {
    AWAITING_ACTIVATION,
    ACTION_SELECT,
    TARGETING,
    ANIMATING,
    ROUND_END,
}

var _state: MatchState
var _builder: MapBuilder
var _pawn_manager: PawnManager
var _hud: BattleHUD
var _overlay: OverlayController
var _control_state: int = ControlState.AWAITING_ACTIVATION
var _pending_action: int = -1
var _pending_ability_id: String = ""
var _pending_item_id: String = ""
var _selected_tile: Vector2i = Vector2i(-999, -999)

func setup(builder: MapBuilder, state: MatchState) -> void
func setup_from_state(builder: MapBuilder, state: MatchState) -> void
func on_tile_selected(coord: Vector2i) -> void
func _unhandled_input(event: InputEvent) -> void
```

**Key methods:**
- `setup()` / `setup_from_state()` — matching Phase4Demo's dual setup pattern. Creates PawnManager and BattleHUD as children. Spawns all pawns.
- `on_tile_selected()` — received from TilePicker signal. Behavior depends on `_control_state` (select unit, target action, etc.).
- `_unhandled_input()` — handles keyboard shortcuts (N, M, F, G, X, R, Escape).
- `_activate_next()` — activates next unactivated unit, handles sleep auto-wait, updates HUD.
- `_execute_action()` — dispatches to TurnActions, updates pawn/HUD/log.
- `_on_action_selected(action_type)` — HUD signal handler, enters TARGETING or executes immediately.
- `_on_ability_selected(ability_id)` — HUD signal handler, enters TARGETING for ability.
- `_format_log_entry(result: Dictionary) -> String` — converts TurnActions result to combat log text.

### E2. `map_scene.gd` update

Modify the existing `map_scene.gd` to use `BattleController` instead of `Phase4Demo`:

```gdscript
# Replace Phase4Demo with BattleController
var controller := BattleController.new()
if has_match:
    controller.setup_from_state(builder, MatchData.match_state)
    MatchData.clear()
else:
    controller.setup(builder, map_data)
add_child(controller)

picker.tile_selected.connect(controller.on_tile_selected)
```

**Reference:** Current wiring in `scenes/map/map_scene.gd` lines 34–46.

### E3. OverlayController extensions (optional)

If needed, add methods for friendly-target and area-preview overlays:

```
# MODIFY: src/map/overlay_controller.gd

func show_ability_range(origin: Vector2i, ability_range: int, friendly: bool) -> void
func show_area_preview(center: Vector2i, radius: int) -> void
```

These use the existing `_paint()` mechanism with new materials (green for friendly, orange for area preview).

---

## Group F — Tests

*Depends on: Groups A–E.*

### F1. `test_pawn_manager.gd` — PawnManager sync logic

```
# tests/map/test_pawn_manager.gd

- test_spawn_all_creates_pawns_for_all_living_units
- test_spawn_ignores_downed_units
- test_move_pawn_updates_position
- test_remove_pawn_cleans_up
- test_highlight_active_sets_correct_pawn
- test_clear_highlight_resets_all
```

**Note:** Tests will need to verify PawnManager behavior without a rendered scene. Focus on dictionary state (pawn counts, lookups) and method call validation. Pawn mesh rendering cannot be validated headlessly.

### F2. `test_ability_resolver_all.gd` — all_abilities() method

```
# tests/core/combat/test_ability_resolver_all.gd (or extend existing test file)

- test_all_abilities_includes_class_granted
- test_all_abilities_includes_equipment_granted
- test_all_abilities_includes_direct_character_abilities
- test_all_abilities_deduplicates
- test_all_abilities_empty_for_no_abilities
```

Uses `DataPipeline` directly (matching `test_match_builder.gd` pattern).

### F3. `test_battle_controller.gd` — state machine transitions

```
# tests/map/test_battle_controller.gd

- test_initial_state_is_awaiting_activation
- test_activate_next_transitions_to_action_select
- test_move_action_transitions_to_targeting
- test_attack_action_transitions_to_targeting
- test_ability_action_transitions_to_targeting
- test_defend_executes_immediately
- test_wait_ends_activation
- test_targeting_cancel_returns_to_action_select
- test_round_end_transitions_on_all_activated
- test_sleeping_unit_auto_waits
```

**Note:** BattleController is a Node that depends on PawnManager and BattleHUD. Tests may need to create minimal stubs or use partial doubles for the HUD. Focus on state transitions rather than visual output.

---

## Group G — Manual Verification

*Depends on: Groups A–F (all implementation and tests complete).*

### G1. Full playthrough checklist

1. Launch game → Draft scene appears.
2. Select a tier (Skirmish recommended for quick testing).
3. Draft Player A party (3–5 characters), confirm.
4. Draft Player B party (3–5 characters), confirm.
5. Match ready screen shows, click "Start Battle".
6. **Verify pawns:** all drafted characters appear as team-colored tokens with race/class symbols on their deployment tiles.
7. **Verify HUD:** round info, team roster, and combat log are visible.
8. Press N → **verify:** next unit activates, pawn highlights, unit info panel shows, action buttons appear.
9. Click Move → **verify:** movement overlay appears. Click valid tile → **verify:** pawn tweens smoothly, AP decrements.
10. Click Attack → **verify:** target overlay appears. Click enemy tile → **verify:** damage applied, combat log updated.
11. Click Abilities ▼ → **verify:** ability list appears with correct abilities for this character.
12. Click an ability → **verify:** range overlay appears. Click target → **verify:** effect applied, log updated.
13. Click Items ▼ → **verify:** item list appears (if unit has usable items, e.g., Rogue's smoke bomb).
14. Click Defend → **verify:** +2 DEF applied, log updated.
15. Click Wait → **verify:** activation ends, next unit prompted.
16. Complete a full round → **verify:** round end state, press R → new round begins.
17. Down a unit → **verify:** pawn removed from map, roster shows downed indicator.
18. **Verify keyboard shortcuts:** N, M, F, G, X, R, Escape all work as alternatives to HUD buttons.

---

## Suggested implementation order

```
A (PawnFactory + UnitPawn) ─┐
                            ├─→ B (PawnManager) ─┐
C (AbilityResolver.all_abilities) ─→ D (BattleHUD) ─┼─→ E (BattleController + map_scene.gd)
                                                      │
                                                      └─→ F (Tests) ─→ G (Manual verification)
```

Groups A and C can be done in parallel. The critical path is A → B → E and C → D → E.

---

## File manifest

### New files

| File | Class | Group | Description |
|------|-------|-------|-------------|
| `src/map/pawn_factory.gd` | `PawnFactory` | A | Token mesh, material, and symbol texture factory |
| `src/map/unit_pawn.gd` | `UnitPawn` | A | Node3D token with symbol face for one deployed character |
| `src/map/pawn_manager.gd` | `PawnManager` | B | Manages all unit pawns |
| `src/ui/battle_hud.gd` | `BattleHUD` | D | Full combat HUD overlay |
| `src/map/battle_controller.gd` | `BattleController` | E | State machine combat controller |
| `tests/map/test_pawn_manager.gd` | — | F | PawnManager GUT tests |
| `tests/map/test_battle_controller.gd` | — | F | BattleController GUT tests |
| `tests/core/combat/test_ability_resolver_all.gd` | — | F | all_abilities() GUT tests |

### Modified files

| File | Group | Changes |
|------|-------|---------|
| `src/core/combat/ability_resolver.gd` | C | Add `all_abilities(unit)` method |
| `scenes/map/map_scene.gd` | E | Replace Phase4Demo with BattleController |
| `src/map/overlay_controller.gd` | E | Add `show_ability_range()` and `show_area_preview()` (optional) |
